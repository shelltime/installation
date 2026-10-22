#!/bin/bash
#
# Sets ShellTime up in a Claude Code cloud environment (claude.ai/code), so the
# sessions started in it are tracked like the ones on your own machines. Add
# this line to the environment's setup script:
#
#   curl -fsSL https://raw.githubusercontent.com/shelltime/installation/main/cloud.bash | bash
#
# Then add your ShellTime API token to the environment as a network secret for
# api.shelltime.xyz, sent in the Authorization header with the prefix CLI.
# Anthropic's agent proxy adds it to the daemon's requests after they leave the
# session's VM, so the token is never in the VM, and the secret's host needs no
# network access setting. An environment without network secrets can hold the
# token in SHELLTIME_TOKEN among its environment variables instead, with
# api.shelltime.xyz allowed by its network access. Setup scripts get neither,
# so this only installs; a SessionStart hook signs in and starts the daemon in
# every session. Anywhere CLAUDE_CODE_REMOTE isn't true, it installs nothing.
#
# Guide: https://shelltime.xyz/blogs/track-claude-code-cloud-sessions

ST_DIR="$HOME/.shelltime"
HOOK_PATH="$ST_DIR/bin/cloud-session-start.sh"
SETTINGS_PATH="$HOME/.claude/settings.json"
RELEASE_URL="https://github.com/shelltime/cli/releases/latest/download"

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

# 1. CLI and daemon, where install.bash puts them (the ShellTime mod looks there)
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

    mkdir -p "$ST_DIR/bin" "$ST_DIR/logs" "$HOME/.local/bin"
    curl -fsSL --retry 3 -o "$TMP_DIR/cli.tar.gz" "$RELEASE_URL/cli_Linux_${arch}.tar.gz"
    tar -xzf "$TMP_DIR/cli.tar.gz" -C "$TMP_DIR" shelltime shelltime-daemon
    install -m 0755 "$TMP_DIR/shelltime" "$TMP_DIR/shelltime-daemon" "$ST_DIR/bin/"
    ln -sf "$ST_DIR/bin/shelltime" "$HOME/.local/bin/shelltime"
}

# 2. Claude Code's OTEL exporter pointed at the daemon
connect_claude_code() {
    "$ST_DIR/bin/shelltime" cc install
}

# 3. The snapshot keeps files but no processes, there is no systemd, and only
# sessions see SHELLTIME_TOKEN, so a SessionStart hook signs in and starts the
# daemon in every session
install_session_hook() {
    cat >"$HOOK_PATH" <<'EOF'
#!/bin/bash
# Claude Code SessionStart hook, installed by ShellTime's cloud.bash. Its stdout
# would go into Claude's context, so it prints nothing.
st="$HOME/.shelltime"
# With the token in a network secret, the CLI signs in with the placeholder
# proxy-injected and sends no Authorization header; the agent proxy adds the
# real one. SHELLTIME_TOKEN, for environments without network secrets, wins.
token="${SHELLTIME_TOKEN:-proxy-injected}"
# The first session, or the token changed in the environment settings
if ! grep -qF "$token" "$st/config.yaml" 2>/dev/null; then
    "$st/bin/shelltime" auth --token "$token" >/dev/null 2>&1 || exit 0
fi
if ! pgrep -fx "$st/bin/shelltime-daemon" >/dev/null; then
    setsid nohup "$st/bin/shelltime-daemon" >>"$st/logs/shelltime-daemon.log" 2>&1 </dev/null &
fi
exit 0
EOF
    chmod 0755 "$HOOK_PATH"

    # Replaces the hook an earlier run added instead of adding a second one
    jq --arg cmd "$HOOK_PATH" '
        .hooks.SessionStart = [(.hooks.SessionStart // [])[] | select(all(.hooks[]?; .command != $cmd))]
            + [{hooks: [{type: "command", command: $cmd}]}]
    ' "$SETTINGS_PATH" >"$SETTINGS_PATH.tmp"
    mv "$SETTINGS_PATH.tmp" "$SETTINGS_PATH"
}

main() {
    # Cloud environments set CLAUDE_CODE_REMOTE=true, and it's never true on
    # your own machine, where this would swap in Linux binaries and add a hook
    if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
        echo "cloud.bash only runs in Claude Code cloud environments (CLAUDE_CODE_REMOTE=true); on your own machine run: curl -sSL https://shelltime.xyz/i | bash" >&2
        return 1
    fi

    TMP_DIR=$(mktemp -d)
    install_cli
    connect_claude_code
    install_session_hook
    echo "ShellTime is installed; Claude Code sessions will be tracked once your ShellTime token is a network secret for api.shelltime.xyz"
}

# Nothing runs before this line, so a download cut short installs nothing
main "$@"
