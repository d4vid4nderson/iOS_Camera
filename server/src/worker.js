// Film Exposures share links.
//
//   GET  /f/<code>                  a shared film: the whole recipe is in <code>, nothing is stored
//   GET  /r/<id>                    a shared roll: a teaser page that asks people to get the app
//   GET  /r/<id>/roll.json          the roll's details, for the app's viewer
//   GET  /r/<id>/<file>.jpg         a frame, the card or the sharer's headshot
//   POST /api/rolls                 start sharing a roll -> { id, token, url, expiresAt }
//   PUT  /api/rolls/<id>/<file>     upload a frame / card / avatar      (Bearer token)
//   POST /api/rolls/<id>/publish    make it visible                     (Bearer token)
//   DELETE /api/rolls/<id>          unshare: delete everything          (Bearer token, or admin)
//   POST /api/rolls/<id>/report     report a roll; 3 reports hide it until reviewed
//   GET  /.well-known/apple-app-site-association   lets these links open the app
//
// Rolls are deleted 30 days after they're shared (checked on every read, and swept daily).

export const APP_ID = 'RN599658F9.com.davidanderson.retrocam';
export const TTL_DAYS = 30;
export const MAX_FRAMES = 36;
export const MAX_IMAGE_BYTES = 4 * 1024 * 1024;
export const HIDE_AFTER_REPORTS = 3;
const DAY = 24 * 60 * 60 * 1000;

export default {
  async fetch(request, env) {
    try {
      return await route(request, env);
    } catch (error) {
      console.error(error);
      return text(500, 'Something went wrong.');
    }
  },
  async scheduled(_event, env) {
    await sweep(env);
  },
};

export async function route(request, env, now = Date.now()) {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, '') || '/';
  const method = request.method;
  let m;

  if (path === '/.well-known/apple-app-site-association' || path === '/apple-app-site-association') {
    return json(200, {
      applinks: { details: [{ appIDs: [APP_ID], components: [{ '/': '/f/*' }, { '/': '/r/*' }] }] },
    });
  }
  if (path === '/' && method === 'GET') return html(200, homePage(env));

  if ((m = path.match(/^\/f\/([A-Za-z0-9_-]{4,200})$/)) && method === 'GET') {
    const film = decodeFilm(m[1]);
    if (!film) return html(404, messagePage('This film link is damaged.', env));
    return html(200, filmPage(film, m[1], url, env));
  }

  if (path === '/api/rolls' && method === 'POST') return createRoll(request, env, url, now);
  if ((m = path.match(/^\/api\/rolls\/([A-Za-z0-9]{10})\/(frame-\d{2}\.jpg|card\.jpg|avatar\.jpg)$/)) && method === 'PUT') {
    return uploadFile(request, env, m[1], m[2], now);
  }
  if ((m = path.match(/^\/api\/rolls\/([A-Za-z0-9]{10})\/publish$/)) && method === 'POST') {
    return publishRoll(request, env, m[1], now);
  }
  if ((m = path.match(/^\/api\/rolls\/([A-Za-z0-9]{10})$/)) && method === 'DELETE') {
    return unshareRoll(request, env, m[1]);
  }
  if ((m = path.match(/^\/api\/rolls\/([A-Za-z0-9]{10})\/report$/)) && method === 'POST') {
    return reportRoll(request, env, m[1], now);
  }

  if ((m = path.match(/^\/r\/([A-Za-z0-9]{10})$/)) && method === 'GET') {
    const meta = await liveRoll(env, m[1], now);
    if (!meta) return html(404, messagePage('This roll has expired or was unshared.', env));
    return html(200, rollPage(meta, url, env));
  }
  if ((m = path.match(/^\/r\/([A-Za-z0-9]{10})\/roll\.json$/)) && method === 'GET') {
    const meta = await liveRoll(env, m[1], now);
    if (!meta) return json(404, { error: 'gone' });
    return json(200, publicMeta(meta, url));
  }
  if ((m = path.match(/^\/r\/([A-Za-z0-9]{10})\/(frame-\d{2}\.jpg|card\.jpg|avatar\.jpg)$/)) && method === 'GET') {
    const meta = await liveRoll(env, m[1], now);
    if (!meta) return text(404, 'Not found');
    const object = await env.ROLLS.get(`rolls/${m[1]}/${m[2]}`);
    if (!object) return text(404, 'Not found');
    return new Response(object.body, {
      headers: { 'content-type': 'image/jpeg', 'cache-control': 'public, max-age=86400' },
    });
  }

  return html(404, messagePage('Nothing here.', env));
}

