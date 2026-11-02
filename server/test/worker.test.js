import { test } from 'node:test';
import assert from 'node:assert/strict';
import { route, sweep, decodeFilm, caption, storeURL, verifyAppleToken, verifyGoogleToken, TTL_DAYS } from '../src/worker.js';

/// In-memory stand-in for an R2 bucket (the calls the worker uses).
class FakeBucket {
  constructor() { this.objects = new Map(); }
  async put(key, value) {
    const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : new Uint8Array(value);
    this.objects.set(key, bytes);
  }
  async get(key) {
    const bytes = this.objects.get(key);
    if (!bytes) return null;
    return { body: bytes, text: async () => new TextDecoder().decode(bytes) };
  }
  async head(key) { return this.objects.has(key) ? {} : null; }
  async delete(keys) { for (const k of [].concat(keys)) this.objects.delete(k); }
  async list({ prefix }) {
    return { objects: [...this.objects.keys()].filter((k) => k.startsWith(prefix)).map((key) => ({ key })), truncated: false };
  }
}

const ORIGIN = 'https://exposures.example.workers.dev';
const env = () => ({ ROLLS: new FakeBucket(), APP_STORE_URL: '' });
const jpeg = (n = 64) => { const b = new Uint8Array(n); b.set([0xff, 0xd8, 0xff]); return b; };
const call = (e, method, path, { body, token, account, type, now } = {}) => {
  const headers = {};
  if (token) headers.authorization = `Bearer ${token}`;
  if (account) headers['x-account'] = account;
  if (type) headers['content-type'] = type;
  return route(new Request(ORIGIN + path, { method, headers, body }), e, now);
};
const PAN50 = 'AW6HXiaACv8aKzUAAACAAICAgAAAADJQQU4gNTA';

test('film codes decode like the app', () => {
  const film = decodeFilm(PAN50);
  assert.equal(film.name, 'PAN 50');
  assert.equal(film.iso, 50);
  assert.equal(film.tone, 'neutral');
  assert.equal(caption(film), 'Black & white · ISO 50 · Fine grain');
  assert.equal(decodeFilm('garbage'), null);
});

test('film page shows the film and a load button', async () => {
  const res = await call(env(), 'GET', `/f/${PAN50}`);
  assert.equal(res.status, 200);
  const page = await res.text();
  assert.match(page, /PAN 50/);
  assert.match(page, new RegExp(`exposures://f/${PAN50}`));
});

test('apple-app-site-association covers film and roll links', async () => {
  const res = await call(env(), 'GET', '/.well-known/apple-app-site-association');
  const body = await res.json();
  assert.equal(res.headers.get('content-type'), 'application/json');
  assert.deepEqual(body.applinks.details[0].appIDs, ['RN599658F9.com.davidanderson.retrocam']);
});

async function shareRoll(e, frames = 2, now = Date.now(), account) {
  const res = await call(e, 'POST', '/api/rolls', {
    type: 'application/json', now, account,
    body: JSON.stringify({ frames, title: 'Roll 02 <b>', film: { name: 'PAN 50', code: PAN50 }, sharer: { id: 'abc12345-def', name: '@david' } }),
  });
  assert.equal(res.status, 201);
  return res.json();
}

