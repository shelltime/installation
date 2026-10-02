"""Installer failure paths, using stubs instead of network or home changes."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "install.bash"


class InstallerFailureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="shelltime-installer-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        binary_dir = self.root / "bin"
        binary_dir.mkdir()
        stubs = {
            "uname": '#!/bin/bash\nif [[ "$1" == -s ]]; then echo Linux; else echo x86_64; fi\n',
            "curl": "#!/bin/bash\nexit 22\n",
        }
        for name, body in stubs.items():
            binary = binary_dir / name
            binary.write_text(body)
            binary.chmod(0o755)
        self.env = os.environ.copy()
        self.env["PATH"] = str(binary_dir) + os.pathsep + self.env["PATH"]
        self.env["TMPDIR"] = str(self.root)

    def test_archive_failure_exits_and_cleans_temporary_directory(self):
        result = subprocess.run(
            ["bash", str(SCRIPT)],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.root.glob("shelltime-install.*")), [])
        self.assertNotIn("Installation complete!", result.stdout)

    def test_hook_failure_preserves_working_file(self):
        hooks = self.root / "hooks"
        hooks.mkdir()
        original = hooks / "bash.bash"
        original.write_text("working hook")
        source = SCRIPT.read_text()
        start = source.index("process_file() {")
        end = source.index("\n# Function to add source", start)
        command = (
            'set -euo pipefail\nhooks_path="$1"\n'
            + source[start:end]
            + "\nprocess_file bash.bash https://example.invalid/hook"
        )
        result = subprocess.run(
            ["bash", "-c", command, "installer-test", str(hooks)],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(original.read_text(), "working hook")
        self.assertEqual(list(hooks.glob("bash.bash.*")), [])


if __name__ == "__main__":
    unittest.main()
