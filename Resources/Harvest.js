// Injected into x.com before the page's own scripts run. It reads the photos out of
// the Bookmarks and Likes timeline pages the site already downloads for itself, and
// can keep scrolling so the site downloads the next page. Nothing else is read.
(() => {
  if (window.__wpHarvest) return;
  window.__wpHarvest = true;

  const timeline = /\/graphql\/[^/?]+\/(Bookmarks|BookmarkFolderTimeline|Likes)(?:\?|$)/;

  const post = (message) => {
    try {
      window.webkit.messageHandlers.harvest.postMessage(JSON.stringify(message));
    } catch (e) {}
  };

  // Walks the whole response instead of following X's exact layout, so a renamed
  // wrapper object doesn't break the import. Photos in quoted tweets count too.
  const collect = (json) => {
    const photos = new Map();
    let entries = 0;
    const walk = (node) => {
      if (!node || typeof node !== 'object') return;
      if (Array.isArray(node)) {
        node.forEach(walk);
        return;
      }
      if (typeof node.entryId === 'string' && !node.entryId.startsWith('cursor-')) entries++;
      if (node.type === 'photo' && typeof node.media_url_https === 'string') {
        const known = photos.get(node.media_url_https);
        const width = (node.original_info && node.original_info.width) || 0;
        if (!known || (!known.width && width)) {
          photos.set(node.media_url_https, {
            url: node.media_url_https,
            tweetUrl: node.expanded_url || null,
            width,
            height: (node.original_info && node.original_info.height) || 0,
          });
        }
      }
      for (const key in node) walk(node[key]);
    };
    walk(json);
    return { photos: [...photos.values()], entries };
  };

  let autoTimer = null;
  let lastPageAt = 0;

  const stopAuto = () => {
    clearInterval(autoTimer);
    autoTimer = null;
  };

  const handle = (url, status, json) => {
    const match = String(url).match(timeline);
    if (!match) return;
    // A rate-limited or failed page is not the end of the list.
    if (status !== 200 || !json || !json.data) {
      post({ event: 'error', status });
      return;
    }
    lastPageAt = Date.now();
    const { photos, entries } = collect(json);
    post({ event: 'photos', op: match[1], entries, photos });
    // X answers the request after the last page with only cursors.
    if (entries === 0 && autoTimer) {
      stopAuto();
      post({ event: 'end', reason: 'done' });
    }
  };

  const open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__wpUrl = String(url);
    return open.apply(this, arguments);
  };
  const send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function () {
    if (timeline.test(this.__wpUrl || '')) {
      this.addEventListener('load', () => {
        try {
          const json = this.responseType === 'json' ? this.response : JSON.parse(this.responseText);
          handle(this.__wpUrl, this.status, json);
        } catch (e) {
          post({ event: 'error', status: -1 });
        }
      });
    }
    return send.apply(this, arguments);
  };

  const nativeFetch = window.fetch;
  window.fetch = function (input) {
    const url = input && typeof input === 'object' && 'url' in input ? input.url : String(input);
    const result = nativeFetch.apply(this, arguments);
    if (timeline.test(url)) {
      result
        .then((response) => response.clone().json().then((json) => handle(url, response.status, json)))
        .catch(() => {});
    }
    return result;
  };

  const retryLabel = /^(retry|try again|إعادة المحاولة|أعد المحاولة|حاول مرة أخرى)$/i;

  const tick = () => {
    window.scrollTo(0, document.documentElement.scrollHeight);
    const idle = Date.now() - lastPageAt;
    if (idle > 12000) {
      const retry = [...document.querySelectorAll('[role="button"]')].find((button) =>
        retryLabel.test((button.textContent || '').trim())
      );
      if (retry) retry.click();
    }
    if (idle > 45000) {
      stopAuto();
      post({ event: 'end', reason: 'idle' });
    }
  };

  window.__wpAuto = (on) => {
    stopAuto();
    if (on) {
      lastPageAt = Date.now();
      autoTimer = setInterval(tick, 1500);
    }
    post({ event: 'running', running: !!on });
  };

  let lastLoggedIn = null;
  const reportSession = () => {
    const loggedIn = /(?:^|;\s*)twid=/.test(document.cookie);
    if (loggedIn !== lastLoggedIn) {
      lastLoggedIn = loggedIn;
      post({ event: 'session', loggedIn });
    }
  };
  reportSession();
  setInterval(reportSession, 1500);
})();
