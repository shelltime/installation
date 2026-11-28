# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **shelltime installation** repository - a collection of shell scripts that install the shelltime CLI and configure shell hooks for zsh, bash, and fish. Shelltime tracks shell command execution times.

## Repository Structure

- `install.bash` - Main installation script that downloads shelltime CLI binaries and sets up shell hooks
- `cloud.bash` - Setup for cloud agent environments (Claude Code cloud, Google Antigravity cloud, and Cursor Cloud Agents), run from an environment's setup/install script with `curl -fsSL https://raw.githubusercontent.com/shelltime/installation/main/cloud.bash | bash`. Detects Claude Code cloud (`CLAUDE_CODE_REMOTE=true`), Antigravity cloud (OS user `antigravity`, including when setup runs as `root` on behalf of `antigravity`), Cursor Cloud Agents (`CURSOR_CLOUD=true`/`1`, `CURSOR_BACKGROUND_AGENT=true`/`1`), or an explicit `SHELLTIME_CLOUD=true` (matching `~/.cursor`/`.cursor/*`/`cursor-agent` vs `~/.gemini`/`.agents/hooks.json`/`agy`, or both in a fresh VM); outside those it installs nothing (ignoring `CURSOR_CODE_REMOTE` and `CURSOR_AGENT`, which local/SSH machines also set). Installs the Linux CLI and daemon into `$TARGET_HOME/.shelltime/bin` (and symlinks into `/usr/local/bin` when writable). For Claude Code cloud, runs `shelltime cc install` and adds a Claude Code SessionStart hook (`~/.shelltime/bin/cloud-session-start.sh`) that signs in with `proxy-injected` (or `SHELLTIME_TOKEN`) and starts the daemon in each session. For Antigravity and Cursor cloud, installs `~/.shelltime/bin/cloud-start.sh` (signs in when `SHELLTIME_TOKEN` is in the env, clears stale `/tmp/shelltime.sock`, starts `shelltime-daemon` with `SHELLTIME_CLOUD=true`) and saves `SHELLTIME_TOKEN` to `config.yaml` if present during setup. For Antigravity, also adds `~/.shelltime/bin/agy-cloud-session-start.sh` under the separate `"shelltime-cloud"` group in `~/.gemini/config/hooks.json` (so `.agents/hooks.json` never yields to it) and fixes ownership to `antigravity` when setup ran as `root`. For Cursor Cloud Agents (which ignore `~/.cursor/hooks.json`), also runs `cloud-start.sh` immediately when `SHELLTIME_TOKEN` is already set. A setup script that exits non-zero stops sessions from starting, so it always exits 0 (its `EXIT` trap reports a failure instead), and nothing runs before the final `main` call, so a truncated download installs nothing. The guides that document it are `content/blogs/track-claude-code-cloud-sessions/` and `content/blogs/track-cursor-and-antigravity/` in the web repo; keep them in step
- `hooks/` - Shell-specific hook scripts that track command execution. They are copies of the CLI's embedded hooks (`model/hooks/` in shelltime/cli, which `shelltime hooks install` and `shelltime init` write over these), so change both together:
  - `zsh.zsh` - Uses zsh's native `preexec` and `precmd` hooks
  - `bash.bash` - Uses `bash-preexec` library for preexec/precmd functionality
  - `fish.fish` - Uses fish's `fish_preexec` and `fish_postexec` events

## Testing

Run the CI workflow locally or on GitHub Actions:
```bash
# The test workflow runs on ubuntu-latest and macos-latest
# Testing shells: zsh, fish, bash
bash ./install.bash
```

Each `test-shells` job runs `bash ./install.bash` from its shell (zsh, fish or bash) with `$SHELL` naming it, as for a user whose login shell it is, in the runner's own home directory (macOS has no `~/.zshrc`, like a fresh account). macOS takes the Homebrew path, Linux the manual one. The CI verifies:
1. Every hook and `bash-preexec.sh` are in `~/.shelltime/hooks/`, and `~/.shelltime/daemon/` exists
2. The login shell's config file exists and sources its hook (`install.bash` creates it for the login shell, and `config.fish` whenever fish is installed)
3. Homebrew path: the cask is installed and links `shelltime` and `shelltime-daemon` into brew's bin, with no `~/.shelltime/bin/shelltime` shadowing it. Manual path: both binaries are in `~/.shelltime/bin`, which the config puts on `PATH`
4. A new interactive shell loads the hook's functions and runs that `shelltime` (bash needs `-i`: Ubuntu's default `~/.bashrc` returns early in a non-interactive shell)

The `test-cloud` job checks that `cloud.bash` installs nothing without `CLAUDE_CODE_REMOTE=true`, then runs it twice with it on x86_64 and arm64 Linux and checks the binaries, the OTEL settings, that the SessionStart hook is registered exactly once, and that the hook prints nothing, signs in with `proxy-injected` (or `SHELLTIME_TOKEN` when set) and starts one daemon.

## How Shell Hooks Work

Each shell hook script:
1. Checks if `shelltime` CLI is available
2. Runs `shelltime gc` on shell startup
3. Creates a unique `SESSION_ID` per shell session
4. Tracks commands via `shelltime track` with `-p=pre` (before execution) and `-p=post` (after execution)
5. Skips tracking for `exit`, `logout`, and `reboot` commands

Bash requires the external `bash-preexec.sh` library (downloaded during installation) since bash doesn't have native preexec/precmd hooks.

## Installation Paths

- CLI binary: `~/.shelltime/bin/shelltime` (manual install), or brew's bin dir when macOS installs the `shelltime/tap/shelltime` cask
- Hook scripts: `~/.shelltime/hooks/`
- Daemon directory: `~/.shelltime/daemon/`

## Commit Rules

Follow Conventional Commits with scope:
```
fix(hooks): correct command tracking in bash
feat(install): add support for ARM64 Linux
refactor(zsh): simplify preexec function
```
