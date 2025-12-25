# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **shelltime installation** repository - a collection of shell scripts that install the shelltime CLI and configure shell hooks for zsh, bash, and fish. Shelltime tracks shell command execution times.

## Repository Structure

- `install.bash` - Main installation script that downloads shelltime CLI binaries and sets up shell hooks
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
