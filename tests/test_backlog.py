"""Install the supplied Backlog runtime into an isolated Steam/XDG fixture."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest
from unittest.mock import Mock, patch
import zipfile

from test_starterkit import Base, kit

ROOT = Path(__file__).resolve().parents[1]


class BacklogTests(Base):
    def setUp(self):
        super().setUp()
        self.wizard.base = ROOT
        self.steam = self.home / 'Steam with spaces'
        (self.steam / 'userdata/123/config').mkdir(parents=True)
        (self.steam / 'steamapps').mkdir()
        self.wizard.steam = self.steam
        self.wizard.sudo.run = Mock(side_effect=AssertionError('Backlog must not use sudo'))

    def test_declining_skips_without_installing(self):
        self.ui.answers = [False]
        self.wizard.install_backlog = Mock(side_effect=AssertionError('Declined'))
        self.wizard.backlog()
        self.assertEqual(self.wizard.results[-1]['state'], 'skipped')

    def test_dry_run_never_downloads_runs_or_writes(self):
        self.wizard.dry = True
        self.wizard.network.download = Mock(side_effect=AssertionError('No download'))
        self.wizard.runner.run = Mock(side_effect=AssertionError('No commands'))
        self.wizard.install_backlog()
        self.assertFalse((self.steam / 'config').exists())

    def test_missing_steam_fails_before_any_download(self):
        self.wizard.steam = None
        self.wizard.network.download = Mock(side_effect=AssertionError('No download'))
        with self.assertRaisesRegex(RuntimeError, 'Steam'):
            self.wizard.install_backlog()

    def test_corrupt_archive_never_executes(self):
        self.wizard.base = self.root
        archive = self.root / 'assets' / kit.BACKLOG_ARCHIVE
        archive.parent.mkdir()
        archive.write_bytes(b'corrupt')
        self.wizard.runner.run = Mock(side_effect=AssertionError('Must not run'))
        with self.assertRaisesRegex(ValueError, 'SHA-256'):
            self.wizard.install_backlog()

    def test_single_file_starter_download_is_checksum_pinned(self):
        self.wizard.base = self.root
        def download(url, target, **kwargs):
            self.assertEqual(url, kit.BACKLOG_URL)
            self.assertEqual(kwargs['digest'], kit.BACKLOG_SHA256)
            shutil.copy2(ROOT / 'assets' / kit.BACKLOG_ARCHIVE, target)
            return target
        self.wizard.network.download = Mock(side_effect=download)
        self.wizard.runner.run = Mock(return_value=subprocess.CompletedProcess([], 0, ''))
        with self.assertRaisesRegex(RuntimeError, 'not found'):
            self.wizard.install_backlog()
        command = self.wizard.runner.run.call_args.args[0]
        self.assertEqual(command[-2:], ['--steam', str(self.steam)])
        self.wizard.network.download.assert_called_once()

    def test_actual_fresh_install_and_update_preserve_config_and_timer(self):
        binaries = self.root / 'bin'
        binaries.mkdir()
        systemctl = binaries / 'systemctl'
        systemctl.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$HOME/systemctl-calls"\n')
        systemctl.chmod(0o755)
        environment = {**os.environ, 'HOME': str(self.home),
                       'XDG_CONFIG_HOME': str(self.home / '.config'),
                       'XDG_DATA_HOME': str(self.home / '.local/share'),
                       'PATH': str(binaries) + os.pathsep + os.environ['PATH']}
        environment.pop('STEAM_API_KEY', None)
        original_run = self.wizard.runner.run
        def run(args, **kwargs):
            return original_run(args, **kwargs, env=environment)
        with patch.object(self.wizard.runner, 'run', side_effect=run):
            self.wizard.install_backlog()
            target = self.steam / 'config/uioverrides/screensavers/backlog'
            config = target / 'config.js'
            fresh = config.read_text()
            self.assertIn('shuffle: true', fresh)
            self.assertIn('minutesPerScene: 5', fresh)
            self.assertIn('hour12: false', fresh)
            customized = fresh.replace('shuffle: true', 'shuffle: false').replace('minutesPerScene: 5', 'minutesPerScene: 1')
            config.write_text(customized)
            (target / 'core.js').write_text('old English version')
            self.wizard.install_backlog()
        self.assertEqual(config.read_text(), customized)
        self.assertIn("' Stunden'", (target / 'core.js').read_text())
        self.assertTrue((target / 'library/library.js').is_file())
        persistent_sync = self.home / '.local/share/backlog/sync.py'
        self.assertTrue(persistent_sync.is_file())
        service = (self.home / '.config/systemd/user/backlog-sync.service').read_text()
        self.assertIn(str(persistent_sync), service)
        self.assertIn(str(self.steam), service)
        self.assertNotIn(str(self.work), service)
        timer = (self.home / '.config/systemd/user/backlog-sync.timer').read_text()
        self.assertIn('OnCalendar=*:0/15', timer)
        self.assertIn('--user enable --now backlog-sync.timer', (self.home / 'systemctl-calls').read_text())

    def test_runtime_german_labels_and_shuffle_without_boundary_repeats(self):
        node = shutil.which('node')
        if not node:
            self.skipTest('Node.js unavailable')
        with zipfile.ZipFile(ROOT / 'assets' / kit.BACKLOG_ARCHIVE) as archive:
            payload = {key: archive.read('backlog-de/backlog/' + name).decode()
                       for key, name in [('config', 'config.js'), ('core', 'core.js')]}
            self.assertTrue(all(not n.startswith('backlog-de/docs/') for n in archive.namelist()))
            self.assertIn('backlog-de/LICENSE', archive.namelist())
        script = r'''
const vm = require('node:vm'), assert = require('node:assert/strict');
const fs = require('node:fs');
const source = JSON.parse(fs.readFileSync(0, 'utf8'));
const sandbox = {window: {BACKLOG_LIBRARY: {games: [{appid:1, name:'Test', playtime:90}]}},
 location: {search:'?seed=42&no-memory'}, URLSearchParams, navigator:{}, console};
vm.createContext(sandbox);
vm.runInContext(source.config, sandbox);
assert.equal(sandbox.window.BACKLOG_CONFIG.shuffle, true);
assert.equal(sandbox.window.BACKLOG_CONFIG.minutesPerScene, 5);
const core = source.core.replace(/\}\)\(\);\s*$/, 'globalThis.check = {buildPlaylist, scene, fmtHours, ago, fmtDate, setPrevious: p => {playlist=p;}};})();');
vm.runInContext(core, sandbox);
const test = sandbox.check;
for (const id of ['mosaic','drift','flip','ripple']) test.scene({id});
let previous = null;
const orders = new Set();
for (let i = 0; i < 100; i++) {
 const list = Array.from(test.buildPlaylist());
 assert.equal(new Set(list).size, 4);
 assert.notEqual(list[0], previous);
 previous = list[3]; test.setPrevious(list); orders.add(list.join(','));
}
assert.ok(orders.size > 1);
assert.equal(test.fmtHours(90), '1,5 Stunden');
assert.equal(test.ago(0), 'noch nie');
assert.match(test.fmtDate(new Date(2026,10,19,12)), /DO, 19\. NOV/);
'''
        result = subprocess.run([node, '-e', script], input=json.dumps(payload), text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
