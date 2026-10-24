# Linux Handheld Starter Kit · website

Multilingual project website for Steam Deck Checker's Linux Handheld
Starter Kit. Includes German, English, Spanish, French, Russian, Simplified
Chinese and Japanese pages.

- `content.json`: all translated text.
- `build_site.py`: renders the seven language directories and German root into `public/`.
- `public/assets/`: responsive CSS, device preview, accessible tabs, languages, clipboard and original logo.
- `public/downloads/`: the standalone `.desktop` launcher, alternative `install.sh`, checksums and source ZIP. Both launchers include all 23 recommendations.
- `worker/runtime.js`: serves the pages, files and `/api/latest-videos`.
- `latest-videos.json`: last verified public feed snapshot, also rendered when JavaScript is unavailable.
- `scripts/embed-assets.py`: embeds all assets into the dependency-free Worker; never edit generated `worker/index.js`.

Rebuild after changing translated content or markup:

```sh
bash scripts/build.sh
node scripts/validate-artifact.mjs
node --test tests/worker.test.mjs
```

To add the future YouTube tutorial, edit `public/assets/config.js` and set
`youtubeVideoId` to the video's 11-character YouTube ID. The placeholder then
becomes a clickable thumbnail. The player loads only after the visitor clicks.
The channel link is already present in the header, tutorial section and footer.

The bottom video section loads the latest nine channel uploads from YouTube's
official RSS feed through the same-origin Worker endpoint, cached for up to ten
minutes. It uses channel ID `UCff1lMuioQfmA9xE6EA7qpQ`, sorts by publication date
and removes duplicate IDs. If YouTube is unavailable, it labels the last available
snapshot with its retrieval date. No API key or third-party CORS proxy is used.
Video titles stay in their original language; UI labels have all seven translations.

No third-party analytics or remote fonts are used. The video cards link to YouTube;
the separate future tutorial player loads only after a click. The interactive
device chooser is a clearly labeled workflow preview. Actual installation happens
in the downloaded installer.

The primary download is `Linux-Handheld-Starter-Kit.desktop`: double-clicking
opens a terminal and launches its embedded installer. No separate shell script
or runtime download of the Starter Kit is needed. The seven language pages
explain the desktop's possible first-launch executable/trust confirmation.
The terminal workflow using `install.sh` remains available as an alternative.

## Build from the GitHub checkout

From the repository root, create the downloads and then build the website:

```bash
python3 scripts/package_release.py
bash website/scripts/build.sh
node website/scripts/validate-artifact.mjs
node --test website/tests/worker.test.mjs
```

The package step copies the launchers, checksums, recommendations and source ZIP
into `website/public/downloads/`. The site build writes complete HTML to
`website/public/` and a dependency-free Worker to `website/dist/server/index.js`.
Generated pages, downloads and Worker bundles are ignored by git.

The public origin remains
`https://linux-handheld-starter-kit.cocoabloom514.chatgpt.site`.
No deployment credentials, owner identifiers or hosting project configuration
are included. Deploying elsewhere requires that provider's own Worker hosting
configuration and an update to `ORIGIN` in `build_site.py`. A plain static host
can serve `public/`, but live video-feed refresh requires the Worker endpoint;
the nine-video snapshot remains visible without it.

This repository does not automatically republish the live website. The existing
public deployment remains independently hosted. Installer releases are handled
by the repository's release workflow; see `../CONTRIBUTING.md`.