// MARK: Rolls

async function createRoll(request, env, url, now) {
  const body = await readJSON(request);
  if (!body) return json(400, { error: 'Expected JSON' });
  const frames = Number(body.frames);
  if (!Number.isInteger(frames) || frames < 1 || frames > MAX_FRAMES) return json(400, { error: 'frames must be 1-36' });
  const id = randomID(10);
  const token = randomHex(32);
  const meta = {
    id,
    status: 'uploading',
    createdAt: now,
    expiresAt: now + TTL_DAYS * DAY,
    frames,
    title: clean(body.title, 60) || 'A roll',
    film: {
      name: clean(body.film?.name, 24),
      code: /^[A-Za-z0-9_-]{4,200}$/.test(body.film?.code || '') ? body.film.code : null,
    },
    sharer: {
      id: /^[A-Za-z0-9-]{8,64}$/.test(body.sharer?.id || '') ? body.sharer.id : null,
      name: clean(body.sharer?.name, 24),
      avatar: false,
    },
    shotAt: clean(body.shotAt, 40),
    tokenHash: await sha256(token),
    reports: 0,
  };
  await putMeta(env, meta);
  return json(201, { id, token, url: `${url.origin}/r/${id}`, expiresAt: new Date(meta.expiresAt).toISOString() });
}

async function uploadFile(request, env, id, file, now) {
  const meta = await getMeta(env, id);
  if (!meta || expired(meta, now)) return json(404, { error: 'gone' });
  if (!(await authorised(request, meta, env))) return json(401, { error: 'unauthorised' });
  if (meta.status !== 'uploading') return json(409, { error: 'already published' });
  const frame = file.match(/^frame-(\d{2})\.jpg$/);
  if (frame && (Number(frame[1]) < 1 || Number(frame[1]) > meta.frames)) return json(400, { error: 'frame out of range' });
  const bytes = await request.arrayBuffer();
  if (bytes.byteLength === 0 || bytes.byteLength > MAX_IMAGE_BYTES) return json(413, { error: 'image too large' });
  const head = new Uint8Array(bytes, 0, 3);
  if (head[0] !== 0xff || head[1] !== 0xd8 || head[2] !== 0xff) return json(415, { error: 'JPEG only' });
  await env.ROLLS.put(`rolls/${id}/${file}`, bytes, { httpMetadata: { contentType: 'image/jpeg' } });
  if (file === 'avatar.jpg' && !meta.sharer.avatar) {
    meta.sharer.avatar = true;
    await putMeta(env, meta);
  }
  return json(200, { ok: true });
}

async function publishRoll(request, env, id, now) {
  const meta = await getMeta(env, id);
  if (!meta || expired(meta, now)) return json(404, { error: 'gone' });
  if (!(await authorised(request, meta, env))) return json(401, { error: 'unauthorised' });
  for (let n = 1; n <= meta.frames; n++) {
    if (!(await env.ROLLS.head(`rolls/${id}/${frameName(n)}`))) return json(409, { error: `frame ${n} missing` });
  }
  meta.status = 'live';
  await putMeta(env, meta);
  return json(200, { ok: true });
}

async function unshareRoll(request, env, id) {
  const meta = await getMeta(env, id);
  if (!meta) return json(200, { ok: true });   // already gone
  if (!(await authorised(request, meta, env))) return json(401, { error: 'unauthorised' });
  await deleteRoll(env, id);
  return json(200, { ok: true });
}

