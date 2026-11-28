#!/bin/bash
#
# Sets ShellTime up in a cloud agent environment so the sessions started in it
# are tracked like the ones on your own machines. Supported environments:
#
#   - Claude Code cloud (claude.ai/code, CLAUDE_CODE_REMOTE=true)
#   - Google Antigravity cloud (OS user `antigravity`, or SHELLTIME_CLOUD=true)
#   - Cursor Cloud Agents (CURSOR_CLOUD=true / CURSOR_BACKGROUND_AGENT=true,
#     or SHELLTIME_CLOUD=true)
#
# Add this line to the environment's setup/install script:
#
#   curl -fsSL https://raw.githubusercontent.com/shelltime/installation/main/cloud.bash | bash
#
# Claude Code cloud:
#   Add your ShellTime API token to the environment as a network secret for
#   api.shelltime.xyz, sent in the Authorization header with the prefix CLI.
#   Anthropic's agent proxy adds it to the daemon's requests after they leave
#   the session's VM, so the token is never in the VM, and the secret's host
#   needs no network access setting. An environment without network secrets can
#   hold the token in SHELLTIME_TOKEN among its environment variables instead,
#   with api.shelltime.xyz allowed by its network access. Setup scripts get
#   neither, so a SessionStart hook signs in and starts the daemon in every
#   session.
#
# Antigravity cloud:
#   Pass your ShellTime API token in SHELLTIME_TOKEN (exported in the setup
#   script or set in the project's environment variables) and commit
#   .agents/hooks.json to your repository (`shelltime agy install`). Setup
#   installs the CLI and daemon, saves SHELLTIME_TOKEN if present, and adds a
#   SessionStart hook in ~/.gemini/config/hooks.json (group "shelltime-cloud")
#   that signs in (when SHELLTIME_TOKEN is in the session env) and starts the
#   daemon in every session.
#
# Cursor Cloud Agents:
#   Add SHELLTIME_TOKEN and SHELLTIME_CLOUD=true to your environment secrets
#   and commit .cursor/hooks.json to your repository (`shelltime cursor install`).
#   Run cloud.bash in the environment's install step and
#   `~/.shelltime/bin/cloud-start.sh` in the start step (or run cloud.bash in
#   the start step directly: when SHELLTIME_TOKEN is present it signs in and
#   starts the daemon immediately).
#
# Outside a cloud environment (no CLAUDE_CODE_REMOTE=true, no `antigravity`
# user, no CURSOR_CLOUD/CURSOR_BACKGROUND_AGENT, and no SHELLTIME_CLOUD=true),
# this installs nothing.
#
# Guides:
#   https://shelltime.xyz/blogs/track-claude-code-cloud-sessions
#   https://shelltime.xyz/blogs/track-cursor-and-antigravity

RELEASE_URL="https://github.com/shelltime/cli/releases/latest/download"
IS_CLAUDE_CLOUD=false
IS_AGY_CLOUD=false
IS_CURSOR_CLOUD=false
TARGET_USER=""
TARGET_HOME=""
ST_DIR=""
CLOUD_START_PATH=""
CLAUDE_HOOK_PATH=""
CLAUDE_SETTINGS_PATH=""
AGY_HOOK_PATH=""
AGY_HOOKS_PATH=""

# A setup script that exits non-zero keeps the environment's sessions from
# starting, so a failure is reported here and never passed on.
finish() {
    local status=$?
    set +e
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
    if [ "$status" -ne 0 ]; then
        echo "ShellTime setup failed; sessions will not be tracked" >&2
    fi
    exit 0
}

trap finish EXIT
set -euo pipefail

is_truthy() {
    case "${1:-}" in
        true | TRUE | True | 1) return 0 ;;
        *) return 1 ;;
    esac
}

