# shelltime Installation

Welcome to shelltime! This guide will help you install the necessary tools using a simple command.

## Quick Install

You can install shelltime tools by running the following command in your terminal:

```bash
curl -sSL https://shelltime.xyz/i | bash
```

## Claude Code Cloud Environments

To track Claude Code sessions that run in the cloud ([claude.ai/code](https://claude.ai/code)), add this line to the cloud environment's setup script:

```bash
curl -fsSL https://raw.githubusercontent.com/shelltime/installation/main/cloud.bash | bash
```

Then add your ShellTime API token to the environment as a network secret: allowed website `api.shelltime.xyz`, header `Authorization`, prefix `CLI`. Anthropic's agent proxy adds it to the daemon's requests outside the session's VM, so sessions never see the token, and the host needs no network access setting. [cloud.bash](cloud.bash) installs the CLI and daemon, connects Claude Code, and adds a SessionStart hook that signs in and starts the daemon in every session. An environment without network secrets can hold the token as `SHELLTIME_TOKEN` in its environment variables instead, with `api.shelltime.xyz` allowed by its network access; the hook uses it when it's set. It never fails the setup script, and outside a cloud environment (where `CLAUDE_CODE_REMOTE` isn't `true`) it installs nothing. The full guide: [Track your Claude Code cloud sessions](https://shelltime.xyz/blogs/track-claude-code-cloud-sessions).

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
