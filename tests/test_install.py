"""Installer regressions using isolated homes, local archives, and network stubs."""

import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "install.bash"


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="shelltime-installer-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.binary_dir = self.root / "bin"
        self.binary_dir.mkdir()
        self.home = self.root / "home with spaces"
        self.home.mkdir()
        self.hooks = self.home / ".shelltime/hooks"
        self.hooks.mkdir(parents=True)
        self.env = os.environ.copy()
        self.env.update({
            "HOME": str(self.home),
            "PATH": str(self.binary_dir) + os.pathsep + self.env["PATH"],
            "TMPDIR": str(self.root),
            "STUB_OS": "Linux",
            "STUB_ARCH": "x86_64",
            "CURL_LOG": str(self.root / "curl.log"),
            "DAEMON_LOG": str(self.root / "daemon.log"),
        })
        self.stub("uname", 'if [[ "$1" == -s ]]; then echo "$STUB_OS"; else echo "$STUB_ARCH"; fi')
        self.stub("curl", "exit 22")
        self.stub("fish", "exit 0")
        self.stub("shelltime", 'echo "$*" >> "$DAEMON_LOG"')

    def stub(self, name, body):
        binary = self.binary_dir / name
        binary.write_text("#!/bin/bash\nset -euo pipefail\n" + body + "\n")
        binary.chmod(0o755)

    def run_script(self, command=None, *args):
        argv = ["bash", str(SCRIPT)] if command is None else [
            "bash", "-c", 'source "$1"; shift; ' + command,
            "installer-test", str(SCRIPT), *map(str, args),
        ]
        return subprocess.run(argv, env=self.env, capture_output=True, text=True, timeout=10)

    def enable_downloads(self, failed_hook=""):
        archive = self.root / "release.tar.gz"
        with tarfile.open(archive, "w:gz") as bundle:
            for name in ("shelltime", "shelltime-daemon"):
                body = b"#!/bin/bash\nexit 0\n"
                entry = tarfile.TarInfo(name)
                entry.size = len(body)
                entry.mode = 0o755
                bundle.addfile(entry, io.BytesIO(body))
        self.env["STUB_ARCHIVE"] = str(archive)
        self.env["FAILED_HOOK"] = failed_hook
        self.stub("curl", '''
url="${@: -1}"
output=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output="$2"; shift 2 ;;
        https://*) url="$1"; shift ;;
        *) shift ;;
    esac
done
echo "$url" >> "$CURL_LOG"
if [[ -z "$output" ]]; then
    cp "$STUB_ARCHIVE" "$(basename "$url")"
elif [[ -n "$FAILED_HOOK" && "$url" == */"$FAILED_HOOK" ]]; then
    exit 22
else
    echo "# updated hook" > "$output"
fi''')

    def test_archive_failure_exits_and_cleans_temporary_directory(self):
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.root.glob("shelltime-install.*")), [])
        self.assertNotIn("Installation complete!", result.stdout)
        self.assertEqual(list(self.home.glob(".shelltime/bin/*")), [])

    def test_hook_failure_preserves_working_file_and_backup(self):
        original = self.hooks / "bash.bash"
        backup = self.hooks / "bash.bash.bak"
        original.write_text("working hook")
        backup.write_text("previous backup")
        result = self.run_script(
            'hooks_path="$1"; process_file bash.bash https://example.invalid/hook', self.hooks,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(original.read_text(), "working hook")
        self.assertEqual(backup.read_text(), "previous backup")
        self.assertEqual(sorted(p.name for p in self.hooks.iterdir()), ["bash.bash", "bash.bash.bak"])

    def test_hook_success_updates_backup_and_sets_permissions(self):
        self.enable_downloads()
        original = self.hooks / "bash.bash"
        backup = self.hooks / "bash.bash.bak"
        original.write_text("working hook")
        backup.write_text("previous backup")
        result = self.run_script(
            'hooks_path="$1"; process_file bash.bash https://example.invalid/hook', self.hooks,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(original.read_text(), "# updated hook\n")
        self.assertEqual(backup.read_text(), "working hook")
        self.assertEqual(original.stat().st_mode & 0o777, 0o644)

    def test_legacy_and_duplicate_source_lines_are_migrated_once(self):
        config = self.home / ".bashrc"
        hook = self.hooks / "bash.bash"
        hook.write_text('loads=$(( ${loads:-0} + 1 ))\n')
        config.write_text(f'# user config\nsource {hook}\nsource "{hook}"\n')
        result = self.run_script(
            'add_source_to_config "$1" "$2"; add_source_to_config "$1" "$2"; '
            'loads=0; source "$1"; echo "$loads"', config, hook,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "1")
        self.assertEqual(config.read_text(), f'# user config\nsource "{hook}"\n')

    def test_new_source_line_with_spaces_is_idempotent(self):
        config = self.home / ".bashrc"
        hook = self.hooks / "bash.bash"
        config.write_text("# keep me\n")
        hook.write_text('echo "hook loaded"\n')
        result = self.run_script(
            'add_source_to_config "$1" "$2"; add_source_to_config "$1" "$2"; source "$1"',
            config, hook,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "hook loaded")
        self.assertEqual(config.read_text(), f'# keep me\nsource "{hook}"\n')

    def test_partial_hook_failure_continues_setup_and_exits_nonzero(self):
        self.enable_downloads(failed_hook="fish.fish")
        fish = self.hooks / "fish.fish"
        fish.write_text("working fish hook")
        fish.with_suffix(".fish.bak").write_text("previous fish backup")
        (self.home / ".bashrc").touch()
        (self.home / ".zshrc").touch()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Installation incomplete", result.stderr)
        self.assertNotIn("Installation complete!", result.stdout)
        self.assertEqual(fish.read_text(), "working fish hook")
        self.assertEqual(fish.with_suffix(".fish.bak").read_text(), "previous fish backup")
        for name in ("zsh.zsh", "bash.bash", "bash-preexec.sh"):
            self.assertEqual((self.hooks / name).read_text(), "# updated hook\n")
        self.assertIn(f'source "{self.hooks}/bash.bash"', (self.home / ".bashrc").read_text())
        self.assertIn(f'source "{self.hooks}/zsh.zsh"', (self.home / ".zshrc").read_text())
        self.assertEqual((self.root / "daemon.log").read_text(), "daemon reinstall\n")
        self.assertEqual(list(self.root.glob("shelltime-install.*")), [])

    def test_successful_install_is_repeatable_with_a_spaced_home(self):
        self.enable_downloads()
        (self.home / ".bashrc").touch()
        for _ in range(2):
            result = self.run_script()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Installation complete!", result.stdout)
        config = (self.home / ".bashrc").read_text()
        self.assertEqual(config.count(f'source "{self.hooks}/bash.bash"'), 1)
        self.assertEqual((self.home / ".shelltime/bin/shelltime").stat().st_mode & 0o777, 0o755)
        self.assertEqual(list(self.root.glob("shelltime-install.*")), [])

    def test_linux_arm_architectures_use_arm64_archives(self):
        for arch in ("arm64", "aarch64"):
            with self.subTest(arch=arch):
                result = self.run_script(
                    'OS=Linux; ARCH="$1"; get_download_url https://example.invalid/cli_', arch,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "https://example.invalid/cli_Linux_arm64.tar.gz")

    def test_unsupported_os_fails_before_downloads(self):
        self.env["STUB_OS"] = "FreeBSD"
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsupported OS: FreeBSD", result.stderr)
        self.assertFalse((self.root / "curl.log").exists())

    def test_piped_install_runs_platform_checks(self):
        self.env["STUB_OS"] = "FreeBSD"
        result = subprocess.run(
            ["bash"], input=SCRIPT.read_text(), env=self.env,
            capture_output=True, text=True, timeout=10,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsupported OS: FreeBSD", result.stderr)

    def test_failed_new_hook_is_not_sourced(self):
        self.enable_downloads(failed_hook="fish.fish")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        fish_config = self.home / ".config/fish/config.fish"
        self.assertNotIn("source ", fish_config.read_text())
        self.assertFalse((self.hooks / "fish.fish").exists())
        self.assertTrue((self.hooks / "bash.bash").exists())

    def test_config_without_trailing_newline_is_preserved(self):
        config = self.home / ".bashrc"
        hook = self.hooks / "bash.bash"
        config.write_text("# existing config")
        result = self.run_script('add_source_to_config "$1" "$2"', config, hook)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(config.read_text(), f'# existing config\nsource "{hook}"\n')

    def test_symlinked_config_target_and_permissions_are_preserved(self):
        target = self.home / "shared.bashrc"
        target.write_text("# shared config\n")
        target.chmod(0o640)
        config = self.home / ".bashrc"
        config.symlink_to(target.name)
        hook = self.hooks / "bash.bash"
        result = self.run_script('add_source_to_config "$1" "$2"', config, hook)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(config.is_symlink())
        self.assertEqual(os.readlink(config), target.name)
        self.assertEqual(target.read_text(), f'# shared config\nsource "{hook}"\n')
        self.assertEqual(target.stat().st_mode & 0o777, 0o640)

    def test_interrupted_hook_download_cleans_pending_files(self):
        self.enable_downloads()
        original = self.hooks / "zsh.zsh"
        original.write_text("working hook")
        curl = self.binary_dir / "curl"
        curl.write_text(curl.read_text().replace(
            'echo "# updated hook" > "$output"', 'kill -TERM "$PPID"\n    exit 143',
        ))
        result = self.run_script()
        self.assertEqual(result.returncode, 143, result.stderr)
        self.assertEqual(original.read_text(), "working hook")
        self.assertEqual(list(self.hooks.glob("zsh.zsh.*")), [])
        self.assertEqual(list(self.root.glob("shelltime-install.*")), [])

    def test_sourcing_helpers_preserves_the_callers_exit_trap(self):
        result = self.run_script('trap "echo preserved" EXIT; source "$1"', SCRIPT)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "preserved")


if __name__ == "__main__":
    unittest.main()