# 0. Decide which cloud environment(s) we are in and which user/home owns the
# agent runtime (Antigravity setup scripts often run as root while the agent
# runs as the OS user `antigravity`). Note: CURSOR_CODE_REMOTE and CURSOR_AGENT
# are also set on local/SSH machines, so they are intentionally not treated as
# cloud signals on their own.
detect_cloud_env() {
    TARGET_USER=$(id -un)
    TARGET_HOME="$HOME"

    if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
        IS_CLAUDE_CLOUD=true
    fi

    if [ "$TARGET_USER" = "antigravity" ]; then
        IS_AGY_CLOUD=true
    elif [ "$(id -u)" -eq 0 ] && id -u antigravity >/dev/null 2>&1; then
        IS_AGY_CLOUD=true
        TARGET_USER="antigravity"
        TARGET_HOME=$(getent passwd antigravity 2>/dev/null | cut -d: -f6 || true)
        TARGET_HOME="${TARGET_HOME:-/home/antigravity}"
    fi

    if is_truthy "${CURSOR_CLOUD:-}" || is_truthy "${CURSOR_BACKGROUND_AGENT:-}"; then
        IS_CURSOR_CLOUD=true
    fi

    if [ "$IS_CLAUDE_CLOUD" = false ] && [ "$IS_AGY_CLOUD" = false ] && [ "$IS_CURSOR_CLOUD" = false ]; then
        if is_truthy "${SHELLTIME_CLOUD:-}"; then
            # Prefer host/agent markers over repo hook files (a repo may commit
            # both .cursor/hooks.json and .agents/hooks.json).
            if [ -d "$TARGET_HOME/.cursor" ] || command -v cursor-agent >/dev/null 2>&1; then
                IS_CURSOR_CLOUD=true
            fi
            if [ -d "$TARGET_HOME/.gemini" ] || command -v agy >/dev/null 2>&1; then
                IS_AGY_CLOUD=true
            fi
            if [ "$IS_CURSOR_CLOUD" = false ] && [ "$IS_AGY_CLOUD" = false ]; then
                if [ -f ".cursor/environment.json" ] || [ -f ".cursor/hooks.json" ]; then
                    IS_CURSOR_CLOUD=true
                fi
                if [ -f ".agents/hooks.json" ]; then
                    IS_AGY_CLOUD=true
                fi
            fi
            # Fresh VM before checkout/agent init: prepare both hook-based cloud agents
            if [ "$IS_CURSOR_CLOUD" = false ] && [ "$IS_AGY_CLOUD" = false ]; then
                IS_CURSOR_CLOUD=true
                IS_AGY_CLOUD=true
            fi
        else
            echo "cloud.bash only runs in cloud agent environments (CLAUDE_CODE_REMOTE=true, Antigravity cloud, CURSOR_CLOUD=true, or SHELLTIME_CLOUD=true); on your own machine run: curl -sSL https://shelltime.xyz/i | bash" >&2
            return 1
        fi
    fi

    ST_DIR="$TARGET_HOME/.shelltime"
    CLOUD_START_PATH="$ST_DIR/bin/cloud-start.sh"
    CLAUDE_HOOK_PATH="$ST_DIR/bin/cloud-session-start.sh"
    CLAUDE_SETTINGS_PATH="$TARGET_HOME/.claude/settings.json"
    AGY_HOOK_PATH="$ST_DIR/bin/agy-cloud-session-start.sh"
    AGY_HOOKS_PATH="$TARGET_HOME/.gemini/config/hooks.json"
}

# 1. CLI and daemon, where install.bash puts them (the ShellTime mod and
# repository hook commands look there and in /usr/local/bin)
install_cli() {
    local arch
    case "$(uname -m)" in
        x86_64) arch=x86_64 ;;
        aarch64 | arm64) arch=arm64 ;;
        *)
            echo "Unsupported architecture: $(uname -m)" >&2
            return 1
            ;;
    esac

    mkdir -p "$ST_DIR/bin" "$ST_DIR/logs" "$TARGET_HOME/.local/bin"
    curl -fsSL --retry 3 -o "$TMP_DIR/cli.tar.gz" "$RELEASE_URL/cli_Linux_${arch}.tar.gz"
    tar -xzf "$TMP_DIR/cli.tar.gz" -C "$TMP_DIR" shelltime shelltime-daemon
    install -m 0755 "$TMP_DIR/shelltime" "$TMP_DIR/shelltime-daemon" "$ST_DIR/bin/"
    ln -sf "$ST_DIR/bin/shelltime" "$TARGET_HOME/.local/bin/shelltime"
    if [ -w /usr/local/bin ]; then
        ln -sf "$ST_DIR/bin/shelltime" /usr/local/bin/shelltime
        ln -sf "$ST_DIR/bin/shelltime-daemon" /usr/local/bin/shelltime-daemon
    fi
}

