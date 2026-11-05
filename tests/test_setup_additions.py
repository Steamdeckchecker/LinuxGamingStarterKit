"""Exercise desktop links and the bundled wallpaper without a real desktop."""
import base64
import configparser
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest
from unittest.mock import Mock, patch
import zlib

from test_starterkit import Base, kit

ROOT = Path(__file__).resolve().parents[1]


class DesktopLinksTests(Base):
    def setUp(self):
        super().setUp()
        self.wizard.base = ROOT
        self.environment = patch.dict(os.environ, {
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "XDG_DATA_HOME": str(self.home / "user data"),
            "XDG_STATE_HOME": str(self.home / ".local/state"),
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def test_localized_desktop_links_have_exact_urls_original_icons_and_no_question(self):
        config = self.home / ".config/user-dirs.dirs"
        config.parent.mkdir()
        config.write_text('XDG_DESKTOP_DIR="$HOME/Mein Schreibtisch"\n')
        self.ui.question = Mock(side_effect=AssertionError("Automatic links must not ask"))
        with patch.object(kit.shutil, "which", return_value=None):
            self.wizard.create_desktop_links()
            self.wizard.create_desktop_links()
        desktop = self.home / "Mein Schreibtisch"
        expected = {
            "Linux-Starterkit.desktop": "https://linux-handheld-starter-kit.cocoabloom514.chatgpt.site/",
            "Steam-Deck-Checker.desktop": "https://www.youtube.com/@SteamDeckChecker",
        }
        for filename, url in expected.items():
            path = desktop / filename
            parser = configparser.ConfigParser(interpolation=None)
            parser.read(path)
            entry = parser["Desktop Entry"]
            self.assertEqual(entry["Type"], "Link")
            self.assertEqual(entry["URL"], url)
            self.assertNotIn("Exec", entry)
            icon = Path(entry["Icon"])
            self.assertEqual(icon.read_bytes(), (ROOT / "assets" / icon.name).read_bytes())
            self.assertTrue(os.access(path, os.X_OK))
        self.assertEqual(len(list(desktop.iterdir())), 2)

    def test_standalone_embedded_icons_work_without_external_assets(self):
        self.wizard.base = self.root / "missing source"
        icons = {p.name: base64.b64encode(zlib.compress(p.read_bytes())).decode("ascii")
                 for p in (ROOT / "assets").glob("*.png")}
        with patch.object(kit, "EMBEDDED_DESKTOP_ICONS", icons), patch.object(kit.shutil, "which", return_value=None):
            self.wizard.create_desktop_links()
        self.assertTrue((self.home / "Desktop/Linux-Starterkit.desktop").is_file())

    def test_xdg_utility_path_and_existing_file_backup_are_used(self):
        desktop = self.home / "Custom desktop"
        desktop.mkdir()
        original = desktop / "Steam-Deck-Checker.desktop"
        original.write_text("existing user content")
        self.wizard.runner.run = Mock(return_value=subprocess.CompletedProcess([], 0, str(desktop) + "\n"))
        with patch.object(kit.shutil, "which", return_value="/usr/bin/xdg-user-dir"):
            self.wizard.create_desktop_links()
        self.assertEqual(original.with_name(original.name + ".starter-kit-backup").read_text(), "existing user content")

    def test_dry_run_never_executes_or_writes(self):
        self.wizard.dry = True
        with patch.object(kit.subprocess, "run", side_effect=AssertionError("No commands")):
            self.wizard.create_desktop_links()
            self.wizard.install_live_wallpaper()
            self.wizard.activate_live_wallpaper()
        self.assertEqual(list(self.home.iterdir()), [])


class WallpaperTests(Base):
    def setUp(self):
        super().setUp()
        self.wizard.base = ROOT
        self.data = self.home / "data"
        self.environment = patch.dict(os.environ, {
            "XDG_DATA_HOME": str(self.data),
            "XDG_CONFIG_HOME": str(self.home / "config"),
            "XDG_STATE_HOME": str(self.home / "state"),
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.wizard.sudo.run = Mock(side_effect=AssertionError("Wallpaper must not use sudo"))

    def test_declining_wallpaper_does_not_install_or_activate(self):
        self.ui.answers = [False]
        self.wizard.install_live_wallpaper = Mock(side_effect=AssertionError("Declined"))
        self.wizard.activate_live_wallpaper = Mock(side_effect=AssertionError("Declined"))
        self.wizard.live_wallpaper()
        self.assertEqual(self.wizard.results[-1]["state"], "skipped")

    def test_failed_install_does_not_activate_and_emulation_can_continue(self):
        self.ui.answers = [True]
        self.wizard.install_live_wallpaper = Mock(side_effect=RuntimeError("QtWebEngine missing"))
        self.wizard.activate_live_wallpaper = Mock(side_effect=AssertionError("Must not activate"))
        self.wizard.live_wallpaper()
        self.assertEqual(self.wizard.results[-1]["state"], "failed")
        self.ui.choices = ["none"]
        self.wizard.emulation()
        self.assertEqual(self.wizard.results[-1]["state"], "skipped")

    def test_plasma5_rejected_before_download(self):
        self.wizard.runner.run = Mock(return_value=subprocess.CompletedProcess([], 0, "plasmashell 5.27.12"))
        self.wizard.network.download = Mock(side_effect=AssertionError("Unsupported desktop"))
        with patch.object(kit.shutil, "which", return_value="/bin/stub"), self.assertRaises(RuntimeError):
            self.wizard.install_live_wallpaper()
        self.assertEqual(self.wizard.runner.run.call_count, 1)

    def test_bundled_original_installer_fresh_install_then_upgrade(self):
        # Run the real supplied installer against isolated stand-ins for KDE.
        # This checks its destination detection without changing the host.
        binaries = self.root / "bin"
        binaries.mkdir()
        commands = {
            "plasmashell": "#!/bin/sh\nprintf 'plasmashell 6.5.0\\n'\n",
            "qdbus6": "#!/bin/sh\nexit 0\n",
            "rpm": "#!/bin/sh\nexit 0\n",
            "kpackagetool6": """#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
args = sys.argv[1:]
root = pathlib.Path(args[args.index("--packageroot") + 1])
action = "--upgrade" if "--upgrade" in args else "--install"
source = pathlib.Path(args[args.index(action) + 1])
root.mkdir(parents=True, exist_ok=True)
destination = root / source.name
if action == "--install" and destination.exists(): sys.exit(1)
if action == "--upgrade" and not destination.exists(): sys.exit(1)
shutil.copytree(source, destination, dirs_exist_ok=True)
with (pathlib.Path(os.environ["XDG_DATA_HOME"]) / "calls.txt").open("a") as out:
    out.write(action + "\\n")
""",
        }
        for name, content in commands.items():
            path = binaries / name
            path.write_text(content)
            path.chmod(0o755)
        with patch.dict(os.environ, {"PATH": str(binaries) + os.pathsep + os.environ["PATH"],
                                    "LIVE_BACKGROUND_INSTALL_TEST": "1"}):
            self.wizard.install_live_wallpaper()
            self.wizard.install_live_wallpaper()
        self.assertEqual((self.data / "calls.txt").read_text().splitlines(), ["--install", "--upgrade"])
        plugin = self.data / "plasma/wallpapers" / kit.LIVE_WALLPAPER_ID
        self.assertIn("<default>neon</default>", (plugin / "contents/config/main.xml").read_text())
        self.assertTrue((plugin / "contents/web/assets/steam-deck-checker.png").is_file())
        self.assertEqual(hashlib.sha256((ROOT / "assets" / kit.LIVE_WALLPAPER_ARCHIVE).read_bytes()).hexdigest(), kit.LIVE_WALLPAPER_SHA256)

    def test_corrupt_package_never_runs_its_installer(self):
        self.wizard.base = self.root
        archive = self.root / "assets" / kit.LIVE_WALLPAPER_ARCHIVE
        archive.parent.mkdir()
        archive.write_bytes(b"corrupt")
        self.wizard.runner.run = Mock(return_value=subprocess.CompletedProcess([], 0, "plasmashell 6.5.0"))
        with patch.object(kit.shutil, "which", return_value="/bin/stub"), self.assertRaisesRegex(ValueError, "SHA-256"):
            self.wizard.install_live_wallpaper()
        self.assertEqual(self.wizard.runner.run.call_count, 1)

    def test_standalone_download_is_checksum_pinned(self):
        self.wizard.base = self.root
        def download(url, target, **kwargs):
            self.assertEqual(url, kit.LIVE_WALLPAPER_URL)
            self.assertEqual(kwargs["digest"], kit.LIVE_WALLPAPER_SHA256)
            shutil.copy2(ROOT / "assets" / kit.LIVE_WALLPAPER_ARCHIVE, target)
            return target
        self.wizard.network.download = Mock(side_effect=download)
        self.wizard.runner.run = Mock(return_value=subprocess.CompletedProcess([], 0, "plasmashell 6.5.0"))
        # Verification must fail: the fake runner never installs the package.
        with patch.object(kit.shutil, "which", return_value="/bin/stub"), self.assertRaisesRegex(RuntimeError, "not found"):
            self.wizard.install_live_wallpaper()
        self.wizard.network.download.assert_called_once()

    def test_activation_scripts_execute_for_multiple_desktops_and_check_results(self):
        node = shutil.which("node")
        if not node:
            self.skipTest("Node.js is required for the Plasma scripting model")
        config = self.home / "config/plasma-org.kde.plasma.desktop-appletsrc"
        config.parent.mkdir()
        config.write_text("existing Plasma configuration")
        calls = []
        def run(args, **kwargs):
            calls.append(args)
            return subprocess.CompletedProcess(args, 0, "STARTER_KIT_NEON_ACTIVE:2" if len(calls) == 2 else "")
        self.wizard.runner.run = Mock(side_effect=run)
        self.wizard.wallpaper_dbus = lambda: "/stub/qdbus6"
        self.wizard.activate_live_wallpaper()
        self.assertEqual(config.read_text(), "existing Plasma configuration")
        self.assertEqual(len(list((self.home / "state").rglob("*.conf"))), 1)
        # Execute the exact generated JavaScript against two distinct desktop
        # containments, including one already using this wallpaper.
        javascript = """
const assert = require('node:assert/strict');
const vm = require('node:vm');
const scripts = JSON.parse(process.argv[1]);
const values = [{Theme:'matrix', Paused:true, LogoPath:'/old/logo'}, {Theme:'random', Paused:true}];
const screens = values.map((config, i) => ({
    wallpaperPlugin: i ? 'org.steamdeckchecker.livebackground' : 'org.kde.image',
    writeConfig(key, value) { config[key] = value; },
    readConfig(key, fallback) { return key in config ? config[key] : fallback; },
    reloadConfig() {}
}));
let printed = '';
const sandbox = {desktops: () => screens, print: s => {printed += s;}};
scripts.forEach(script => vm.runInNewContext(script, sandbox));
values.forEach(v => { assert.equal(v.Theme, 'neon'); assert.equal(v.LogoPath, ''); assert.equal(v.Paused, false); assert.equal(v.Fps, 24); assert.equal(v.Quality, 60); });
assert.equal(printed, 'STARTER_KIT_NEON_ACTIVE:2');
"""
        result = subprocess.run([node, "-e", javascript, json.dumps([c[-1] for c in calls])],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.wizard.runner.run = Mock(return_value=subprocess.CompletedProcess([], 0, ""))
        with self.assertRaisesRegex(RuntimeError, "Aktivierung"):
            self.wizard.activate_live_wallpaper()


if __name__ == "__main__":
    unittest.main()
