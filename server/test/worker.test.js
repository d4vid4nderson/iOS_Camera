import { test } from 'node:test';
import assert from 'node:assert/strict';
import { route, sweep, decodeFilm, caption, TTL_DAYS } from '../src/worker.js';

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
const call = (e, method, path, { body, token, type, now } = {}) => {
  const headers = {};
  if (token) headers.authorization = `Bearer ${token}`;
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

async function shareRoll(e, frames = 2, now = Date.now()) {
  const res = await call(e, 'POST', '/api/rolls', {
    type: 'application/json', now,
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
