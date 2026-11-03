// Film Exposures share links.
//
//   GET  /f/<code>                  a shared film: the whole recipe is in <code>, nothing is stored
//   GET  /r/<id>                    a shared roll: a teaser page that asks people to get the app
//   GET  /r/<id>/roll.json          the roll's details, for the app's viewer
//   GET  /r/<id>/<file>.jpg         a frame, the card or the sharer's headshot
//   POST /api/rolls                 start sharing a roll -> { id, token, url, expiresAt }
//   PUT  /api/rolls/<id>/<file>     upload a frame / card / avatar      (Bearer token)
//                                   once it's live: add the next frame (a roll still being shot
//                                   grows as its frames develop), or replace the card
//   POST /api/rolls/<id>/publish    make it visible                     (Bearer token)
//   DELETE /api/rolls/<id>          unshare: delete everything          (Bearer token, or admin)
//   POST /api/rolls/<id>/report     report a roll; 3 reports hide it until reviewed
//   POST /api/rolls/<id>/visibility { public }   put a roll on your profile, or take it off (account)
//   POST /api/rolls/<id>/cover { cover }  which frame (1-based) is the roll's cover (Bearer token, or owner)
//   GET  /api/rolls/<id>/likes      { counts: { "<frame>": n }, mine: [frame],   (account optional)
//                                     likers: { "<frame>": [{ id, name, avatar }] } }
//                                   frame "0" is the whole roll
//   PUT|DELETE /api/rolls/<id>/frames/<n>/like   like or unlike a frame          (account)
//   PUT|DELETE /api/rolls/<id>/like              like or unlike the whole roll   (account)
//
//   POST /api/auth/apple { identityToken }  Sign in with Apple -> { token, me }
//   POST /api/auth/google { idToken }       Sign in with Google -> { token, me }
//   POST /api/auth/facebook { code, redirectUri }  Facebook Login -> { token, me }
//   GET  /auth/facebook/callback            Facebook sends people back here; it opens the app
//        (signed in already? the same calls add that sign-in to your account instead)
//   POST /api/me/avatar/use { provider }    go back to your Google or Facebook photo (account)
//   POST /api/auth/signout                  forget this session              (account)
//   POST /api/apple/notifications           Apple: someone stopped using Sign in with Apple
//        here or deleted their Apple Account; that sign-in (or the whole account) is removed
//   GET|PUT|DELETE /api/me                  your profile: { name } / delete your account (account)
//   PUT|DELETE /api/me/avatar               your headshot (JPEG)             (account)
//   POST /api/me/terms                      agree to the rules for public rolls (account)
//   GET  /u/<id>                            a profile page; /u/<id>/profile.json for the app
//        (signed in: also the rolls shared with your followers or with you, and whether you follow)
//
//   Social (all "(account)"):
//   PUT  /api/me { name, handle, discoverable }   your @handle (unique) and whether search finds you
//   GET  /api/users/search?q=                search people by @handle or name
//   GET  /api/users/browse?after=            everyone findable, by handle, a page at a time
//   POST|DELETE /api/users/<id>/follow       ask to follow (they approve) / unfollow or cancel
//   GET  /api/users/<id>/followers|following  who follows them / whom they follow
//   POST|DELETE /api/users/<id>/block        block: no following, finding or sharing either way
//   GET  /api/me/requests                    people asking to follow you
//   POST /api/me/requests/<id> { accept }    approve or turn down a follow request
//   DELETE /api/me/followers/<id>            remove a follower
//   GET  /api/feed                           recent rolls from people you follow
//   GET  /api/rolls/browse?after=            everyone's public rolls, newest first, a page at a time
//   GET  /api/me/inbox                       rolls shared with you
//   POST /api/rolls/<id>/visibility { audience, people }  who sees a roll: private, people,
//        followers, public, or link (anyone with the link, for 30 days)
//
// A roll that isn't public or link-shared hands out its photos as signed links that expire,
// so only the people it's for can load them.
//   GET  /privacy, /terms, /support         the website's policy pages and support form
//   POST /api/support                       a support message (stored; no email address is published)
//   GET  /admin                             the support inbox (password: the ADMIN_TOKEN secret)
//   GET|DELETE /api/admin/support[/<id>]    read / clear support messages (Bearer ADMIN_TOKEN)
//   GET  /.well-known/apple-app-site-association   lets these links open the app
//
// "(account)" means an X-Account header with the session token from /api/auth/*.
// Link-shared rolls are deleted 30 days after they're shared (checked on every read, and swept
// daily). Rolls on a profile stay until they're taken off it or deleted.

import { SITE_CSS, siteHeader, siteFooter, homeBody, privacyBody, termsBody, supportBody, inboxBody, SUPPORT_TOPICS } from './site.js';