# Shared start helper for hook-based cloud agents (Cursor Cloud Agents `start`
# step and Antigravity's SessionStart hook): signs in if SHELLTIME_TOKEN is in
# the environment, clears any stale socket, and starts shelltime-daemon once.
install_cloud_start_script() {
    cat >"$CLOUD_START_PATH" <<'EOF'
#!/bin/bash
# Starts ShellTime in a cloud agent VM (Antigravity SessionStart hook, Cursor
# Cloud Agents start step, or any VM with SHELLTIME_CLOUD=true).
export SHELLTIME_CLOUD=true
st="$HOME/.shelltime"
mkdir -p "$st/logs"
if [ -n "${SHELLTIME_TOKEN:-}" ] && ! grep -qF -- "$SHELLTIME_TOKEN" "$st/config.yaml" 2>/dev/null; then
    "$st/bin/shelltime" auth --token "$SHELLTIME_TOKEN" >/dev/null 2>&1 || true
fi
if [ -f "$st/config.yaml" ] && ! pgrep -fx "$st/bin/shelltime-daemon" >/dev/null 2>&1; then
    rm -f /tmp/shelltime.sock
    setsid nohup "$st/bin/shelltime-daemon" >>"$st/logs/shelltime-daemon.log" 2>&1 </dev/null &
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -S /tmp/shelltime.sock ] && break
        sleep 0.1 2>/dev/null || sleep 1
    done
fi
exit 0
EOF
    chmod 0755 "$CLOUD_START_PATH"
}

# 2a. Claude Code's OTEL exporter pointed at the daemon
connect_claude_code() {
    HOME="$TARGET_HOME" "$ST_DIR/bin/shelltime" cc install
}

