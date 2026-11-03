// Following, search, blocking and who may see a roll. Most of these try to reach a roll
// they shouldn't: as a stranger, signed out, after a block, with a forged photo link.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { route, validHandle, searchWord } from '../src/worker.js';

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
    // Like R2: keys in lexicographic order.
    return { objects: [...this.objects.keys()].filter((k) => k.startsWith(prefix)).sort().map((key) => ({ key })), truncated: false };
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

async function shareRoll(e, frames = 2, now = Date.now(), account) {
  const res = await call(e, 'POST', '/api/rolls', {
    type: 'application/json', now, account,
    body: JSON.stringify({ frames, title: 'Roll 02 <b>', film: { name: 'PAN 50', code: PAN50 }, sharer: { id: 'abc12345-def', name: '@david' } }),
  });
  assert.equal(res.status, 201);
  return res.json();
}

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


const get = async (e, path, who) => call(e, 'GET', path, { account: who?.token });
const getJSON = async (e, path, who) => (await get(e, path, who)).json();

async function person(e, apple, sub, name, handle) {
  const p = await signIn(e, apple, sub, name);
  await call(e, 'POST', '/api/me/terms', { account: p.token });
  if (handle) {
    const res = await call(e, 'PUT', '/api/me', { account: p.token, type: 'application/json', body: JSON.stringify({ handle }) });
    assert.equal(res.status, 200, `handle ${handle}`);
  }
  return { ...p, id: p.me.id };
}

const audience = (e, who, id, body) => call(e, 'POST', `/api/rolls/${id}/visibility`, { account: who.token, type: 'application/json', body: JSON.stringify(body) });
const followReq = (e, who, target, on = true) => call(e, on ? 'POST' : 'DELETE', `/api/users/${target.id}/follow`, { account: who.token });
const answer = (e, who, from, accept) => call(e, 'POST', `/api/me/requests/${from.id}`, { account: who.token, type: 'application/json', body: JSON.stringify({ accept }) });

async function cast() {
  const { e, apple } = await accountEnv();
  const ana = await person(e, apple, 'a', 'Ana Lima', 'ana');
  const ben = await person(e, apple, 'b', 'Ben Ito', 'ben.ito');
  const cy = await person(e, apple, 'c', 'Cy', 'cy_');
  return { e, apple, ana, ben, cy };
}

test('handles are checked and unique', async () => {
  assert.ok(validHandle('ana'));
  assert.ok(validHandle('ben.ito_2'));
  for (const bad of ['ab', 'a'.repeat(21), '.ana', 'ana.', 'an..a', 'Ana', 'an a', 'admin', 'support']) assert.ok(!validHandle(bad), bad);
  assert.equal(searchWord('Zoë Çelik'), 'zoecelik');

  const { e, ben } = await cast();
  const taken = await call(e, 'PUT', '/api/me', { account: ben.token, type: 'application/json', body: JSON.stringify({ handle: '@Ana' }) });
  assert.equal(taken.status, 409, 'someone has it, whatever the case or @');
  const me = await (await call(e, 'PUT', '/api/me', { account: ben.token, type: 'application/json', body: JSON.stringify({ handle: 'benny' }) })).json();
  assert.equal(me.handle, 'benny');
  // The old handle is free again.
  assert.equal((await call(e, 'PUT', '/api/me', { account: ben.token, type: 'application/json', body: JSON.stringify({ handle: 'ben.ito' }) })).status, 200);
});

test('search finds people by handle or name, but not hidden or blocked ones', async () => {
  const { e, ana, ben, cy } = await cast();
  const find = async (q, who = ana) => (await getJSON(e, `/api/users/search?q=${encodeURIComponent(q)}`, who)).people.map((p) => p.handle);
  assert.equal((await call(e, 'GET', '/api/users/search?q=ben')).status, 401, 'signed in only');
  assert.deepEqual(await find('ben'), ['ben.ito']);
  assert.deepEqual(await find('ITO'), ['ben.ito'], 'by a word of the name');
  assert.deepEqual(await find('a'), [], 'two letters at least');
  assert.deepEqual(await find('an'), [], 'not yourself');

  await call(e, 'PUT', '/api/me', { account: ben.token, type: 'application/json', body: JSON.stringify({ discoverable: false }) });
  assert.deepEqual(await find('ben'), [], 'ben turned search off');
  await call(e, 'PUT', '/api/me', { account: ben.token, type: 'application/json', body: JSON.stringify({ discoverable: true }) });
  await call(e, 'POST', `/api/users/${ana.id}/block`, { account: ben.token });
  assert.deepEqual(await find('ben'), [], 'ben blocked ana');
  assert.deepEqual(await find('ana', cy), ['ana']);
});