test('a roll uploads, publishes, shows and unshares', async () => {
  const e = env();
  const { id, token, url } = await shareRoll(e);
  assert.equal(url, `${ORIGIN}/r/${id}`);

  // Not visible until published.
  assert.equal((await call(e, 'GET', `/r/${id}`)).status, 404);
  // Needs the token; JPEG only.
  assert.equal((await call(e, 'PUT', `/api/rolls/${id}/frame-01.jpg`, { body: jpeg() })).status, 401);
  assert.equal((await call(e, 'PUT', `/api/rolls/${id}/frame-01.jpg`, { body: new Uint8Array(10), token })).status, 415);
  assert.equal((await call(e, 'PUT', `/api/rolls/${id}/frame-03.jpg`, { body: jpeg(), token })).status, 400);
  assert.equal((await call(e, 'PUT', `/api/rolls/${id}/frame-01.jpg`, { body: jpeg(), token })).status, 200);
  // Publishing checks every frame arrived.
  assert.equal((await call(e, 'POST', `/api/rolls/${id}/publish`, { token })).status, 409);
  await call(e, 'PUT', `/api/rolls/${id}/frame-02.jpg`, { body: jpeg(), token });
  await call(e, 'PUT', `/api/rolls/${id}/card.jpg`, { body: jpeg(), token });
  assert.equal((await call(e, 'POST', `/api/rolls/${id}/publish`, { token })).status, 200);

  const page = await (await call(e, 'GET', `/r/${id}`)).text();
  assert.match(page, /Roll 02 &lt;b&gt;/, 'titles are escaped');
  assert.match(page, /og:image/);
  assert.match(page, new RegExp(`exposures://r/${id}`), 'opens in the app');
  assert.doesNotMatch(page, /frame-01\.jpg/, 'the web page is a teaser, not the roll');
  assert.match(page, /coming soon to the App Store/);
  const meta = await (await call(e, 'GET', `/r/${id}/roll.json`)).json();
  assert.equal(meta.frames.length, 2);
  assert.equal(meta.film.code, PAN50);
  assert.equal(meta.sharer.name, '@david');
  assert.equal((await call(e, 'GET', `/r/${id}/frame-01.jpg`)).status, 200);

  assert.equal((await call(e, 'DELETE', `/api/rolls/${id}`, { token: 'wrong' })).status, 401);
  assert.equal((await call(e, 'DELETE', `/api/rolls/${id}`, { token })).status, 200);
  assert.equal((await call(e, 'GET', `/r/${id}`)).status, 404);
  assert.equal(e.ROLLS.objects.size, 0, 'everything deleted');
});

test('rolls expire after 30 days', async () => {
  const e = env();
  const start = Date.UTC(2026, 10, 2);
  const { id, token } = await shareRoll(e, 1, start);
  await call(e, 'PUT', `/api/rolls/${id}/frame-01.jpg`, { body: jpeg(), token, now: start });
  await call(e, 'POST', `/api/rolls/${id}/publish`, { token, now: start });
  const day = 24 * 60 * 60 * 1000;
  assert.equal((await call(e, 'GET', `/r/${id}`, { now: start + (TTL_DAYS - 1) * day })).status, 200);
  assert.equal(await sweep(e, start + (TTL_DAYS - 1) * day), 0);
  assert.equal(await sweep(e, start + TTL_DAYS * day), 1);
  assert.equal(e.ROLLS.objects.size, 0);
});

test('three reports hide a roll', async () => {
  const e = env();
  const { id, token } = await shareRoll(e, 1);
  await call(e, 'PUT', `/api/rolls/${id}/frame-01.jpg`, { body: jpeg(), token });
  await call(e, 'POST', `/api/rolls/${id}/publish`, { token });
  for (let i = 0; i < 3; i++) {
    const res = await call(e, 'POST', `/api/rolls/${id}/report`, { type: 'application/json', body: JSON.stringify({ reason: 'Spam' }), now: Date.now() + i });
    assert.equal(res.status, 200);
  }
  assert.equal((await call(e, 'GET', `/r/${id}`)).status, 404);
});

test('rejects bad roll requests', async () => {
  const e = env();
  assert.equal((await call(e, 'POST', '/api/rolls', { type: 'application/json', body: JSON.stringify({ frames: 40 }) })).status, 400);
  assert.equal((await call(e, 'POST', '/api/rolls', { type: 'application/json', body: 'nope' })).status, 400);
});

test('roll pages send people without the app to the App Store', async () => {
  const e = { ...env(), APP_STORE_ID: '6740000000' };
  assert.equal(storeURL(e), 'https://apps.apple.com/app/id6740000000');
  const { id, token } = await shareRoll(e, 1);
  await call(e, 'PUT', `/api/rolls/${id}/frame-01.jpg`, { body: jpeg(), token });
  await call(e, 'POST', `/api/rolls/${id}/publish`, { token });
  const page = await (await call(e, 'GET', `/r/${id}`)).text();
  assert.match(page, /Get Film Exposures to see the whole roll/);
  assert.match(page, /apple-itunes-app" content="app-id=6740000000, app-argument=https:/);
});

// MARK: Accounts, public rolls and likes

