# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **shelltime installation** repository - a collection of shell scripts that install the shelltime CLI and configure shell hooks for zsh, bash, and fish. Shelltime tracks shell command execution times.

## Repository Structure

- `install.bash` - Main installation script that downloads shelltime CLI binaries and sets up shell hooks
- `cloud.bash` - Setup for Claude Code cloud environments, run from an environment's setup script with `curl -fsSL https://raw.githubusercontent.com/shelltime/installation/main/cloud.bash | bash`. Installs the Linux CLI and daemon into `~/.shelltime/bin`, runs `shelltime cc install`, and adds a Claude Code SessionStart hook (`~/.shelltime/bin/cloud-session-start.sh`, embedded in the script) that signs in and starts the daemon in each session. The token is a network secret of the environment (host `api.shelltime.xyz`, header `Authorization`, prefix `CLI`) that Anthropic's agent proxy adds to requests outside the VM, so the hook signs in with the placeholder `proxy-injected` (the CLI then sends no `Authorization` header; needs a CLI release with `model.ProxyInjectedToken`). `SHELLTIME_TOKEN` in the environment variables, for environments without network secrets, replaces the placeholder. Setup scripts get neither. It installs nothing unless `CLAUDE_CODE_REMOTE` is `true`, which cloud environments set (the setup script inherits it from `environment-manager`) and which is never true on a user's own machine. A setup script that exits non-zero stops sessions from starting, so it always exits 0 (its `EXIT` trap reports a failure instead), and nothing runs before the final `main` call, so a truncated download installs nothing. The guide that documents it is `content/blogs/track-claude-code-cloud-sessions/` in the web repo; keep the two in step
- `hooks/` - Shell-specific hook scripts that track command execution:
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

The CI verifies:
1. Installation script runs successfully across shells
2. Shell configuration files are properly sourced
3. Hook files are placed in `~/.shelltime/hooks/`

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

- CLI binary: `~/.shelltime/bin/shelltime`
- Hook scripts: `~/.shelltime/hooks/`
- Daemon directory: `~/.shelltime/daemon/`

## Commit Rules

Follow Conventional Commits with scope:
```
fix(hooks): correct command tracking in bash
feat(install): add support for ARM64 Linux
refactor(zsh): simplify preexec function
```
