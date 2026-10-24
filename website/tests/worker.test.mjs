import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import {createWorker, parseFeed, FEED_URL} from '../worker/runtime.js';

const feed = await readFile(new URL('./fixtures/youtube-feed.xml', import.meta.url), 'utf8');
const snapshot = JSON.parse(await readFile(new URL('../latest-videos.json', import.meta.url), 'utf8'));
const request = (path, method = 'GET') => new Request('https://starter-kit.example' + path, {method});
const entry = (id, title, date) => `<entry><yt:videoId>${id}</yt:videoId><title>${title}</title><published>${date}</published></entry>`;

test('official feed yields exactly nine newest distinct video IDs', () => {
  const videos = parseFeed(feed);
  assert.equal(videos.length, 9);
  assert.equal(new Set(videos.map(v => v.id)).size, 9);
  assert.deepEqual(videos.map(v => v.id), snapshot.videos.map(v => v.id));
  assert.ok(videos.every((v, i) => !i || Date.parse(v.published) <= Date.parse(videos[i-1].published)));
});

test('feed parser sorts, deduplicates, decodes titles and ignores malformed entries', () => {
  const xml = '<feed>' + entry('aaaaaaaaaaa', 'Old', '2025-01-01T00:00:00Z') +
    entry('bbbbbbbbbbb', 'A &amp; B &#x1f3ae;', '2026-01-01T00:00:00Z') +
    entry('ccccccccccc', '<![CDATA[Test <title>]]>', '2026-02-01T00:00:00Z') +
    entry('bbbbbbbbbbb', 'Duplicate', '2026-01-01T00:00:00Z') +
    entry('../bad', 'Invalid ID', '2026-10-01T00:00:00Z') + entry('ddddddddddd', 'No date', 'invalid') +
    'defghijk'.split('').map((c, i) => entry(c.repeat(11), 'Older ' + c, `2024-01-${String(i+1).padStart(2,'0')}T00:00:00Z`)).join('') + '</feed>';
  const videos = parseFeed(xml);
  assert.equal(videos.length, 9);
  assert.deepEqual(videos.slice(0, 3).map(v => v.id), ['ccccccccccc','bbbbbbbbbbb','aaaaaaaaaaa']);
  assert.equal(new Set(videos.map(v => v.id)).size, 9);
  assert.equal(videos[0].title, 'Test <title>');
  assert.equal(videos[1].title, 'A & B 🎮');
  assert.throws(() => parseFeed('<feed/>'));
});

test('concurrent page requests share one live feed request and cache it', async () => {
  let calls = 0;
  const worker = createWorker({}, snapshot, async url => {
    calls++; assert.equal(url, FEED_URL);
    return new Response(feed);
  });
  const results = await Promise.all(Array.from({length: 4}, () => worker.fetch(request('/api/latest-videos'))));
  for (const response of results) {
    const data = await response.json();
    assert.equal(data.stale, false);
    assert.equal(data.videos.length, 9);
  }
  assert.equal(calls, 1);
  const head = await worker.fetch(request('/api/latest-videos', 'HEAD'));
  assert.equal(await head.text(), '');
  assert.equal(calls, 1);
});

test('upstream errors preserve last available videos and explicitly mark stale data', async () => {
  for (const result of [async () => new Response('unavailable', {status:503}), async () => { throw new Error('network'); }, async () => new Response('<feed/>')]) {
    const worker = createWorker({}, snapshot, result);
    const response = await worker.fetch(request('/api/latest-videos'));
    const data = await response.json();
    assert.equal(data.stale, true);
    assert.equal(data.fetchedAt, snapshot.fetchedAt);
    assert.deepEqual(data.videos, snapshot.videos);
    assert.equal(response.headers.get('cache-control'), 'no-store');
  }
});

test('all seven pages contain nine cards, official links and standalone downloads', async () => {
  const products = ['https://store.steampowered.com/steamos/', 'https://cachyos.org/', 'https://bazzite.gg/', 'https://decky.xyz/', 'https://retrodeck.net/', 'https://www.emudeck.com/'];
  const content = JSON.parse(await readFile(new URL('../content.json', import.meta.url), 'utf8'));
  for (const lang of ['de','en','es','fr','ru','zh','ja']) {
    const page = await readFile(new URL(`../public/${lang}/index.html`, import.meta.url), 'utf8');
    assert.equal((page.match(/<article class="latest-card">/g) || []).length, 9, lang);
    assert.equal((page.match(/class="button button-primary" href="\/downloads\/Linux-Handheld-Starter-Kit.desktop" download/g) || []).length, 3, lang);
    assert.ok(page.includes('href="/downloads/install.sh" download'), lang);
    assert.ok(page.includes('https://github.com/Steamdeckchecker/LinuxGamingStarterKit'), lang);
    assert.ok(page.includes('id="tutorial-video"'), lang);
    assert.ok(page.includes(content[lang].latestTitle), lang);
    assert.ok(content[lang].footerNote.includes('EmuDeck') && content[lang].footerNote.includes('RetroDECK'), lang);
    for (const url of products) assert.ok(page.includes('href="' + url + '"'), `${lang}: ${url}`);
  }
});

test('final deployment artifact serves pages, original logo and correct installer bytes', async () => {
  const source = await readFile(new URL('../dist/server/index.js', import.meta.url), 'utf8');
  const {default: worker} = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
  for (const path of ['/', '/de/', '/en/', '/es/', '/fr/', '/ru/', '/zh/', '/ja/']) {
    const response = await worker.fetch(request(path));
    assert.equal(response.status, 200, path);
    assert.match(response.headers.get('content-type'), /text\/html/);
    assert.match(await response.text(), /id="latest-video-list"/);
  }
  const installer = await worker.fetch(request('/downloads/install.sh'));
  const actual = Buffer.from(await installer.arrayBuffer());
  assert.deepEqual(actual, await readFile(new URL('../public/downloads/install.sh', import.meta.url)));
  assert.match(installer.headers.get('content-disposition'), /attachment; filename="install.sh"/);
  const desktop = await worker.fetch(request('/downloads/Linux-Handheld-Starter-Kit.desktop'));
  assert.equal(desktop.headers.get('content-type'), 'application/x-desktop');
  assert.match(desktop.headers.get('content-disposition'), /attachment; filename="Linux-Handheld-Starter-Kit.desktop"/);
  assert.deepEqual(Buffer.from(await desktop.arrayBuffer()), await readFile(new URL('../public/downloads/Linux-Handheld-Starter-Kit.desktop', import.meta.url)));
  const logo = await worker.fetch(request('/assets/steam-deck-checker.png'));
  assert.deepEqual(Buffer.from(await logo.arrayBuffer()), await readFile(new URL('../public/assets/steam-deck-checker.png', import.meta.url)));
  assert.equal((await worker.fetch(request('/en'))).status, 308);
  assert.equal((await worker.fetch(request('/missing'))).status, 404);
  assert.equal((await worker.fetch(request('/api/latest-videos', 'POST'))).status, 405);
});