/// A stand-in for Apple: a signing key, its public half in env.APPLE_KEYS, and tokens.
async function fakeApple(defaults = { iss: 'https://appleid.apple.com', aud: 'com.davidanderson.retrocam' }) {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true, ['sign', 'verify']);
  const jwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
  const b64 = (v) => Buffer.from(typeof v === 'string' ? v : new Uint8Array(v)).toString('base64url');
  const sign = async (claims, kid = 'test-key') => {
    const head = b64(JSON.stringify({ alg: 'RS256', kid }));
    const body = b64(JSON.stringify({ ...defaults, exp: Math.floor(Date.now() / 1000) + 600, ...claims }));
    const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', pair.privateKey, new TextEncoder().encode(`${head}.${body}`));
    return `${head}.${body}.${b64(sig)}`;
  };
  return { keys: [{ ...jwk, kid: 'test-key', alg: 'RS256', use: 'sig' }], sign };
}

async function accountEnv() {
  const apple = await fakeApple();
  return { e: { ...env(), APPLE_KEYS: apple.keys }, apple };
}

async function signIn(e, apple, sub, name) {
  const res = await call(e, 'POST', '/api/auth/apple', {
    type: 'application/json', body: JSON.stringify({ identityToken: await apple.sign({ sub }), name }),
  });
  assert.equal(res.status, 200);
  return res.json();
}

async function liveRoll(e, frames, account, now) {
  const shared = await shareRoll(e, frames, now, account);
  for (let n = 1; n <= frames; n++) {
    await call(e, 'PUT', `/api/rolls/${shared.id}/frame-${String(n).padStart(2, '0')}.jpg`, { body: jpeg(), token: shared.token, now });
  }
  await call(e, 'PUT', `/api/rolls/${shared.id}/card.jpg`, { body: jpeg(), token: shared.token, now });
  assert.equal((await call(e, 'POST', `/api/rolls/${shared.id}/publish`, { token: shared.token, now })).status, 200);
  return shared;
}

test('Sign in with Apple tokens are checked', async () => {
  const { e, apple } = await accountEnv();
  assert.ok(await verifyAppleToken(await apple.sign({ sub: 'apple-1' }), e));
  assert.equal(await verifyAppleToken(await apple.sign({ sub: 'apple-1', aud: 'com.someone.else' }), e), null, 'other apps');
  assert.equal(await verifyAppleToken(await apple.sign({ sub: 'apple-1', exp: 1 }), e), null, 'expired');
  assert.equal(await verifyAppleToken(await apple.sign({ sub: 'apple-1', iss: 'https://evil.example' }), e), null, 'other issuers');
  assert.equal(await verifyAppleToken(await apple.sign({ sub: 'apple-1' }, 'unknown'), e), null, 'unknown keys');
  const forged = (await apple.sign({ sub: 'apple-1' })).split('.');
  forged[1] = Buffer.from(JSON.stringify({ iss: 'https://appleid.apple.com', aud: 'com.davidanderson.retrocam', sub: 'apple-2', exp: 9e9 })).toString('base64url');
  assert.equal(await verifyAppleToken(forged.join('.'), e), null, 'tampered claims');
  assert.equal((await call(e, 'POST', '/api/auth/apple', { type: 'application/json', body: '{"identityToken":"x.y.z"}' })).status, 401);
});

test('signing in again finds the same account', async () => {
  const { e, apple } = await accountEnv();
  const first = await signIn(e, apple, 'apple-1', '@david');
  const again = await signIn(e, apple, 'apple-1');
  assert.equal(again.me.id, first.me.id);
  assert.notEqual(again.token, first.token, 'each phone gets its own session');
  assert.equal(again.me.name, '@david');
  assert.match(first.me.url, /\/u\/[A-Za-z0-9]{12}$/);
  assert.equal((await call(e, 'GET', '/api/me')).status, 401);
  assert.equal((await (await call(e, 'GET', '/api/me', { account: first.token })).json()).id, first.me.id);
  await call(e, 'POST', '/api/auth/signout', { account: first.token });
  assert.equal((await call(e, 'GET', '/api/me', { account: first.token })).status, 401, 'signed out');
  assert.equal((await call(e, 'GET', '/api/me', { account: again.token })).status, 200, 'other sessions keep working');
});

