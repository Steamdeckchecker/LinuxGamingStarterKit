"""Offline desktop launcher checks; only harmless stub installers are run."""
import base64
import configparser
import ctypes
from ctypes.util import find_library
import hashlib
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from desktop_launcher import build_desktop, FILENAME


class DesktopLauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.receipt = self.root / "receipt"
        self.installer = b'''#!/bin/bash
set -euo pipefail
test "$STARTER_KIT_TERMINAL" = 1
printf '%s' "$0" > "$LHSK_TEST_RECEIPT"
sleep .05
test -f "$0"
printf 'stub installer finished\\n'
'''
        self.path = self.root / "Folder with spaces – 测试" / FILENAME
        self.path.parent.mkdir()
        self.path.write_text(build_desktop(self.installer))
        self.path.chmod(0o755)

    def config(self):
        config = configparser.ConfigParser(interpolation=None)
        config.optionxform = str
        config.read(self.path, encoding="utf-8")
        return config["Desktop Entry"]

    def run_launcher(self, location=None):
        args = shlex.split(self.config()["Exec"])
        self.assertEqual(args[0], "python3")
        self.assertEqual(args[-1], "%k")
        args[0] = sys.executable
        args[-1] = str(self.path) if location is None else location
        return subprocess.run(args, input="", capture_output=True, text=True, timeout=5,
                              env={**os.environ, "LANG": "en_US.UTF-8", "LC_ALL": "", "LC_MESSAGES": "", "LHSK_TEST_RECEIPT": str(self.receipt)})

    def test_embedded_bytes_hash_and_terminal_setting(self):
        entry = self.config()
        self.assertEqual(base64.b64decode(entry["X-Starter-Kit-Installer-Base64"]), self.installer)
        self.assertEqual(entry["X-Starter-Kit-Installer-SHA256"], hashlib.sha256(self.installer).hexdigest())
        self.assertEqual(entry["Terminal"], "true")
        self.assertEqual(entry["Exec"].count("%k"), 1)
        for language in ("de", "es", "fr", "ru", "zh", "ja"):
            self.assertIn("Comment[" + language + "]", entry)

    def test_glib_desktop_parser_accepts_file(self):
        library = find_library("gio-2.0")
        if not library:
            self.skipTest("GIO is not installed")
        gio = ctypes.CDLL(library)
        gio.g_desktop_app_info_new_from_filename.argtypes = [ctypes.c_char_p]
        gio.g_desktop_app_info_new_from_filename.restype = ctypes.c_void_p
        application = gio.g_desktop_app_info_new_from_filename(os.fsencode(self.path))
        self.assertTrue(application)
        gio.g_app_info_get_executable.argtypes = [ctypes.c_void_p]
        gio.g_app_info_get_executable.restype = ctypes.c_char_p
        self.assertEqual(gio.g_app_info_get_executable(application), b"python3")
        gio.g_object_unref.argtypes = [ctypes.c_void_p]
        gio.g_object_unref(application)

    def test_path_with_spaces_waits_for_installer_then_cleans_up(self):
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("stub installer finished", result.stdout)
        self.assertFalse(Path(self.receipt.read_text()).exists())

    def test_percent_encoded_file_uri_is_supported(self):
        result = self.run_launcher(self.path.as_uri())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("stub installer finished", result.stdout)

    def test_corrupt_payload_or_checksum_never_runs(self):
        for key, value in (("X-Starter-Kit-Installer-Base64", "invalid%%%"), ("X-Starter-Kit-Installer-SHA256", "0" * 64)):
            with self.subTest(key=key):
                text = build_desktop(self.installer)
                text = "\n".join(key + "=" + value if line.startswith(key + "=") else line for line in text.splitlines()) + "\n"
                self.path.write_text(text)
                result = self.run_launcher()
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.receipt.exists())

    def test_remote_location_is_rejected_without_downloading(self):
        result = self.run_launcher("https://example.invalid/launcher.desktop")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("local file", result.stderr)
        self.assertFalse(self.receipt.exists())

    def test_installer_failure_is_returned(self):
        self.path.write_text(build_desktop(b"#!/bin/bash\nexit 7\n"))
        result = self.run_launcher()
        self.assertEqual(result.returncode, 7)
        self.assertIn("exit 7", result.stderr)


if __name__ == "__main__":
    unittest.main()
