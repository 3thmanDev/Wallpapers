// Runs Resources/Harvest.txt against fake X timeline responses, outside any browser:
//   node Tests/harvest-check.js
// The responses copy the shape of X's real Bookmarks/Likes pages (checked against a
// live account), with made-up ids and no real tweets.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

let failures = 0;
const check = (condition, label) => {
  if (condition) {
    console.log(`ok    ${label}`);
  } else {
    failures++;
    console.log(`FAIL  ${label}`);
  }
};

const photo = (name, tweet, width, height, withSize = true) => ({
  type: 'photo',
  id_str: name.length + '00' + tweet,
  media_url_https: `https://pbs.twimg.com/media/${name}.jpg`,
  expanded_url: `https://x.com/someone/status/${tweet}/photo/1`,
  ...(withSize ? { original_info: { width, height, focus_rects: [] } } : {}),
});

const tweetEntry = (tweet, media, quoted) => ({
  entryId: `tweet-${tweet}`,
  sortIndex: tweet,
  content: {
    entryType: 'TimelineTimelineItem',
    itemContent: {
      itemType: 'TimelineTweet',
      tweet_results: {
        result: {
          __typename: 'Tweet',
          rest_id: tweet,
          legacy: {
            // X lists the photos twice; the first copy sometimes has no size.
            entities: { media: media.map((m) => ({ ...m, original_info: undefined })) },
            extended_entities: { media },
          },
          ...(quoted ? { quoted_status_result: { result: quoted } } : {}),
        },
      },
    },
  },
});

const cursor = (kind) => ({ entryId: `cursor-${kind}-1`, content: { entryType: 'TimelineTimelineCursor', value: 'abc' } });

const page = (key, entries) => ({
  data: { [key]: { timeline: { instructions: [{ type: 'TimelineAddEntries', entries }] } } },
});

const firstBookmarks = page('bookmark_timeline_v2', [
  tweetEntry('1001', [photo('AAAAportrait1', '1001', 1290, 2796), photo('AAAAportrait2', '1001', 1290, 2796)]),
  tweetEntry('1002', [{ type: 'video', media_url_https: 'https://pbs.twimg.com/ext_tw_video_thumb/1/pu/img/x.jpg' }]),
  tweetEntry('1003', [], {
    __typename: 'Tweet',
    rest_id: '900',
    legacy: { extended_entities: { media: [photo('QQQQquoted', '900', 1080, 1920)] } },
  }),
  cursor('top'),
  cursor('bottom'),
]);
const lastPage = page('bookmark_timeline_v2', [cursor('top'), cursor('bottom')]);
const likes = page('favorites_timeline', [tweetEntry('2001', [photo('LLLLsquare', '2001', 2048, 2048)]), cursor('bottom')]);

// Minimal browser: a fake XMLHttpRequest whose responses the test decides.
const messages = [];
const intervals = [];
class FakeXHR {
  open(method, url) {
    this.url = url;
  }
  addEventListener(type, listener) {
    this.listener = listener;
  }
  send() {
    this.sent = true;
  }
  respond(status, body) {
    this.status = status;
    this.responseType = '';
    this.responseText = JSON.stringify(body);
    if (this.listener) this.listener();
  }
}
const window = {
  webkit: { messageHandlers: { harvest: { postMessage: (text) => messages.push(JSON.parse(text)) } } },
  fetch: () => new Promise(() => {}),
  scrollTo: () => {},
};
const context = {
  window,
  XMLHttpRequest: FakeXHR,
  document: { cookie: 'guest_id=1; twid=u%3D123; ct0=abc', documentElement: { scrollHeight: 9000 }, querySelectorAll: () => [] },
  setInterval: (fn) => intervals.push(fn) && intervals.length,
  clearInterval: () => {},
  console,
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'Resources', 'Harvest.txt'), 'utf8'), context);

const request = (url) => {
  const xhr = new context.XMLHttpRequest();
  xhr.open('GET', url);
  xhr.send();
  return xhr;
};
const take = () => messages.splice(0, messages.length);

check(take().some((m) => m.event === 'session' && m.loggedIn === true), 'reports signed in from the twid cookie');

request('/i/api/graphql/abc123/Bookmarks?variables=%7B%7D').respond(200, firstBookmarks);
let sent = take();
let photos = sent.find((m) => m.event === 'photos');
check(photos && photos.op === 'Bookmarks', 'bookmarks page is reported as Bookmarks');
check(photos && photos.photos.length === 3, `3 photos found, videos skipped (got ${photos && photos.photos.length})`);
check(photos && photos.entries === 3, `3 tweet entries counted, cursors not (got ${photos && photos.entries})`);
check(photos && photos.photos.every((p) => p.width > 0 && p.height > 0), 'every photo keeps its original size');
check(photos && photos.photos.some((p) => p.url.includes('QQQQquoted')), 'photo in a quoted tweet is found');
check(photos && photos.photos[0].tweetUrl === 'https://x.com/someone/status/1001/photo/1', 'tweet link is passed on');
check(!sent.some((m) => m.event === 'end'), 'no end while not auto-scrolling');

request('https://x.com/i/api/graphql/xyz/HomeTimeline?variables=1').respond(200, firstBookmarks);
check(take().length === 0, 'home timeline is ignored');

window.__wpAuto(true);
check(take().some((m) => m.event === 'running' && m.running === true), 'auto-scroll reports running');

request('/i/api/graphql/abc123/Bookmarks?variables=2').respond(429, { errors: [{ message: 'Rate limit exceeded' }] });
sent = take();
check(sent.some((m) => m.event === 'error' && m.status === 429), 'rate limit is reported as an error');
check(!sent.some((m) => m.event === 'end'), 'rate limit is not taken as the end');

request('/i/api/graphql/abc123/Likes?variables=3').respond(200, likes);
photos = take().find((m) => m.event === 'photos');
check(photos && photos.op === 'Likes' && photos.photos.length === 1, 'likes page is reported as Likes');

request('/i/api/graphql/abc123/Bookmarks?variables=4').respond(200, lastPage);
sent = take();
check(sent.some((m) => m.event === 'photos' && m.entries === 0), 'last page has no entries');
check(sent.some((m) => m.event === 'end' && m.reason === 'done'), 'last page ends the auto-scroll');

console.log(failures === 0 ? 'harvest: all checks passed' : `harvest: ${failures} checks failed`);
process.exit(failures === 0 ? 0 : 1);