test('public rolls go on the profile and stop expiring', async () => {
  const { e, apple } = await accountEnv();
  const { token: account, me } = await signIn(e, apple, 'apple-1', '@david');
  await call(e, 'PUT', '/api/me/avatar', { account, body: jpeg() });
  const start = Date.UTC(2026, 10, 2);
  const { id } = await liveRoll(e, 2, account, start);

  const roll = await (await call(e, 'GET', `/r/${id}/roll.json`, { now: start })).json();
  assert.equal(roll.sharer.id, me.id, 'blocking the sharer blocks the account');
  assert.equal(roll.sharer.profile, me.url);
  assert.match(roll.sharer.avatar, new RegExp(`/u/${me.id}/avatar\\.jpg`));
  assert.equal(roll.public, false);

  // The rules come first.
  const vis = (pub) => call(e, 'POST', `/api/rolls/${id}/visibility`, { account, type: 'application/json', body: JSON.stringify({ public: pub }), now: start });
  assert.equal((await vis(true)).status, 403);
  await call(e, 'POST', '/api/me/terms', { account });
  const made = await (await vis(true)).json();
  assert.equal(made.public, true);
  assert.equal(made.expiresAt, null);

  const profile = await (await call(e, 'GET', `/u/${me.id}/profile.json`, { now: start })).json();
  assert.equal(profile.name, '@david');
  assert.deepEqual(profile.rolls.map((r) => r.id), [id]);
  assert.match(profile.rolls[0].cover, /frame-01\.jpg$/);
  const page = await (await call(e, 'GET', `/u/${me.id}`, { now: start })).text();
  assert.match(page, /@david/);
  assert.match(page, new RegExp(`exposures://u/${me.id}`));
  assert.match(page, new RegExp(`href="/r/${id}"`));
  assert.match(await (await call(e, 'GET', `/r/${id}`, { now: start })).text(), /profile<\/a>/);

  // Long past 30 days it's still there.
  const later = start + 400 * 24 * 60 * 60 * 1000;
  assert.equal(await sweep(e, later), 0);
  assert.equal((await call(e, 'GET', `/r/${id}`, { now: later })).status, 200);

  // Taking it off the profile.
  const off = await (await call(e, 'POST', `/api/rolls/${id}/visibility`, { account, type: 'application/json', body: '{"public":false}', now: later })).json();
  assert.equal(off.public, false);
  assert.equal((await (await call(e, 'GET', `/u/${me.id}/profile.json`, { now: later })).json()).rolls.length, 0);

  // Someone else can't change it.
  const other = await signIn(e, apple, 'apple-2');
  assert.equal((await call(e, 'POST', `/api/rolls/${id}/visibility`, { account: other.token, type: 'application/json', body: '{"public":true}', now: later })).status, 403);
});

test('a roll shared before signing in can be claimed with its token', async () => {
  const { e, apple } = await accountEnv();
  const { id, token } = await liveRoll(e, 1);
  const { token: account, me } = await signIn(e, apple, 'apple-1');
  await call(e, 'POST', '/api/me/terms', { account });
  const body = '{"public":true}';
  assert.equal((await call(e, 'POST', `/api/rolls/${id}/visibility`, { account, type: 'application/json', body })).status, 403, 'needs the roll token');
  assert.equal((await call(e, 'POST', `/api/rolls/${id}/visibility`, { account, token, type: 'application/json', body })).status, 200);
  assert.equal((await (await call(e, 'GET', `/u/${me.id}/profile.json`)).json()).rolls.length, 1);
});

test('frames can be liked once per account', async () => {
  const { e, apple } = await accountEnv();
  const a = await signIn(e, apple, 'apple-1');
  const b = await signIn(e, apple, 'apple-2');
  const { id } = await liveRoll(e, 3, a.token);
  const like = (who, n, on = true) => call(e, on ? 'PUT' : 'DELETE', `/api/rolls/${id}/frames/${n}/like`, { account: who.token });

  assert.equal((await call(e, 'PUT', `/api/rolls/${id}/frames/1/like`)).status, 401, 'needs an account');
  assert.equal((await like(a, 4)).status, 400, 'frame out of range');
  await like(a, 1);
  await like(a, 1);   // twice is still one like
  assert.equal((await (await like(b, 1)).json()).count, 2);
  await like(b, 3);
  let likes = await (await call(e, 'GET', `/api/rolls/${id}/likes`, { account: b.token })).json();
  assert.deepEqual(likes, { counts: { 1: 2, 3: 1 }, mine: [1, 3] });
  assert.equal((await (await like(b, 1, false)).json()).count, 1);
  likes = await (await call(e, 'GET', `/api/rolls/${id}/likes`)).json();
  assert.deepEqual(likes, { counts: { 1: 1, 3: 1 }, mine: [] });
});

