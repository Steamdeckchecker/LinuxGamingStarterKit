# Contributing

Please open an [issue](https://github.com/Steamdeckchecker/LinuxGamingStarterKit/issues)
with your distribution/version, handheld model, selected installer language,
the failing step and relevant terminal output. Remove passwords, tokens and
personal information before posting logs. Logs are stored in
`~/.local/state/linux-handheld-starter-kit/`.

Changes to installer logic belong in `starterkit.py`; launcher changes belong
in `desktop_bootstrap.py` / `desktop_launcher.py`. Update `recommend.txt` for
the embedded recommended plugin list, then run `python3 build.py` and commit
the generated `install.sh`, `.desktop` and root `SHA256SUMS` together.

Run these offline checks before submitting a change:

```bash
python3 build.py
python3 -m unittest discover -s tests -v
python3 scripts/package_release.py
bash website/scripts/build.sh
node website/scripts/validate-artifact.mjs
node --test website/tests/worker.test.mjs
```

Python 3.9+ is supported by the installed wizard. Building the deliverables
uses Python 3.12; website checks use Node.js 20 or newer. No Python or npm
packages are required. Website text lives in `website/content.json`; generated
HTML, the bundled Worker and download copies are not committed.

## Maintainer: publishing a release

`VERSION` is the release trigger. Before changing it, update the version in
the installer/build/website sources, add `docs/releases/v<version>.md`, update
the changelog and run the checks above. A push to `main` that changes `VERSION`
starts the release workflow; normal source/documentation commits do not publish
another release. Editing `docs/releases/v<current-version>.md` refreshes the
published release description and marks it as the latest regular release. The
same workflow can be started manually in Actions.

The workflow rebuilds the launchers, runs the installer and website checks,
creates a draft release, uploads the two standalone launchers, source ZIP and
SHA-256 manifest, then publishes it as the latest regular release. It uses GitHub's temporary
`GITHUB_TOKEN`, scoped to this repository; no personal access token is needed.
For an already published version, its description is refreshed from the release
notes, the prerelease flag is cleared and it is marked as latest. Its tag and
download assets are preserved.