# 2b. Claude Code SessionStart hook: the snapshot keeps files but no processes,
# there is no systemd, and only sessions see SHELLTIME_TOKEN
install_claude_session_hook() {
    cat >"$CLAUDE_HOOK_PATH" <<'EOF'
#!/bin/bash
# Claude Code SessionStart hook, installed by ShellTime's cloud.bash. Its stdout
# would go into Claude's context, so it prints nothing.
st="$HOME/.shelltime"
# With the token in a network secret, the CLI signs in with the placeholder
# proxy-injected and sends no Authorization header; the agent proxy adds the
# real one. SHELLTIME_TOKEN, for environments without network secrets, wins.
token="${SHELLTIME_TOKEN:-proxy-injected}"
# The first session, or the token changed in the environment settings
if ! grep -qF -- "$token" "$st/config.yaml" 2>/dev/null; then
    "$st/bin/shelltime" auth --token "$token" >/dev/null 2>&1 || exit 0
fi
if ! pgrep -fx "$st/bin/shelltime-daemon" >/dev/null; then
    setsid nohup "$st/bin/shelltime-daemon" >>"$st/logs/shelltime-daemon.log" 2>&1 </dev/null &
fi
exit 0
EOF
    chmod 0755 "$CLAUDE_HOOK_PATH"

    # Replaces the hook an earlier run added instead of adding a second one
    jq --arg cmd "$CLAUDE_HOOK_PATH" '
        .hooks.SessionStart = [(.hooks.SessionStart // [])[] | select(all(.hooks[]?; .command != $cmd))]
            + [{hooks: [{type: "command", command: $cmd}]}]
    ' "$CLAUDE_SETTINGS_PATH" >"$CLAUDE_SETTINGS_PATH.tmp"
    mv "$CLAUDE_SETTINGS_PATH.tmp" "$CLAUDE_SETTINGS_PATH"
}

# 3a. When SHELLTIME_TOKEN is exported in the setup/install script, bake it
# into config.yaml so it survives into live sessions.
auth_if_token_present() {
    if [ -n "${SHELLTIME_TOKEN:-}" ]; then
        HOME="$TARGET_HOME" "$ST_DIR/bin/shelltime" auth --token "$SHELLTIME_TOKEN" >/dev/null
    fi
}

# 3b. Antigravity SessionStart hook: invokes cloud-start.sh and prints {} under
# a separate hook group ("shelltime-cloud") so .agents/hooks.json never yields
# to it.
install_agy_session_hook() {
    cat >"$AGY_HOOK_PATH" <<'EOF'
#!/bin/bash
# Antigravity SessionStart hook, installed by ShellTime's cloud.bash.
# Antigravity requires a JSON object on stdout.
"$HOME/.shelltime/bin/cloud-start.sh" >/dev/null 2>&1 || true
echo '{}'
exit 0
EOF
    chmod 0755 "$AGY_HOOK_PATH"

    mkdir -p "$(dirname "$AGY_HOOKS_PATH")"
    if [ ! -s "$AGY_HOOKS_PATH" ]; then
        echo '{}' >"$AGY_HOOKS_PATH"
    fi

    if command -v jq >/dev/null 2>&1; then
        jq --arg cmd "$AGY_HOOK_PATH" \
            '.["shelltime-cloud"] = {"SessionStart": [{"type": "command", "command": $cmd, "timeout": 15}]}' \
            "$AGY_HOOKS_PATH" >"$AGY_HOOKS_PATH.tmp"
        mv "$AGY_HOOKS_PATH.tmp" "$AGY_HOOKS_PATH"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c '
import json, sys
path, cmd = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
data["shelltime-cloud"] = {"SessionStart": [{"type": "command", "command": cmd, "timeout": 15}]}
with open(path + ".tmp", "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
' "$AGY_HOOKS_PATH" "$AGY_HOOK_PATH"
        mv "$AGY_HOOKS_PATH.tmp" "$AGY_HOOKS_PATH"
    else
        echo "Neither jq nor python3 is available to update $AGY_HOOKS_PATH" >&2
        return 1
    fi
}

# 4. When setup ran as root on behalf of `antigravity`, hand ownership of the
# files we created to that user so the runtime hooks and daemon can read config.
fix_ownership() {
    if [ "$(id -u)" -ne 0 ] || [ "$TARGET_USER" = "root" ]; then
        return 0
    fi
    local group
    group=$(id -gn "$TARGET_USER")
    chown -R "$TARGET_USER:$group" "$ST_DIR"
    chown "$TARGET_USER:$group" "$TARGET_HOME/.local" "$TARGET_HOME/.local/bin" 2>/dev/null || true
    chown -h "$TARGET_USER:$group" "$TARGET_HOME/.local/bin/shelltime" 2>/dev/null || true
    if [ "$IS_AGY_CLOUD" = true ]; then
        chown "$TARGET_USER:$group" "$TARGET_HOME/.gemini" "$TARGET_HOME/.gemini/config" "$AGY_HOOKS_PATH" 2>/dev/null || true
    fi
    if [ "$IS_CLAUDE_CLOUD" = true ]; then
        chown "$TARGET_USER:$group" "$TARGET_HOME/.claude" "$CLAUDE_SETTINGS_PATH" 2>/dev/null || true
    fi
}

main() {
    detect_cloud_env

    TMP_DIR=$(mktemp -d)
    install_cli

    if [ "$IS_CLAUDE_CLOUD" = true ]; then
        connect_claude_code
        install_claude_session_hook
    fi

    if [ "$IS_AGY_CLOUD" = true ] || [ "$IS_CURSOR_CLOUD" = true ]; then
        install_cloud_start_script
        auth_if_token_present
    fi

    if [ "$IS_AGY_CLOUD" = true ]; then
        install_agy_session_hook
    fi

    fix_ownership

    # Cursor Cloud Agents ignore ~/.cursor/hooks.json and rely on the start
    # step: when cloud.bash is run with SHELLTIME_TOKEN as the runtime user,
    # start the daemon immediately so a single start-step call works too.
    if [ "$IS_CURSOR_CLOUD" = true ] && [ -n "${SHELLTIME_TOKEN:-}" ] && [ "$TARGET_USER" = "$(id -un)" ]; then
        HOME="$TARGET_HOME" "$CLOUD_START_PATH"
    fi

    if [ "$IS_CLAUDE_CLOUD" = true ] && [ "$IS_AGY_CLOUD" = false ] && [ "$IS_CURSOR_CLOUD" = false ]; then
        echo "ShellTime is installed; Claude Code sessions will be tracked once your ShellTime token is a network secret for api.shelltime.xyz"
    elif [ "$IS_AGY_CLOUD" = true ] && [ "$IS_CLAUDE_CLOUD" = false ] && [ "$IS_CURSOR_CLOUD" = false ]; then
        echo "ShellTime is installed; Antigravity sessions will be tracked (ensure .agents/hooks.json is committed in your repo)"
    elif [ "$IS_CURSOR_CLOUD" = true ] && [ "$IS_CLAUDE_CLOUD" = false ] && [ "$IS_AGY_CLOUD" = false ]; then
        echo "ShellTime is installed; Cursor Cloud Agent sessions will be tracked (run ~/.shelltime/bin/cloud-start.sh in your start step and ensure .cursor/hooks.json is committed in your repo)"
    else
        echo "ShellTime is installed for cloud agent sessions"
    fi
}

# Nothing runs before this line, so a download cut short installs nothing
main "$@"