test('deleting an account deletes everything it put on the server', async () => {
  const { e, apple } = await accountEnv();
  const keep = await signIn(e, apple, 'apple-keep');
  const { id: kept } = await liveRoll(e, 1, keep.token);
  const before = new Set(e.ROLLS.objects.keys());

  const gone = await signIn(e, apple, 'apple-gone', '@gone');
  await call(e, 'PUT', '/api/me/avatar', { account: gone.token, body: jpeg() });
  const { id } = await liveRoll(e, 2, gone.token);
  await call(e, 'PUT', `/api/rolls/${id}/frames/1/like`, { account: keep.token });
  await call(e, 'PUT', `/api/rolls/${kept}/frames/1/like`, { account: gone.token });

  assert.equal((await call(e, 'DELETE', '/api/me', { account: gone.token })).status, 200);
  assert.deepEqual(new Set(e.ROLLS.objects.keys()), new Set([...before, `users/${keep.me.id}/likes/${id}/01`]),
    'only the other account’s own note of its like on the deleted roll is left');
  assert.equal((await call(e, 'GET', `/u/${gone.me.id}`)).status, 404);
  assert.equal((await call(e, 'GET', `/r/${id}`)).status, 404);
  assert.equal((await call(e, 'GET', '/api/me', { account: gone.token })).status, 401);
  // Signing in with the same Apple ID starts a fresh account.
  assert.notEqual((await signIn(e, apple, 'apple-gone')).me.id, gone.me.id);
});

// MARK: Google and Facebook

const GOOGLE_CLIENT = '1234-abc.apps.googleusercontent.com';
const GOOGLE_PHOTO = 'https://lh3.googleusercontent.com/a/photo=s96-c';
const FB_PHOTO = 'https://scontent.xx.fbcdn.net/v/t1/photo.jpg';

/// Everything at once: Apple, Google and Facebook stand-ins, and a fake network for photos
/// and Facebook's Graph API.
async function socialEnv() {
  const apple = await fakeApple();
  const google = await fakeApple({ iss: 'https://accounts.google.com', aud: GOOGLE_CLIENT });
  const fetched = [];
  const FETCH = async (href) => {
    fetched.push(href);
    const u = new URL(href);
    if (u.hostname === 'lh3.googleusercontent.com') return new Response(jpeg(100));
    if (u.hostname.endsWith('fbcdn.net')) return new Response(jpeg(120));
    if (u.pathname.endsWith('/oauth/access_token')) {
      return u.searchParams.get('code') === 'good-code' && u.searchParams.get('client_secret') === 'fb-secret'
        ? Response.json({ access_token: 'fb-token' }) : new Response('{}', { status: 400 });
    }
    if (u.pathname.endsWith('/me') && u.searchParams.get('access_token') === 'fb-token') {
      return Response.json({ id: '9876', name: 'Dave FB', picture: { data: { url: FB_PHOTO, is_silhouette: false } } });
    }
    return new Response('nope', { status: 404 });
  };
  const e = {
    ...env(), APPLE_KEYS: apple.keys, GOOGLE_KEYS: google.keys, GOOGLE_CLIENT_IDS: `other-client, ${GOOGLE_CLIENT}`,
    FACEBOOK_APP_ID: '1111', FACEBOOK_APP_SECRET: 'fb-secret', FETCH,
  };
  return { e, apple, google, fetched };
}

const googleIn = async (e, google, sub, extra = {}, account) => call(e, 'POST', '/api/auth/google', {
  type: 'application/json', account,
  body: JSON.stringify({ idToken: await google.sign({ sub, name: 'Dave G', picture: GOOGLE_PHOTO, ...extra }) }),
});
const facebookIn = (e, code = 'good-code', account) => call(e, 'POST', '/api/auth/facebook', {
  type: 'application/json', account, body: JSON.stringify({ code }),
});

test('Google ID tokens are checked', async () => {
  const { e, google, apple } = await socialEnv();
  assert.ok(await verifyGoogleToken(await google.sign({ sub: 'g-1' }), e));
  assert.ok(await verifyGoogleToken(await google.sign({ sub: 'g-1', iss: 'accounts.google.com' }), e));
  assert.equal(await verifyGoogleToken(await google.sign({ sub: 'g-1', aud: 'someone-elses-client' }), e), null);
  assert.equal(await verifyGoogleToken(await google.sign({ sub: 'g-1', exp: 1 }), e), null);
  assert.equal(await verifyGoogleToken(await apple.sign({ sub: 'g-1' }), e), null, 'an Apple token is not a Google token');
  assert.equal(await verifyGoogleToken(await google.sign({ sub: 'g-1' }), { ...e, GOOGLE_CLIENT_IDS: '' }), null, 'off until configured');
});

