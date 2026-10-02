#!/bin/bash
set -euo pipefail

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

get_download_url() {
    local baseUrl="$1"
    local downloadUrl=""

    if [[ "$OS" == "Darwin" ]]; then
        baseUrl="${baseUrl}${OS}"
        if [[ "$ARCH" == "x86_64" ]]; then
            downloadUrl="${baseUrl}_x86_64.zip"
        elif [[ "$ARCH" == "arm64" ]]; then
            downloadUrl="${baseUrl}_arm64.zip"
        else
            echo "Unsupported architecture: $ARCH on macOS"
            exit 1
        fi
        if ! command_exists unzip; then
            echo "Error: unzip is not installed."
            exit 1
        fi
    elif [[ "$OS" == "Linux" ]]; then
        baseUrl="${baseUrl}${OS}"
        if [[ "$ARCH" == "x86_64" ]]; then
            downloadUrl="${baseUrl}_x86_64.tar.gz"
        elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
            downloadUrl="${baseUrl}_arm64.tar.gz"
        else
            echo "Unsupported architecture: $ARCH on Linux"
            exit 1
        fi
        if ! command_exists tar; then
            echo "Error: tar is not installed."
            exit 1
        fi
    else
        echo "Unsupported OS: $OS"
        exit 1
    fi

    echo "$downloadUrl"
}

process_file() {
    local file="$1"
    local url="$2"
    local pending_file
    pending_file=$(mktemp "${hooks_path}/${file}.XXXXXX") || return 1
    if ! curl -fsSL --connect-timeout 15 --max-time 60 "$url" -o "$pending_file"; then
        rm -f -- "$pending_file"
        echo "Error: Failed to download $file. Existing hook and backup preserved." >&2
        return 1
    fi
    if ! chmod 644 "$pending_file"; then
        rm -f -- "$pending_file"
        return 1
    fi
    if [ -f "${hooks_path}/${file}" ]; then
        if ! mv -f -- "${hooks_path}/${file}" "${hooks_path}/${file}.bak"; then
            rm -f -- "$pending_file"
            return 1
        fi
    fi
    if ! mv -- "$pending_file" "${hooks_path}/${file}"; then
        if [ -f "${hooks_path}/${file}.bak" ]; then
            mv -- "${hooks_path}/${file}.bak" "${hooks_path}/${file}" || true
        fi
        rm -f -- "$pending_file"
        return 1
    fi
}

add_source_to_config() {
    local config_file="$1"
    local source_file="$2"
    local pending_config
    pending_config=$(mktemp "${config_file}.XXXXXX") || return 1

    # Migrate the legacy unquoted spelling and remove previously emitted duplicates.
    if ! SHELLTIME_SOURCE_FILE="$source_file" awk '
        BEGIN {
            legacy = "source " ENVIRON["SHELLTIME_SOURCE_FILE"]
            quoted = "source \"" ENVIRON["SHELLTIME_SOURCE_FILE"] "\""
        }
        {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (line == legacy || line == quoted) {
                if (!found) print quoted
                found = 1
            } else {
                print
            }
        }
        END { if (!found) print quoted }
    ' "$config_file" > "$pending_config"; then
        rm -f -- "$pending_config"
        return 1
    fi
    # Preserve permissions and symlinks on the user's shell configuration.
    if ! cat "$pending_config" > "$config_file"; then
        rm -f -- "$pending_config"
        return 1
    fi
    rm -f -- "$pending_config"
}

install_shelltime() {
# Determine the OS and architecture
OS=$(uname -s)
ARCH=$(uname -m)

case "$OS" in
    Darwin|Linux) ;;
    *) echo "Unsupported OS: $OS. Use macOS, Linux, or WSL." >&2; exit 1 ;;
esac

# Flag to track whether Homebrew installation was used
BREW_INSTALLED=false

# Check for required commands
if ! command_exists curl; then
    echo "Error: curl is not installed."
    exit 1
fi

