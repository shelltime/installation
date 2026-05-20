#!/bin/bash

# Determine the OS and architecture
OS=$(uname -s)
ARCH=$(uname -m)

# Function to check if a command is available
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

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
DAEMON_FILE_NAME="${CLI_FILE_NAME}daemon_"

cd /tmp
curr_time_dir="shelltime_install_$(date +"%Y%m%d_%H%M%S")"
mkdir -p "$curr_time_dir"
cd "$curr_time_dir"

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
        elif [[ "$ARCH" == "aarch64" ]]; then
            downloadUrl="${baseUrl}_arm64.tar.gz"
        else
            echo "Unsupported architecture: $ARCH on Linux"
            exit 1
        fi
        if ! command_exists tar; then
            echo "Error: tar is not installed."
            exit 1
        fi
    elif [[ "$OS" == "MINGW64_NT" ]] || [[ "$OS" == "MSYS_NT" ]] || [[ "$OS" == "CYGWIN_NT" ]]; then
        baseUrl="${baseUrl}Windows"
        if [[ "$ARCH" == "x86_64" ]]; then
            downloadUrl="${baseUrl}_x86_64.zip"
        elif [[ "$ARCH" == "aarch64" ]]; then
            downloadUrl="${baseUrl}_arm64.zip"
        else
            echo "Unsupported architecture: $ARCH on Windows"
            exit 1
        fi
        if ! command_exists unzip; then
            echo "Error: unzip is not installed."
            exit 1
        fi
    else
        echo "Unsupported OS: $OS"
        exit 1
    fi

    echo "$downloadUrl"
}

URL=$(get_download_url "$CLI_FILE_NAME")

# Download the file
FILENAME=$(basename "$URL")
curl -sSLO "$URL"

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
    mkdir -p "$HOME/.shelltime/bin"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create $HOME/.shelltime/bin directory."
        exit 1
    fi
fi

# Move the binary to the appropriate location
if [[ "$OS" == "Darwin" ]] || [[ "$OS" == "Linux" ]]; then
    mv shelltime "$HOME/.shelltime/bin/"
    if [ -f "shelltime-daemon" ]; then
        mv shelltime-daemon "$HOME/.shelltime/bin/"
    else
        echo "" >&2
        echo "WARNING: shelltime-daemon binary was NOT found in $FILENAME." >&2
        echo "         The CLI will attempt to auto-download it on first" >&2
        echo "         'shelltime daemon install/reinstall'." >&2
        echo "" >&2
    fi
# elif [[ "$OS" == "MINGW64_NT" ]] || [[ "$OS" == "MSYS_NT" ]] || [[ "$OS" == "CYGWIN_NT" ]]; then
    # mv shelltime /c/Windows/System32/
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

cd /tmp
if [ -d "/tmp/$curr_time_dir" ]; then
    rm -rf "/tmp/$curr_time_dir"
fi


# HELP WANTED
# I don't know where the `/bin` folder in windows. so i don't know where should the binaries be installed.
# if you know, please let me know.

if [[ "$OS" == "MINGW64_NT" ]] || [[ "$OS" == "MSYS_NT" ]] || [[ "$OS" == "CYGWIN_NT" ]]; then
	echo "Note: Please move /tmp/shelltime to your bin folder manually."
	echo "If you know where binaries should be installed on Windows, please open an issue: https://github.com/shelltime/cli"
fi

fi  # end of manual installation block

# Check if $HOME/.shelltime/daemon exists, create if not
if [ ! -d "$HOME/.shelltime/daemon" ]; then
    mkdir -p "$HOME/.shelltime/daemon"
    if [ $? -ne 0 ]; then
        echo "Warning: Failed to create $HOME/.shelltime/daemon directory. Daemon functionality may be unavailable."
    fi
fi

# STEP 2
# insert a preexec and postexec script to user configuration, including `zsh` and `fish`

# Define the path
hooks_path="$HOME/.shelltime/hooks"

# Check if the directory exists
if [ ! -d "$hooks_path" ]; then
    mkdir -p "$hooks_path"
    if [ $? -ne 0 ]; then
        echo "Warning: Failed to create $hooks_path directory. Shell hooks may be unavailable."
    fi
fi


# Function to check and delete .bak files
check_and_delete_bak() {
    local file="$1"
    if [ -f "${hooks_path}/${file}.bak" ]; then
        rm "${hooks_path}/${file}.bak"
    fi
}

# Function to check, rename, and download files
process_file() {
    local file="$1"
    local url="$2"

    # Check if the file exists and rename it
    if [ -f "${hooks_path}/${file}" ]; then
        mv "${hooks_path}/${file}" "${hooks_path}/${file}.bak"
    fi

    # Download the new file
    curl -sSL "${url}" -o "${hooks_path}/${file}"
}

# Function to add source line to config file if not already present
add_source_to_config() {
    local config_file="$1"
    local source_file="$2"
    local source_line="source ${source_file}"

    if ! grep -qF "${source_line}" "${config_file}"; then
        echo "${source_line}" >> "${config_file}"
    fi
}

# Ensure hooks_path exists
mkdir -p "$hooks_path"

# Check and delete .bak files
check_and_delete_bak "zsh.zsh"
check_and_delete_bak "fish.fish"

# Process zsh.zsh
process_file "zsh.zsh" "https://raw.githubusercontent.com/shelltime/installation/master/hooks/zsh.zsh"

# Process fish.fish
process_file "fish.fish" "https://raw.githubusercontent.com/shelltime/installation/master/hooks/fish.fish"

# Process bash.bash
process_file "bash-preexec.sh" "https://raw.githubusercontent.com/rcaloras/bash-preexec/master/bash-preexec.sh"
process_file "bash.bash" "https://raw.githubusercontent.com/shelltime/installation/master/hooks/bash.bash"

# Add source lines to config files
if [ -f "$HOME/.zshrc" ]; then
    add_source_to_config "$HOME/.zshrc" "${hooks_path}/zsh.zsh"
fi
if [ -f "$HOME/.config/fish/config.fish" ]; then
    add_source_to_config "$HOME/.config/fish/config.fish" "${hooks_path}/fish.fish"
fi
if [ -f "$HOME/.bashrc" ]; then
    add_source_to_config "$HOME/.bashrc" "${hooks_path}/bash.bash"
fi

# Reinstall daemon if shelltime is available
if command_exists shelltime; then
    shelltime daemon reinstall > /dev/null 2>&1
fi

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Reload your shell:  source ~/.zshrc  (or ~/.bashrc / ~/.config/fish/config.fish)"
echo "  2. Run:  shelltime init"
echo ""