test('Google sign-in brings in the name and photo', async () => {
  const { e, google, fetched } = await socialEnv();
  const res = await googleIn(e, google, 'g-1');
  assert.equal(res.status, 200);
  const { token, me } = await res.json();
  assert.equal(me.name, 'Dave G');
  assert.deepEqual(me.logins, ['google']);
  assert.equal(me.avatarSource, 'google');
  assert.deepEqual(me.photos, ['google']);
  assert.ok(fetched.includes('https://lh3.googleusercontent.com/a/photo=s600-c'), 'asks Google for a big photo');
  assert.equal((await call(e, 'GET', `/u/${me.id}/avatar.jpg`)).status, 200);
  // Same Google account, same Film Exposures account.
  assert.equal((await (await googleIn(e, google, 'g-1')).json()).me.id, me.id);
  assert.ok(token);
});

test('photos only come from the provider’s own image hosts', async () => {
  const { e, google, fetched } = await socialEnv();
  const { me } = await (await googleIn(e, google, 'g-2', { picture: 'https://evil.example.com/x.jpg' })).json();
  assert.equal(me.avatar, null);
  assert.ok(!fetched.some((h) => h.includes('evil.example.com')));
});

test('Facebook sign-in swaps the code on the server', async () => {
  const { e } = await socialEnv();
  assert.equal((await facebookIn(e, 'bad-code')).status, 401);
  const { me } = await (await facebookIn(e)).json();
  assert.equal(me.name, 'Dave FB');
  assert.deepEqual(me.logins, ['facebook']);
  assert.equal(me.avatarSource, 'facebook');
  assert.equal((await facebookIn({ ...e, FACEBOOK_APP_SECRET: '' })).status, 503, 'off until configured');

  // Facebook sends people back to the web; the server hands the code to the app.
  const back = await call(e, 'GET', '/auth/facebook/callback?code=abc&state=xyz');
  assert.equal(back.status, 302);
  assert.equal(back.headers.get('location'), 'exposures://auth/facebook?code=abc&state=xyz');
});

test('your own photo wins, and you can go back to a provider’s', async () => {
  const { e, google } = await socialEnv();
  const { token: account } = await (await googleIn(e, google, 'g-1')).json();
  let me = await (await call(e, 'PUT', '/api/me/avatar', { account, body: jpeg(80) })).json();
  assert.equal(me.avatarSource, 'own');
  // Signing in with Google again doesn't replace it.
  me = (await (await googleIn(e, google, 'g-1')).json()).me;
  assert.equal(me.avatarSource, 'own');
  me = await (await call(e, 'POST', '/api/me/avatar/use', { account, type: 'application/json', body: '{"provider":"google"}' })).json();
  assert.equal(me.avatarSource, 'google');
  assert.equal(e.ROLLS.objects.get(`users/${me.id}/avatar.jpg`).length, 100, 'Google’s photo is back');
  assert.equal((await call(e, 'POST', '/api/me/avatar/use', { account, type: 'application/json', body: '{"provider":"facebook"}' })).status, 404);
});

test('sign-ins can be added to one account, but not stolen from another', async () => {
  const { e, apple, google } = await socialEnv();
  const { token: account, me } = await signIn(e, apple, 'apple-1', '@david');
  assert.deepEqual(me.logins, ['apple']);
  // Signed in with Apple, add Google and Facebook.
  const added = await (await googleIn(e, google, 'g-1', {}, account)).json();
  assert.equal(added.token, null, 'no new session when adding a sign-in');
  assert.equal(added.me.id, me.id);
  assert.equal(added.me.name, '@david', 'keeps the name you already had');
  assert.equal(added.me.avatarSource, 'google', 'no headshot yet, so Google’s photo is used');
  assert.deepEqual((await (await facebookIn(e, 'good-code', account)).json()).me.logins, ['apple', 'google', 'facebook']);
  // Each now signs in to the same account.
  assert.equal((await (await googleIn(e, google, 'g-1')).json()).me.id, me.id);
  assert.equal((await (await facebookIn(e)).json()).me.id, me.id);

  // Someone else can't add your Google account to theirs.
  const other = await signIn(e, apple, 'apple-2');
  const res = await googleIn(e, google, 'g-1', {}, other.token);
  assert.equal(res.status, 409);

  // Deleting the account frees all three.
  await call(e, 'DELETE', '/api/me', { account });
  assert.notEqual((await (await googleIn(e, google, 'g-1')).json()).me.id, me.id);
  assert.ok(![...e.ROLLS.objects.keys()].some((k) => k.startsWith(`users/${me.id}`)));
});