# On macOS, prefer Homebrew installation if brew is available
if [[ "$OS" == "Darwin" ]] && command_exists brew; then
    echo "Homebrew detected on macOS. Attempting to install via brew..."
    if brew install shelltime/tap/shelltime; then
        BREW_INSTALLED=true
        echo "Successfully installed shelltime via Homebrew."
        # Rename old manual-install binaries so the system uses the Homebrew version
        if [ -f "$HOME/.shelltime/bin/shelltime" ]; then
            mv "$HOME/.shelltime/bin/shelltime" "$HOME/.shelltime/bin/shelltime.bak"
            echo "Renamed ~/.shelltime/bin/shelltime to shelltime.bak (now using Homebrew version)"
        fi
        if [ -f "$HOME/.shelltime/bin/shelltime-daemon" ]; then
            mv "$HOME/.shelltime/bin/shelltime-daemon" "$HOME/.shelltime/bin/shelltime-daemon.bak"
            echo "Renamed ~/.shelltime/bin/shelltime-daemon to shelltime-daemon.bak (now using Homebrew version)"
        fi
    else
        echo "Homebrew installation failed. Falling back to manual installation..."
    fi
fi

if [ "$BREW_INSTALLED" = false ]; then

CLI_FILE_NAME="https://github.com/shelltime/cli/releases/latest/download/cli_"

curr_time_dir=$(mktemp -d "${TMPDIR:-/tmp}/shelltime-install.XXXXXX")
trap 'rm -rf -- "$curr_time_dir"' EXIT
cd "$curr_time_dir"

URL=$(get_download_url "$CLI_FILE_NAME")

# Download the file
FILENAME=$(basename "$URL")
curl -fsSLO --connect-timeout 15 --max-time 300 "$URL"

# Check if the download was successful
if [ ! -f "$FILENAME" ]; then
    echo "Error: Failed to download $FILENAME"
    exit 1
fi

# Extract the file
if [[ "$FILENAME" == *.zip ]]; then
    unzip "$FILENAME" > /dev/null
elif [[ "$FILENAME" == *.tar.gz ]]; then
    tar zxvf "$FILENAME" > /dev/null
else
    echo "Unsupported file type: $FILENAME"
    exit 1
fi

# Check if the shelltime file exists
if [ ! -f "shelltime" ]; then
    echo "Error: shelltime binary not found after extraction"
    exit 1
fi

# Check if $HOME/.shelltime/bin exists, create if not
if [ ! -d "$HOME/.shelltime/bin" ]; then
    if ! mkdir -p "$HOME/.shelltime/bin"; then
        echo "Error: Failed to create $HOME/.shelltime/bin directory."
        exit 1
    fi
fi

# Move the binary to the appropriate location
if [[ "$OS" == "Darwin" ]] || [[ "$OS" == "Linux" ]]; then
    chmod 755 shelltime
    mv shelltime "$HOME/.shelltime/bin/"
    if [ -f "shelltime-daemon" ]; then
        chmod 755 shelltime-daemon
        mv shelltime-daemon "$HOME/.shelltime/bin/"
    else
        echo "" >&2
        echo "WARNING: shelltime-daemon binary was NOT found in $FILENAME." >&2
        echo "         The CLI will attempt to auto-download it on first" >&2
        echo "         'shelltime daemon install/reinstall'." >&2
        echo "" >&2
    fi
fi

