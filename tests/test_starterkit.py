"""Offline regression tests. Never install software or invoke real sudo/Steam."""
import contextlib
import base64
import io
import json
import logging
import os
from pathlib import Path
import shutil
import struct
import string
import subprocess
import sys
import tarfile
import tempfile
import types
import unittest
from unittest.mock import patch, Mock
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import starterkit as kit


class FakeGui:
    def __init__(self):
        self.tr = kit.Translator("de")
        self.messages = []
        self.answers = []
        self.choices = []
        self.entries = []

    def info(self, title, text, error=False):
        self.messages.append((title, text, error))

    def question(self, title, text):
        return self.answers.pop(0) if self.answers else False

    def choose(self, *args, **kwargs):
        return self.choices.pop(0) if self.choices else None

    def entry(self, *args, **kwargs):
        return self.entries.pop(0) if self.entries else None

    @contextlib.contextmanager
    def busy(self, title):
        yield


class Base(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home/fabian"
        self.home.mkdir(parents=True)
        self.work = self.root / "work"
        self.work.mkdir()
        self.ui = FakeGui()
        self.log = logging.getLogger("test")
        self.log.addHandler(logging.NullHandler())
        self.wizard = kit.Wizard(self.ui, self.home, self.root, self.work, self.log, self.root / "test.log")

    def archive(self, name="plugin.zip", files=None):
        target = self.root / name
        with zipfile.ZipFile(target, "w") as z:
            for filename, content in (files or {"Demo/plugin.json": '{"name":"Demo","author":"Test"}', "Demo/package.json": '{"version":"1.0.0"}', "Demo/dist/index.js": "// built frontend"}).items():
                z.writestr(filename, content)
        return target


class TranslationTests(unittest.TestCase):
    def test_all_dialogs_and_apps_have_all_seven_languages(self):
        for key, values in kit.TEXT.items():
            self.assertEqual(set(values), set(kit.LANGUAGES), key)
            self.assertTrue(all(isinstance(x, str) and x for x in values.values()), key)
            placeholders = [set(name for _, name, _, _ in string.Formatter().parse(v) if name) for v in values.values()]
            self.assertTrue(all(x == placeholders[0] for x in placeholders), key)
        self.assertEqual(len(kit.APPS), 16)
        self.assertEqual(len({x[1] for x in kit.APPS}), 16)
        for _, _, description, _ in kit.APPS:
            self.assertEqual(set(description), set(kit.LANGUAGES))


class RecommendationTests(Base):
    def test_comments_bom_crlf_duplicates_and_descriptions(self):
        path = self.root / "recommend.txt"
        path.write_bytes(b'\xef\xbb\xbf# heading\r\nhttps://github.com/Example/Demo.git | Description\r\nexample/demo # duplicate\r\nOther/Plugin\r\n')
        self.assertEqual(kit.read_recommend(path), [("Example/Demo", "Description"), ("Other/Plugin", "")])

    def test_rejects_commands_and_non_github_urls(self):
        for value in ("x/y;touch /tmp/bad", "https://evil.example/x/y", "../etc", "x/..", "$(whoami)/plugin", "x/y z"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                kit.normalize_repo(value)

    def test_supplied_recommendations_are_all_preserved(self):
        path = Path(__file__).resolve().parents[1] / "recommend.txt"
        self.assertEqual(len(kit.read_recommend(path)), 23)

    def test_recommended_choice_works_without_any_external_file(self):
        self.ui.choices = ["recommended"]
        with patch.object(kit, "read_recommend", side_effect=AssertionError("No separate file needed")):
            selected = self.wizard.plugin_selection()
        self.assertEqual(len(selected), 23)
        self.assertEqual(selected, kit.parse_recommend(kit.EMBEDDED_RECOMMENDATIONS))

    def test_explicit_recommendation_override_is_used(self):
        path = self.root / "custom.txt"
        path.write_text("Example/Custom\n")
        self.wizard.recommend = path
        self.ui.choices = ["recommended"]
        self.assertEqual(self.wizard.plugin_selection(), [("Example/Custom", "")])

    def test_embedded_recommendations_match_maintainer_source(self):
        path = Path(__file__).resolve().parents[1] / "recommend.txt"
        self.assertEqual(kit.parse_recommend(kit.EMBEDDED_RECOMMENDATIONS), kit.read_recommend(path))


class VideoOverwriteTests(Base):
    def test_existing_movies_are_replaced_and_missing_directories_created(self):
        archive = self.archive("videos.zip", {"a/startup.webm": b"new", "a/second.webm": b"second"})
        self.wizard.network.latest = lambda repo: None
        self.wizard.network.download = lambda *args, **kwargs: archive
        destination = self.home / ".steam/root/config/uioverrides/movies"
        self.wizard.install_videos("Example/Videos", destination)
        self.assertEqual((destination / "startup.webm").read_bytes(), b"new")
        (destination / "startup.webm").write_bytes(b"old")
        (destination / "keep.webm").write_bytes(b"keep")
        self.wizard.install_videos("Example/Videos", destination)
        self.assertEqual((destination / "startup.webm").read_bytes(), b"new")
        self.assertEqual((destination / "keep.webm").read_bytes(), b"keep")

    def test_duplicate_basenames_have_deterministic_last_file_wins(self):
        archive = self.archive("videos.zip", {"a/startup.webm": b"first", "b/startup.webm": b"last"})
        self.wizard.network.latest = lambda repo: None
        self.wizard.network.download = lambda *args, **kwargs: archive
        destination = self.home / "movies"
        self.wizard.install_videos("Example/Videos", destination)
        self.assertEqual((destination / "startup.webm").read_bytes(), b"last")

    def test_replacing_movie_symlink_does_not_modify_external_file(self):
        external = self.home / "external.webm"
        external.write_bytes(b"outside")
        destination = self.home / "movies"
        destination.mkdir()
        (destination / "startup.webm").symlink_to(external)
        archive = self.archive("videos.zip", {"startup.webm": b"new"})
        self.wizard.network.latest = lambda repo: None
        self.wizard.network.download = lambda *args, **kwargs: archive
        self.wizard.install_videos("Example/Videos", destination)
        self.assertEqual(external.read_bytes(), b"outside")
        self.assertFalse((destination / "startup.webm").is_symlink())


class LiveProgressTests(Base):
    def reporter(self):
        stream = io.StringIO()
        return kit.TerminalProgress(kit.Translator("de"), stream), stream

    def test_known_total_shows_percentage_and_unknown_total_shows_activity(self):
        progress, stream = self.reporter()
        progress.start("Test")
        progress.update(5, 10, unit="files", force=True)
        self.assertRegex(stream.getvalue(), r"50(?:\.0)?%")
        stream.seek(0)
        stream.truncate()
        progress.start("Unknown")
        progress.update(5, None, force=True)
        self.assertNotIn("%", stream.getvalue())

    def test_extraction_reaches_100_percent_after_all_files_exist(self):
        progress, stream = self.reporter()
        out = kit.extract_archive(self.archive(files={"one": "a" * 200, "two": "b" * 300}), self.work / "unpack", progress=progress)
        self.assertEqual((out / "two").stat().st_size, 300)
        self.assertRegex(stream.getvalue(), r"100(?:\.0)?%")

    def test_command_output_is_visible_before_process_exits(self):
        ack = self.root / "ack"
        logger = logging.getLogger("live-handshake")
        logger.setLevel(logging.INFO)
        class Ack(logging.Handler):
            def emit(self, record):
                if record.getMessage() == "ready":
                    ack.touch()
        handler = Ack()
        logger.addHandler(handler)
        self.addCleanup(logger.removeHandler, handler)
        progress, _ = self.reporter()
        script = "import pathlib,sys,time; p=pathlib.Path(sys.argv[1]); print('ready', flush=True)\nwhile not p.exists(): time.sleep(.01)\nprint('finished', flush=True)"
        result = kit.Runner(logger, progress=progress).run([sys.executable, "-c", script, str(ack)], timeout=3)
        self.assertEqual(result.returncode, 0)
        self.assertIn("finished", result.stdout)

    def test_timed_out_process_is_terminated_before_return(self):
        pidfile = self.root / "pid"
        progress, _ = self.reporter()
        script = "import os,pathlib,sys,time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(30)"
        with self.assertRaises(subprocess.TimeoutExpired):
            kit.Runner(self.log, progress=progress).run([sys.executable, "-c", script, str(pidfile)], timeout=.5)
        with self.assertRaises(ProcessLookupError):
            os.kill(int(pidfile.read_text()), 0)


class ArchiveTests(Base):
    def test_normal_and_nested_plugin_archives(self):
        plugin = self.archive()
        outer = self.archive("installer.zip", {"Installer/install.sh": "# unused", "Installer/payload.zip": plugin.read_bytes()})
        out = kit.extract_archive(outer, self.work / "out")
        root = self.wizard.plugin_root(out)
        self.assertEqual(json.loads((root / "plugin.json").read_text())["name"], "Demo")

    def test_traversal_is_rejected(self):
        for name in ("../bad", "/tmp/bad", "x/../../bad", "x\\bad", "C:/bad"):
            with self.subTest(name=name):
                path = self.archive("unsafe.zip", {name: "bad"})
                with self.assertRaises(ValueError):
                    kit.extract_archive(path, self.work / "out")
        self.assertFalse((self.work / "bad").exists())

    def test_zip_symlinks_rejected(self):
        path = self.root / "symlink.zip"
        with zipfile.ZipFile(path, "w") as z:
            info = zipfile.ZipInfo("link")
            info.create_system = 3
            info.external_attr = (0o120777 << 16)
            z.writestr(info, "/etc/passwd")
        with self.assertRaises(ValueError):
            kit.extract_archive(path, self.work / "out")

    def test_tar_symlinks_rejected(self):
        path = self.root / "unsafe.tar.gz"
        with tarfile.open(path, "w:gz") as tar:
            info = tarfile.TarInfo("link")
            info.type = tarfile.SYMTYPE
            info.linkname = "/etc/passwd"
            tar.addfile(info)
        with self.assertRaises(ValueError):
            kit.extract_archive(path, self.work / "out")

    def test_extraction_size_limit(self):
        path = self.archive(files={"large": "12345"})
        with self.assertRaises(ValueError):
            kit.extract_archive(path, self.work / "out", limit=4)

    def test_source_without_built_frontend_is_not_installed(self):
        out = kit.extract_archive(self.archive(files={"Source/plugin.json": '{"name":"Source"}', "Source/src/index.tsx": "// source"}), self.work / "out")
        self.assertIsNone(self.wizard.plugin_root(out))

    def test_nested_webm_found_and_metadata_ignored(self):
        inner = self.archive("videos.zip", {"movies/one.webm": b"\x1aE\xdf\xa3video", "__MACOSX/._two.webm": b"metadata"})
        outer = self.archive("outer.zip", {"bundle/pack.zip": inner.read_bytes()})
        out = kit.extract_archive(outer, self.work / "out")
        self.assertEqual([x.name for x in kit.find_video_files(out)], ["one.webm"])


class SteamTests(Base):
    def test_detects_user_home_and_symlinked_native_steam(self):
        actual = self.home / ".local/share/Steam"
        (actual / "steamapps").mkdir(parents=True)
        (self.home / ".steam").mkdir()
        (self.home / ".steam/root").symlink_to(actual)
        self.assertEqual(kit.discover_steam(self.home), actual)

    def test_detects_flatpak_steam(self):
        actual = self.home / ".var/app/com.valvesoftware.Steam/data/Steam"
        (actual / "userdata").mkdir(parents=True)
        self.assertEqual(kit.discover_steam(self.home), actual)

    def test_merge_preserves_unknown_fields_and_is_idempotent(self):
        original = kit.dump_binary_vdf([[0, b"shortcuts", [[0, b"7", [[1, b"AppName", b"My existing game"], [1, b"Exe", b'"/games/demo"'], [3, b"SomeFloat", struct.pack("<f", 1.25)], [7, b"WideInteger", struct.pack("<Q", 2**40)]]]]]])
        self.assertEqual(kit.dump_binary_vdf(kit.parse_binary_vdf(original)), original)
        apps = [("Heroic", "com.heroicgameslauncher.hgl"), ("Discord", "com.discordapp.Discord")]
        merged = kit.merge_shortcuts(original, apps, self.home, "/usr/bin/flatpak")
        entries = kit.vdf_get(kit.parse_binary_vdf(merged), "shortcuts")
        self.assertEqual([x[1] for x in entries], [b"7", b"8", b"9"])
        self.assertEqual(entries[0][2], kit.vdf_get(kit.parse_binary_vdf(original), "shortcuts")[0][2])
        self.assertEqual(kit.merge_shortcuts(merged, apps, self.home, "/usr/bin/flatpak"), merged)

    def test_recognizes_existing_shortcuts_from_other_tools(self):
        old = [[0, b"shortcuts", [[0, b"0", [[1, b"appname", b"Existing Discord"], [1, b"exe", b'"/usr/bin/flatpak"'], [1, b"LaunchOptions", b"run --branch=stable --arch=x86_64 com.discordapp.Discord"]]]]]]
        original = kit.dump_binary_vdf(old)
        self.assertEqual(kit.merge_shortcuts(original, [("Discord", "com.discordapp.Discord")], self.home, "/usr/bin/flatpak"), original)

    def test_corrupt_vdf_is_never_silently_replaced(self):
        for data in (b"broken", b"\x00shortcuts\x00", b"\x09field\x00", b"\x08trailing"):
            with self.subTest(data=data), self.assertRaises(ValueError):
                kit.merge_shortcuts(data, [("App", "x.y.App")], self.home, "/usr/bin/flatpak")

    def test_real_file_backup_and_repeat_without_duplicates(self):
        steam = self.home / ".local/share/Steam"
        path = steam / "userdata/123/config/shortcuts.vdf"
        path.parent.mkdir(parents=True)
        original = kit.dump_binary_vdf([[0, b"shortcuts", []]])
        path.write_bytes(original)
        with patch.object(kit, "steam_running", return_value=False), patch.object(self.wizard, "steam_command", return_value=["steam"]), patch.object(self.wizard, "restart_steam"):
            self.wizard.steam_shortcuts([("Discord", "com.discordapp.Discord")])
            first = path.read_bytes()
            self.wizard.steam_shortcuts([("Discord", "com.discordapp.Discord")])
        self.assertEqual(path.read_bytes(), first)
        backups = list(path.parent.glob("*.bak"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), original)

    def test_will_not_write_when_steam_reappears(self):
        steam = self.home / ".local/share/Steam"
        path = steam / "userdata/123/config/shortcuts.vdf"
        path.parent.mkdir(parents=True)
        path.write_bytes(kit.dump_binary_vdf([[0, b"shortcuts", []]]))
        original = path.read_bytes()
        with patch.object(kit, "steam_running", side_effect=[False, True]), patch.object(self.wizard, "steam_command", return_value=["steam"]), self.assertRaises(RuntimeError):
            self.wizard.steam_shortcuts([("Discord", "com.discordapp.Discord")])
        self.assertEqual(path.read_bytes(), original)

    def test_emudeck_appimage_shortcut_uses_env_and_is_idempotent(self):
        path = self.home / "My Applications/EmuDeck.AppImage"
        merged = kit.merge_shortcuts(b"", [], self.home, "/usr/bin/flatpak", appimages=[("EmuDeck", path)])
        entries = kit.vdf_get(kit.parse_binary_vdf(merged), "shortcuts")
        self.assertEqual(len(entries), 1)
        fields = entries[0][2]
        self.assertEqual(kit.vdf_get(fields, "AppName"), b"EmuDeck")
        self.assertEqual(kit.shlex.split(kit.vdf_get(fields, "Exe").decode()), ["/usr/bin/env"])
        self.assertEqual(kit.shlex.split(kit.vdf_get(fields, "LaunchOptions").decode()), ["APPIMAGE_EXTRACT_AND_RUN=1", str(path)])
        self.assertEqual(kit.merge_shortcuts(merged, [], self.home, "/usr/bin/flatpak", appimages=[("EmuDeck", path)]), merged)

    def test_existing_direct_appimage_shortcut_is_recognized(self):
        path = self.home / "Applications/EmuDeck.AppImage"
        original = kit.dump_binary_vdf([[0, b"shortcuts", [[0, b"0", [[1, b"AppName", b"EmuDeck"], [1, b"Exe", kit.steam_quote(path).encode()]]]]]])
        self.assertEqual(kit.merge_shortcuts(original, [], self.home, "/usr/bin/flatpak", appimages=[("EmuDeck", path)]), original)

    def test_missing_appimage_does_not_stop_steam_or_write_shortcuts(self):
        with patch.object(self.wizard, "steam_command") as command, self.assertRaises(RuntimeError):
            self.wizard.steam_shortcuts([], appimages=[("EmuDeck", self.home / "missing.AppImage")])
        command.assert_not_called()


class SteamRestartTests(Base):
    def setUp(self):
        super().setUp()
        self.steam = self.home / ".local/share/Steam"
        self.path = self.steam / "userdata/123/config/shortcuts.vdf"
        self.path.parent.mkdir(parents=True)
        self.path.write_bytes(kit.dump_binary_vdf([[0, b"shortcuts", []]]))
        self.command = patch.object(self.wizard, "steam_command", return_value=["/fake/steam"])
        self.command.start()
        self.addCleanup(self.command.stop)

    def test_stop_then_save_then_wait_three_seconds_then_launch_detached(self):
        state = {"running": True}
        events = []
        self.ui.answers = [True]
        process = Mock()
        process.poll.return_value = None
        def shutdown(args, **kwargs):
            events.append(("shutdown", args))
            state["running"] = False
        def start(args, **kwargs):
            entries = kit.vdf_get(kit.parse_binary_vdf(self.path.read_bytes()), "shortcuts")
            self.assertEqual(kit.vdf_get(entries[0][2], "FlatpakAppID"), b"com.discordapp.Discord")
            self.assertEqual(events[-1], ("wait", 3))
            self.assertTrue(kwargs["start_new_session"])
            self.assertEqual(kwargs["stdin"], subprocess.DEVNULL)
            events.append(("start", args))
            state["running"] = True
            return process
        with patch.object(kit, "steam_running", side_effect=lambda: state["running"]), patch.object(self.wizard.runner, "run", side_effect=shutdown), patch.object(kit.time, "sleep", side_effect=lambda seconds: events.append(("wait", seconds))), patch.object(kit.subprocess, "Popen", side_effect=start):
            self.wizard.steam_shortcuts([("Discord", "com.discordapp.Discord")])
        self.assertEqual(events, [("shutdown", ["/fake/steam", "-shutdown"]), ("wait", 3), ("start", ["/fake/steam"])])
        process.wait.assert_not_called()

    def test_refusing_steam_shutdown_leaves_library_untouched(self):
        original = self.path.read_bytes()
        with patch.object(kit, "steam_running", return_value=True), patch.object(self.wizard.runner, "run") as run, patch.object(self.wizard, "restart_steam") as restart, self.assertRaises(kit.Cancelled):
            self.wizard.steam_shortcuts([("Discord", "com.discordapp.Discord")])
        self.assertEqual(self.path.read_bytes(), original)
        run.assert_not_called()
        restart.assert_not_called()

    def test_shutdown_timeout_does_not_write_or_start_another_client(self):
        original = self.path.read_bytes()
        self.ui.answers = [True]
        with patch.object(kit, "steam_running", return_value=True), patch.object(self.wizard.runner, "run"), patch.object(kit.time, "monotonic", side_effect=[0, 91]), patch.object(self.wizard, "restart_steam") as restart, self.assertRaises(RuntimeError):
            self.wizard.steam_shortcuts([("Discord", "com.discordapp.Discord")])
        self.assertEqual(self.path.read_bytes(), original)
        restart.assert_not_called()

    def test_write_failure_restores_previously_running_steam(self):
        original = self.path.read_bytes()
        self.ui.answers = [True]
        state = {"running": True}
        def shutdown(*args, **kwargs):
            state["running"] = False
        with patch.object(kit, "steam_running", side_effect=lambda: state["running"]), patch.object(self.wizard.runner, "run", side_effect=shutdown), patch.object(kit, "atomic_write", side_effect=OSError("disk full")), patch.object(self.wizard, "restart_steam") as restart, self.assertRaisesRegex(OSError, "disk full"):
            self.wizard.steam_shortcuts([("Discord", "com.discordapp.Discord")])
        self.assertEqual(self.path.read_bytes(), original)
        restart.assert_called_once_with(["/fake/steam"])

    def test_start_failure_preserves_saved_shortcut(self):
        process = Mock()
        process.poll.return_value = 1
        with patch.object(kit, "steam_running", return_value=False), patch.object(kit.time, "sleep") as sleep, patch.object(kit.subprocess, "Popen", return_value=process), self.assertRaisesRegex(RuntimeError, "Steam"):
            self.wizard.steam_shortcuts([("Discord", "com.discordapp.Discord")])
        entries = kit.vdf_get(kit.parse_binary_vdf(self.path.read_bytes()), "shortcuts")
        self.assertEqual(len(entries), 1)
        sleep.assert_called_once_with(3)

    def test_flatpak_steam_is_restarted_through_flatpak(self):
        self.command.stop()
        flatpak_steam = self.home / ".var/app/com.valvesoftware.Steam/data/Steam"
        process = Mock()
        with patch.object(kit.shutil, "which", return_value="/usr/bin/flatpak"):
            command = self.wizard.steam_command(flatpak_steam)
        self.assertEqual(command, ["flatpak", "run", "com.valvesoftware.Steam"])
        with patch.object(kit, "steam_running", side_effect=[False, True]), patch.object(kit.time, "sleep") as sleep, patch.object(kit.subprocess, "Popen", return_value=process) as popen:
            self.wizard.restart_steam(command)
        self.assertEqual(popen.call_args.args[0], command)
        sleep.assert_called_once_with(3)


class EmulationShortcutTests(Base):
    def test_retrodeck_offers_flatpak_shortcut_after_installation(self):
        self.ui.choices = ["retrodeck"]
        self.ui.answers = [True]
        events = []
        self.wizard.install_app = lambda *args: events.append("installed")
        self.wizard.steam_shortcuts = lambda apps: events.append(("shortcut", apps))
        self.wizard.emulation()
        self.assertEqual(events, ["installed", ("shortcut", [("RetroDECK", "net.retrodeck.retrodeck")])])

    def test_emudeck_offers_appimage_shortcut_after_wizard_returns(self):
        self.ui.choices = ["emudeck"]
        self.ui.answers = [True]
        target = self.home / "Applications/EmuDeck.AppImage"
        events = []
        def installed():
            events.append("installer closed")
            return target
        self.wizard.install_emudeck = installed
        self.wizard.steam_shortcuts = lambda apps, appimages: events.append(("shortcut", appimages))
        self.wizard.emulation()
        self.assertEqual(events, ["installer closed", ("shortcut", [("EmuDeck", target)])])

    def test_failed_emulation_install_never_offers_shortcut(self):
        for choice in ("retrodeck", "emudeck"):
            with self.subTest(choice=choice):
                self.ui.choices = [choice]
                self.ui.answers = [True]
                self.wizard.install_app = Mock(side_effect=RuntimeError("failed"))
                self.wizard.install_emudeck = Mock(side_effect=RuntimeError("failed"))
                self.wizard.steam_shortcuts = Mock()
                self.wizard.emulation()
                self.wizard.steam_shortcuts.assert_not_called()
                self.assertEqual(self.ui.answers, [True])

    def test_declining_shortcut_never_changes_or_restarts_steam(self):
        self.ui.choices = ["retrodeck"]
        self.ui.answers = [False]
        self.wizard.install_app = Mock()
        self.wizard.steam_shortcuts = Mock()
        self.wizard.emulation()
        self.wizard.steam_shortcuts.assert_not_called()

    def test_dry_run_emulation_shortcuts_never_launch_sleep_or_write(self):
        self.wizard.dry = self.wizard.runner.dry = True
        for choice in ("retrodeck", "emudeck"):
            with self.subTest(choice=choice):
                self.ui.choices = [choice]
                self.ui.answers = [True]
                with patch.object(kit.subprocess, "run", side_effect=AssertionError("Must not run")), patch.object(kit.subprocess, "Popen", side_effect=AssertionError("Must not launch")), patch.object(kit.time, "sleep", side_effect=AssertionError("Must not wait")):
                    self.wizard.emulation()
        self.assertFalse((self.home / "Applications").exists())


class FlowTests(Base):
    def test_order_and_no_decky_skips_plugin_step(self):
        events = []
        for name in ("devices", "passwords", "videos", "applications", "emulation", "finish"):
            setattr(self.wizard, name, lambda name=name: events.append(name))
        self.wizard.decky = lambda: events.append("decky") or False
        self.wizard.plugin_selection = lambda: self.fail("Plugins must be skipped")
        self.wizard.run()
        self.assertEqual(events, ["devices", "passwords", "videos", "decky", "applications", "emulation", "finish"])

    def test_order_with_plugins(self):
        events = []
        for name in ("devices", "passwords", "videos", "applications", "emulation", "finish"):
            setattr(self.wizard, name, lambda name=name: events.append(name))
        self.wizard.decky = lambda: events.append("decky") or True
        self.wizard.plugin_selection = lambda: events.append("selection") or [("x/y", "")]
        self.wizard.install_plugins = lambda x: events.append("plugins")
        self.wizard.run()
        self.assertEqual(events, ["devices", "passwords", "videos", "decky", "selection", "plugins", "applications", "emulation", "finish"])

    def test_flatpaks_install_sequentially_and_only_successes_added(self):
        self.ui.choices = [[kit.APPS[0][1], kit.APPS[1][1], kit.APPS[2][1]]]
        self.ui.answers = [True]
        events = []
        def install(name, appid, remote):
            events.append(("start", name))
            if name == "ProtonUp-Qt":
                raise RuntimeError("download failed")
            events.append(("done", name))
        self.wizard.install_app = install
        self.wizard.steam_shortcuts = lambda apps: events.append(("steam", apps))
        self.wizard.applications()
        self.assertEqual(events, [("start", "Heroic"), ("done", "Heroic"), ("start", "ProtonUp-Qt"), ("start", "Proton Plus"), ("done", "Proton Plus"), ("steam", [("Heroic", kit.APPS[0][1]), ("Proton Plus", kit.APPS[2][1])])])

    def test_flatpak_commands_are_user_scoped_and_waited(self):
        calls = []
        self.wizard.runner.run = lambda args, **kwargs: calls.append(args)
        self.wizard.flatpak_installed = Mock(side_effect=[False, True])
        with patch.object(kit.shutil, "which", return_value="/usr/bin/flatpak"):
            self.wizard.install_app("GeForce NOW", "com.nvidia.geforcenow", "GeForceNOW")
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0][:5], ["flatpak", "remote-add", "--user", "--if-not-exists", "GeForceNOW"])
        self.assertEqual(calls[1], ["flatpak", "install", "--user", "--noninteractive", "-y", "GeForceNOW", "com.nvidia.geforcenow"])

    def test_installed_flatpak_reused_without_reinstall(self):
        self.wizard.flatpak_installed = lambda appid: True
        self.wizard.runner.run = lambda *a, **kw: self.fail("Must not reinstall")
        with patch.object(kit.shutil, "which", return_value="/usr/bin/flatpak"):
            self.wizard.install_app("Discord", "com.discordapp.Discord")

    def test_password_creation_is_followed_by_fresh_authentication(self):
        events = []
        self.ui.answers = [True]
        self.wizard.sudo.password_status = lambda: "NP"
        self.wizard.sudo.create_password = lambda: events.append("passwd")
        self.wizard.sudo.authenticate = lambda force=False: events.append(("sudo", force)) or True
        self.wizard.passwords()
        self.assertEqual(events, ["passwd", ("sudo", True)])

    def test_password_is_only_sent_to_stdin(self):
        sudo = self.wizard.sudo
        self.ui.entries = ["secret-test-value"]
        with patch.object(kit.shutil, "which", return_value="/usr/bin/sudo"), patch.object(kit.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run:
            self.assertTrue(sudo.authenticate(force=True))
            args, kwargs = run.call_args
            self.assertNotIn("secret-test-value", str(args))
            self.assertEqual(kwargs["input"], "secret-test-value\n")
            self.assertNotIn("secret-test-value", str(sudo.__dict__))
            sudo.close()

    def test_failed_download_does_not_continue_to_install(self):
        self.wizard.network.latest = lambda repo: {"assets": [{"name": "plugin.zip", "browser_download_url": "https://github.com/x/y/test.zip"}]}
        self.wizard.asset_download = Mock(side_effect=RuntimeError("offline"))
        self.wizard.store_package = lambda *args: None
        self.wizard.network.download = Mock(side_effect=RuntimeError("offline"))
        self.wizard.sudo.run = lambda *a, **kw: self.fail("Must not deploy failed download")
        with self.assertRaises(RuntimeError):
            self.wizard.prepare_plugin("x/y")

    def test_dry_run_calls_no_real_system_commands(self):
        self.wizard.dry = True
        self.wizard.runner.dry = True
        with patch.object(kit.subprocess, "run", side_effect=AssertionError("Must not execute")):
            self.wizard.install_app("Discord", "com.discordapp.Discord")
            self.wizard.install_videos("x/y", self.home / "movies")
            self.wizard.steam_shortcuts([("Discord", "com.discordapp.Discord")])
            self.wizard.install_emudeck()
        self.assertFalse((self.home / "movies").exists())

    def test_cancelled_optional_task_is_skipped(self):
        ok, _ = self.wizard.attempt("Steam", lambda: (_ for _ in ()).throw(kit.Cancelled()))
        self.assertFalse(ok)
        self.assertEqual(self.wizard.results[-1]["state"], "skipped")
        self.assertEqual(self.ui.messages, [])

    def test_plugin_service_restart_is_attempted_after_deployment_failure(self):
        self.ui.answers = [True]
        self.wizard.sudo.authenticate = lambda: True
        manifest = self.root / "manifest.json"
        manifest.write_text("{}")
        self.wizard.prepare_plugin = lambda repo: manifest
        commands = []
        def run(args, **kwargs):
            commands.append(args)
            if "--apply-plugin" in args:
                raise RuntimeError("deployment failed")
        self.wizard.sudo.run = run
        self.wizard.runner.run = lambda *a, **kw: None
        self.wizard.install_plugins([("x/y", "")])
        self.assertEqual(commands[0], ["systemctl", "stop", "plugin_loader.service"])
        self.assertEqual(commands[-1], ["systemctl", "start", "plugin_loader.service"])
        self.assertTrue(any(x['state'] == 'failed' and x['item'] == 'x/y' for x in self.wizard.results))

    def test_plugin_service_stop_failure_skips_deployment(self):
        self.ui.answers = [True]
        self.wizard.sudo.authenticate = lambda: True
        self.wizard.prepare_plugin = lambda repo: self.root / "manifest.json"
        commands = []
        def run(args, **kwargs):
            commands.append(args)
            raise RuntimeError("service missing")
        self.wizard.sudo.run = run
        self.wizard.install_plugins([("x/y", "")])
        self.assertEqual(commands, [["systemctl", "stop", "plugin_loader.service"]])
        self.assertEqual(self.wizard.results[-1]["state"], "skipped")

    def test_complete_simulated_wizard_in_each_language(self):
        for lang in kit.LANGUAGES:
            with self.subTest(lang=lang):
                ui = FakeGui()
                ui.choices = [lang, "oled", "none", ["com.discordapp.Discord"], "none"]
                ui.answers = [False, True, False]  # no Decky, add shortcuts, no reboot
                def gui_factory(translator):
                    ui.tr = translator
                    return ui
                with patch.object(kit, "Gui", side_effect=gui_factory), patch.object(kit.Path, "home", return_value=self.home), patch.object(kit.os, "geteuid", return_value=1000), patch.object(kit.subprocess, "run", side_effect=AssertionError("Dry-run must not execute system commands")), patch.object(kit.logging, "basicConfig"):
                    self.assertEqual(kit.main(["--dry-run", "--lang", lang]), 0)
                self.assertEqual(ui.tr.lang, lang)
                self.assertEqual(ui.choices, [])
                self.assertEqual(ui.answers, [])


class SudoTicketTests(Base):
    """Exercise real child processes with sudo's documented timestamp semantics."""
    def setUp(self):
        super().setUp()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        executable = self.bin / "sudo"
        executable.write_text("#!" + sys.executable + "\n" + '''
import os
from pathlib import Path
import subprocess
import sys

args = sys.argv[1:]
ticket = Path(__file__).with_name("ticket")
owner = str(os.getppid())
valid = ticket.exists() and ticket.read_text() == owner
if args == ["-k"]:
    ticket.unlink(missing_ok=True)
    sys.exit(0)
if "-v" in args:
    if "-S" in args:
        if sys.stdin.readline().rstrip("\\n") != "dummy-password":
            sys.exit(1)
        # sudo -k -v accepts a password but does not cache authorization.
        if "-k" not in args:
            ticket.write_text(owner)
        sys.exit(0)
    sys.exit(0 if valid else 1)
if args and args[0] == "-n":
    if not valid:
        print("sudo: a password is required", file=sys.stderr)
        sys.exit(1)
    sys.exit(subprocess.run(args[1:]).returncode)
sys.exit(2)
''')
        executable.chmod(0o755)
        environment = patch.dict(os.environ, {"PATH": str(self.bin) + os.pathsep + os.environ.get("PATH", "")})
        environment.start()
        self.addCleanup(environment.stop)
        self.addCleanup(self.wizard.sudo.close)

    def test_authorization_is_reused_for_synchronous_decky_command(self):
        self.ui.entries = ["dummy-password"]
        self.assertTrue(self.wizard.sudo.authenticate(force=True))
        installer = self.work / "decky-install.sh"
        completed = self.work / "completed"
        installer.write_text("#!/bin/bash\nprintf 'Decky setup started\\n'\nsleep .05\nprintf 'finished' > " + kit.shlex.quote(str(completed)) + "\n")
        result = self.wizard.sudo.run(["bash", str(installer)], timeout=3)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(completed.read_text(), "finished")
        self.wizard.sudo.close()
        self.assertFalse((self.bin / "ticket").exists())

    def test_wrong_password_never_creates_authorization(self):
        self.ui.entries = ["wrong-password"]
        self.assertFalse(self.wizard.sudo.authenticate(force=True))
        self.assertFalse(self.wizard.sudo.authorized)
        self.assertFalse((self.bin / "ticket").exists())

    def test_fresh_authentication_does_not_accept_an_old_ticket(self):
        (self.bin / "ticket").write_text(str(os.getpid()))
        self.ui.entries = ["wrong-password"]
        self.assertFalse(self.wizard.sudo.authenticate(force=True))
        self.assertFalse((self.bin / "ticket").exists())


class StoreTests(Base):
    def test_store_package_requires_exact_author_and_name(self):
        self.wizard.store_attempted = True
        self.wizard.store = [{"name": "Demo", "author": "Other", "versions": [{"hash": "a" * 64}]}]
        self.wizard.network.json = lambda *a, **kw: {"encoding": "base64", "content": base64.b64encode(b'{"name":"Demo","author":"Expected"}').decode()}
        self.wizard.network.download = lambda *a, **kw: self.fail("Wrong author's package must never be downloaded")
        self.assertIsNone(self.wizard.store_package("x/y", self.work))

    def test_store_content_address_and_digest(self):
        self.wizard.store_attempted = True
        digest = "a" * 64
        self.wizard.store = [{"name": "Demo", "author": "Test", "versions": [{"hash": digest, "created": "2026-10-19"}]}]
        self.wizard.network.json = lambda *a, **kw: {"encoding": "base64", "content": base64.b64encode(b'{"name":"Demo","author":"Test"}').decode()}
        archive = self.archive()
        self.wizard.network.download = Mock(return_value=archive)
        root = self.wizard.store_package("x/y", self.work)
        self.assertTrue((root / "dist/index.js").is_file())
        args, kwargs = self.wizard.network.download.call_args
        self.assertIn("/versions/" + digest + ".zip", args[0])
        self.assertEqual(kwargs["digest"], digest)


class DeploymentTests(Base):
    def deploy(self, manifest, **patches):
        user = types.SimpleNamespace(pw_dir=str(self.home), pw_uid=os.getuid(), pw_gid=os.getgid())
        with patch.dict(os.environ, {"SUDO_USER": "test-user"}), patch.object(kit.pwd, "getpwnam", return_value=user), patch.object(kit.os, "geteuid", return_value=0), patch.object(kit.os, "chown"), contextlib.redirect_stdout(io.StringIO()):
            kit.apply_plugin(manifest)

    def prepared(self):
        out = kit.extract_archive(self.archive(), self.work / "extracted") / "Demo"
        manifest = self.work / "manifest.json"
        manifest.write_text(json.dumps({"source": str(out), "folder": "Demo"}))
        return manifest

    def test_existing_plugin_is_backed_up_and_new_files_installed(self):
        old = self.home / "homebrew/plugins/existing-folder"
        (old / "dist").mkdir(parents=True)
        (old / "plugin.json").write_text('{"name":"Demo"}')
        (old / "dist/index.js").write_text("old")
        self.deploy(self.prepared())
        self.assertEqual((old / "dist/index.js").read_text(), "// built frontend")
        backups = list((self.home / "homebrew/.starter-kit-backups").rglob("dist/index.js"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "old")

    def test_deployment_rollback_restores_old_version(self):
        old = self.home / "homebrew/plugins/Demo"
        old.mkdir(parents=True)
        (old / "plugin.json").write_text('{"name":"Demo"}')
        (old / "keep.txt").write_text("original")
        manifest = self.prepared()
        rename = os.rename
        def fail_staging(src, dst):
            if Path(src).name.startswith(".starterkit-"):
                raise OSError("simulated disk error")
            return rename(src, dst)
        with patch.object(kit.os, "rename", side_effect=fail_staging), self.assertRaises(OSError):
            self.deploy(manifest)
        self.assertEqual((old / "keep.txt").read_text(), "original")

    def test_symlinked_decky_root_is_rejected(self):
        external = self.root / "outside"
        external.mkdir()
        (self.home / "homebrew").symlink_to(external)
        with self.assertRaises(ValueError):
            self.deploy(self.prepared())
        self.assertFalse((external / "plugins").exists())

    def test_existing_different_plugin_is_not_overwritten(self):
        old = self.home / "homebrew/plugins/Demo"
        old.mkdir(parents=True)
        (old / "plugin.json").write_text('{"name":"Different plugin"}')
        with self.assertRaises(ValueError):
            self.deploy(self.prepared())
        self.assertEqual(json.loads((old / "plugin.json").read_text())["name"], "Different plugin")


class DownloadTests(Base):
    def test_hash_mismatch_leaves_existing_file_intact(self):
        path = self.root / "download.bin"
        path.write_bytes(b"old")
        class Response(io.BytesIO):
            headers = {"Content-Length": "3"}
        network = kit.Network(self.log)
        network.open = lambda url: Response(b"new")
        with patch.object(kit.time, "sleep"), self.assertRaises(ValueError):
            network.download("https://example.org/archive", path, digest="0" * 64)
        self.assertEqual(path.read_bytes(), b"old")
        self.assertFalse(path.with_suffix(".bin.part").exists())

    def test_https_enforced(self):
        for url in ("http://example.org", "file:///etc/passwd", "https://user:password@example.org"):
            with self.assertRaises(ValueError):
                kit.https_url(url)

    def test_latest_stable_uses_github_latest_not_first_prerelease(self):
        network = kit.Network(self.log)
        network.json = Mock(return_value={"tag_name": "stable"})
        self.assertEqual(network.latest("x/y")["tag_name"], "stable")
        self.assertIn("/releases/latest", network.json.call_args[0][0])
        network.latest("x/y")
        self.assertEqual(network.json.call_count, 1)


if __name__ == "__main__":
    unittest.main()