async function reportRoll(request, env, id, now) {
  const meta = await getMeta(env, id);
  if (!meta || expired(meta, now)) return json(404, { error: 'gone' });
  let reason = 'Inappropriate';
  const type = request.headers.get('content-type') || '';
  if (type.includes('application/json')) {
    reason = clean((await readJSON(request))?.reason, 200) || reason;
  } else if (type.includes('form')) {
    reason = clean((await request.formData()).get('reason'), 200) || reason;
  }
  await env.ROLLS.put(`reports/${id}/${now}.json`, JSON.stringify({ id, reason, at: new Date(now).toISOString() }));
  meta.reports = (meta.reports || 0) + 1;
  if (meta.reports >= HIDE_AFTER_REPORTS && meta.status === 'live') meta.status = 'hidden';
  await putMeta(env, meta);
  if (type.includes('form')) return html(200, messagePage('Thanks. The roll has been reported and will be reviewed.', env));
  return json(200, { ok: true });
}

/// The roll if it's published and not expired (an expired roll is deleted on sight).
async function liveRoll(env, id, now) {
  const meta = await getMeta(env, id);
  if (!meta) return null;
  if (expired(meta, now)) {
    await deleteRoll(env, id);
    return null;
  }
  return meta.status === 'live' ? meta : null;
}