test('accounts made before Google and Facebook still work', async () => {
  const { e, apple } = await socialEnv();
  const { me } = await signIn(e, apple, 'apple-old');
  // An account record from the first version: one appleKey, no logins.
  const record = JSON.parse(new TextDecoder().decode(e.ROLLS.objects.get(`users/${me.id}.json`)));
  record.appleKey = record.logins.apple;
  delete record.logins;
  await e.ROLLS.put(`users/${me.id}.json`, JSON.stringify(record));
  const again = await signIn(e, apple, 'apple-old');
  assert.equal(again.me.id, me.id);
  assert.deepEqual(again.me.logins, ['apple']);
  await call(e, 'DELETE', '/api/me', { account: again.token });
  assert.ok(![...e.ROLLS.objects.keys()].some((k) => k.startsWith('accounts/')), 'its Apple sign-in is freed');
});

test('colour film links decode like the app', async () => {
  // A version-2 code: the black & white settings, then the colour ones, tone, effect, ISO, name.
  const bytes = [2, ...Array(18).fill(128), ...Array(15).fill(128), 0, 0, 0x01, 0x90, ...new TextEncoder().encode('TIDE 200')];
  const code = Buffer.from(bytes).toString('base64url');
  const film = decodeFilm(code);
  assert.equal(film.color, true);
  assert.equal(film.name, 'TIDE 200');
  assert.equal(film.iso, 400);
  assert.ok(Math.abs(film.saturation - 0.8) < 0.01);
  assert.match(caption(film), /^Color · ISO 400/);
  const page = await (await call(env(), 'GET', `/f/${code}`)).text();
  assert.match(page, /TIDE 200/);
  assert.match(page, /Saturation/);
  assert.equal(decodeFilm(Buffer.from([5, ...bytes.slice(1)]).toString('base64url')), null, 'unknown versions are refused');
  assert.equal(decodeFilm(Buffer.from(bytes.slice(0, 30)).toString('base64url')), null, 'short colour codes are refused');
});

test('version 3 colour codes carry strength; version 2 opens at full strength', () => {
  const name = [...new TextEncoder().encode('SOFT')];
  const v3 = decodeFilm(Buffer.from([3, ...Array(18).fill(128), ...Array(15).fill(128), 64, 0, 0, 0x01, 0x90, ...name]).toString('base64url'));
  assert.equal(v3.color, true);
  assert.ok(Math.abs(v3.strength - 64 / 255) < 0.001);
  assert.equal(v3.name, 'SOFT');
  const v2 = decodeFilm(Buffer.from([2, ...Array(18).fill(128), ...Array(15).fill(128), 0, 0, 0x01, 0x90, ...name]).toString('base64url'));
  assert.equal(v2.strength, 1);
  assert.equal(v2.name, 'SOFT');
});

test('version 4 colour codes carry unify', () => {
  const name = [...new TextEncoder().encode('EARTH 200')];
  const v4 = decodeFilm(Buffer.from([4, ...Array(18).fill(128), ...Array(15).fill(128), 178, 179, 27, 0, 0, 0, 200, ...name]).toString('base64url'));
  assert.ok(Math.abs(v4.unify - 179 / 255) < 0.001);
  assert.ok(Math.abs(v4.unifyHue - 27 / 255) < 0.001);
  assert.equal(v4.name, 'EARTH 200');
  assert.equal(v4.iso, 200);
});

// MARK: Website

