# shelltime Installation

Welcome to shelltime! This guide will help you install the necessary tools using a simple command.

## Quick Install

The installer supports macOS and Linux (including WSL). A failed binary download
stops installation. If a hook download fails, its existing hook and backup are
preserved while the remaining hooks and daemon setup continue. The installer
then exits with an error so you can retry. Upgrades migrate existing source lines
without loading hooks twice.

You can install shelltime tools by running the following command in your terminal:

```bash
curl -sSL https://shelltime.xyz/i | bash
```

## What Next?

Once the installation script finishes successfully, you should be able to track your shell time.

Visit [shelltime.xyz](https://shelltime.xyz) for guides and usage documentation.

## Testing

Run `python3 -m unittest discover -s tests` to check upgrades, download failures,
paths containing spaces, and platform detection without network requests or
changes to your shell configuration. CI runs these tests on Linux and macOS.

## Having Issues?

If you encounter any problems during the installation or have any questions, please:
*   Check the output of the script for any error messages.
*   Visit [shelltime.xyz](https://shelltime.xyz) for general help and documentation.
*   [Open an issue on our GitHub repository](https://github.com/shelltime/cli/issues/new/choose)

---

We hope you find shelltime useful!
