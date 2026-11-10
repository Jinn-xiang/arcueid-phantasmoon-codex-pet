"""Release checks. All installer writes are confined to temporary fake app homes."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "pet" / "phantasmoon"


class ReleaseTests(unittest.TestCase):
    def test_manifest_and_png(self):
        manifest = json.loads((ASSETS / "pet.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["displayName"], "Phantasmoon")
        self.assertEqual(manifest["spriteVersionNumber"], 2)
        self.assertEqual(manifest["spritesheetPath"], "spritesheet.png")
        data = (ASSETS / "spritesheet.png").read_bytes()
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(struct.unpack(">IIBB", data[16:26]), (1536, 2288, 8, 6))
        release = json.loads((ROOT / "release.json").read_text(encoding="utf-8"))
        self.assertEqual(release["framesPerRow"], [6, 8, 8, 4, 5, 8, 6, 6, 6, 8, 8])
        for name, expected in release["sha256"].items():
            self.assertEqual(hashlib.sha256((ROOT / name).read_bytes()).hexdigest(), expected)
            for script in ("install.sh", "install.ps1"):
                self.assertIn(expected, (ROOT / script).read_text(encoding="ascii"))

    def test_public_payload_has_no_account_binding(self):
        manifest = json.loads((ASSETS / "pet.json").read_text(encoding="utf-8"))
        self.assertEqual(set(manifest), {"displayName", "description", "spriteVersionNumber", "spritesheetPath"})
        for name in ("README.md", "release.json", "install.sh", "install.ps1"):
            text = (ROOT / name).read_text(encoding="utf-8")
            self.assertIsNone(re.search(r"pet_[0-9a-f]{20,}|/Users/[^/\s]+/|[?&](?:sig|token)=", text))


RUNNERS = []
if os.name != "nt" and Path("/bin/bash").exists():
    RUNNERS.append(("bash", "/bin/bash"))
ps = shutil.which("powershell.exe") or shutil.which("pwsh")
if ps:
    RUNNERS.append(("powershell", ps))


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="phantasmoon-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)

    def run_installer(self, kind, binary, app_state, *, assets=ASSETS, dry=False, env=None):
        if kind == "bash":
            command = [binary, str(ROOT / "install.sh"), "--codex-home", str(app_state), "--asset-root", str(assets)]
            if dry:
                command.append("--dry-run")
        else:
            command = [binary, "-NoProfile", "-NonInteractive", "-File", str(ROOT / "install.ps1"),
                       "-CodexHome", str(app_state), "-AssetRoot", str(assets)]
            if dry:
                command.append("-DryRun")
        return subprocess.run(command, env=env, capture_output=True, text=True, timeout=45)

    def each_runner(self):
        if not RUNNERS:
            self.skipTest("No supported installer runtime found")
        for kind, binary in RUNNERS:
            app_state = self.base / (kind + " App State [test] 中文")
            app_state.mkdir()
            yield kind, binary, app_state

    def assert_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def assert_payload(self, target):
        for name in ("pet.json", "spritesheet.png"):
            self.assertEqual((target / name).read_bytes(), (ASSETS / name).read_bytes())

    def assert_no_temporary_files(self, app_state):
        self.assertFalse(list(app_state.glob(".phantasmoon-*")))

    def test_install_and_idempotent_reinstall(self):
        for kind, binary, app_state in self.each_runner():
            with self.subTest(runtime=kind):
                self.assert_ok(self.run_installer(kind, binary, app_state))
                target = app_state / "pets/phantasmoon"
                self.assert_payload(target)
                (target / "extra.txt").write_text("keep me", encoding="ascii")
                self.assert_ok(self.run_installer(kind, binary, app_state))
                self.assertEqual((target / "extra.txt").read_text(), "keep me")
                self.assertFalse((app_state / "pet-backups").exists())
                self.assert_no_temporary_files(app_state)

    def test_update_preserves_complete_old_pet_and_other_pets(self):
        for kind, binary, app_state in self.each_runner():
            with self.subTest(runtime=kind):
                target = app_state / "pets/phantasmoon"
                target.mkdir(parents=True)
                (target / "pet.json").write_bytes(b"old manifest")
                (target / "spritesheet.png").write_bytes(b"old image")
                (target / "marker.txt").write_bytes(b"private local addition")
                other = app_state / "pets/other-pet"
                other.mkdir()
                (other / "pet.json").write_bytes(b"untouched")
                self.assert_ok(self.run_installer(kind, binary, app_state))
                self.assert_payload(target)
                backups = list((app_state / "pet-backups/phantasmoon").iterdir())
                self.assertEqual(len(backups), 1)
                self.assertEqual((backups[0] / "pet.json").read_bytes(), b"old manifest")
                self.assertEqual((backups[0] / "spritesheet.png").read_bytes(), b"old image")
                self.assertEqual((backups[0] / "marker.txt").read_bytes(), b"private local addition")
                self.assertEqual((other / "pet.json").read_bytes(), b"untouched")
                self.assert_no_temporary_files(app_state)

    def test_corrupt_payload_never_replaces_existing_pet(self):
        bad = self.base / "corrupt payload"
        shutil.copytree(ASSETS, bad)
        with (bad / "spritesheet.png").open("ab") as stream:
            stream.write(b"corruption")
        for kind, binary, app_state in self.each_runner():
            with self.subTest(runtime=kind):
                target = app_state / "pets/phantasmoon"
                target.mkdir(parents=True)
                (target / "marker").write_bytes(b"previous version")
                result = self.run_installer(kind, binary, app_state, assets=bad)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("checksum mismatch", result.stdout + result.stderr)
                self.assertEqual(list(target.iterdir()), [target / "marker"])
                self.assertEqual((target / "marker").read_bytes(), b"previous version")
                self.assertFalse((app_state / "pet-backups").exists())
                self.assert_no_temporary_files(app_state)

    def test_dry_run_and_missing_home_do_not_write(self):
        for kind, binary, app_state in self.each_runner():
            with self.subTest(runtime=kind):
                self.assert_ok(self.run_installer(kind, binary, app_state, dry=True))
                self.assertEqual(list(app_state.iterdir()), [])
                missing = app_state / "missing"
                self.assertNotEqual(self.run_installer(kind, binary, missing).returncode, 0)
                self.assertFalse(missing.exists())

    def test_lock_is_respected(self):
        for kind, binary, app_state in self.each_runner():
            with self.subTest(runtime=kind):
                lock = app_state / ".phantasmoon-install.lock"
                if kind == "bash":
                    lock.mkdir()
                else:
                    lock.write_bytes(b"another installer")
                self.assertNotEqual(self.run_installer(kind, binary, app_state).returncode, 0)
                self.assertTrue(lock.exists())
                self.assertFalse((app_state / "pets").exists())

    @unittest.skipIf(os.name == "nt", "POSIX symlink test")
    def test_symlink_target_is_rejected(self):
        for kind, binary, app_state in self.each_runner():
            with self.subTest(runtime=kind):
                outside = app_state / "outside"
                outside.mkdir()
                (outside / "marker").write_bytes(b"untouched")
                (app_state / "pets").mkdir()
                (app_state / "pets/phantasmoon").symlink_to(outside, target_is_directory=True)
                self.assertNotEqual(self.run_installer(kind, binary, app_state).returncode, 0)
                self.assertEqual(list(outside.iterdir()), [outside / "marker"])
                self.assert_no_temporary_files(app_state)

    @unittest.skipUnless(Path("/bin/bash").exists() and os.name != "nt", "Bash-only fault injection")
    def test_bash_rolls_back_if_final_move_fails(self):
        app_state = self.base / "rollback"
        target = app_state / "pets/phantasmoon"
        target.mkdir(parents=True)
        (target / "marker").write_bytes(b"previous version")
        mock_bin = self.base / "mock-bin"
        mock_bin.mkdir()
        mock_mv = mock_bin / "mv"
        mock_mv.write_text('#!/bin/bash\ncase "$1" in */payload) exit 19 ;; esac\nexec /bin/mv "$@"\n', encoding="ascii")
        mock_mv.chmod(0o755)
        env = os.environ.copy()
        env["PATH"] = str(mock_bin) + os.pathsep + env.get("PATH", "")
        result = self.run_installer("bash", "/bin/bash", app_state, env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((target / "marker").read_bytes(), b"previous version")
        self.assert_no_temporary_files(app_state)

    @unittest.skipUnless(Path("/bin/bash").exists() and os.name != "nt", "Bash profile isolation")
    def test_explicit_pro_ignores_conflicting_shell_codex_home(self):
        user = self.base / "fake-user"
        pro = user / ".codex-pro"
        codex = user / ".codex"
        pro.mkdir(parents=True)
        codex.mkdir()
        env = os.environ.copy()
        # These variables are isolated in the child test process, never the session.
        env.update(HOME=str(user), CODEX_HOME=str(codex))
        result = subprocess.run(["/bin/bash", str(ROOT / "install.sh"), "--app", "pro"],
                                env=env, capture_output=True, text=True, timeout=45)
        self.assert_ok(result)
        self.assert_payload(pro / "pets/phantasmoon")
        self.assertEqual(list(codex.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