export const APP_ID = 'RN599658F9.com.davidanderson.retrocam';
export const TTL_DAYS = 30;
export const MAX_FRAMES = 36;
export const MAX_IMAGE_BYTES = 4 * 1024 * 1024;
export const HIDE_AFTER_REPORTS = 3;
export const APPLE_ISSUER = 'https://appleid.apple.com';
export const APPLE_AUDIENCE = 'com.davidanderson.retrocam';
export const GOOGLE_ISSUERS = ['https://accounts.google.com', 'accounts.google.com'];
export const PROVIDERS = ['apple', 'google', 'facebook'];
const FACEBOOK_GRAPH = 'https://graph.facebook.com/v19.0';
const DAY = 24 * 60 * 60 * 1000;
const ROLL = '([A-Za-z0-9]{10})';
const USER = '([A-Za-z0-9]{12})';

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
  // www.filmexposures.com -> filmexposures.com, so every link has one address.
  if (url.hostname.startsWith('www.')) {
    url.hostname = url.hostname.slice(4);
    return new Response(null, { status: 301, headers: { location: url.href } });
  }
  const path = url.pathname.replace(/\/+$/, '') || '/';
  const method = request.method;
  let m;

  if (path === '/.well-known/apple-app-site-association' || path === '/apple-app-site-association') {
    return json(200, {
      applinks: { details: [{ appIDs: [APP_ID], components: [{ '/': '/f/*' }, { '/': '/r/*' }, { '/': '/u/*' }] }] },
    });
  }
  if (path === '/' && method === 'GET') return html(200, homePage(env));
  if (path === '/privacy' && method === 'GET') {
    return html(200, layout({ title: 'Privacy policy · Film Exposures', description: 'What Film Exposures collects, and the choices you have.', env, body: privacyBody() }));
  }
  if (path === '/terms' && method === 'GET') {
    return html(200, layout({ title: 'Terms of use · Film Exposures', description: 'The terms for using Film Exposures.', env, body: termsBody() }));
  }
  if (path === '/support' && method === 'GET') {
    return html(200, layout({ title: 'Support · Film Exposures', description: 'Get help with Film Exposures.', env,
      body: supportBody({ sent: url.searchParams.get('sent') === '1' }) }));
  }
  if (path === '/api/support' && method === 'POST') return submitSupport(request, env, now);
  if (path === '/admin' && method === 'GET') {
    return html(200, layout({ title: 'Support inbox · Film Exposures', description: 'Support inbox', env, body: inboxBody(), noindex: true }));
  }
  if (path === '/api/admin/support' && method === 'GET') return listSupport(request, env);
  if ((m = path.match(/^\/api\/admin\/support\/([A-Za-z0-9-]{8,64})$/)) && method === 'DELETE') return closeSupport(request, env, m[1]);

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
  if ((m = path.match(new RegExp(`^/api/rolls/${ROLL}/visibility$`))) && method === 'POST') {
    return setVisibility(request, env, m[1], url, now);
  }
  if ((m = path.match(new RegExp(`^/api/rolls/${ROLL}/cover$`))) && method === 'POST') {
    return setCover(request, env, m[1], now);
  }
  if ((m = path.match(new RegExp(`^/api/rolls/${ROLL}/likes$`))) && method === 'GET') {
    return listLikes(request, env, m[1], now);
  }
  if ((m = path.match(new RegExp(`^/api/rolls/${ROLL}/frames/(\\d{1,2})/like$`))) && (method === 'PUT' || method === 'DELETE')) {
    const frame = Number(m[2]);
    if (frame < 1) return json(400, { error: 'frame out of range' });
    return likeFrame(request, env, m[1], frame, method === 'PUT', now);
  }
  if ((m = path.match(new RegExp(`^/api/rolls/${ROLL}/like$`))) && (method === 'PUT' || method === 'DELETE')) {
    return likeFrame(request, env, m[1], 0, method === 'PUT', now);
  }

  if (path === '/api/auth/apple' && method === 'POST') return signInWithApple(request, env, url, now);
  if (path === '/api/auth/google' && method === 'POST') return signInWithGoogle(request, env, url, now);
  if (path === '/api/auth/facebook' && method === 'POST') return signInWithFacebook(request, env, url, now);
  if (path === '/auth/facebook/callback' && method === 'GET') {
    // Facebook only sends people back to a web address; this hands the code to the app.
    const back = new URL('exposures://auth/facebook');
    for (const key of ['code', 'state', 'error']) {
      const value = url.searchParams.get(key);
      if (value) back.searchParams.set(key, value.slice(0, 2000));
    }
    return new Response(null, { status: 302, headers: { location: back.href } });
  }
  if (path === '/api/me/avatar/use' && method === 'POST') return useProviderPhoto(request, env, url);
  if (path === '/api/auth/signout' && method === 'POST') return signOut(request, env);
  if (path === '/api/apple/notifications' && method === 'POST') return appleNotification(request, env, now);
  if (path === '/api/me' && method === 'GET') return withUser(request, env, (user) => json(200, mePayload(user, url)));
  if (path === '/api/me' && method === 'PUT') return updateMe(request, env, url);
  if (path === '/api/me' && method === 'DELETE') return deleteAccount(request, env);
  if (path === '/api/me/avatar' && (method === 'PUT' || method === 'DELETE')) return updateAvatar(request, env, url, method === 'PUT');
  if (path === '/api/me/terms' && method === 'POST') {
    return withUser(request, env, async (user) => {
      user.termsAt = user.termsAt || now;
      await putUser(env, user);
      return json(200, mePayload(user, url));
    });
  }

  if (path === '/api/users/search' && method === 'GET') return searchUsers(request, env, url);
  if (path === '/api/users/browse' && method === 'GET') return browseUsers(request, env, url);
  if ((m = path.match(new RegExp(`^/api/users/${USER}/follow$`))) && (method === 'POST' || method === 'DELETE')) {
    return follow(request, env, url, m[1], method === 'POST', now);
  }
  if ((m = path.match(new RegExp(`^/api/users/${USER}/(followers|following)$`))) && method === 'GET') {
    return followList(request, env, url, m[1], m[2]);
  }
  if ((m = path.match(new RegExp(`^/api/users/${USER}/block$`))) && (method === 'POST' || method === 'DELETE')) {
    return block(request, env, m[1], method === 'POST');
  }
  if (path === '/api/me/requests' && method === 'GET') return listRequests(request, env, url);
  if ((m = path.match(new RegExp(`^/api/me/requests/${USER}$`))) && method === 'POST') return answerRequest(request, env, url, m[1]);
  if ((m = path.match(new RegExp(`^/api/me/followers/${USER}$`))) && method === 'DELETE') return removeFollower(request, env, m[1]);
  if (path === '/api/feed' && method === 'GET') return feed(request, env, url, now);
  if (path === '/api/rolls/browse' && method === 'GET') return browseRolls(request, env, url, now);
  if (path === '/api/me/inbox' && method === 'GET') return inbox(request, env, url, now);

  if ((m = path.match(new RegExp(`^/u/${USER}$`))) && method === 'GET') {
    const profile = await publicProfile(env, m[1], url, now);
    if (!profile) return html(404, messagePage('There is no profile here.', env));
    return html(200, profilePage(profile, url, env));
  }
  if ((m = path.match(new RegExp(`^/u/${USER}/profile\\.json$`))) && method === 'GET') {
    const profile = await publicProfile(env, m[1], url, now, await currentUser(request, env));
    if (!profile) return json(404, { error: 'gone' });
    return json(200, profile);
  }
  if ((m = path.match(new RegExp(`^/u/${USER}/avatar\\.jpg$`))) && method === 'GET') {
    const object = await env.ROLLS.get(`users/${m[1]}/avatar.jpg`);
    if (!object) return text(404, 'Not found');
    return new Response(object.body, { headers: { 'content-type': 'image/jpeg', 'cache-control': 'public, max-age=300' } });
  }

  if ((m = path.match(/^\/r\/([A-Za-z0-9]{10})$/)) && method === 'GET') {
    const meta = await liveRoll(env, m[1], now);
    if (!meta) return html(404, messagePage('This roll has expired or was unshared.', env));
    // The web has no sign-in, so it only shows rolls that anyone may see.
    if (!isOpen(meta)) return html(404, messagePage('This roll is only for the people it was shared with. Open it in Film Exposures.', env));
    return html(200, rollPage(await rollPayload(env, meta, url, now), meta, url, env));
  }
  if ((m = path.match(/^\/r\/([A-Za-z0-9]{10})\/roll\.json$/)) && method === 'GET') {
    const meta = await liveRoll(env, m[1], now);
    const viewer = await currentUser(request, env);
    if (!meta || !(await canView(env, meta, viewer))) return json(404, { error: 'gone' });
    return json(200, await rollPayload(env, meta, url, now, viewer));
  }
  if ((m = path.match(/^\/r\/([A-Za-z0-9]{10})\/(frame-\d{2}\.jpg|card\.jpg|avatar\.jpg)$/)) && method === 'GET') {
    const meta = await liveRoll(env, m[1], now);
    if (!meta) return text(404, 'Not found');
    const open = isOpen(meta);
    if (!open && !(await signedOK(env, meta.id, m[2], url, now)) && !(await canView(env, meta, await currentUser(request, env)))) {
      return text(404, 'Not found');
    }
    const object = await env.ROLLS.get(`rolls/${m[1]}/${m[2]}`);
    if (!object) return text(404, 'Not found');
    return new Response(object.body, {
      headers: { 'content-type': 'image/jpeg', 'cache-control': open ? 'public, max-age=86400' : 'private, max-age=3600' },
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
  const user = await currentUser(request, env);
  const id = randomID(10);
  const token = randomHex(32);
  const meta = {
    id,
    status: 'uploading',
    createdAt: now,
    expiresAt: now + TTL_DAYS * DAY,
    frames,
    cover: coverFrame(body.cover, frames),
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
    owner: null,
    public: false,
  };
  if (user) own(meta, user);
  await putMeta(env, meta);
  if (user) await env.ROLLS.put(`users/${user.id}/rolls/${id}`, '1');
  return json(201, { id, token, url: `${url.origin}/r/${id}`, expiresAt: new Date(meta.expiresAt).toISOString() });
}

async function uploadFile(request, env, id, file, now) {
  const meta = await getMeta(env, id);
  if (!meta || expired(meta, now)) return json(404, { error: 'gone' });
  if (!(await authorised(request, meta, env))) return json(401, { error: 'unauthorised' });
  const frame = file.match(/^frame-(\d{2})\.jpg$/);
  // A live roll can take its next frame (the roll is still being shot) or a new card.
  const appending = meta.status === 'live' && frame && Number(frame[1]) === meta.frames + 1 && meta.frames < MAX_FRAMES;
  if (meta.status !== 'uploading' && !appending && !(meta.status === 'live' && file === 'card.jpg')) {
    return json(409, { error: 'already published' });
  }
  if (frame && !appending && (Number(frame[1]) < 1 || Number(frame[1]) > meta.frames)) return json(400, { error: 'frame out of range' });
  const bytes = await request.arrayBuffer();
  if (bytes.byteLength === 0 || bytes.byteLength > MAX_IMAGE_BYTES) return json(413, { error: 'image too large' });
  const head = new Uint8Array(bytes, 0, 3);
  if (head[0] !== 0xff || head[1] !== 0xd8 || head[2] !== 0xff) return json(415, { error: 'JPEG only' });
  await env.ROLLS.put(`rolls/${id}/${file}`, bytes, { httpMetadata: { contentType: 'image/jpeg' } });
  if (appending) {
    meta.frames += 1;
    await putMeta(env, meta);
    return json(200, { ok: true, frames: meta.frames });
  }
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
  if (!isOpen(meta) && !(await canView(env, meta, await currentUser(request, env)))) return json(404, { error: 'gone' });
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

// MARK: Support form

export const SUPPORT_PER_HOUR = 5;

/// A support message from the website's form (or JSON). Stored for the inbox; the
/// sender's email is kept only to reply. A filled-in hidden field marks a bot: it's
/// thanked and dropped. Each address can send a handful an hour.
async function submitSupport(request, env, now) {
  const type = request.headers.get('content-type') || '';
  const isForm = !type.includes('application/json');
  let fields = {};
  if (isForm) {
    try { fields = Object.fromEntries((await request.formData()).entries()); } catch { fields = {}; }
  } else {
    fields = (await readJSON(request)) || {};
  }
  const back = (problem) => isForm
    ? html(problem ? 400 : 200, layout({ title: 'Support · Film Exposures', description: 'Get help with Film Exposures.', env,
        body: supportBody({ sent: !problem, error: problem || '' }) }))
    : json(problem ? 400 : 200, problem ? { error: problem } : { ok: true });

  if (fields.website) return back('');   // the hidden field: a bot
  const email = clean(fields.email, 200);
  const name = clean(fields.name, 80);
  const topic = SUPPORT_TOPICS.includes(fields.topic) ? fields.topic : 'Something else';
  const message = typeof fields.message === 'string' ? fields.message.replace(/\u0000/g, '').trim().slice(0, 4000) : '';
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return back('Please give an email address we can reply to.');
  if (message.length < 10) return back('Please tell us a little more (at least 10 characters).');

  const ip = request.headers.get('cf-connecting-ip') || 'unknown';
  const hour = Math.floor(now / (60 * 60 * 1000));
  const rateKey = `support-rate/${hour}/${(await sha256(`${ip}:${hour}`)).slice(0, 32)}`;
  const sentThisHour = Number(await (await env.ROLLS.get(rateKey))?.text() || 0);
  if (sentThisHour >= SUPPORT_PER_HOUR) return back('Too many messages from here in the last hour. Please try again later.');
  await env.ROLLS.put(rateKey, String(sentThisHour + 1));

  const id = `${now}-${randomID(8)}`;
  await env.ROLLS.put(`support/${id}.json`, JSON.stringify({ id, at: new Date(now).toISOString(), email, name, topic, message }));
  return back('');
}

async function adminOnly(request, env, handler) {
  if (!env.ADMIN_TOKEN) return json(503, { error: 'not set up' });
  const header = request.headers.get('authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (!token || (await sha256(token)) !== (await sha256(env.ADMIN_TOKEN))) return json(401, { error: 'unauthorised' });
  return handler();
}

async function listSupport(request, env) {
  return adminOnly(request, env, async () => {
    const messages = [];
    for await (const keys of listKeys(env, 'support/')) {
      for (const key of keys) {
        const object = await env.ROLLS.get(key);
        if (object) messages.push(JSON.parse(await object.text()));
      }
    }
    messages.sort((a, b) => (a.at < b.at ? 1 : -1));
    return json(200, { messages: messages.slice(0, 200) });
  });
}

async function closeSupport(request, env, id) {
  return adminOnly(request, env, async () => {
    const object = await env.ROLLS.get(`support/${id}.json`);
    if (object) {
      await env.ROLLS.put(`support-done/${id}.json`, await object.text());
      await env.ROLLS.delete(`support/${id}.json`);
    }
    return json(200, { ok: true });
  });
}

// MARK: Public rolls and likes

/// Put a roll on its owner's profile (it stops expiring), or take it off (it expires 30 days
/// from now, like a link share). Signing in claims a roll shared before you had an account:
/// send the roll's own token too.
async function setVisibility(request, env, id, url, now) {
  const user = await currentUser(request, env);
  if (!user) return json(401, { error: 'sign in first' });
  const meta = await getMeta(env, id);
  if (!meta || expired(meta, now)) return json(404, { error: 'gone' });
  if (meta.owner !== user.id) {
    if (meta.owner || !(await authorised(request, meta, env))) return json(403, { error: 'not your roll' });
    own(meta, user);
    await env.ROLLS.put(`users/${user.id}/rolls/${id}`, '1');
  }
  const body = (await readJSON(request)) || {};
  // Older apps send { public }; newer ones say who the roll is for.
  const audience = AUDIENCES.includes(body.audience) ? body.audience : body.public ? 'public' : 'link';
  if (SHARED.includes(audience) && !user.termsAt) return json(403, { error: 'terms' });
  let people = [];
  if (audience === 'people') {
    const ids = [...new Set(Array.isArray(body.people) ? body.people : [])].filter((x) => typeof x === 'string' && new RegExp(`^${USER}$`).test(x) && x !== user.id);
    if (ids.length > MAX_PEOPLE) return json(400, { error: `at most ${MAX_PEOPLE} people` });
    for (const pid of ids) {
      if ((await getUser(env, pid)) && !(await blockedEitherWay(env, user.id, pid))) people.push(pid);
    }
    if (!people.length) return json(400, { error: 'choose who to share it with' });
  }
  // The inbox follows who the roll is shared with.
  const before = audienceOf(meta) === 'people' ? meta.people || [] : [];
  for (const pid of before.filter((x) => !people.includes(x))) await env.ROLLS.delete(`inbox/${pid}/${id}`);
  for (const pid of people.filter((x) => !before.includes(x))) await env.ROLLS.put(`inbox/${pid}/${id}`, String(now));
  meta.audience = audience;
  meta.people = people;
  meta.public = audience === 'public';
  await indexPublic(env, meta, now);
  meta.expiresAt = SHARED.includes(audience) ? null : now + TTL_DAYS * DAY;
  await putMeta(env, meta);
  return json(200, {
    audience, people, public: meta.public,
    expiresAt: meta.expiresAt == null ? null : new Date(meta.expiresAt).toISOString(),
  });
}

/// The roll's cover frame (1-based); anything out of range is the first frame.
function coverFrame(value, frames) {
  const n = Number(value);
  return Number.isInteger(n) && n >= 1 && n <= frames ? n : 1;
}

/// Choose which frame is the roll's cover (on profiles). Its owner, or its token.
async function setCover(request, env, id, now) {
  const meta = await getMeta(env, id);
  if (!meta || expired(meta, now)) return json(404, { error: 'gone' });
  const user = await currentUser(request, env);
  if (!(user && meta.owner === user.id) && !(await authorised(request, meta, env))) return json(401, { error: 'unauthorised' });
  const body = (await readJSON(request)) || {};
  const n = Number(body.cover);
  if (!Number.isInteger(n) || n < 1 || n > meta.frames) return json(400, { error: 'cover out of range' });
  meta.cover = n;
  await putMeta(env, meta);
  return json(200, { cover: n });
}

/// Who liked each frame, and the roll itself (frame 0), by name and headshot.
export const MAX_LIKERS_SHOWN = 50;

async function listLikes(request, env, id, now) {
  const meta = await liveRoll(env, id, now);
  const user = await currentUser(request, env);
  if (!meta || !(await canView(env, meta, user))) return json(404, { error: 'gone' });
  const origin = new URL(request.url).origin;
  const counts = {};
  const mine = [];
  const ids = {};
  for await (const keys of listKeys(env, `likes/${id}/`)) {
    for (const key of keys) {
      const [, , frame, liker] = key.split('/');
      const n = Number(frame);
      counts[n] = (counts[n] || 0) + 1;
      if (user && liker === user.id) mine.push(n);
      (ids[n] ||= []).push(liker);
    }
  }
  // Each person is looked up once, however many frames they liked. Accounts that have
  // since been deleted are left out.
  const people = new Map();
  const person = async (uid) => {
    if (!people.has(uid)) {
      const u = await getUser(env, uid);
      people.set(uid, u && { id: u.id, name: u.name || null, avatar: u.avatar ? `${origin}/u/${u.id}/avatar.jpg?v=${u.avatar}` : null });
    }
    return people.get(uid);
  };
  const likers = {};
  for (const [n, list] of Object.entries(ids)) {
    // You first, then everyone else.
    const ordered = [...list].sort((a, b) => (b === user?.id) - (a === user?.id));
    likers[n] = (await Promise.all(ordered.slice(0, MAX_LIKERS_SHOWN).map(person))).filter(Boolean);
  }
  return json(200, { counts, mine: mine.sort((a, b) => a - b), likers });
}

async function likeFrame(request, env, id, frame, on, now) {
  const user = await currentUser(request, env);
  if (!user) return json(401, { error: 'sign in first' });
  const meta = await liveRoll(env, id, now);
  if (!meta || !(await canView(env, meta, user))) return json(404, { error: 'gone' });
  if (frame < 0 || frame > meta.frames) return json(400, { error: 'frame out of range' });   // 0: the roll
  const nn = String(frame).padStart(2, '0');
  // One object per like, so two people liking at once can't overwrite each other.
  const keys = [`likes/${id}/${nn}/${user.id}`, `users/${user.id}/likes/${id}/${nn}`];
  if (on) {
    for (const key of keys) await env.ROLLS.put(key, '1');
  } else {
    await env.ROLLS.delete(keys);
  }
  let count = 0;
  for await (const page of listKeys(env, `likes/${id}/${nn}/`)) count += page.length;
  return json(200, { frame, liked: on, count });
}

// MARK: Accounts (Sign in with Apple)

async function signInWithApple(request, env, url, now) {
  const body = await readJSON(request);
  const claims = body?.identityToken ? await verifyAppleToken(String(body.identityToken), env, now) : null;
  if (!claims) return json(401, { error: 'Sign in with Apple could not be verified.' });
  return signIn(request, env, url, now, 'apple', claims.sub, { name: clean(body.name, 24) });
}

async function signInWithGoogle(request, env, url, now) {
  const body = await readJSON(request);
  const claims = body?.idToken ? await verifyGoogleToken(String(body.idToken), env, now) : null;
  if (!claims) return json(401, { error: 'Sign in with Google could not be verified.' });
  // Google's photo URLs end in a size (=s96-c); ask for a bigger one.
  const photo = typeof claims.picture === 'string' ? claims.picture.replace(/=s\d+(-c)?$/, '=s600-c') : null;
  return signIn(request, env, url, now, 'google', claims.sub, { name: clean(claims.name, 24), photo });
}

/// Facebook Login: the app gets a code from Facebook's login page; the server swaps it for
/// an access token (which needs the app secret), then asks Facebook who it is.
async function signInWithFacebook(request, env, url, now) {
  if (!env.FACEBOOK_APP_ID || !env.FACEBOOK_APP_SECRET) return json(503, { error: 'Facebook Login is not set up.' });
  const body = await readJSON(request);
  const code = typeof body?.code === 'string' ? body.code : '';
  const redirectUri = `${url.origin}/auth/facebook/callback`;
  if (!code) return json(400, { error: 'Expected a code' });
  const exchange = new URL(`${FACEBOOK_GRAPH}/oauth/access_token`);
  exchange.search = new URLSearchParams({
    client_id: env.FACEBOOK_APP_ID, client_secret: env.FACEBOOK_APP_SECRET, redirect_uri: redirectUri, code,
  }).toString();
  const tokenRes = await facebookFetch(env, exchange.href);
  const accessToken = tokenRes?.access_token;
  if (!accessToken) return json(401, { error: 'Facebook Login could not be verified.' });
  const me = new URL(`${FACEBOOK_GRAPH}/me`);
  me.search = new URLSearchParams({ fields: 'id,name,picture.width(600).height(600)', access_token: accessToken }).toString();
  const person = await facebookFetch(env, me.href);
  if (!person?.id) return json(401, { error: 'Facebook Login could not be verified.' });
  const picture = person.picture?.data;
  const photo = picture && !picture.is_silhouette && typeof picture.url === 'string' ? picture.url : null;
  return signIn(request, env, url, now, 'facebook', String(person.id), { name: clean(person.name, 24), photo });
}

async function facebookFetch(env, href) {
  try {
    const res = await (env.FETCH || fetch)(href);
    return res.ok ? await res.json() : null;
  } catch {
    return null;
  }
}

/// Sign in with a provider's verified id. Already signed in (X-Account), it adds this
/// sign-in to your account instead. The provider's photo becomes your headshot when you
/// don't have one of your own, and is kept so you can go back to it.
async function signIn(request, env, url, now, provider, sub, { name, photo }) {
  const key = await sha256(`${provider}:${sub}`);
  const link = await env.ROLLS.get(`accounts/${key}.json`);
  const linkedID = link ? JSON.parse(await link.text()).id : null;
  const current = await currentUser(request, env);
  let user;
  let token = null;

  if (current) {
    if (linkedID && linkedID !== current.id) {
      return json(409, { error: `That ${providerName(provider)} account already belongs to another Film Exposures account.` });
    }
    user = current;
  } else {
    user = linkedID ? await getUser(env, linkedID) : null;
    if (!user) {
      user = { id: randomID(12), name, avatar: 0, avatarSource: null, createdAt: now, termsAt: null, logins: {} };
    }
  }
  logins(user)[provider] = key;
  if (!user.name && name) user.name = name;
  if (photo && (await importPhoto(env, user, provider, photo))) {
    user.photos = { ...(user.photos || {}), [provider]: true };
    if (!user.avatar) await setAvatarFromProvider(env, user, provider);
  }
  await putUser(env, user);
  await env.ROLLS.put(`accounts/${key}.json`, JSON.stringify({ id: user.id }));

  if (!current) {
    token = randomHex(32);
    const hash = await sha256(token);
    await env.ROLLS.put(`sessions/${hash}.json`, JSON.stringify({ id: user.id, createdAt: now }));
    await env.ROLLS.put(`users/${user.id}/sessions/${hash}`, '1');
  }
  return json(200, { token, me: mePayload(user, url) });
}

const PHOTO_HOSTS = [/\.googleusercontent\.com$/, /\.fbcdn\.net$/, /^platform-lookaside\.fbsbx\.com$/, /^graph\.facebook\.com$/];

/// Keep a copy of a provider's photo (JPEG only, from the provider's own image hosts).
async function importPhoto(env, user, provider, href) {
  let target;
  try { target = new URL(href); } catch { return false; }
  if (target.protocol !== 'https:' || !PHOTO_HOSTS.some((host) => host.test(target.hostname))) return false;
  try {
    const res = await (env.FETCH || fetch)(target.href);
    if (!res.ok) return false;
    const bytes = await res.arrayBuffer();
    if (bytes.byteLength === 0 || bytes.byteLength > MAX_IMAGE_BYTES) return false;
    const head = new Uint8Array(bytes, 0, 3);
    if (head[0] !== 0xff || head[1] !== 0xd8 || head[2] !== 0xff) return false;
    await env.ROLLS.put(`users/${user.id}/photo-${provider}.jpg`, bytes, { httpMetadata: { contentType: 'image/jpeg' } });
    return true;
  } catch {
    return false;
  }
}

async function setAvatarFromProvider(env, user, provider) {
  const object = await env.ROLLS.get(`users/${user.id}/photo-${provider}.jpg`);
  if (!object) return false;
  await env.ROLLS.put(`users/${user.id}/avatar.jpg`, await new Response(object.body).arrayBuffer(),
    { httpMetadata: { contentType: 'image/jpeg' } });
  user.avatar = (user.avatar || 0) + 1;
  user.avatarSource = provider;
  return true;
}

async function useProviderPhoto(request, env, url) {
  return withUser(request, env, async (user) => {
    const provider = (await readJSON(request))?.provider;
    if (!PROVIDERS.includes(provider) || !user.photos?.[provider]) return json(404, { error: 'no photo from that sign-in' });
    if (!(await setAvatarFromProvider(env, user, provider))) return json(404, { error: 'no photo from that sign-in' });
    await putUser(env, user);
    return json(200, mePayload(user, url));
  });
}

/// The sign-ins on an account ({ apple: key, google: key }); older accounts kept one appleKey.
function logins(user) {
  if (!user.logins) user.logins = {};
  if (user.appleKey) {
    user.logins.apple = user.logins.apple || user.appleKey;
    delete user.appleKey;
  }
  return user.logins;
}

const providerName = (p) => ({ apple: 'Apple', google: 'Google', facebook: 'Facebook' }[p] || p);

async function signOut(request, env) {
  const token = request.headers.get('x-account') || '';
  if (!token) return json(200, { ok: true });
  const hash = await sha256(token);
  const session = await env.ROLLS.get(`sessions/${hash}.json`);
  if (session) {
    const { id } = JSON.parse(await session.text());
    await env.ROLLS.delete([`sessions/${hash}.json`, `users/${id}/sessions/${hash}`]);
  }
  return json(200, { ok: true });
}

async function updateMe(request, env, url) {
  return withUser(request, env, async (user) => {
    const body = await readJSON(request);
    if (!body) return json(400, { error: 'Expected JSON' });
    if (typeof body.name === 'string') user.name = clean(body.name, 24);
    if (typeof body.discoverable === 'boolean') user.discoverable = body.discoverable;
    if (typeof body.handle === 'string') {
      const handle = body.handle.trim().replace(/^@/, '').toLowerCase();
      if (handle !== user.handle) {
        if (!validHandle(handle)) return json(400, { error: 'handle', reason: 'Use 3 to 20 letters, numbers, _ or .' });
        if (!(await claimHandle(env, handle, user.id))) return json(409, { error: 'handle', reason: 'That handle is taken.' });
        if (user.handle) await env.ROLLS.delete(`handles/${user.handle}`);
        user.handle = handle;
      }
    }
    await indexUser(env, user);
    await putUser(env, user);
    return json(200, mePayload(user, url));
  });
}

async function updateAvatar(request, env, url, upload) {
  return withUser(request, env, async (user) => {
    if (upload) {
      const bytes = await request.arrayBuffer();
      if (bytes.byteLength === 0 || bytes.byteLength > MAX_IMAGE_BYTES) return json(413, { error: 'image too large' });
      const head = new Uint8Array(bytes, 0, 3);
      if (head[0] !== 0xff || head[1] !== 0xd8 || head[2] !== 0xff) return json(415, { error: 'JPEG only' });
      await env.ROLLS.put(`users/${user.id}/avatar.jpg`, bytes, { httpMetadata: { contentType: 'image/jpeg' } });
      user.avatar = (user.avatar || 0) + 1;   // a version, so caches pick up a new headshot
      user.avatarSource = 'own';
    } else {
      await env.ROLLS.delete(`users/${user.id}/avatar.jpg`);
      user.avatar = 0;
      user.avatarSource = null;
    }
    await putUser(env, user);
    return json(200, mePayload(user, url));
  });
}

/// Delete an account and everything it put on the server: its rolls (public or not), its
/// likes, its headshot and its sessions.
async function deleteAccount(request, env) {
  return withUser(request, env, async (user) => {
    await removeUser(env, user);
    return json(200, { ok: true });
  });
}

async function removeUser(env, user) {
  await forgetSocial(env, user);
  for await (const keys of listKeys(env, `users/${user.id}/`)) {
    for (const key of keys) {
      const parts = key.split('/');
      if (parts[2] === 'rolls') await deleteRoll(env, parts[3]);
      else if (parts[2] === 'likes') await env.ROLLS.delete(`likes/${parts[3]}/${parts[4]}/${user.id}`);
      else if (parts[2] === 'sessions') await env.ROLLS.delete(`sessions/${parts[3]}.json`);
    }
  }
  await deletePrefix(env, `users/${user.id}/`);
  const keys = Object.values(logins(user)).map((key) => `accounts/${key}.json`);
  await env.ROLLS.delete([`users/${user.id}.json`, ...keys]);
}

/// Sign in with Apple's server-to-server notifications. When someone stops using Sign in
/// with Apple for this app (consent-revoked) or deletes their Apple Account (account-delete),
/// that sign-in comes off their account; if it was their only one, the account is deleted
/// like DELETE /api/me. Email events are ignored (no email addresses are kept).
async function appleNotification(request, env, now) {
  const text = await request.text().catch(() => '');
  let payload = null;
  try { payload = JSON.parse(text).payload; } catch { payload = new URLSearchParams(text).get('payload'); }
  if (typeof payload !== 'string' || payload.length > 8000) return json(400, { error: 'expected a payload' });
  const keys = await signingKeys(env, 'APPLE', 'https://appleid.apple.com/auth/keys', now);
  const claims = await verifyJWT(payload, keys, [APPLE_ISSUER], [env.APPLE_AUDIENCE || APPLE_AUDIENCE], now, { notification: true });
  if (!claims) return json(401, { error: 'not from Apple' });
  let event = claims.events;
  if (typeof event === 'string') { try { event = JSON.parse(event); } catch { event = null; } }
  if (!event || typeof event.sub !== 'string' || !event.sub) return json(400, { error: 'no event' });
  if (event.type !== 'consent-revoked' && event.type !== 'account-delete') return json(200, { ok: true });

  const key = await sha256(`apple:${event.sub}`);
  const link = await env.ROLLS.get(`accounts/${key}.json`);
  if (!link) return json(200, { ok: true });
  const user = await getUser(env, JSON.parse(await link.text()).id);
  if (!user) {
    await env.ROLLS.delete(`accounts/${key}.json`);
    return json(200, { ok: true });
  }
  const others = Object.keys(logins(user)).filter((p) => p !== 'apple' && logins(user)[p]);
  if (others.length === 0) {
    await removeUser(env, user);
  } else {
    delete logins(user).apple;
    if (user.photos) delete user.photos.apple;
    await putUser(env, user);
    await env.ROLLS.delete(`accounts/${key}.json`);
  }
  return json(200, { ok: true });
}

/// Someone's public rolls, newest first (hidden and expired ones left out).
async function publicProfile(env, id, url, now, viewer = null) {
  const user = await getUser(env, id);
  if (!user) return null;
  if (viewer && viewer.id !== id && (await blockedEitherWay(env, viewer.id, id))) return null;
  const rolls = [];
  for await (const keys of listKeys(env, `users/${id}/rolls/`)) {
    for (const key of keys) {
      const meta = await getMeta(env, key.split('/')[3]);
      if (!meta || meta.status !== 'live' || expired(meta, now)) continue;
      // A profile shows public rolls, and the ones shared with you; link shares stay off it.
      if (!(await onProfile(env, meta, viewer))) continue;
      rolls.push({ ...(await rollTile(env, meta, url, now)), createdAt: meta.createdAt });
    }
  }
  rolls.sort((a, b) => b.createdAt - a.createdAt);
  const { id: uid, name, avatar, url: link, handle } = mePayload(user, url);
  const profile = {
    id: uid, name, avatar, url: link, handle, rolls: rolls.map(({ createdAt, ...r }) => r),
    followers: await countKeys(env, `followers/${id}/`),
    following: await countKeys(env, `following/${id}/`),
  };
  if (viewer) profile.relation = await relation(env, viewer.id, id);
  return profile;
}

function mePayload(user, url) {
  return {
    id: user.id,
    name: user.name || null,
    avatar: user.avatar ? `${url.origin}/u/${user.id}/avatar.jpg?v=${user.avatar}` : null,
    url: `${url.origin}/u/${user.id}`,
    termsAccepted: Boolean(user.termsAt),
    logins: PROVIDERS.filter((p) => logins(user)[p]),
    avatarSource: user.avatar ? user.avatarSource || 'own' : null,
    photos: PROVIDERS.filter((p) => user.photos?.[p]),
    handle: user.handle || null,
    discoverable: user.discoverable !== false,
  };
}

function own(meta, user) {
  meta.owner = user.id;
  meta.sharer.id = user.id;   // so blocking the person blocks every roll they share
}

const getUser = async (env, id) => {
  const object = await env.ROLLS.get(`users/${id}.json`);
  return object ? JSON.parse(await object.text()) : null;
};
const putUser = (env, user) => env.ROLLS.put(`users/${user.id}.json`, JSON.stringify(user));

/// The signed-in account from the X-Account header, or null.
async function currentUser(request, env) {
  const token = request.headers.get('x-account') || '';
  if (!/^[0-9a-f]{64}$/.test(token)) return null;
  const session = await env.ROLLS.get(`sessions/${await sha256(token)}.json`);
  if (!session) return null;
  return getUser(env, JSON.parse(await session.text()).id);
}

async function withUser(request, env, handler) {
  const user = await currentUser(request, env);
  if (!user) return json(401, { error: 'sign in first' });
  return handler(user);
}

const keyCache = new Map();

/// A provider's public signing keys (env.<NAME>_KEYS overrides them in tests).
async function signingKeys(env, name, href, now) {
  if (env[`${name}_KEYS`]) return env[`${name}_KEYS`];
  const cached = keyCache.get(href);
  if (cached && now - cached.at < 60 * 60 * 1000) return cached.keys;
  try {
    const res = await (env.FETCH || fetch)(href);
    if (!res.ok) return cached?.keys || [];
    const keys = (await res.json()).keys || [];
    keyCache.set(href, { keys, at: now });
    return keys;
  } catch {
    return cached?.keys || [];
  }
}

/// The claims of an RS256 identity token, if one of `keys` signed it, it's from one of
/// `issuers` for one of `audiences`, and it hasn't expired; otherwise null.
/// With { notification: true } (Apple's server-to-server events, which carry no sub or
/// exp of their own) it instead needs an issue time from the last week.
async function verifyJWT(token, keys, issuers, audiences, now, { notification = false } = {}) {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  let header, claims;
  try {
    header = JSON.parse(new TextDecoder().decode(base64url(parts[0])));
    claims = JSON.parse(new TextDecoder().decode(base64url(parts[1])));
  } catch {
    return null;
  }
  if (header.alg !== 'RS256') return null;
  const jwk = keys.find((k) => k.kid === header.kid);
  if (!jwk) return null;
  try {
    const key = await crypto.subtle.importKey('jwk', { kty: jwk.kty, n: jwk.n, e: jwk.e },
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
    const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, base64url(parts[2]),
      new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
    if (!ok) return null;
  } catch {
    return null;
  }
  const aud = [].concat(claims.aud);
  if (!issuers.includes(claims.iss) || !aud.some((a) => audiences.includes(a))) return null;
  if (notification) {
    if (typeof claims.iat !== 'number') return null;
    const age = now - claims.iat * 1000;
    if (age > 7 * 24 * 60 * 60 * 1000 || age < -5 * 60 * 1000) return null;
    if (typeof claims.exp === 'number' && claims.exp * 1000 <= now) return null;
    return claims;
  }
  if (typeof claims.sub !== 'string' || !claims.sub) return null;
  if (typeof claims.exp !== 'number' || claims.exp * 1000 <= now) return null;
  return claims;
}

/// A Sign in with Apple identity token for this app.
export async function verifyAppleToken(token, env, now = Date.now()) {
  const keys = await signingKeys(env, 'APPLE', 'https://appleid.apple.com/auth/keys', now);
  return verifyJWT(token, keys, [APPLE_ISSUER], [env.APPLE_AUDIENCE || APPLE_AUDIENCE], now);
}

/// A Google ID token for one of this app's OAuth clients (GOOGLE_CLIENT_IDS, comma-separated).
export async function verifyGoogleToken(token, env, now = Date.now()) {
  const audiences = String(env.GOOGLE_CLIENT_IDS || '').split(',').map((s) => s.trim()).filter(Boolean);
  if (!audiences.length) return null;
  const keys = await signingKeys(env, 'GOOGLE', 'https://www.googleapis.com/oauth2/v3/certs', now);
  return verifyJWT(token, keys, GOOGLE_ISSUERS, audiences, now);
}

function base64url(value) {
  const b64 = value.replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4)), (c) => c.charCodeAt(0));
}

export async function sweep(env, now = Date.now()) {
  // Support rate-limit counters older than the current hour.
  const hour = Math.floor(now / (60 * 60 * 1000));
  for await (const keys of listKeys(env, 'support-rate/')) {
    const old = keys.filter((k) => Number(k.split('/')[1]) < hour);
    if (old.length) await env.ROLLS.delete(old);
  }
  let cursor;
  let removed = 0;
  do {
    const page = await env.ROLLS.list({ prefix: 'meta/', cursor });
    for (const object of page.objects) {
      const meta = await getMeta(env, object.key.slice(5, -5));
      if (meta && expired(meta, now)) {
        await deleteRoll(env, meta.id);
        removed++;
      } else if (meta && !meta.publicKey && audienceOf(meta) === 'public') {
        // Public before browsing existed: put it in the index.
        await indexPublic(env, meta, meta.createdAt || now);
        await putMeta(env, meta);
      }
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return removed;
}

async function deleteRoll(env, id) {
  const meta = await getMeta(env, id);
  await deletePrefix(env, `rolls/${id}/`);
  // Likes go with the roll; the likers' own lists are tidied when they're read or deleted.
  await deletePrefix(env, `likes/${id}/`);
  if (meta?.owner) await env.ROLLS.delete(`users/${meta.owner}/rolls/${id}`);
  for (const pid of meta?.people || []) await env.ROLLS.delete(`inbox/${pid}/${id}`);
  if (meta?.publicKey) await env.ROLLS.delete(meta.publicKey);
  await env.ROLLS.delete(`meta/${id}.json`);
}

async function deletePrefix(env, prefix) {
  for await (const keys of listKeys(env, prefix)) {
    if (keys.length) await env.ROLLS.delete(keys);
  }
}

/// Every key under a prefix, a page at a time.
async function* listKeys(env, prefix) {
  let cursor;
  do {
    const page = await env.ROLLS.list({ prefix, cursor });
    yield page.objects.map((o) => o.key);
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
}

/// A roll as the app and the page show it. A roll that belongs to an account shows that
/// account's current name and headshot, and links to its profile.
async function rollPayload(env, meta, url, now = Date.now(), viewer = null) {
  const base = `${url.origin}/r/${meta.id}`;
  const file = (name) => fileURL(env, meta, name, url, now);
  let sharer = { id: meta.sharer.id, name: meta.sharer.name, avatar: meta.sharer.avatar ? await file('avatar.jpg') : null, profile: null };
  const owner = meta.owner ? await getUser(env, meta.owner) : null;
  if (owner) {
    sharer = {
      id: owner.id, name: owner.name || null,
      avatar: owner.avatar ? `${url.origin}/u/${owner.id}/avatar.jpg?v=${owner.avatar}` : null,
      profile: `${url.origin}/u/${owner.id}`,
      handle: owner.handle || null,
    };
  }
  const payload = {
    id: meta.id,
    title: meta.title,
    film: meta.film,
    sharer,
    shotAt: meta.shotAt,
    frames: await Promise.all(Array.from({ length: meta.frames }, (_, i) => file(frameName(i + 1)))),
    cover: coverFrame(meta.cover, meta.frames),
    card: await file('card.jpg'),
    url: base,
    public: Boolean(meta.public && owner),
    audience: audienceOf(meta),
    expiresAt: meta.expiresAt == null ? null : new Date(meta.expiresAt).toISOString(),
  };
  // Only the owner sees who a roll is shared with.
  if (viewer && meta.owner === viewer.id && payload.audience === 'people') {
    payload.people = (await Promise.all((meta.people || []).map((pid) => getUser(env, pid)))).filter(Boolean).map((u) => personPayload(u, url));
  }
  return payload;
}

const frameName = (n) => `frame-${String(n).padStart(2, '0')}.jpg`;
const expired = (meta, now) => meta.expiresAt != null && now >= meta.expiresAt;
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


// MARK: Social: handles, search, following, blocking, audiences

export const AUDIENCES = ['private', 'people', 'followers', 'public', 'link'];
const SHARED = ['people', 'followers', 'public'];   // on a profile or in an inbox: needs the rules, never expires
export const MAX_PEOPLE = 50;
const RESERVED = new Set(['admin', 'support', 'help', 'filmexposures', 'film_exposures', 'exposures', 'official', 'staff', 'team', 'me', 'you', 'null', 'undefined']);

const audienceOf = (meta) => meta.audience || (meta.public ? 'public' : 'link');
const isOpen = (meta) => ['public', 'link'].includes(audienceOf(meta));
const has = async (env, key) => Boolean(await env.ROLLS.head(key));
const following = (env, a, b) => has(env, `following/${a}/${b}`);   // a follows b

export function validHandle(handle) {
  return /^[a-z0-9_](?:[a-z0-9_.]{1,18})[a-z0-9_]$/.test(handle) && !handle.includes('..') && !RESERVED.has(handle);
}

/// Take a handle if nobody else has it. Claimed by writing the key, then reading it back,
/// so of two people claiming at once only one keeps it.
async function claimHandle(env, handle, uid) {
  const existing = await env.ROLLS.get(`handles/${handle}`);
  if (existing && (await existing.text()) !== uid) return false;
  await env.ROLLS.put(`handles/${handle}`, uid);
  const check = await env.ROLLS.get(`handles/${handle}`);
  return (await check.text()) === uid;
}

/// Lower case, accents off, letters and numbers only: what search compares.
export function searchWord(value) {
  return String(value || '').normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9_.]/g, '');
}

/// Search keys for an account: its handle and each word of its name. Kept on the account
/// so they can be taken down when they change.
async function indexUser(env, user) {
  const words = user.discoverable === false || !user.handle ? [] : [...new Set([
    user.handle, ...String(user.name || '').split(/\s+/).map(searchWord),
  ].filter((w) => w && w.length >= 1).map((w) => w.slice(0, 30)))];
  const keys = words.map((w) => `search/${w}/${user.id}`);
  const old = (user.searchKeys || []).filter((k) => !keys.includes(k));
  if (old.length) await env.ROLLS.delete(old);
  for (const key of keys) await env.ROLLS.put(key, '1');
  user.searchKeys = keys;
}

function personPayload(u, url) {
  return { id: u.id, handle: u.handle || null, name: u.name || null, avatar: u.avatar ? `${url.origin}/u/${u.id}/avatar.jpg?v=${u.avatar}` : null };
}

async function blockedEitherWay(env, a, b) {
  return (await has(env, `blocks/${a}/${b}`)) || (await has(env, `blocks/${b}/${a}`));
}

/// How the viewer stands with someone: "self", "following", "requested" or "none", plus
/// whether they follow (or ask to follow) the viewer back.
async function relation(env, viewer, id) {
  if (viewer === id) return { status: 'self' };
  const status = (await following(env, viewer, id)) ? 'following' : (await has(env, `requests/${id}/${viewer}`)) ? 'requested' : 'none';
  return {
    status,
    followsYou: await following(env, id, viewer),
    askedYou: await has(env, `requests/${viewer}/${id}`),
    blocked: await has(env, `blocks/${viewer}/${id}`),
  };
}

/// Who may see a roll. Its owner always; then by audience: anyone (public, link), approved
/// followers, or the people it was shared with. Blocking either way shuts it.
async function canView(env, meta, viewer) {
  if (!meta || meta.status !== 'live') return false;
  if (viewer && meta.owner === viewer.id) return true;
  if (viewer && meta.owner && (await blockedEitherWay(env, viewer.id, meta.owner))) return false;
  const audience = audienceOf(meta);
  if (audience === 'public' || audience === 'link') return true;
  if (!viewer || !meta.owner) return false;
  if (audience === 'followers') return following(env, viewer.id, meta.owner);
  if (audience === 'people') return (meta.people || []).includes(viewer.id);
  return false;
}

/// Whether a roll shows on its owner's profile for this viewer (not link shares).
async function onProfile(env, meta, viewer) {
  if (viewer && meta.owner === viewer.id) return true;
  return audienceOf(meta) !== 'link' && canView(env, meta, viewer);
}

async function rollTile(env, meta, url, now) {
  const base = `${url.origin}/r/${meta.id}`;
  return {
    id: meta.id, title: meta.title, film: meta.film.name || null, frames: meta.frames, shotAt: meta.shotAt,
    cover: await fileURL(env, meta, frameName(coverFrame(meta.cover, meta.frames)), url, now),
    card: await fileURL(env, meta, 'card.jpg', url, now), url: base, audience: audienceOf(meta),
  };
}

// Signed links for photos that aren't for everyone. A link lasts until the end of the next
// hour, so it can be cached for a while but can't be passed around for long.
const HOUR = 60 * 60 * 1000;
let urlKey = null;

async function signingKey(env) {
  // One promise, so photos signed at the same moment all wait for the same key.
  urlKey ||= (async () => {
    let secret = env.URL_SIGNING_KEY;
    if (!secret) {
      const stored = await env.ROLLS.get('config/url-signing-key');
      secret = stored ? await stored.text() : null;
      if (!secret) {
        // Read it back: if two servers made a key at once, both use whichever was kept.
        await env.ROLLS.put('config/url-signing-key', randomHex(32));
        secret = await (await env.ROLLS.get('config/url-signing-key')).text();
      }
    }
    return crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
  })();
  return urlKey;
}
export function resetSigningKey() { urlKey = null; }

async function signature(env, id, file, exp) {
  const mac = await crypto.subtle.sign('HMAC', await signingKey(env), new TextEncoder().encode(`${id}/${file}/${exp}`));
  return btoa(String.fromCharCode(...new Uint8Array(mac).slice(0, 18))).replace(/\+/g, '-').replace(/\//g, '_');
}

async function fileURL(env, meta, file, url, now) {
  const plain = `${url.origin}/r/${meta.id}/${file}`;
  if (isOpen(meta)) return plain;
  const exp = (Math.floor(now / HOUR) + 2) * HOUR;
  return `${plain}?exp=${exp}&sig=${await signature(env, meta.id, file, exp)}`;
}

async function signedOK(env, id, file, url, now) {
  const exp = Number(url.searchParams.get('exp'));
  const sig = url.searchParams.get('sig') || '';
  if (!Number.isFinite(exp) || exp < now || exp > now + 3 * HOUR || !sig) return false;
  return sig === (await signature(env, id, file, exp));
}

async function countKeys(env, prefix) {
  let n = 0;
  for await (const keys of listKeys(env, prefix)) n += keys.length;
  return n;
}

async function people(env, url, ids) {
  return (await Promise.all(ids.map((pid) => getUser(env, pid)))).filter(Boolean).map((u) => personPayload(u, url));
}

async function searchUsers(request, env, url) {
  return withUser(request, env, async (user) => {
    const q = searchWord(url.searchParams.get('q')).slice(0, 30);
    if (q.length < 2) return json(200, { people: [] });
    const ids = [];
    for await (const keys of listKeys(env, `search/${q}`)) {
      for (const key of keys) {
        const pid = key.split('/')[2];
        if (pid !== user.id && !ids.includes(pid)) ids.push(pid);
      }
      if (ids.length >= 40) break;
    }
    const found = [];
    for (const pid of ids) {
      if (found.length >= 20) break;
      if (await blockedEitherWay(env, user.id, pid)) continue;
      const u = await getUser(env, pid);
      if (!u || u.discoverable === false || !u.handle) continue;
      found.push({ ...personPayload(u, url), status: (await relation(env, user.id, pid)).status });
    }
    // Handles that start with the search first, then names.
    found.sort((a, b) => (b.handle?.startsWith(q) || 0) - (a.handle?.startsWith(q) || 0));
    return json(200, { people: found });
  });
}

export const BROWSE_PAGE = 30;

/// Everyone who can be found (a handle, search left on, not blocked either way), in handle
/// order, a page at a time: `after` is the last handle of the previous page.
async function browseUsers(request, env, url) {
  return withUser(request, env, async (user) => {
    const after = searchWord(url.searchParams.get('after')).slice(0, 30);
    const found = [];
    let cursor;
    let more = false;
    outer: do {
      const page = await env.ROLLS.list({ prefix: 'handles/', cursor, startAfter: after ? `handles/${after}` : undefined, limit: 100 });
      for (const object of page.objects) {
        const handle = object.key.slice('handles/'.length);
        if (after && handle <= after) continue;
        if (found.length >= BROWSE_PAGE) { more = true; break outer; }
        const pid = await (await env.ROLLS.get(object.key))?.text();
        if (!pid || pid === user.id || (await blockedEitherWay(env, user.id, pid))) continue;
        const u = await getUser(env, pid);
        if (!u || u.discoverable === false || u.handle !== handle) continue;
        found.push({ ...personPayload(u, url), status: (await relation(env, user.id, pid)).status });
      }
      cursor = page.truncated ? page.cursor : undefined;
      if (cursor) more = true;
    } while (cursor && found.length < BROWSE_PAGE);
    if (!cursor && found.length < BROWSE_PAGE) more = false;
    return json(200, { people: found, after: more && found.length ? found[found.length - 1].handle : null });
  });
}

async function follow(request, env, url, id, on, now) {
  return withUser(request, env, async (user) => {
    if (id === user.id) return json(400, { error: 'that is you' });
    const target = await getUser(env, id);
    if (!target) return json(404, { error: 'no such person' });
    if (!on) {
      await env.ROLLS.delete([`following/${user.id}/${id}`, `followers/${id}/${user.id}`, `requests/${id}/${user.id}`]);
      return json(200, { status: 'none' });
    }
    if (!user.handle) return json(409, { error: 'handle', reason: 'Choose a handle first, so people know who is asking.' });
    if (await blockedEitherWay(env, user.id, id)) return json(404, { error: 'no such person' });
    if (await following(env, user.id, id)) return json(200, { status: 'following' });
    // Every follow is a request that the other person approves.
    await env.ROLLS.put(`requests/${id}/${user.id}`, String(now));
    return json(200, { status: 'requested' });
  });
}

async function listRequests(request, env, url) {
  return withUser(request, env, async (user) => {
    const ids = [];
    for await (const keys of listKeys(env, `requests/${user.id}/`)) ids.push(...keys.map((k) => k.split('/')[2]));
    return json(200, { people: await people(env, url, ids) });
  });
}

async function answerRequest(request, env, url, id) {
  return withUser(request, env, async (user) => {
    if (!(await has(env, `requests/${user.id}/${id}`))) return json(404, { error: 'no request' });
    const body = (await readJSON(request)) || {};
    await env.ROLLS.delete(`requests/${user.id}/${id}`);
    if (body.accept && (await getUser(env, id)) && !(await blockedEitherWay(env, user.id, id))) {
      await env.ROLLS.put(`following/${id}/${user.id}`, '1');
      await env.ROLLS.put(`followers/${user.id}/${id}`, '1');
      return json(200, { status: 'follower' });
    }
    return json(200, { status: 'declined' });
  });
}

async function removeFollower(request, env, id) {
  return withUser(request, env, async (user) => {
    await env.ROLLS.delete([`following/${id}/${user.id}`, `followers/${user.id}/${id}`]);
    return json(200, { ok: true });
  });
}

async function followList(request, env, url, id, which) {
  return withUser(request, env, async (user) => {
    if (id !== user.id && (await blockedEitherWay(env, user.id, id))) return json(404, { error: 'no such person' });
    const ids = [];
    for await (const keys of listKeys(env, `${which}/${id}/`)) ids.push(...keys.map((k) => k.split('/')[2]));
    return json(200, { people: await people(env, url, ids.slice(0, 500)) });
  });
}

async function block(request, env, id, on) {
  return withUser(request, env, async (user) => {
    if (id === user.id) return json(400, { error: 'that is you' });
    if (!on) {
      await env.ROLLS.delete(`blocks/${user.id}/${id}`);
      return json(200, { blocked: false });
    }
    await env.ROLLS.put(`blocks/${user.id}/${id}`, '1');
    // Blocking ends following and requests both ways.
    await env.ROLLS.delete([
      `following/${user.id}/${id}`, `followers/${id}/${user.id}`, `following/${id}/${user.id}`, `followers/${user.id}/${id}`,
      `requests/${user.id}/${id}`, `requests/${id}/${user.id}`,
    ]);
    return json(200, { blocked: true });
  });
}

// MARK: Browse: everyone's public rolls

/// Public rolls are kept in an index, newest first: one key per roll, named so that
/// listing it in order gives the latest first. A roll joins when it goes public and leaves
/// when it doesn't (or is deleted). Callers save the roll's details afterwards.
async function indexPublic(env, meta, now) {
  const wanted = audienceOf(meta) === 'public' && Boolean(meta.owner);
  if (wanted && !meta.publicKey) {
    meta.publicKey = `public/${String(1e13 - now).padStart(13, '0')}-${meta.id}`;
    await env.ROLLS.put(meta.publicKey, meta.id);
  } else if (!wanted && meta.publicKey) {
    await env.ROLLS.delete(meta.publicKey);
    meta.publicKey = null;
  }
}

/// Index every public roll that isn't yet (rolls made public before the index existed).
async function backfillPublic(env, now) {
  for await (const keys of listKeys(env, 'meta/')) {
    for (const key of keys) {
      const meta = await getMeta(env, key.slice(5, -5));
      if (meta && !meta.publicKey && audienceOf(meta) === 'public' && !expired(meta, now)) {
        await indexPublic(env, meta, meta.createdAt || now);
        await putMeta(env, meta);
      }
    }
  }
}

export const BROWSE_ROLLS_PAGE = 30;

async function browseRolls(request, env, url, now) {
  return withUser(request, env, async (user) => {
    const after = /^public\/\d{13}-[A-Za-z0-9]{10}$/.test(url.searchParams.get('after') || '') ? url.searchParams.get('after') : '';
    if (!after && (await env.ROLLS.list({ prefix: 'public/', limit: 1 })).objects.length === 0) await backfillPublic(env, now);
    const rolls = [];
    let last = null;
    let more = false;
    let cursor;
    outer: do {
      const page = await env.ROLLS.list({ prefix: 'public/', cursor, startAfter: after || undefined, limit: 100 });
      for (const object of page.objects) {
        if (after && object.key <= after) continue;
        if (rolls.length >= BROWSE_ROLLS_PAGE) { more = true; break outer; }
        const meta = await liveRoll(env, object.key.split('-').pop(), now);
        if (!meta || audienceOf(meta) !== 'public' || !meta.owner) {
          if (!meta || audienceOf(meta) !== 'public') await env.ROLLS.delete(object.key);   // stale
          continue;
        }
        if (meta.owner !== user.id && (await blockedEitherWay(env, user.id, meta.owner))) continue;
        const owner = await getUser(env, meta.owner);
        if (!owner) continue;
        rolls.push({ ...(await rollTile(env, meta, url, now)), by: personPayload(owner, url), sharedAt: new Date(meta.createdAt).toISOString() });
        last = object.key;
      }
      cursor = page.truncated ? page.cursor : undefined;
      if (cursor) more = true;
    } while (cursor && rolls.length < BROWSE_ROLLS_PAGE);
    if (!cursor && rolls.length < BROWSE_ROLLS_PAGE) more = false;
    return json(200, { rolls, after: more ? last : null });
  });
}

export const FEED_SIZE = 50;

/// Recent rolls from the people you follow that you may see, newest first.
async function feed(request, env, url, now) {
  return withUser(request, env, async (user) => {
    const rolls = [];
    for await (const keys of listKeys(env, `following/${user.id}/`)) {
      for (const key of keys) {
        const owner = await getUser(env, key.split('/')[2]);
        if (!owner) continue;
        for await (const rollKeys of listKeys(env, `users/${owner.id}/rolls/`)) {
          for (const rk of rollKeys) {
            const meta = await getMeta(env, rk.split('/')[3]);
            if (!meta || meta.status !== 'live' || expired(meta, now) || audienceOf(meta) === 'link') continue;
            if (!(await canView(env, meta, user))) continue;
            rolls.push({ ...(await rollTile(env, meta, url, now)), by: personPayload(owner, url), createdAt: meta.createdAt });
          }
        }
      }
    }
    rolls.sort((a, b) => b.createdAt - a.createdAt);
    return json(200, { rolls: rolls.slice(0, FEED_SIZE).map(({ createdAt, ...r }) => ({ ...r, sharedAt: new Date(createdAt).toISOString() })) });
  });
}

/// Rolls shared with you by name, newest first.
async function inbox(request, env, url, now) {
  return withUser(request, env, async (user) => {
    const rolls = [];
    for await (const keys of listKeys(env, `inbox/${user.id}/`)) {
      for (const key of keys) {
        const id = key.split('/')[2];
        const meta = await liveRoll(env, id, now);
        if (!meta || !(await canView(env, meta, user))) continue;
        const owner = await getUser(env, meta.owner);
        if (!owner) continue;
        const at = Number(await (await env.ROLLS.get(key))?.text()) || meta.createdAt;
        rolls.push({ ...(await rollTile(env, meta, url, now)), by: personPayload(owner, url), at });
      }
    }
    rolls.sort((a, b) => b.at - a.at);
    return json(200, { rolls: rolls.map(({ at, ...r }) => ({ ...r, sharedAt: new Date(at).toISOString() })) });
  });
}

/// An account's handle, search entries, follows, requests, blocks and inbox, for deleting it.
async function forgetSocial(env, user) {
  if (user.handle) {
    const owner = await env.ROLLS.get(`handles/${user.handle}`);
    if (owner && (await owner.text()) === user.id) await env.ROLLS.delete(`handles/${user.handle}`);
  }
  if (user.searchKeys?.length) await env.ROLLS.delete(user.searchKeys);
  const id = user.id;
  for (const [mine, theirs] of [['following', 'followers'], ['followers', 'following']]) {
    for await (const keys of listKeys(env, `${mine}/${id}/`)) {
      for (const key of keys) await env.ROLLS.delete(`${theirs}/${key.split('/')[2]}/${id}`);
    }
    await deletePrefix(env, `${mine}/${id}/`);
  }
  await deletePrefix(env, `requests/${id}/`);
  await deletePrefix(env, `blocks/${id}/`);
  await deletePrefix(env, `inbox/${id}/`);
  // Requests and blocks this account made of others are left to expire with nothing to point at:
  // every read checks that the account still exists.
}

// MARK: Film codes (mirror of RetroCam/FilmCode.swift)

const FIELDS = [
  ['red', -1, 2], ['green', -1, 2], ['blue', -1, 2],
  ['contrast', 0, 1], ['key', -1, 1], ['blackLift', 0, 0.25], ['whitePoint', 0.75, 1],
  ['grain', 0, 1], ['grainSize', 0.6, 3], ['vignette', 0, 1.2],
  ['toneAmount', 0, 1], ['bloom', 0, 1], ['edgeSoftness', 0, 1], ['exposure', -1, 1], ['fog', 0, 1],
  ['effectAmount', 0, 1], ['effectX', 0, 1], ['effectY', 0, 1],
];
// Colour films (code version 2) carry these after the ones above.
const COLOR_FIELDS = [
  ['saturation', 0, 1.6], ['warmth', -1, 1], ['tint', -1, 1],
  ['shadowHue', 0, 1], ['shadowAmount', 0, 1], ['highlightHue', 0, 1], ['highlightAmount', 0, 1],
  ['aqua', -1, 1],
  ['redShadows', -1, 1], ['redHighlights', -1, 1], ['greenShadows', -1, 1],
  ['greenHighlights', -1, 1], ['blueShadows', -1, 1], ['blueHighlights', -1, 1],
  ['halation', 0, 1],
];
// Version 3 adds how strongly the colour look applies.
const V3_FIELDS = [['strength', 0, 1]];
// Version 4 adds colour unity (a frame's colours gathered toward one hue).
const V4_FIELDS = [['unify', 0, 1], ['unifyHue', 0, 1]];
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
  if (![1, 2, 3, 4].includes(bytes[0])) return null;
  const isColor = bytes[0] !== 1;
  const packed = FIELDS.concat(
    isColor ? COLOR_FIELDS : [], bytes[0] >= 3 ? V3_FIELDS : [], bytes[0] >= 4 ? V4_FIELDS : []);
  const fixed = 1 + packed.length + 2 + 2;
  if (bytes.length < fixed) return null;
  const film = { color: isColor, strength: 1, unify: 0 };
  packed.forEach(([name, lo, hi], i) => { film[name] = lo + (bytes[1 + i] / 255) * (hi - lo); });
  let at = 1 + packed.length;
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
  const kind = film.color ? 'Color'
    : film.tone === 'neutral' || film.toneAmount < 0.3 ? 'Black & white' : `${TONE_NAMES[film.tone]} toned`;
  const texture = film.grain < 0.2 ? 'Fine grain' : film.grain < 0.45 ? 'Medium grain' : 'Heavy grain';
  return `${kind} · ISO ${film.iso} · ${texture}`;
}

/// An approximate tone scale for the page: black to white through the film's range and toning.
function toneScale(film, steps = 9) {
  if (film.color) return colorScale(film, steps);
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

/// A colour film's tone scale: grey through its white balance and grade (mirror of
/// RetroCam/ColorGrade.swift, without the blue-only aqua shift, which greys don't feel).
function colorScale(film, steps) {
  const luma = (r, g, b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;
  const clamp = (x) => Math.min(Math.max(x, 0), 1);
  const hueRGB = (h) => {
    const hh = (((h % 1) + 1) % 1) * 6, x = 1 - Math.abs((hh % 2) - 1);
    return hh < 1 ? [1, x, 0] : hh < 2 ? [x, 1, 0] : hh < 3 ? [0, 1, x] : hh < 4 ? [0, x, 1] : hh < 5 ? [x, 0, 1] : [1, 0, x];
  };
  const tint = (h) => { const c = hueRGB(h); const y = luma(...c); return c.map((v) => v - y); };
  const st = tint(film.shadowHue), ht = tint(film.highlightHue);
  const gains = [1 + 0.07 * film.warmth + 0.03 * film.tint, 1 + 0.01 * film.warmth - 0.05 * film.tint, 1 - 0.08 * film.warmth + 0.03 * film.tint];
  const bends = [[film.redShadows, film.redHighlights], [film.greenShadows, film.greenHighlights], [film.blueShadows, film.blueHighlights]];
  return Array.from({ length: steps }, (_, i) => {
    const x = film.blackLift + (i / (steps - 1)) * (film.whitePoint - film.blackLift);
    let c = gains.map((k) => clamp(x * k));
    c = c.map((v, j) => clamp(v + 0.08 * (bends[j][0] * 6.75 * v * (1 - v) ** 2 + bends[j][1] * 6.75 * v * v * (1 - v))));
    let y = luma(...c);
    c = c.map((v) => clamp(y + film.saturation * (v - y)));
    y = luma(...c);
    const ws = film.shadowAmount * Math.max(0, 1 - y / 0.5) ** 2, wh = film.highlightAmount * Math.max(0, (y - 0.5) / 0.5) ** 2;
    c = c.map((v, j) => clamp(v + 0.3 * (ws * st[j] + wh * ht[j])));
    // STRENGTH mixes the look back toward plain grey.
    const g = i / (steps - 1);
    c = c.map((v) => g + film.strength * (v - g));
    return `rgb(${c.map((v) => Math.round(v * 255)).join(',')})`;
  });
}

function settingsList(film) {
  const pct = (v) => `${Math.round(v * 100)}%`;
  if (film.color) {
    const deg = (h) => `${Math.round(h * 360) % 360}°`;
    const signed = (v) => `${v > 0 ? '+' : ''}${Math.round(v * 100)}`;
    const rows = [['Strength', pct(film.strength)], ['Contrast', pct(film.contrast)], ['Saturation', pct(film.saturation)], ['Warmth', signed(film.warmth)]];
    if (film.shadowAmount > 0.02) rows.push(['Shadow color', `${deg(film.shadowHue)} ${pct(film.shadowAmount)}`]);
    if (film.highlightAmount > 0.02) rows.push(['Light color', `${deg(film.highlightHue)} ${pct(film.highlightAmount)}`]);
    if (film.unify > 0.02) rows.push(['Unify', `${deg(film.unifyHue)} ${pct(film.unify)}`]);
    if (film.halation > 0.02) rows.push(['Halation', pct(film.halation)]);
    rows.push(['Grain', pct(film.grain)]);
    if (film.effect !== 'none') rows.push(['Effect', `${EFFECT_NAMES[film.effect]} ${pct(film.effectAmount)}`]);
    return rows;
  }
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

function rollPage(roll, meta, url, env) {
  // On the web a roll is a teaser: its card (the first frames) and who shot it. The whole
  // roll opens in the app, so people without it are asked to get it.
  const base = `/r/${meta.id}`;
  const who = roll.sharer.name ? esc(roll.sharer.name) : 'Someone';
  const avatar = roll.sharer.avatar ? `<img class="avatar" src="${esc(roll.sharer.avatar)}" alt="">` : '';
  const whoLine = roll.sharer.profile
    ? `<a class="who" href="${esc(roll.sharer.profile)}">${avatar}<span>${who} shared a roll</span></a>`
    : `<div class="who">${avatar}<span>${who} shared a roll</span></div>`;
  const lifetime = roll.public
    ? `On <a href="${esc(roll.sharer.profile)}">${who}'s profile</a>.`
    : `Shared rolls disappear ${new Date(meta.expiresAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' })}.`;
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
      ${whoLine}
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
      <p class="small muted">${lifetime}</p>`,
  });
}

function profilePage(profile, url, env) {
  const who = profile.name ? esc(profile.name) : 'A Film Exposures photographer';
  const avatar = profile.avatar ? `<img class="avatar" src="${esc(profile.avatar)}" alt="">` : '';
  const tiles = profile.rolls.map((r) => `<a href="/r/${r.id}"><img src="${esc(r.cover)}" alt="" loading="lazy">
      <b>${esc(r.title)}</b><span>${r.frames} ${r.frames === 1 ? 'frame' : 'frames'}${r.film ? ` · ${esc(r.film)}` : ''}</span></a>`).join('');
  const store = storeURL(env);
  return layout({
    title: `${profile.name || 'Profile'} on Film Exposures`,
    description: `${profile.rolls.length} ${profile.rolls.length === 1 ? 'roll' : 'rolls'} of film on Film Exposures.`,
    image: profile.rolls[0]?.card, url: url.href, env, appArgument: url.href,
    body: `
      <p class="eyebrow">FILM EXPOSURES · PROFILE</p>
      <div class="profile-head">${avatar}<div><h1>${who}</h1>
        <p class="muted">${profile.rolls.length} ${profile.rolls.length === 1 ? 'roll' : 'rolls'}</p></div></div>
      ${profile.rolls.length ? `<div class="rolls">${tiles}</div>` : '<p class="muted">No public rolls yet.</p>'}
      ${store ? `<a class="button primary" href="${esc(store)}">Get Film Exposures</a>` : '<p class="button disabled">Film Exposures is coming soon to the App Store</p>'}
      <a class="button" href="exposures://u/${profile.id}">Already have Film Exposures? Open the profile</a>`,
  });
}

function homePage(env) {
  return layout({
    title: 'Film Exposures · A film camera for your iPhone',
    description: 'Shoot rolls of 36 on black & white and color films, develop them later, and share your films.',
    image: 'https://filmexposures.com/og-image.png', url: 'https://filmexposures.com/',
    env, wide: true, body: homeBody(esc(storeURL(env))),
  });
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

function layout({ title, description, image, url, body, env, appArgument, wide = false, noindex = false }) {
  const appID = env?.APP_STORE_ID ? String(env.APP_STORE_ID).replace(/\D/g, '') : '';
  return `<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<meta name="theme-color" content="#0e0e0f">
<link rel="icon" type="image/png" href="/favicon.png"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
${noindex ? '<meta name="robots" content="noindex">' : ''}
<meta property="og:site_name" content="Film Exposures">
<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(description)}">
${url ? `<meta property="og:url" content="${esc(url)}">` : ''}
${appID ? `<meta name="apple-itunes-app" content="app-id=${appID}${appArgument ? `, app-argument=${esc(appArgument)}` : ''}">` : ''}
${image ? `<meta property="og:image" content="${esc(image)}"><meta name="twitter:card" content="summary_large_image">` : '<meta name="twitter:card" content="summary">'}
<style>${SITE_CSS}</style></head><body>${siteHeader()}<main${wide ? ' class="wide"' : ''}>${body}</main>${siteFooter()}</body></html>`;
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
