import { test } from 'node:test';
import assert from 'node:assert/strict';
import { route, sweep, decodeFilm, caption, storeURL, verifyAppleToken, TTL_DAYS } from '../src/worker.js';

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
async function fakeApple() {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true, ['sign', 'verify']);
  const jwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
  const b64 = (v) => Buffer.from(typeof v === 'string' ? v : new Uint8Array(v)).toString('base64url');
  const sign = async (claims, kid = 'test-key') => {
    const head = b64(JSON.stringify({ alg: 'RS256', kid }));
    const body = b64(JSON.stringify({
      iss: 'https://appleid.apple.com', aud: 'com.davidanderson.retrocam',
      exp: Math.floor(Date.now() / 1000) + 600, ...claims,
    }));
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
