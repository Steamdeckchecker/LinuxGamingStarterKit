#!/usr/bin/env python3
"""Build seven accessible language versions for the Site Worker."""
import html
import json
from pathlib import Path

BASE = Path(__file__).resolve().parent
DIST = BASE / "public"
CONTENT = json.loads((BASE / "content.json").read_text())
LATEST = json.loads((BASE / "latest-videos.json").read_text())
ORIGIN = "https://linux-handheld-starter-kit.cocoabloom514.chatgpt.site"
CHANNEL = "https://www.youtube.com/@SteamDeckChecker/"
PACKAGE = "/downloads/Linux-Handheld-Starter-Kit-v0.1.0.zip"
SCRIPT = "/downloads/install.sh"
LAUNCHER = "/downloads/Linux-Handheld-Starter-Kit.desktop"
GITHUB = "https://github.com/Steamdeckchecker/LinuxGamingStarterKit"
TERMINAL_COMMAND = 'curl -fL --retry 3 -o install.sh "https://github.com/Steamdeckchecker/LinuxGamingStarterKit/releases/download/v0.1.0/install.sh" && bash install.sh'
OFFICIAL = {"SteamOS": "https://store.steampowered.com/steamos/", "CachyOS": "https://cachyos.org/", "Bazzite": "https://bazzite.gg/", "Decky Loader": "https://decky.xyz/", "RetroDECK": "https://retrodeck.net/", "EmuDeck": "https://www.emudeck.com/"}
LANGUAGES = {"de": "Deutsch", "en": "English", "es": "Español", "fr": "Français", "ru": "Русский", "zh": "中文", "ja": "日本語"}
E = lambda value: html.escape(str(value), quote=True)


def linked_text(value):
    """Link only a fixed allowlist of product names, after escaping content."""
    import re
    return re.sub("|".join(re.escape(name) for name in OFFICIAL),
                  lambda match: f'<a class="product-link" href="{OFFICIAL[match[0]]}" target="_blank" rel="noopener noreferrer">{match[0]}</a>', E(value))

PATHS = {
    "arrow": '<path d="M5 12h14m-6-6 6 6-6 6"/>',
    "download": '<path d="M12 3v12m-5-5 5 5 5-5M4 16v4h16v-4"/>',
    "check": '<path d="m5 12 4 4 10-10"/>',
    "copy": '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M15 8V4H4v11h4"/>',
    "globe": '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c6 5 6 13 0 18-6-5-6-13 0-18Z"/>',
    "terminal": '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="m7 9 3 3-3 3m6 0h4"/>',
    "movie": '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16M3 9h4m-4 6h4M17 9h4m-4 6h4"/>',
    "plugins": '<path d="M8 3v4H4v6h4v4h6v-4h4V7h-4V3Z"/><path d="M14 17v4h6v-6h-2"/>',
    "apps": '<rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/>',
    "game": '<path d="M7 7h10c4 0 6 12 3 12-2 0-3-4-5-4H9c-2 0-3 4-5 4C1 19 3 7 7 7Z"/><path d="M8 9v5m-2-2h4m6-2h.1m2 3h.1"/>',
    "info": '<circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-10h.01"/>',
    "youtube": '<rect x="2" y="5" width="20" height="14" rx="4"/><path d="m10 9 6 3-6 3Z"/>',
    "external": '<path d="M14 3h7v7m0-7L10 14M10 4H4v16h16v-6"/>',
    "github": '<path d="M8 20c-5 1-5-3-7-3m14 6v-4c0-1-.4-2-1-2.5 4-.5 8-2 8-7.5A6 6 0 0 0 20 5a6 6 0 0 0-.1-4S18.3.5 15 3a15 15 0 0 0-8 0C3.7.5 2.1 1 2.1 1A6 6 0 0 0 2 5a6 6 0 0 0-2 4c0 5.5 4 7 8 7.5A4 4 0 0 0 7 19v4" transform="translate(2 0) scale(.85)"/>',
}


def icon(name, cls="icon"):
    return f'<svg class="{cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{PATHS[name]}</svg>'


def device_icon(machine=False):
    paths = '<rect x="15" y="3" width="34" height="34" rx="5"/><path d="M20 10h24M21 15h12M21 20h8"/><circle cx="41" cy="29" r="2"/>' if machine else '<rect x="2" y="6" width="60" height="29" rx="8"/><rect x="15" y="10" width="34" height="21" rx="2"/><path d="M9 15v8m-4-4h8"/><circle cx="55" cy="16" r="1"/><circle cx="55" cy="24" r="1"/>'
    return f'<svg class="device-icon" viewBox="0 0 64 40" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true">{paths}</svg>'