# Add $HOME/.shelltime/bin to user path
if [[ "$OS" == "Darwin" ]] || [[ "$OS" == "Linux" ]]; then
    # For Zsh
    if [ -f "$HOME/.zshrc" ]; then
        if ! grep -q '$HOME/.shelltime/bin' "$HOME/.zshrc"; then
            echo '# Added by shelltime' >> "$HOME/.zshrc"
            echo 'export PATH="$HOME/.shelltime/bin:$PATH"' >> "$HOME/.zshrc"
        fi
    fi

    # For Fish
    if command_exists fish; then
        if [ ! -d "$HOME/.config/fish" ]; then
            mkdir -p "$HOME/.config/fish"
        fi
        if [ ! -f "$HOME/.config/fish/config.fish" ]; then
            touch "$HOME/.config/fish/config.fish"
        fi
        if ! grep -q '$HOME/.shelltime/bin' "$HOME/.config/fish/config.fish"; then
            echo '# Added by shelltime' >> "$HOME/.config/fish/config.fish"
            echo 'fish_add_path $HOME/.shelltime/bin' >> "$HOME/.config/fish/config.fish"
        fi
    fi

    # For Bash
    if [ -f "$HOME/.bashrc" ]; then
        if ! grep -q '$HOME/.shelltime/bin' "$HOME/.bashrc"; then
            echo '# Added by shelltime' >> "$HOME/.bashrc"
            echo 'export PATH="$HOME/.shelltime/bin:$PATH"' >> "$HOME/.bashrc"
        fi
    fi
fi

# Clean up

cd "${TMPDIR:-/tmp}"

fi  # end of manual installation block

# Check if $HOME/.shelltime/daemon exists, create if not
if [ ! -d "$HOME/.shelltime/daemon" ]; then
    if ! mkdir -p "$HOME/.shelltime/daemon"; then
        echo "Warning: Failed to create $HOME/.shelltime/daemon directory. Daemon functionality may be unavailable." >&2
        return 1
    fi
fi

# STEP 2
# insert a preexec and postexec script to user configuration, including `zsh` and `fish`

# Define the path
hooks_path="$HOME/.shelltime/hooks"

# Check if the directory exists
if [ ! -d "$hooks_path" ]; then
    if ! mkdir -p "$hooks_path"; then
        echo "Warning: Failed to create $hooks_path directory. Shell hooks may be unavailable." >&2
        return 1
    fi
fi

installation_failed=false

# Process zsh.zsh
if ! process_file "zsh.zsh" "https://raw.githubusercontent.com/shelltime/installation/master/hooks/zsh.zsh"; then
    installation_failed=true
fi

# Process fish.fish
if ! process_file "fish.fish" "https://raw.githubusercontent.com/shelltime/installation/master/hooks/fish.fish"; then
    installation_failed=true
fi

# Process bash.bash
if ! process_file "bash-preexec.sh" "https://raw.githubusercontent.com/rcaloras/bash-preexec/master/bash-preexec.sh"; then
    installation_failed=true
fi
if ! process_file "bash.bash" "https://raw.githubusercontent.com/shelltime/installation/master/hooks/bash.bash"; then
    installation_failed=true
fi

# Add source lines to config files
if [ -f "$HOME/.zshrc" ] && [ -f "${hooks_path}/zsh.zsh" ]; then
    add_source_to_config "$HOME/.zshrc" "${hooks_path}/zsh.zsh"
fi
if [ -f "$HOME/.config/fish/config.fish" ] && [ -f "${hooks_path}/fish.fish" ]; then
    add_source_to_config "$HOME/.config/fish/config.fish" "${hooks_path}/fish.fish"
fi
if [ -f "$HOME/.bashrc" ] && [ -f "${hooks_path}/bash.bash" ] && [ -f "${hooks_path}/bash-preexec.sh" ]; then
    add_source_to_config "$HOME/.bashrc" "${hooks_path}/bash.bash"
fi

# Reinstall daemon if shelltime is available
if command_exists shelltime; then
    if ! shelltime daemon reinstall > /dev/null 2>&1; then
        echo "Warning: Daemon setup failed. Run shelltime doctor after authentication." >&2
    fi
fi

echo ""
if [ "$installation_failed" = true ]; then
    echo "Installation incomplete: some hooks could not be updated. Rerun the installer to retry." >&2
    return 1
fi
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Reload your shell:  source ~/.zshrc  (or ~/.bashrc / ~/.config/fish/config.fish)"
echo "  2. Run:  shelltime init"
echo ""
}

# Also run when piped to Bash, where BASH_SOURCE is empty.
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    install_shelltime
fi