export async function sweep(env, now = Date.now()) {
  let cursor;
  let removed = 0;
  do {
    const page = await env.ROLLS.list({ prefix: 'meta/', cursor });
    for (const object of page.objects) {
      const meta = await getMeta(env, object.key.slice(5, -5));
      if (meta && expired(meta, now)) {
        await deleteRoll(env, meta.id);
        removed++;
      }
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return removed;
}

async function deleteRoll(env, id) {
  let cursor;
  do {
    const page = await env.ROLLS.list({ prefix: `rolls/${id}/`, cursor });
    const keys = page.objects.map((o) => o.key);
    if (keys.length) await env.ROLLS.delete(keys);
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  await env.ROLLS.delete(`meta/${id}.json`);
}

function publicMeta(meta, url) {
  const base = `${url.origin}/r/${meta.id}`;
  return {
    id: meta.id,
    title: meta.title,
    film: meta.film,
    sharer: { id: meta.sharer.id, name: meta.sharer.name, avatar: meta.sharer.avatar ? `${base}/avatar.jpg` : null },
    shotAt: meta.shotAt,
    frames: Array.from({ length: meta.frames }, (_, i) => `${base}/${frameName(i + 1)}`),
    card: `${base}/card.jpg`,
    expiresAt: new Date(meta.expiresAt).toISOString(),
  };
}

const frameName = (n) => `frame-${String(n).padStart(2, '0')}.jpg`;
const expired = (meta, now) => now >= meta.expiresAt;
const getMeta = async (env, id) => {
  const object = await env.ROLLS.get(`meta/${id}.json`);
  return object ? JSON.parse(await object.text()) : null;
};
const putMeta = (env, meta) => env.ROLLS.put(`meta/${meta.id}.json`, JSON.stringify(meta));

async function authorised(request, meta, env) {
  const header = request.headers.get('authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (!token) return false;
  if (env.ADMIN_TOKEN && token === env.ADMIN_TOKEN) return true;
  return (await sha256(token)) === meta.tokenHash;
}

// MARK: Film codes (mirror of RetroCam/FilmCode.swift)

const FIELDS = [
  ['red', -1, 2], ['green', -1, 2], ['blue', -1, 2],
  ['contrast', 0, 1], ['key', -1, 1], ['blackLift', 0, 0.25], ['whitePoint', 0.75, 1],
  ['grain', 0, 1], ['grainSize', 0.6, 3], ['vignette', 0, 1.2],
  ['toneAmount', 0, 1], ['bloom', 0, 1], ['edgeSoftness', 0, 1], ['exposure', -1, 1], ['fog', 0, 1],
  ['effectAmount', 0, 1], ['effectX', 0, 1], ['effectY', 0, 1],
];
export const TONES = ['neutral', 'warm', 'cool', 'selenium', 'split', 'gold', 'platinum', 'cyanotype', 'tintype'];
const TONE_NAMES = {
  warm: 'Sepia', cool: 'Cool', selenium: 'Selenium', split: 'Split', gold: 'Gold',
  platinum: 'Platinum', cyanotype: 'Cyanotype', tintype: 'Tintype',
};
// Ink, mid and paper colours of each toning (RetroCam/FilmStock.swift, Toning.stops).
const STOPS = {
  neutral: [[0, 0, 0], [0.5, 0.5, 0.5], [1, 1, 1]],
  warm: [[0.03, 0.015, 0], [0.57, 0.47, 0.35], [1, 0.95, 0.85]],
  cool: [[0, 0.005, 0.025], [0.46, 0.5, 0.56], [0.97, 1, 1]],
  selenium: [[0.04, 0, 0.035], [0.51, 0.46, 0.49], [1, 1, 0.99]],
  split: [[0, 0.01, 0.045], [0.53, 0.48, 0.46], [1, 0.9, 0.8]],
  gold: [[0, 0.01, 0.04], [0.46, 0.49, 0.54], [1, 0.99, 0.97]],
  platinum: [[0.05, 0.04, 0.03], [0.55, 0.5, 0.44], [0.97, 0.94, 0.88]],
  cyanotype: [[0.02, 0.1, 0.28], [0.28, 0.45, 0.62], [0.96, 0.97, 0.95]],
  tintype: [[0.04, 0.03, 0.02], [0.48, 0.44, 0.38], [0.88, 0.85, 0.76]],
};
export const EFFECTS = ['none', 'fisheye', 'swirl', 'tiltShift', 'zoomBurst', 'drag', 'double', 'prism', 'ripple', 'halftone', 'etch', 'kaleido'];
const EFFECT_NAMES = {
  fisheye: 'Fisheye', swirl: 'Swirl', tiltShift: 'Tilt-shift', zoomBurst: 'Zoom burst', drag: 'Drag',
  double: 'Double exposure', prism: 'Prism', ripple: 'Ripple', halftone: 'Halftone', etch: 'Etch', kaleido: 'Kaleido',
};

export function decodeFilm(code) {
  let bytes;
  try {
    const b64 = code.replace(/-/g, '+').replace(/_/g, '/');
    bytes = Uint8Array.from(atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4)), (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
  const fixed = 1 + FIELDS.length + 2 + 2;
  if (bytes.length < fixed || bytes[0] !== 1) return null;
  const film = {};
  FIELDS.forEach(([name, lo, hi], i) => { film[name] = lo + (bytes[1 + i] / 255) * (hi - lo); });
  let at = 1 + FIELDS.length;
  if (bytes[at] >= TONES.length || bytes[at + 1] >= EFFECTS.length) return null;
  film.tone = TONES[bytes[at]];
  film.effect = EFFECTS[bytes[at + 1]];
  at += 2;
  film.iso = (bytes[at] << 8) | bytes[at + 1];
  at += 2;
  try {
    film.name = new TextDecoder('utf-8', { fatal: true }).decode(bytes.slice(at)).slice(0, 18) || 'SHARED FILM';
  } catch {
    return null;
  }
  return film;
}

/// "Black & white · ISO 50 · Fine grain" (FilmStock.shareCaption).
export function caption(film) {
  const kind = film.tone === 'neutral' || film.toneAmount < 0.3 ? 'Black & white' : `${TONE_NAMES[film.tone]} toned`;
  const texture = film.grain < 0.2 ? 'Fine grain' : film.grain < 0.45 ? 'Medium grain' : 'Heavy grain';
  return `${kind} · ISO ${film.iso} · ${texture}`;
}

/// An approximate tone scale for the page: black to white through the film's range and toning.
function toneScale(film, steps = 9) {
  const [ink, mid, paper] = STOPS[film.tone] || STOPS.neutral;
  const a = film.toneAmount;
  return Array.from({ length: steps }, (_, i) => {
    const x = film.blackLift + (i / (steps - 1)) * (film.whitePoint - film.blackLift);
    const rgb = [0, 1, 2].map((c) => {
      const k = a * ink[c], m2 = 0.5 + a * (mid[c] - 0.5), p = 1 + a * (paper[c] - 1);
      const c1 = -3 * k + 4 * m2 - p, c2 = 2 * k - 4 * m2 + 2 * p;
      return Math.round(Math.min(Math.max(k + c1 * x + c2 * x * x, 0), 1) * 255);
    });
    return `rgb(${rgb.join(',')})`;
  });
}

function settingsList(film) {
  const pct = (v) => `${Math.round(v * 100)}%`;
  const rows = [
    ['Contrast', pct(film.contrast)], ['Grain', pct(film.grain)], ['Vignette', pct(film.vignette / 1.2)],
  ];
  if (film.toneAmount >= 0.05 && film.tone !== 'neutral') rows.push(['Toning', `${TONE_NAMES[film.tone]} ${pct(film.toneAmount)}`]);
  if (film.bloom > 0.02) rows.push(['Glow', pct(film.bloom)]);
  if (film.fog > 0.02) rows.push(['Fog', pct(film.fog)]);
  if (film.edgeSoftness > 0.02) rows.push(['Soft edges', pct(film.edgeSoftness)]);
  if (film.effect !== 'none') rows.push(['Effect', `${EFFECT_NAMES[film.effect]} ${pct(film.effectAmount)}`]);
  return rows;
}

// MARK: Pages

function filmPage(film, code, url, env) {
  const title = `${film.name} · a film on Film Exposures`;
  const strip = toneScale(film).map((c) => `<i style="background:${c}"></i>`).join('');
  const rows = settingsList(film).map(([k, v]) => `<li><span>${esc(k)}</span><b>${esc(v)}</b></li>`).join('');
  return layout({
    title, description: caption(film), url: url.href, env,
    body: `
      <p class="eyebrow">FILM EXPOSURES · SHARED FILM</p>
      <h1>${esc(film.name)}</h1>
      <p class="muted">${esc(caption(film))}</p>
      <div class="strip">${strip}</div>
      <ul class="settings">${rows}</ul>
      <a class="button primary" href="exposures://f/${code}">Load this film in Film Exposures</a>
      ${storeButton(env)}
      <p class="small muted">Every setting comes with it: curve, filter, toning, grain, vignette and effects.</p>`,
  });
}

function rollPage(meta, url, env) {
  // On the web a roll is a teaser: its card (the first frames) and who shot it. The whole
  // roll opens in the app, so people without it are asked to get it.
  const base = `/r/${meta.id}`;
  const who = meta.sharer.name ? esc(meta.sharer.name) : 'Someone';
  const avatar = meta.sharer.avatar ? `<img class="avatar" src="${base}/avatar.jpg" alt="">` : '';
  const frames = `${meta.frames} ${meta.frames === 1 ? 'frame' : 'frames'}`;
  const film = meta.film.name ? ` · shot on ${esc(meta.film.name)}` : '';
  const store = storeURL(env);
  const get = store
    ? `<a class="button primary" href="${esc(store)}">Get Film Exposures to see the whole roll</a>`
    : '<p class="button disabled">Film Exposures is coming soon to the App Store</p>';
  return layout({
    title: `${meta.title} · ${who} on Film Exposures`,
    description: `${meta.frames} frames${meta.film.name ? ` shot on ${meta.film.name}` : ''}. Open it in Film Exposures.`,
    image: `${url.origin}${base}/card.jpg`, url: url.href, env, appArgument: url.href,
    body: `
      <div class="who">${avatar}<span>${who} shared a roll</span></div>
      <h1>${esc(meta.title)}</h1>
      <p class="muted">${frames}${film}</p>
      <img class="card" src="${base}/card.jpg" alt="${esc(meta.title)}">
      ${get}
      <a class="button" href="exposures://r/${meta.id}">Already have Film Exposures? Open the roll</a>
      <p class="small muted">Swipe through every frame and load the film it was shot on, right in the app.</p>
      <details class="report"><summary>Report this roll</summary>
        <form method="post" action="/api/rolls/${meta.id}/report">
          <select name="reason"><option>Nudity or sexual content</option><option>Violence or abuse</option><option>Hate or harassment</option><option>Spam</option><option>Something else</option></select>
          <button type="submit">Send report</button>
        </form></details>
      <p class="small muted">Shared rolls disappear ${new Date(meta.expiresAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' })}.</p>`,
  });
}

function homePage(env) {
  return layout({ title: 'Film Exposures', description: 'A film camera for your iPhone.', env, body: `
    <p class="eyebrow">FILM EXPOSURES</p><h1>A film camera for your iPhone.</h1>
    <p class="muted">Shoot rolls of 36, develop them later, and share your films.</p>${storeButton(env)}` });
}

function messagePage(message, env) {
  return layout({ title: 'Film Exposures', description: message, env, body: `
    <p class="eyebrow">FILM EXPOSURES</p><h1>${esc(message)}</h1>${storeButton(env)}` });
}

/// The App Store page: APP_STORE_ID (the app's Apple ID, from App Store Connect), or a full
/// APP_STORE_URL (e.g. a public TestFlight link). Empty until the app is listed.
export function storeURL(env) {
  if (env.APP_STORE_ID) return `https://apps.apple.com/app/id${String(env.APP_STORE_ID).replace(/\D/g, '')}`;
  return env.APP_STORE_URL || '';
}

function storeButton(env) {
  const store = storeURL(env);
  return store ? `<a class="button" href="${esc(store)}">Get Film Exposures</a>` : '';
}

function layout({ title, description, image, url, body, env, appArgument }) {
  const appID = env?.APP_STORE_ID ? String(env.APP_STORE_ID).replace(/\D/g, '') : '';
  return `<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(description)}">
${url ? `<meta property="og:url" content="${esc(url)}">` : ''}
${appID ? `<meta name="apple-itunes-app" content="app-id=${appID}${appArgument ? `, app-argument=${esc(appArgument)}` : ''}">` : ''}
${image ? `<meta property="og:image" content="${esc(image)}"><meta name="twitter:card" content="summary_large_image">` : '<meta name="twitter:card" content="summary">'}
<style>
:root{--bg:#0e0e0f;--fg:#f2f0ec;--muted:#8c8a86;--line:#2a2a2b;--accent:#e8762e}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.45 -apple-system,BlinkMacSystemFont,"Inter","Segoe UI",sans-serif}
main{max-width:640px;margin:0 auto;padding:32px 16px 56px}
.eyebrow{font-size:12px;letter-spacing:.08em;color:var(--muted);font-weight:600;margin:0 0 12px}
h1{font-size:44px;line-height:1.05;letter-spacing:-.02em;margin:0 0 8px}
.muted{color:var(--muted)}.small{font-size:13px}
.strip{display:flex;gap:4px;margin:24px 0}.strip i{flex:1;height:56px;border-radius:6px}
.settings{list-style:none;padding:0;margin:0 0 24px;border-top:1px solid var(--line)}
.settings li{display:flex;justify-content:space-between;padding:10px 0;border-bottom:1px solid var(--line)}
.settings span{color:var(--muted)}
.button{display:block;text-align:center;padding:14px;border-radius:999px;margin:10px 0;text-decoration:none;color:var(--fg);background:#1d1d1e;font-weight:600}
.button.primary{background:var(--accent);color:#111}
.who{display:flex;align-items:center;gap:10px;margin-bottom:16px;font-weight:600}
.avatar{width:40px;height:40px;border-radius:50%;object-fit:cover}
.card{width:100%;display:block;border-radius:14px;margin:20px 0 8px}
.button.disabled{color:var(--muted);background:transparent;border:1px solid var(--line)}
.report{margin-top:32px;color:var(--muted)}.report form{display:flex;gap:8px;margin-top:10px;flex-wrap:wrap}
select,button{font:inherit;padding:8px 12px;border-radius:8px;border:1px solid var(--line);background:#1d1d1e;color:var(--fg)}
</style></head><body><main>${body}</main></body></html>`;
}

// MARK: Helpers

function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function clean(value, max) {
  if (typeof value !== 'string') return '';
  return value.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, max);
}
async function readJSON(request) {
  try { return await request.json(); } catch { return null; }
}
function randomID(length) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  let id = '';
  for (const b of bytes) id += alphabet[b % alphabet.length];
  return id.padEnd(length, 'x').replace(/[^A-Za-z0-9]/g, 'x');
}
function randomHex(bytes) {
  return [...crypto.getRandomValues(new Uint8Array(bytes))].map((b) => b.toString(16).padStart(2, '0')).join('');
}
async function sha256(value) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
const json = (status, body) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
const html = (status, body) => new Response(body, { status, headers: { 'content-type': 'text/html; charset=utf-8' } });
const text = (status, body) => new Response(body, { status, headers: { 'content-type': 'text/plain' } });