def button(t, small=False):
    return f'<a class="button button-primary" href="{LAUNCHER}" download>{icon("download")}<span>{E(t["download"])}</span></a>'


def video_cards(t):
    return ''.join(f'''<article class="latest-card"><a href="https://www.youtube.com/watch?v={E(video['id'])}" target="_blank" rel="noopener noreferrer">
      <div class="latest-thumbnail"><img src="https://i.ytimg.com/vi/{E(video['id'])}/hqdefault.jpg" alt="" width="480" height="360" loading="lazy" referrerpolicy="no-referrer"><span class="latest-play" aria-hidden="true">{icon('youtube')}</span></div>
      <div class="latest-card-copy"><time datetime="{E(video['published'])}">{E(video['published'][:10])}</time><h3>{E(video['title'])}</h3><span class="latest-watch">{E(t['latestWatch'])}{icon('external')}</span></div>
    </a></article>''' for video in LATEST['videos'][:9])


def page(lang):
    t = CONTENT[lang]
    html_lang = "zh-Hans" if lang == "zh" else lang
    options = "".join(f'<option value="{key}" lang="{"zh-Hans" if key == "zh" else key}"{ " selected" if key == lang else ""}>{E(label)}</option>' for key, label in LANGUAGES.items())
    alternates = "\n".join(f'<link rel="alternate" hreflang="{"zh-Hans" if key == "zh" else key}" href="{ORIGIN}/{key}/">' for key in LANGUAGES)
    devices = ["Steam Deck LCD", "Steam Deck OLED", "Steam Machine", "MSI Claw", "Legion Go", t["other"]]
    device_buttons = "".join(f'<button class="device" type="button" data-device="{E(name)}" aria-pressed="{"true" if i == 0 else "false"}">{icon("check", "selected-check")}{device_icon(i == 2)}<span>{E(name)}</span></button>' for i, name in enumerate(devices))
    stats = "".join(f'<div class="stat"><b>{number}</b><span>{E(label)}</span></div>' for number, label in zip([6,23,7], t["stats"]))
    tab_icons = ["movie", "plugins", "apps", "game"]
    tabs = "".join(f'<button class="tab" id="tab-{i}" type="button" role="tab" aria-controls="panel-{i}" aria-selected="{"true" if i == 0 else "false"}" tabindex="{0 if i == 0 else -1}">{icon(tab_icons[i])}{E(tab["label"])}</button>' for i, tab in enumerate(t["tabs"]))
    tags = [
        devices,
        ["SDC Benchmark", "TrailerHero", "ThemeDeck", "SteamGridDB", "CSS Loader", "MAKO", "HelixSR Manager", "Decky LSFG-VK"],
        ["Heroic", "ProtonUp-Qt", "Proton Plus", "VacuumTube", "Lutris", "Moonlight", "chiaki-ng", "GeForce NOW", "XStreaming", "Flatseal", "Filelight", "Discord", "Google Chrome", "LibreOffice", "SuperTuxKart", "Ring Racers"],
        ["RetroDECK", "EmuDeck"]
    ]
    panels = []
    for i, tab in enumerate(t["tabs"]):
        cloud = "".join(f'<span class="tag{" tag-featured" if n < 2 else ""}">{linked_text(name)}</span>' for n, name in enumerate(tags[i]))
        if i == 1:
            cloud += f'<a class="text-link tag-foot" href="/downloads/recommend.txt" download>{E(t["recommend"])} {icon("download")}</a>'
        panels.append(f'<section class="tab-panel" id="panel-{i}" role="tabpanel" aria-labelledby="tab-{i}" tabindex="0"{" hidden" if i else ""}><div><h3>{E(tab["title"])}</h3><p>{linked_text(tab["text"])}</p><p class="tab-note">{icon("check")}{E(tab["note"])}</p></div><div class="tag-cloud">{cloud}</div></section>')
    step_html = []
    for i, (title, text) in enumerate(t["steps"]):
        command = f'<div class="command"><code>{E(TERMINAL_COMMAND)}</code><button class="copy-button" type="button" data-copy="{E(TERMINAL_COMMAND)}" aria-label="{E(t["copy"])}">{icon("copy")}<span>{E(t["copy"])}</span></button></div><div id="copy-status" class="copy-status" role="status" aria-live="polite" aria-atomic="true"></div><p class="dry-run">{E(t["tryFirst"])}<code>bash install.sh --dry-run</code></p>' if i == 1 else ""
        if command:
            command = f'<details class="terminal-alternative" open><summary>{E(t["terminalAlternative"])}</summary><p>{E(t["terminalAlternativeText"])}</p>{command}</details>'
        step_html.append(f'<li><h3>{E(title)}</h3><p>{E(text)}</p>{command}</li>')
    faqs = "".join(f'<details><summary>{E(question)}</summary><p>{linked_text(answer)}</p></details>' for question, answer in t["faq"])
    language_links = " ".join(f'<a href="/{key}/" hreflang="{"zh-Hans" if key == "zh" else key}" lang="{"zh-Hans" if key == "zh" else key}">{E(name)}</a>' for key, name in LANGUAGES.items())
    return f'''<!doctype html>
<html lang="{html_lang}">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Linux Handheld Starter Kit · Steam Deck Checker</title>
<meta name="description" content="{E(t['intro'])}">
<meta name="theme-color" content="#0d1016">
<link rel="canonical" href="{ORIGIN}/{lang}/">
{alternates}
<link rel="alternate" hreflang="x-default" href="{ORIGIN}/de/">
<meta property="og:type" content="website"><meta property="og:title" content="Linux Handheld Starter Kit · Steam Deck Checker">
<meta property="og:description" content="{E(t['intro'])}"><meta property="og:url" content="{ORIGIN}/{lang}/">
<meta property="og:image" content="{ORIGIN}/assets/steam-deck-checker.png"><meta property="og:image:alt" content="Steam Deck Checker">
<link rel="icon" type="image/png" href="/assets/steam-deck-checker.png">
<link rel="stylesheet" href="/assets/site.css">
<script defer src="/assets/config.js"></script><script defer src="/assets/site.js"></script>
</head>
<body data-copied="{E(t['copied'])}" data-copy-error="{E(t['copyError'])}">
<a class="skip" href="#main">{E(t['skip'])}</a>
<header class="header" id="top"><div class="wrap header-inner">
  <div class="branding"><a class="channel-logo" href="{CHANNEL}" target="_blank" rel="noopener noreferrer" aria-label="Steam Deck Checker · YouTube"><img src="/assets/steam-deck-checker.png" alt="Steam Deck Checker" width="391" height="166"></a><a class="brand" href="/{lang}/">LINUX HANDHELD<span>STARTER KIT</span></a></div>
  <nav class="header-nav" aria-label="Linux Handheld Starter Kit"><a href="#kit">{E(t['nav'][0])}</a><a href="#install">{E(t['nav'][1])}</a><a href="#tutorial">{E(t['nav'][2])}</a></nav>
  <div class="header-tools"><a class="youtube-link" href="{CHANNEL}" target="_blank" rel="noopener noreferrer">{icon('youtube')}<span>YouTube</span></a><div class="language">{icon('globe')}<label class="sr-only" for="language">{E(t['language'])}</label><select id="language">{options}</select></div></div>
</div></header>
<main id="main">
  <section class="hero wrap" aria-labelledby="headline">
    <div class="hero-grid"><div class="hero-copy"><p class="eyebrow">{E(t['eyebrow'])}</p><h1 id="headline">{E(t['hero'][0])}<span>{E(t['hero'][1])}</span></h1><p class="intro">{E(t['intro'])}</p><div class="hero-actions">{button(t)}<a class="button button-secondary" href="#install">{E(t['how'])}{icon('arrow')}</a></div><p class="zip-note">{E(t['zipNote'])}</p><div class="platforms"><span>{E(t['platform'])}</span>{''.join('<b>'+linked_text(name)+'</b>' for name in ['SteamOS','CachyOS','Bazzite'])}</div></div>
    <div class="hero-preview"><div class="preview-label"><span>{E(t['preview'])}</span><span class="release">{E(t['release'])}</span></div><div class="preview-window"><div class="window-bar"><span class="window-brand">{icon('terminal')}Linux Handheld Starter Kit</span><span class="window-controls" aria-hidden="true"><i></i><i></i><i></i></span></div><div class="window-content"><div class="window-step">{E(t['previewStep'])}</div><h2>{E(t['previewTitle'])}</h2><p>{E(t['previewSub'])}</p><div class="device-grid" role="group" aria-label="{E(t['previewTitle'])}">{device_buttons}</div><div class="video-match"><span>{E(t['selectedVideo'])}</span><strong>{icon('check')}<span id="matched-device" aria-live="polite">Steam Deck LCD</span></strong></div><div class="window-next">{E(t['previewNext'])}{icon('arrow')}</div></div></div><p class="preview-note">{E(t['previewHint'])}</p></div></div>
    <div class="stats">{stats}</div>
  </section>
  <section class="kit section" id="kit"><div class="wrap"><div class="section-head"><p class="eyebrow">{E(t['kitEyebrow'])}</p><h2>{E(t['kitTitle'])}</h2><p>{E(t['kitIntro'])}</p></div><div class="tabs" role="tablist" aria-label="{E(t['nav'][0])}">{tabs}</div>{''.join(panels)}</div></section>
  <section class="installation section wrap" id="install"><div class="installation-grid"><div class="section-head"><p class="eyebrow">{E(t['installEyebrow'])}</p><h2>{E(t['installTitle'])}</h2><p>{E(t['installIntro'])}</p><div class="install-download">{button(t)}</div><div class="install-links"><a href="{SCRIPT}" download>{E(t['script'])}</a><a href="{GITHUB}" target="_blank" rel="noopener noreferrer">{E(t['project'])}</a><a href="{PACKAGE}" download>{E(t['source'])}</a><a href="/downloads/SHA256SUMS" download>SHA-256</a></div></div><ol class="steps">{''.join(step_html)}</ol></div><aside class="test-note">{icon('info')}<span>{linked_text(t['testNote'])}</span></aside></section>
  <section class="tutorial section wrap" id="tutorial"><div class="tutorial-grid"><div class="tutorial-copy"><p class="eyebrow">{E(t['tutorialEyebrow'])}</p><h2>{E(t['tutorialTitle'])}</h2><p>{E(t['tutorialText'])}</p><a class="button button-secondary" href="{CHANNEL}" target="_blank" rel="noopener noreferrer">{icon('youtube')}{E(t['channel'])}{icon('external')}</a></div><div class="video-placeholder" id="tutorial-video" data-play="{E(t['videoPlay'])}"><img src="/assets/steam-deck-checker.png" alt="Steam Deck Checker" width="391" height="166" loading="lazy"><h3>{E(t['videoSoon'])}</h3><p>{E(t['videoSub'])}</p></div></div></section>
  <section class="faq section wrap"><div class="faq-grid"><div class="section-head"><p class="eyebrow">{E(t['faqEyebrow'])}</p><h2>{E(t['faqTitle'])}</h2></div><div class="faq-list">{faqs}</div></div></section>
  <section class="latest section wrap" id="latest-videos" data-watch="{E(t['latestWatch'])}" data-loading="{E(t['latestLoading'])}" data-unavailable="{E(t['latestUnavailable'])}" data-snapshot="{E(t['latestSnapshot'])}" data-updated="{E(t['latestUpdated'])}">
    <div class="latest-heading"><div class="section-head"><p class="eyebrow">{E(t['latestEyebrow'])}</p><h2>{E(t['latestTitle'])}</h2><p>{E(t['latestText'])}</p></div><a class="text-link" href="{CHANNEL}videos" target="_blank" rel="noopener noreferrer">{E(t['latestChannel'])}{icon('arrow')}</a></div>
    <div class="latest-grid" id="latest-video-list">{video_cards(t)}</div><p class="latest-status" id="latest-video-status" role="status" aria-live="polite">{E(t['latestSnapshot'])} <time datetime="{E(LATEST['fetchedAt'])}">{E(LATEST['fetchedAt'][:10])}</time></p>
  </section>
  <section class="closing"><div class="wrap"><h2>{E(t['ctaTitle'])}</h2><p>{E(t['ctaText'])}</p>{button(t)}</div></section>
</main>
<footer class="footer wrap"><div class="footer-top"><div class="footer-identity"><a href="{CHANNEL}" target="_blank" rel="noopener noreferrer" aria-label="Steam Deck Checker · YouTube"><img src="/assets/steam-deck-checker.png" alt="Steam Deck Checker" width="391" height="166" loading="lazy"></a><p>{E(t['footer'])}</p></div><nav class="footer-links" aria-label="Steam Deck Checker"><a href="{CHANNEL}" target="_blank" rel="noopener noreferrer">{icon('youtube')}YouTube</a><a href="{GITHUB}" target="_blank" rel="noopener noreferrer">{icon('github')}GitHub</a><a href="{PACKAGE}" download>{E(t['source'])}{icon('download')}</a></nav></div><div class="footer-bottom"><p>{E(t['footerNote'])}</p><span>Linux Handheld Starter Kit · v0.1.0</span></div><nav class="language-links" aria-label="{E(t['language'])}">{language_links}</nav></footer>
</body></html>'''


if __name__ == "__main__":
    for lang in LANGUAGES:
        folder = DIST / lang
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "index.html").write_text(page(lang), encoding="utf-8")
    (DIST / "index.html").write_text(page("de"), encoding="utf-8")
    (DIST / "robots.txt").write_text(f"User-agent: *\nAllow: /\nSitemap: {ORIGIN}/sitemap.xml\n")
    (DIST / "sitemap.xml").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' + ''.join(f'<url><loc>{ORIGIN}/{lang}/</loc></url>' for lang in LANGUAGES) + '</urlset>\n')
    print("Built de, en, es, fr, ru, zh, ja and the German entry page.")
