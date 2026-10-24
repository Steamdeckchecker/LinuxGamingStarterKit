(() => {
  'use strict';
  const language = document.querySelector('#language');
  language?.addEventListener('change', () => {
    const code = language.value;
    if (!['de','en','es','fr','ru','zh','ja'].includes(code)) return;
    try { localStorage.setItem('starter-kit-language', code); } catch (_) {}
    location.assign('/' + code + '/' + location.hash);
  });
  if (location.pathname === '/') {
    try {
      const saved = localStorage.getItem('starter-kit-language');
      if (saved && saved !== 'de' && ['en','es','fr','ru','zh','ja'].includes(saved)) location.replace('/' + saved + '/' + location.hash);
    } catch (_) {}
  }
  document.querySelectorAll('[data-device]').forEach(button => {
    button.addEventListener('click', () => {
      document.querySelectorAll('[data-device]').forEach(other => other.setAttribute('aria-pressed', String(button === other)));
      const output = document.querySelector('#matched-device');
      if (output) output.textContent = button.dataset.device;
    });
  });
  const tabs = [...document.querySelectorAll('[role="tab"]')];
  function selectTab(tab) {
    tabs.forEach(other => {
      const active = other === tab;
      other.setAttribute('aria-selected', String(active));
      other.tabIndex = active ? 0 : -1;
      const panel = document.getElementById(other.getAttribute('aria-controls'));
      if (panel) panel.hidden = !active;
    });
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => selectTab(tab));
    tab.addEventListener('keydown', event => {
      let target;
      if (event.key === 'ArrowRight') target = tabs[(index + 1) % tabs.length];
      if (event.key === 'ArrowLeft') target = tabs[(index - 1 + tabs.length) % tabs.length];
      if (event.key === 'Home') target = tabs[0];
      if (event.key === 'End') target = tabs[tabs.length - 1];
      if (target) { event.preventDefault(); target.focus(); selectTab(target); }
    });
  });
  document.querySelectorAll('[data-copy]').forEach(button => {
    button.addEventListener('click', async () => {
      const status = document.querySelector('#copy-status');
      try {
        if (navigator.clipboard?.writeText) {
          await navigator.clipboard.writeText(button.dataset.copy);
        } else {
          const input = document.createElement('textarea');
          input.value = button.dataset.copy;
          input.setAttribute('readonly', '');
          input.style.position = 'fixed'; input.style.opacity = '0';
          document.body.appendChild(input); input.select();
          const ok = document.execCommand('copy'); input.remove(); button.focus();
          if (!ok) throw new Error('Clipboard unavailable');
        }
        if (status) status.textContent = document.body.dataset.copied;
      } catch (_) {
        if (status) status.textContent = document.body.dataset.copyError;
      }
    });
  });
  const latest = document.querySelector('#latest-videos');
  if (latest) {
    const list = latest.querySelector('#latest-video-list');
    const status = latest.querySelector('#latest-video-status');
    const originalDate = status?.querySelector('time')?.dateTime;
    const template = list?.querySelector('.latest-card');
    const dateLabel = value => {
      const date = new Date(value);
      return Number.isNaN(date.getTime()) ? '' : new Intl.DateTimeFormat(document.documentElement.lang, {
        year: 'numeric', month: 'short', day: 'numeric'
      }).format(date);
    };
    latest.querySelectorAll('time').forEach(time => { time.textContent = dateLabel(time.dateTime); });
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 12000);
    if (status) status.textContent = latest.dataset.loading;
    fetch('/api/latest-videos?limit=9', { signal: controller.signal, credentials: 'same-origin' })
      .then(response => { if (!response.ok) throw new Error('Feed unavailable'); return response.json(); })
      .then(data => {
        const seen = new Set();
        const videos = Array.isArray(data.videos) ? data.videos.filter(video => {
          if (!/^[\w-]{11}$/.test(video.id) || seen.has(video.id) || typeof video.title !== 'string' || !video.title.trim() || !dateLabel(video.published)) return false;
          seen.add(video.id); return true;
        }).slice(0, 9) : [];
        if (videos.length !== 9 || !template || !dateLabel(data.fetchedAt)) throw new Error('Incomplete feed');
        const cards = videos.map(video => {
          const card = template.cloneNode(true);
          card.querySelector('a').href = 'https://www.youtube.com/watch?v=' + video.id;
          card.querySelector('img').src = 'https://i.ytimg.com/vi/' + video.id + '/hqdefault.jpg';
          card.querySelector('h3').textContent = video.title;
          const time = card.querySelector('time');
          time.dateTime = video.published; time.textContent = dateLabel(video.published);
          return card;
        });
        list.replaceChildren(...cards);
        if (status) status.textContent = (data.stale ? latest.dataset.snapshot : latest.dataset.updated) + ' ' + dateLabel(data.fetchedAt);
      })
      .catch(() => {
        if (status) status.textContent = latest.dataset.unavailable + (originalDate ? ' ' + latest.dataset.snapshot + ' ' + dateLabel(originalDate) : '');
      })
      .finally(() => clearTimeout(timer));
  }

  const videoId = window.STARTER_KIT?.youtubeVideoId;
  const holder = document.querySelector('#tutorial-video');
  if (holder && typeof videoId === 'string' && /^[\w-]{11}$/.test(videoId)) {
    const button = document.createElement('button');
    button.type = 'button'; button.className = 'video-play';
    button.setAttribute('aria-label', holder.dataset.play);
    const thumbnail = document.createElement('img');
    thumbnail.src = 'https://i.ytimg.com/vi/' + videoId + '/hqdefault.jpg';
    thumbnail.alt = holder.dataset.play;
    thumbnail.loading = 'lazy';
    const play = document.createElement('span'); play.textContent = '▶'; play.setAttribute('aria-hidden', 'true');
    button.append(thumbnail, play);
    holder.className = 'video-holder'; holder.replaceChildren(button);
    button.addEventListener('click', () => {
      const player = document.createElement('iframe');
      player.src = 'https://www.youtube-nocookie.com/embed/' + videoId + '?autoplay=1';
      player.title = holder.dataset.play;
      player.allow = 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture';
      player.allowFullscreen = true; player.referrerPolicy = 'strict-origin-when-cross-origin';
      holder.replaceChildren(player);
    });
  }
})();
