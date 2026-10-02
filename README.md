# shelltime Installation

Welcome to shelltime! This guide will help you install the necessary tools using a simple command.

## Quick Install

The installer supports macOS and Linux (including WSL). Failed downloads stop installation and preserve existing shell hooks.

You can install shelltime tools by running the following command in your terminal:

```bash
curl -sSL https://shelltime.xyz/i | bash
```

## What Next?

Once the installation script finishes successfully, you should be able to track your shell time.

Visit [shelltime.xyz](https://shelltime.xyz) for guides and usage documentation.

## Testing

Run `python3 -m unittest discover -s tests` to check download failures and hook preservation without network requests or changes to your shell configuration.

## Having Issues?

If you encounter any problems during the installation or have any questions, please:
*   Check the output of the script for any error messages.
*   Visit [shelltime.xyz](https://shelltime.xyz) for general help and documentation.
*   [Open an issue on our GitHub repository](https://github.com/shelltime/cli/issues/new/choose)

---

We hope you find shelltime useful!
