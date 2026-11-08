"""CLI rename regression tests. All installations, downloads, and processes are fixtures."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class OmniClockCLITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="omniclock-cli-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin with spaces"
        self.bin.mkdir()
        self.home = self.root / "home"
        self.home.mkdir()
        self.tmp = self.root / "tmp"
        self.tmp.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), TMPDIR=str(self.tmp),
                        PATH=str(self.bin) + ":/usr/bin:/bin:/usr/sbin:/sbin")
        self.env.pop("TOKENCLOCK_INSTALL_URL", None)
        for name in ("omniclock", "tokenclock"):
            shutil.copy2(ROOT / "cli" / name, self.bin / name)
        self.trace = self.root / "calls.txt"
        self.env["CLI_TEST_TRACE"] = str(self.trace)

    def executable(self, name, body):
        path = self.bin / name
        path.write_text(body)
        path.chmod(0o755)
        return path

    def invoke(self, name, *arguments, check=True):
        return subprocess.run([str(self.bin / name), *arguments], env=self.env,
                              text=True, capture_output=True, check=check)

    def fake_download(self, installer):
        payload = self.root / "downloaded-installer.sh"
        payload.write_text(installer)
        self.env["CLI_TEST_INSTALLER"] = str(payload)
        self.executable("curl", '''#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$CLI_TEST_TRACE"
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then shift; cp "$CLI_TEST_INSTALLER" "$1"; exit 0; fi
  shift
done
exit 2
''')
        for name in ("pgrep", "pkill", "launchctl"):
            self.executable(name, '#!/usr/bin/env bash\nprintf "UNEXPECTED_PROCESS_CALL\\n" >> "$CLI_TEST_TRACE"\nexit 1\n')
        self.executable("codesign", '#!/usr/bin/env bash\nexit 1\n')

    def test_help_matches_and_legacy_standalone_download_still_runs(self):
        new = self.invoke("omniclock", "help").stdout
        old = self.invoke("tokenclock", "help").stdout
        self.assertEqual(new, old)
        self.assertIn("OmniClock", new)
        self.assertIn("omniclock update", new)
        standalone = self.root / "standalone" / "tokenclock"
        standalone.parent.mkdir()
        shutil.copy2(ROOT / "cli/omniclock", standalone)
        result = subprocess.run([str(standalone), "help"], env=self.env,
                                check=True, capture_output=True, text=True)
        self.assertEqual(result.stdout, new)

    def test_compatibility_preserves_arguments_exit_status_and_path_fallback(self):
        result_file = self.root / "argv.json"
        self.env["CLI_TEST_ARGS"] = str(result_file)
        self.executable("omniclock", '''#!/usr/bin/env bash
printf '%s\\0' "$@" > "$CLI_TEST_ARGS"
exit 37
''')
        args = ["update", "--normal", "a path with spaces", "literal$VALUE", "semicolon;literal", ""]
        result = self.invoke("tokenclock", *args, check=False)
        self.assertEqual(result.returncode, 37)
        self.assertEqual(result_file.read_bytes().split(b"\0")[:-1], [a.encode() for a in args])
        legacy = self.root / "another directory" / "tokenclock"
        legacy.parent.mkdir()
        shutil.copy2(ROOT / "cli/tokenclock", legacy)
        result = subprocess.run([str(legacy), *args], env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 37)

    def test_old_and_new_check_download_same_source_without_runtime_changes(self):
        sentinel = self.home / ".tokenclock/normal/TokenClock"
        sentinel.parent.mkdir(parents=True)
        sentinel.write_bytes(b"existing runtime must not change")
        digest = hashlib.sha256(sentinel.read_bytes()).hexdigest()
        self.fake_download('#!/usr/bin/env bash\necho SHOULD_NOT_EXECUTE >> "$CLI_TEST_TRACE"\n')
        for name in ("tokenclock", "omniclock"):
            result = self.invoke(name, "update", "--check")
            self.assertIn("no upgrade performed", result.stdout)
        calls = self.trace.read_text()
        self.assertEqual(calls.count("https://www.ailyre.com/omniclock/install.sh"), 2)
        self.assertNotIn("SHOULD_NOT_EXECUTE", calls)
        self.assertNotIn("UNEXPECTED_PROCESS_CALL", calls)
        self.assertEqual(hashlib.sha256(sentinel.read_bytes()).hexdigest(), digest)

    def test_cli_only_update_keeps_legacy_override_and_does_not_restart(self):
        self.env["TOKENCLOCK_INSTALL_URL"] = "https://updates.example.invalid/custom/install.sh"
        self.fake_download('''#!/usr/bin/env bash
# BEGIN MACOS SIGNATURE POLICY
printf 'ARGS=%s\\n' "$*" >> "$CLI_TEST_TRACE"
printf 'DEPLOYED=0\\nCLI_UPDATED=1\\n' > "$TOKENCLOCK_STATUS_FILE"
''')
        for name in ("tokenclock", "omniclock"):
            result = self.invoke(name, "update", "--normal")
            self.assertIn("does not need a restart", result.stdout)
        calls = self.trace.read_text()
        self.assertEqual(calls.count("https://updates.example.invalid/custom/install.sh"), 2)
        self.assertEqual(calls.count("ARGS=--no-start --normal"), 2)
        self.assertNotIn("UNEXPECTED_PROCESS_CALL", calls)

    def install_helper(self, source=True):
        text = (ROOT / "cli/install.sh").read_text()
        block = text.split("# BEGIN OMNICLOCK CLI INSTALL\n", 1)[1].split("# END OMNICLOCK CLI INSTALL", 1)[0]
        builds = self.root / "build source"
        if source:
            directory = builds / "main/cli"
            directory.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / "cli/omniclock", directory / "omniclock")
        helper = self.root / "install-cli.sh"
        helper.write_text('''#!/usr/bin/env bash
set -eu
BIN_DIR="$1"
BUILD_DIR="$2"
INSTALL_URL="https://www.ailyre.com/omniclock/install.sh"
BRANCHES=(main)
WRAPPER_TMP=""; COMPAT_TMP=""
trap '[ -z "$WRAPPER_TMP" ] || rm -f "$WRAPPER_TMP"; [ -z "$COMPAT_TMP" ] || rm -f "$COMPAT_TMP"' EXIT
say() { :; }
step() { :; }
die() { printf '%s\\n' "$*" >&2; exit 1; }
sha256_file() { shasum -a 256 "$1" | cut -d' ' -f1; }
''' + block + '\ninstall_cli_commands\nprintf "CLI_UPDATED=%s\\n" "$WRAPPER_CHANGED"\n')
        helper.chmod(0o755)
        return helper, builds

    def test_installer_installs_both_commands_and_is_idempotent(self):
        helper, builds = self.install_helper()
        (self.bin / "omniclock").unlink()
        (self.bin / "tokenclock").write_text("old standalone wrapper\n")
        args = ["/bin/bash", str(helper), str(self.bin), str(builds)]
        first = subprocess.run(args, env=self.env, capture_output=True, text=True, check=True)
        self.assertIn("CLI_UPDATED=1", first.stdout)
        self.assertEqual((self.bin / "omniclock").read_bytes(), (ROOT / "cli/omniclock").read_bytes())
        self.assertEqual((self.bin / "tokenclock").read_bytes(), (ROOT / "cli/tokenclock").read_bytes())
        self.assertEqual(self.invoke("omniclock", "help").stdout, self.invoke("tokenclock", "help").stdout)
        again = subprocess.run(args, env=self.env, capture_output=True, text=True, check=True)
        self.assertIn("CLI_UPDATED=0", again.stdout)
        self.assertFalse(list(self.bin.glob(".*.new.*")))

    def test_running_old_wrapper_survives_atomic_install(self):
        helper, builds = self.install_helper()
        old = self.bin / "tokenclock"
        old.write_text('#!/usr/bin/env bash\nbash "$@"\n' + '# old script padding\n' * 5000 + 'printf "OLD_PROCESS_FINISHED\\n"\n')
        old.chmod(0o755)
        result = subprocess.run([str(old), str(helper), str(self.bin), str(builds)], env=self.env,
                                text=True, capture_output=True, check=True)
        self.assertIn("OLD_PROCESS_FINISHED", result.stdout)
        self.assertEqual((self.bin / "tokenclock").read_bytes(), (ROOT / "cli/tokenclock").read_bytes())

    def test_cached_legacy_source_downloads_the_canonical_cli(self):
        helper, builds = self.install_helper(source=False)
        old_source = builds / "main/cli/tokenclock"
        old_source.parent.mkdir(parents=True)
        old_source.write_text("#!/usr/bin/env bash\nexit 99\n")
        self.fake_download((ROOT / "cli/omniclock").read_text())
        result = subprocess.run(["/bin/bash", str(helper), str(self.bin), str(builds)], env=self.env,
                                capture_output=True, text=True, check=True)
        self.assertIn("https://www.ailyre.com/omniclock/omniclock", self.trace.read_text())
        self.assertEqual((self.bin / "omniclock").read_bytes(), (ROOT / "cli/omniclock").read_bytes())
        self.assertEqual(self.invoke("tokenclock", "help").stdout, self.invoke("omniclock", "help").stdout)

    def test_failed_download_preserves_existing_commands(self):
        helper, builds = self.install_helper(source=False)
        before = {p.name: p.read_bytes() for p in [self.bin / "omniclock", self.bin / "tokenclock"]}
        self.executable("curl", '#!/usr/bin/env bash\nexit 22\n')
        result = subprocess.run(["/bin/bash", str(helper), str(self.bin), str(builds)], env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual({name: (self.bin / name).read_bytes() for name in before}, before)
        self.assertFalse(list(self.bin.glob(".*.new.*")))


if __name__ == "__main__":
    unittest.main()
