# shelltime Installation

Welcome to shelltime! This guide will help you install the necessary tools using a simple command.

## Quick Install

You can install shelltime tools by running the following command in your terminal:

```bash
curl -sSL https://shelltime.xyz/i | bash
```

## Cloud Agent Environments (Claude Code, Google Antigravity & Cursor)

To track cloud sessions in **Claude Code** ([claude.ai/code](https://claude.ai/code)), **Google Antigravity** ([antigravity.google.com](https://antigravity.google.com)), or **Cursor Cloud Agents** ([cursor.com](https://cursor.com/docs/cloud-agent/setup)), add this line to the environment's setup/install script:

```bash
curl -fsSL https://raw.githubusercontent.com/shelltime/installation/main/cloud.bash | bash
```

- **Claude Code cloud (`CLAUDE_CODE_REMOTE=true`)**: Add your ShellTime API token to the environment as a network secret: allowed website `api.shelltime.xyz`, header `Authorization`, prefix `CLI`. Anthropic's agent proxy adds it to the daemon's requests outside the session's VM, so sessions never see the token, and the host needs no network access setting. [cloud.bash](cloud.bash) installs the CLI and daemon, connects Claude Code, and adds a SessionStart hook that signs in and starts the daemon in every session. An environment without network secrets can hold the token as `SHELLTIME_TOKEN` in its environment variables instead, with `api.shelltime.xyz` allowed by its network access; the hook uses it when it's set. Guide: [Track your Claude Code cloud sessions](https://shelltime.xyz/blogs/track-claude-code-cloud-sessions).
- **Google Antigravity cloud (OS user `antigravity`, or `SHELLTIME_CLOUD=true`)**: Commit `.agents/hooks.json` to your repository (`shelltime agy install`) and pass your ShellTime API token via `SHELLTIME_TOKEN` (exported in the setup script or set in the project's environment variables). [cloud.bash](cloud.bash) installs the CLI and daemon (automatically targeting the `antigravity` user when setup runs as `root`), saves `SHELLTIME_TOKEN` into `~/.shelltime/config.yaml` when present, and registers a SessionStart hook in `~/.gemini/config/hooks.json` (`shelltime-cloud`) that starts `shelltime-daemon` in every live session. Guide: [Track Cursor and Antigravity with ShellTime](https://shelltime.xyz/blogs/track-cursor-and-antigravity).
- **Cursor Cloud Agents (`CURSOR_CLOUD=true` / `CURSOR_BACKGROUND_AGENT=true`, or `SHELLTIME_CLOUD=true`)**: Commit `.cursor/hooks.json` to your repository (`shelltime cursor install`) and add `SHELLTIME_TOKEN` + `SHELLTIME_CLOUD=true` to the environment's secrets. Run `cloud.bash` in the install step and `~/.shelltime/bin/cloud-start.sh` in the start step (or run `cloud.bash` in the start step directly — when `SHELLTIME_TOKEN` is set, it signs in and starts `shelltime-daemon` immediately). Guide: [Track Cursor and Antigravity with ShellTime](https://shelltime.xyz/blogs/track-cursor-and-antigravity).

[cloud.bash](cloud.bash) never fails the setup script, and outside a cloud environment (no `CLAUDE_CODE_REMOTE=true`, no `antigravity` user, no `CURSOR_CLOUD`/`CURSOR_BACKGROUND_AGENT`, and no `SHELLTIME_CLOUD=true`) it installs nothing.

## What Next?

Once the installation script finishes successfully, you should be able to track your shell time.

Visit [shelltime.xyz](https://shelltime.xyz) for guides and usage documentation.

## Having Issues?

If you encounter any problems during the installation or have any questions, please:
*   Check the output of the script for any error messages.
*   Visit [shelltime.xyz](https://shelltime.xyz) for general help and documentation.
*   [Open an issue on our GitHub repository](https://github.com/shelltime/cli/issues/new/choose)

---

We hope you find shelltime useful!