test('browsing lists findable people by handle, a page at a time', async () => {
  const { e, apple, ana, ben, cy } = await cast();
  assert.equal((await call(e, 'GET', '/api/users/browse')).status, 401, 'signed in only');
  const names = async (who, after = '') => {
    const page = await getJSON(e, `/api/users/browse${after ? `?after=${after}` : ''}`, who);
    return [page.people.map((p) => p.handle), page.after];
  };
  assert.deepEqual(await names(cy), [['ana', 'ben.ito'], null], 'everyone but you, by handle');
  await call(e, 'PUT', '/api/me', { account: ben.token, type: 'application/json', body: JSON.stringify({ discoverable: false }) });
  assert.deepEqual((await names(cy))[0], ['ana'], 'not people who turned search off');
  await call(e, 'POST', `/api/users/${cy.id}/block`, { account: ana.token });
  assert.deepEqual((await names(cy))[0], [], 'not people who blocked you');
  await person(e, apple, 'd', 'Dee', 'dee');
  assert.deepEqual(await names(ben, 'ana'), [['cy_', 'dee'], null], 'after a handle');

  // Pages of 30.
  for (let n = 0; n < 31; n++) await person(e, apple, `p${n}`, `P ${n}`, `p${String(n).padStart(2, '0')}`);
  const [first, next] = await names(ben);
  assert.equal(first.length, 30);
  assert.equal(next, first[29]);
  const [rest, end] = await names(ben, next);
  assert.ok(rest.length >= 1 && end === null, 'the last page ends');
  assert.ok(!rest.some((h) => first.includes(h)), 'no repeats');
});

test('browse lists everyone\'s public rolls, newest first', async () => {
  const { e, ana, ben, cy } = await cast();
  assert.equal((await call(e, 'GET', '/api/rolls/browse')).status, 401, 'signed in only');
  const t0 = Date.now();
  const share = async (who, body, at) => {
    const { id } = await liveRoll(e, 2, who.token, at);
    assert.equal((await call(e, 'POST', `/api/rolls/${id}/visibility`, { account: who.token, type: 'application/json', body: JSON.stringify(body), now: at })).status, 200);
    return id;
  };
  const a1 = await share(ana, { audience: 'public' }, t0 + 1000);
  const b1 = await share(ben, { audience: 'public' }, t0 + 2000);
  await share(ana, { audience: 'followers' }, t0 + 3000);
  await share(ben, { public: false }, t0 + 4000);   // a link share
  const ids = async (who, after) => (await getJSON(e, `/api/rolls/browse${after ? `?after=${encodeURIComponent(after)}` : ''}`, who));
  let page = await ids(cy);
  assert.deepEqual(page.rolls.map((r) => r.id), [b1, a1], 'public only, newest first');
  assert.equal(page.rolls[0].by.handle, 'ben.ito');
  assert.equal(page.after, null);

  await call(e, 'POST', `/api/rolls/${b1}/visibility`, { account: ben.token, type: 'application/json', body: JSON.stringify({ audience: 'followers' }) });
  assert.deepEqual((await ids(cy)).rolls.map((r) => r.id), [a1], 'gone when it stops being public');
  await call(e, 'POST', `/api/users/${cy.id}/block`, { account: ana.token });
  assert.deepEqual((await ids(cy)).rolls, [], 'not from people who blocked you');
});