test('the website has its pages, linked from every page', async () => {
  const e = env();
  for (const [path, words] of [['/', /A film camera/], ['/privacy', /Privacy policy/], ['/terms', /Terms of use/], ['/support', /How can we help/]]) {
    const res = await call(e, 'GET', path);
    assert.equal(res.status, 200, path);
    const page = await res.text();
    assert.match(page, words, path);
    assert.match(page, /href="\/privacy"/, `${path} links the privacy policy`);
    assert.match(page, /href="\/terms"/, `${path} links the terms`);
    assert.match(page, /href="\/support"/, `${path} links support`);
    assert.match(page, /© \d{4} Film Exposures/, `${path} has the copyright line`);
    assert.doesNotMatch(page, /@gmail|@moregroup|mailto:/, `${path} shows no email address`);
  }
});

const support = (e, fields, { ip = '1.2.3.4', now } = {}) => route(new Request(ORIGIN + '/api/support', {
  method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'cf-connecting-ip': ip },
  body: new URLSearchParams(fields).toString(),
}), e, now);
const good = { email: 'someone@example.com', name: 'Sam', topic: 'Report a problem', message: 'The develop timer never fires.' };

test('the support form stores messages for the inbox', async () => {
  const e = { ...env(), ADMIN_TOKEN: 'inbox-password' };
  const res = await support(e, good);
  assert.equal(res.status, 200);
  assert.match(await res.text(), /Your message has been sent/);
  const stored = [...e.ROLLS.objects.keys()].filter((k) => k.startsWith('support/'));
  assert.equal(stored.length, 1);

  // The inbox needs the password.
  assert.equal((await call(e, 'GET', '/api/admin/support')).status, 401);
  assert.equal((await call(e, 'GET', '/api/admin/support', { token: 'wrong' })).status, 401);
  const { messages } = await (await call(e, 'GET', '/api/admin/support', { token: 'inbox-password' })).json();
  assert.equal(messages.length, 1);
  assert.equal(messages[0].email, 'someone@example.com');
  assert.equal(messages[0].topic, 'Report a problem');

  // Done moves it out of the inbox.
  assert.equal((await call(e, 'DELETE', `/api/admin/support/${messages[0].id}`, { token: 'inbox-password' })).status, 200);
  assert.equal((await (await call(e, 'GET', '/api/admin/support', { token: 'inbox-password' })).json()).messages.length, 0);
  assert.ok(e.ROLLS.objects.has(`support-done/${messages[0].id}.json`));

  assert.equal((await call(env(), 'GET', '/api/admin/support', { token: 'x' })).status, 503, 'no inbox until the password is set');
  assert.equal((await call(e, 'GET', '/admin')).status, 200);
});

test('the support form checks what it gets', async () => {
  const e = env();
  assert.equal((await support(e, { ...good, email: 'not-an-email' })).status, 400);
  assert.equal((await support(e, { ...good, message: 'hi' })).status, 400);
  // A bot fills the hidden field: thanked, not stored.
  const bot = await support(e, { ...good, website: 'http://spam.example' });
  assert.equal(bot.status, 200);
  assert.ok(![...e.ROLLS.objects.keys()].some((k) => k.startsWith('support/')));
  // An odd topic is filed under "Something else"; HTML in messages is kept as text.
  await support(e, { ...good, topic: '<script>', message: '<b>bold</b> request here' });
  const saved = JSON.parse(new TextDecoder().decode([...e.ROLLS.objects.entries()].find(([k]) => k.startsWith('support/'))[1]));
  assert.equal(saved.topic, 'Something else');
});

test('the support form limits each address to a few an hour', async () => {
  const e = env();
  const now = Date.UTC(2026, 10, 2, 15, 10);
  for (let i = 0; i < 5; i++) assert.equal((await support(e, good, { now: now + i })).status, 200);
  assert.equal((await support(e, good, { now: now + 9 })).status, 400, 'sixth in the hour');
  assert.equal((await support(e, good, { ip: '5.6.7.8', now: now + 10 })).status, 200, 'someone else can still write');
  assert.equal((await support(e, good, { now: now + 61 * 60 * 1000 })).status, 200, 'the next hour is fine');
  await sweep(e, now + 2 * 60 * 60 * 1000);
  assert.ok(![...e.ROLLS.objects.keys()].some((k) => k.startsWith('support-rate/')), 'old counters are swept');
test('www sends people to the plain domain', async () => {
  const res = await route(new Request('https://www.filmexposures.com/r/AbCdEfGh23?x=1'), env());
  assert.equal(res.status, 301);
  assert.equal(res.headers.get('location'), 'https://filmexposures.com/r/AbCdEfGh23?x=1');
});
