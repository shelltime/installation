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

The environment also needs your ShellTime API token as `SHELLTIME_TOKEN` in its environment variables, and `api.shelltime.xyz` allowed by its network access. [cloud.bash](cloud.bash) installs the CLI and daemon, connects Claude Code, and adds a SessionStart hook that signs in with the token and starts the daemon in every session. It never fails the setup script. The full guide: [Track your Claude Code cloud sessions](https://shelltime.xyz/blogs/track-claude-code-cloud-sessions).

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