test('a profile link shows the preview the app made, or the site image', async () => {
  const { e, ana } = await cast();
  let page = await (await call(e, 'GET', `/u/${ana.id}`)).text();
  assert.match(page, /og:image" content="https:\/\/exposures.example.workers.dev\/og-image.png"/);
  assert.equal((await call(e, 'PUT', '/api/me/preview', { body: jpeg() })).status, 401);
  assert.equal((await call(e, 'PUT', '/api/me/preview', { account: ana.token, body: new Uint8Array([1, 2, 3]) })).status, 415);
  const { preview } = await (await call(e, 'PUT', '/api/me/preview', { account: ana.token, body: jpeg() })).json();
  assert.match(preview, /\/u\/\w{12}\/preview.jpg\?v=1$/);
  page = await (await call(e, 'GET', `/u/${ana.id}`)).text();
  assert.ok(page.includes(`og:image" content="${preview}"`));
  assert.equal((await call(e, 'GET', `/u/${ana.id}/preview.jpg`)).status, 200);
  assert.equal((await getJSON(e, `/u/${ana.id}/profile.json`)).preview, preview);
});

test('send a profile or a roll to a follower; it shows up for them to follow or view', async () => {
  const { e, ana, ben, cy } = await cast();
  const sendIt = (who, body) => call(e, 'POST', '/api/sends', { account: who.token, type: 'application/json', body: JSON.stringify(body) });
  // Ben follows Ana, so Ana can send to Ben; Cy doesn't follow Ana.
  await followReq(e, ben, ana);
  await answer(e, ana, ben, true);
  assert.equal((await call(e, 'POST', '/api/sends', { type: 'application/json', body: '{}' })).status, 401);
  assert.equal((await sendIt(ana, { to: 'cy_', kind: 'profile', id: ben.id })).status, 403, 'only to people who follow you');
  assert.equal((await sendIt(ana, { to: 'nobody', kind: 'profile', id: ben.id })).status, 404);
  assert.equal((await sendIt(ana, { to: '@Ben.Ito', kind: 'profile', id: cy.id })).status, 200, 'by handle, any case, with @');

  const followersRoll = await rollFor(e, ana, { audience: 'followers' });
  const cysOnly = await rollFor(e, ana, { audience: 'people', people: [cy.id] });
  assert.equal((await sendIt(ana, { to: ben.id, kind: 'roll', id: followersRoll })).status, 200);
  assert.equal((await sendIt(ana, { to: ben.id, kind: 'roll', id: cysOnly })).status, 403, "not a roll they can't see");

  let sends = (await getJSON(e, '/api/me/sends', ben)).sends;
  assert.deepEqual(sends.map((x) => x.kind).sort(), ['profile', 'roll']);
  const profile = sends.find((x) => x.kind === 'profile');
  assert.equal(profile.from.handle, 'ana');
  assert.equal(profile.profile.handle, 'cy_');
  assert.equal(profile.profile.status, 'none');
  assert.equal(sends.find((x) => x.kind === 'roll').roll.id, followersRoll);
  assert.deepEqual((await getJSON(e, '/api/me/sends', cy)).sends, [], 'only for the person it was sent to');

  // Dismissing takes it away; removing the follower takes away the roll they could see.
  assert.equal((await call(e, 'DELETE', `/api/me/sends/${profile.key}`, { account: ben.token })).status, 200);
  await call(e, 'DELETE', `/api/me/followers/${ben.id}`, { account: ana.token });
  sends = (await getJSON(e, '/api/me/sends', ben)).sends;
  assert.deepEqual(sends, []);
});

test('following is a request the other person approves', async () => {
  const { e, apple, ana, ben } = await cast();
  const noHandle = await person(e, apple, 'd', 'Dee');
  assert.equal((await followReq(e, noHandle, ana)).status, 409, 'a handle first');
  assert.equal((await followReq(e, ana, ana)).status, 400);

  assert.equal((await (await followReq(e, ben, ana)).json()).status, 'requested');
  assert.equal((await getJSON(e, `/u/${ana.id}/profile.json`, ben)).relation.status, 'requested');
  assert.deepEqual((await getJSON(e, '/api/me/requests', ana)).people.map((p) => p.handle), ['ben.ito']);
  assert.equal((await answer(e, ben, ana, true)).status, 404, "ben can't approve his own request");
  assert.equal((await (await answer(e, ana, ben, true)).json()).status, 'follower');

  let profile = await getJSON(e, `/u/${ana.id}/profile.json`, ben);
  assert.equal(profile.relation.status, 'following');
  assert.equal(profile.followers, 1);
  assert.deepEqual((await getJSON(e, `/api/users/${ben.id}/following`, ana)).people.map((p) => p.handle), ['ana']);
  assert.deepEqual((await getJSON(e, '/api/me/requests', ana)).people, []);

  // Ana can remove Ben; Ben can unfollow.
  await call(e, 'DELETE', `/api/me/followers/${ben.id}`, { account: ana.token });
  assert.equal((await getJSON(e, `/u/${ana.id}/profile.json`, ben)).relation.status, 'none');
  await followReq(e, ben, ana);
  await answer(e, ana, ben, false);
  assert.equal((await getJSON(e, `/u/${ana.id}/profile.json`, ben)).relation.status, 'none', 'turned down');
});

async function rollFor(e, owner, body) {
  const { id } = await liveRoll(e, 2, owner.token);
  const res = await audience(e, owner, id, body);
  assert.equal(res.status, 200, JSON.stringify(body));
  return id;
}

/// Everything a viewer could try for a roll: its details, a photo, likes and liking.
async function reach(e, id, who) {
  const json = await get(e, `/r/${id}/roll.json`, who);
  const page = await call(e, 'GET', `/r/${id}`);
  const photo = await call(e, 'GET', `/r/${id}/frame-01.jpg`);
  const likes = await get(e, `/api/rolls/${id}/likes`, who);
  const like = who ? await call(e, 'PUT', `/api/rolls/${id}/frames/1/like`, { account: who.token }) : { status: 401 };
  return { json: json.status, page: page.status, photo: photo.status, likes: likes.status, like: like.status };
}

test('a followers roll is for approved followers only, photos included', async () => {
  const { e, ana, ben, cy } = await cast();
  await followReq(e, ben, ana);
  await answer(e, ana, ben, true);
  await followReq(e, cy, ana);   // asked, not approved
  const id = await rollFor(e, ana, { audience: 'followers' });

  const roll = await getJSON(e, `/r/${id}/roll.json`, ben);
  assert.equal(roll.audience, 'followers');
  assert.match(roll.frames[0], /\?exp=\d+&sig=/, 'photos come as signed links');
  assert.equal((await call(e, 'GET', roll.frames[0].replace(ORIGIN, ''))).status, 200, 'a signed link loads');
  assert.equal((await reach(e, id, ben)).like, 200);

  for (const [who, label] of [[cy, 'asked but not approved'], [null, 'signed out']]) {
    const r = await reach(e, id, who);
    assert.equal(r.json, 404, label);
    assert.equal(r.photo, 404, `${label}: the plain photo link`);
    assert.equal(r.page, 404, `${label}: the web page`);
    assert.equal(r.likes, 404, label);
  }
  assert.equal((await call(e, 'PUT', `/api/rolls/${id}/frames/1/like`, { account: cy.token })).status, 404, 'no liking what you cannot see');

  // Forged, moved or stale signatures fail.
  const signed = new URL(roll.frames[0]);
  const sig = signed.searchParams.get('sig');
  const exp = signed.searchParams.get('exp');
  assert.equal((await call(e, 'GET', `/r/${id}/frame-02.jpg?exp=${exp}&sig=${sig}`)).status, 404, 'a signature is for one photo');
  assert.equal((await call(e, 'GET', `/r/${id}/frame-01.jpg?exp=${Number(exp) + 3600000}&sig=${sig}`)).status, 404, 'changing the time breaks it');
  const later = Number(exp) + 1;
  assert.equal((await call(e, 'GET', `/r/${id}/frame-01.jpg?exp=${exp}&sig=${sig}`, { now: later })).status, 404, 'expired');

  // On Ana's profile: Ben sees it, Cy and the web don't.
  assert.equal((await getJSON(e, `/u/${ana.id}/profile.json`, ben)).rolls.length, 1);
  assert.equal((await getJSON(e, `/u/${ana.id}/profile.json`, cy)).rolls.length, 0);
  assert.equal((await getJSON(e, `/u/${ana.id}/profile.json`)).rolls.length, 0);
  // In Ben's feed, not Cy's.
  assert.deepEqual((await getJSON(e, '/api/feed', ben)).rolls.map((r) => r.id), [id]);
  assert.deepEqual((await getJSON(e, '/api/feed', cy)).rolls, []);

  // Removing Ben takes it away from him.
  await call(e, 'DELETE', `/api/me/followers/${ben.id}`, { account: ana.token });
  assert.equal((await reach(e, id, ben)).json, 404);
});

test('a roll for specific people reaches only them, in their inbox', async () => {
  const { e, ana, ben, cy } = await cast();
  assert.equal((await audience(e, ana, (await liveRoll(e, 1, ana.token)).id, { audience: 'people', people: [] })).status, 400, 'someone to share with');
  const id = await rollFor(e, ana, { audience: 'people', people: [ben.id, 'nobody123456'] });

  assert.equal((await reach(e, id, ben)).json, 200);
  assert.equal((await reach(e, id, cy)).json, 404);
  assert.equal((await reach(e, id, null)).photo, 404);
  assert.deepEqual((await getJSON(e, '/api/me/inbox', ben)).rolls.map((r) => r.id), [id]);
  assert.deepEqual((await getJSON(e, '/api/me/inbox', cy)).rolls, []);
  const own = await getJSON(e, `/r/${id}/roll.json`, ana);
  assert.deepEqual(own.people.map((p) => p.handle), ['ben.ito'], 'the owner sees who; unknown accounts dropped');
  assert.equal((await getJSON(e, `/r/${id}/roll.json`, ben)).people, undefined, 'recipients do not see the list');

  // Swap Ben for Cy.
  await audience(e, ana, id, { audience: 'people', people: [cy.id] });
  assert.equal((await reach(e, id, ben)).json, 404);
  assert.deepEqual((await getJSON(e, '/api/me/inbox', ben)).rolls, []);
  assert.deepEqual((await getJSON(e, '/api/me/inbox', cy)).rolls.map((r) => r.id), [id]);
  // Private: only Ana.
  await audience(e, ana, id, { audience: 'private' });
  assert.equal((await reach(e, id, cy)).json, 404);
  assert.deepEqual((await getJSON(e, '/api/me/inbox', cy)).rolls, []);
  assert.equal((await reach(e, id, ana)).json, 200, 'the owner still can');
});

test('public and link rolls stay open; older apps still work', async () => {
  const { e, ana, cy } = await cast();
  const pub = await rollFor(e, ana, { public: true });
  const roll = await getJSON(e, `/r/${pub}/roll.json`);
  assert.equal(roll.audience, 'public');
  assert.doesNotMatch(roll.frames[0], /sig=/, 'open rolls keep plain, cacheable links');
  assert.equal((await reach(e, pub, null)).page, 200);
  assert.equal((await getJSON(e, `/u/${ana.id}/profile.json`)).rolls.length, 1);

  const link = await rollFor(e, ana, { public: false });
  assert.equal((await getJSON(e, `/r/${link}/roll.json`)).audience, 'link');
  assert.equal((await reach(e, link, cy)).json, 200, 'anyone with the link');
  assert.equal((await getJSON(e, `/u/${ana.id}/profile.json`, cy)).rolls.length, 1, 'link shares stay off profiles');
});

test('blocking cuts follows, rolls and profiles both ways', async () => {
  const { e, ana, ben } = await cast();
  await followReq(e, ben, ana);
  await answer(e, ana, ben, true);
  const followers = await rollFor(e, ana, { audience: 'followers' });
  const pub = await rollFor(e, ana, { audience: 'public' });

  await call(e, 'POST', `/api/users/${ben.id}/block`, { account: ana.token });
  assert.equal((await reach(e, followers, ben)).json, 404);
  assert.equal((await get(e, `/r/${pub}/roll.json`, ben)).status, 404, 'signed in, even public rolls');
  assert.equal((await get(e, `/u/${ana.id}/profile.json`, ben)).status, 404);
  assert.equal((await followReq(e, ben, ana)).status, 404, 'no asking again');
  assert.equal((await getJSON(e, `/u/${ana.id}/profile.json`, ana)).followers, 0, 'the follow is gone');
  assert.equal((await audience(e, ana, followers, { audience: 'people', people: [ben.id] })).status, 400, 'no sharing with them');

  await call(e, 'DELETE', `/api/users/${ben.id}/block`, { account: ana.token });
  assert.equal((await get(e, `/r/${pub}/roll.json`, ben)).status, 200);
  assert.equal((await reach(e, followers, ben)).json, 404, 'unblocking does not restore the follow');
});

test('deleting an account takes its handle, follows and shares with it', async () => {
  const { e, apple, ana, ben } = await cast();
  await followReq(e, ben, ana);
  await answer(e, ana, ben, true);
  const id = await rollFor(e, ana, { audience: 'people', people: [ben.id] });
  await call(e, 'DELETE', '/api/me', { account: ana.token });

  assert.deepEqual((await getJSON(e, `/api/users/${ben.id}/following`, ben)).people, []);
  assert.deepEqual((await getJSON(e, '/api/me/inbox', ben)).rolls, []);
  assert.deepEqual((await getJSON(e, '/api/users/search?q=ana', ben)).people, []);
  assert.equal((await get(e, `/r/${id}/roll.json`, ben)).status, 404);
  await person(e, apple, 'z', 'Zed', 'ana');   // the handle is free again
});
