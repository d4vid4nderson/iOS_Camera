// The filmexposures.com website: the home page, privacy policy, terms, support form and
// the support inbox. Styled like the app: near-black, copper accent, monospace labels,
// film tone strips.
//
// The privacy policy describes exactly what the app and this server collect. Keep it in
// step with the code (RetroCam/RollShare.swift, Account.swift, SocialSignIn.swift and
// worker.js) whenever either changes.

export const OWNER = 'Film Exposures';
export const EFFECTIVE = 'November 3, 2026';
export const GOVERNING_LAW = 'the State of Texas, United States';
export const SUPPORT_TOPICS = ['Help using the app', 'Account or sign-in', 'Report a problem', 'Report content', 'Privacy request', 'Something else'];

export const SITE_CSS = `
:root{--bg:#0f0d0c;--panel:#171513;--panel2:#1f1c19;--fg:#f2ede4;--muted:#8f887d;--line:#2c2824;--accent:#e8762e;--accent-ink:#1a0f07;
--mono:ui-monospace,"SF Mono",SFMono-Regular,Menlo,Consolas,monospace;
--edge:#f0a24e;--base:#15100c;--light:#f6ecd6;--ink:#2b2117;
--grain:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2' stitchTiles='stitch'/%3E%3CfeColorMatrix values='0 0 0 0 .5 0 0 0 0 .5 0 0 0 0 .5 0 0 0 .55 0'/%3E%3C/filter%3E%3Crect width='160' height='160' filter='url(%23n)'/%3E%3C/svg%3E")}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;background:radial-gradient(120% 80% at 50% 0%,#1b1714 0%,var(--bg) 60%) fixed,var(--bg);color:var(--fg);font:16px/1.5 -apple-system,BlinkMacSystemFont,"Inter","Segoe UI",sans-serif}

a{color:var(--fg)}
.site-head,.site-foot{max-width:960px;margin:0 auto;padding:18px 20px;display:flex;align-items:center;justify-content:space-between;gap:16px}
.brand{font:700 13px/1 var(--mono);letter-spacing:.14em;text-decoration:none;display:flex;align-items:center;gap:10px}
.brand i{width:12px;height:12px;border-radius:50%;background:var(--accent);display:inline-block;box-shadow:0 0 0 3px rgba(232,118,46,.18)}
.nav{display:flex;gap:18px;font:600 12px/1 var(--mono);letter-spacing:.08em}
.nav a{text-decoration:none;color:var(--muted)}.nav a:hover{color:var(--fg)}
main{max-width:640px;margin:0 auto;padding:24px 20px 56px}
main.wide{max-width:960px}
.eyebrow{font:600 12px/1.2 var(--mono);letter-spacing:.12em;color:var(--muted);margin:0 0 12px;text-transform:uppercase}
h1{font-size:44px;line-height:1.05;letter-spacing:-.02em;margin:0 0 12px}
h2{font-size:22px;letter-spacing:-.01em;margin:36px 0 10px}
h3{font:700 12px/1.3 var(--mono);letter-spacing:.1em;text-transform:uppercase;color:var(--muted);margin:24px 0 8px}
.muted{color:var(--muted)}.small{font-size:13px}
.lede{font-size:19px;color:#c9c6c0;max-width:34em;margin:0 0 24px}
.strip{display:flex;gap:4px;margin:24px 0}.strip i{flex:1;height:56px;border-radius:6px}
.settings{list-style:none;padding:0;margin:0 0 24px;border-top:1px solid var(--line)}
.settings li{display:flex;justify-content:space-between;padding:10px 0;border-bottom:1px solid var(--line)}
.settings span{color:var(--muted)}
.button{display:block;text-align:center;padding:14px 22px;border-radius:999px;margin:10px 0;text-decoration:none;color:var(--fg);background:var(--panel2);font-weight:600;border:0;font-size:16px;cursor:pointer;width:100%}
.button.primary{background:var(--accent);color:var(--accent-ink)}
.button.disabled{color:var(--muted);background:transparent;border:1px solid var(--line);cursor:default}
.inline-buttons{display:flex;gap:10px;flex-wrap:wrap}.inline-buttons .button{width:auto;display:inline-block}
.who{display:flex;align-items:center;gap:10px;margin-bottom:16px;font-weight:600;color:var(--fg);text-decoration:none}
.profile-head{display:flex;align-items:center;gap:16px;margin-bottom:20px}.profile-head .avatar{width:72px;height:72px}
.profile-head h1{font-size:32px;margin:0}
.rolls{display:grid;grid-template-columns:repeat(2,1fr);gap:12px;margin:20px 0}
.rolls a{text-decoration:none;color:var(--fg)}.rolls img{width:100%;aspect-ratio:3/4;object-fit:cover;border-radius:10px;display:block;background:var(--panel2)}
.rolls b{display:block;font-size:14px;margin-top:6px}.rolls span{font-size:12px;color:var(--muted)}
.avatar{width:40px;height:40px;border-radius:50%;object-fit:cover}
.card{width:100%;display:block;border-radius:14px;margin:20px 0 8px}
.report{margin-top:32px;color:var(--muted)}.report form{display:flex;gap:8px;margin-top:10px;flex-wrap:wrap}
select,button,input,textarea{font:inherit;color:var(--fg)}
.report select,.report button{padding:8px 12px;border-radius:8px;border:1px solid var(--line);background:var(--panel2)}
/* Home */
.hero{padding:40px 0 8px}
.hero h1{font-size:clamp(40px,7vw,68px)}
.counter{display:inline-flex;align-items:baseline;gap:10px;font:700 15px/1 var(--mono);color:var(--muted);letter-spacing:.08em;margin-bottom:22px}
.counter b{font-size:30px;color:var(--accent);letter-spacing:0}
/* The films, as 35mm slides in their mounts */
.shelf{display:flex;align-items:center;gap:10px;font:700 11px/1 var(--mono);letter-spacing:.16em;color:var(--muted);text-transform:uppercase;margin:30px 0 14px}
.shelf::after{content:"";flex:1;height:1px;background:linear-gradient(90deg,var(--line),transparent)}
.films{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:18px 16px;margin:0 0 8px}
.mount{--card:#ece3cf;--card2:#ddd1b6;--print:#3a2d1f;--print2:#6f604c;
  position:relative;aspect-ratio:1;border:0;border-radius:9px;padding:0;cursor:pointer;font:inherit;text-align:left;color:var(--print);
  background:linear-gradient(155deg,var(--card),var(--card2));
  box-shadow:inset 0 1px 0 rgba(255,255,255,.55),inset 0 -2px 0 rgba(0,0,0,.12),0 1px 0 rgba(0,0,0,.4),0 8px 18px -8px rgba(0,0,0,.7);
  display:flex;flex-direction:column;align-items:stretch;transition:transform .18s ease,box-shadow .18s ease}
.mount.bw{--card:#e6e5e1;--card2:#cfcdc7;--print:#26262a;--print2:#5d5c5a}
.mount::before{content:"";position:absolute;inset:0;border-radius:inherit;background:var(--grain);opacity:.18;mix-blend-mode:multiply;pointer-events:none}
.mount .label{display:flex;align-items:baseline;justify-content:space-between;gap:6px;padding:9.5% 10% 0;font:800 clamp(11px,1.25vw,13px)/1 var(--mono);letter-spacing:.06em;white-space:nowrap;overflow:hidden}
.mount .label em{font-style:normal;font-weight:600;font-size:.82em;color:var(--print2)}
.mount .window{position:relative;align-self:center;width:74%;aspect-ratio:3/2;flex:none;margin:6.5% 0 0;border-radius:3px;overflow:hidden;background:#0b0907;
  box-shadow:0 0 0 1px rgba(0,0,0,.35),inset 0 0 0 1px rgba(0,0,0,.5),0 1px 0 1px rgba(255,255,255,.35)}
.mount .window img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;display:block}
.mount .window::after{content:"";position:absolute;inset:0;box-shadow:inset 0 0 12px rgba(0,0,0,.45);pointer-events:none}
.mount .note{display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;margin:auto 0 8%;padding:0 10%;font-size:clamp(10px,1.05vw,11.5px);line-height:1.25;color:var(--print2)}
.mount:hover{transform:translateY(-3px) rotate(-.6deg);box-shadow:inset 0 1px 0 rgba(255,255,255,.55),inset 0 -2px 0 rgba(0,0,0,.12),0 14px 26px -10px rgba(0,0,0,.85)}
.mount:focus-visible{outline:none;box-shadow:0 0 0 2px var(--bg),0 0 0 4px var(--edge)}
.mount[aria-expanded=true]{transform:translateY(-4px);box-shadow:0 0 0 2px var(--bg),0 0 0 3px rgba(240,162,78,.75),0 16px 28px -12px rgba(0,0,0,.9)}
/* Opened: the same slide, larger, with the before/after in its window */
.film-open{grid-column:1/-1;margin:6px 0 14px;display:grid;justify-items:center;gap:12px}
.film-open[hidden]{display:none}
.slide{--card:#ece3cf;--card2:#ddd1b6;--print:#3a2d1f;--print2:#6f604c;position:relative;width:min(100%,calc((100vh - 96px) / .86));width:min(100%,calc((100svh - 96px) / .86));border-radius:clamp(12px,2vw,20px);color:var(--print);
  background:linear-gradient(155deg,var(--card),var(--card2));display:flex;flex-direction:column;
  box-shadow:inset 0 1px 0 rgba(255,255,255,.6),inset 0 -3px 0 rgba(0,0,0,.12),0 2px 0 rgba(0,0,0,.4),0 30px 60px -24px rgba(0,0,0,.9)}
.slide.bw{--card:#e6e5e1;--card2:#cfcdc7;--print:#26262a;--print2:#5d5c5a}
.slide::before{content:"";position:absolute;inset:0;border-radius:inherit;background:var(--grain);opacity:.18;mix-blend-mode:multiply;pointer-events:none}
.slide .label{display:flex;align-items:baseline;justify-content:space-between;gap:12px;padding:6% 7% 0;font:800 clamp(14px,3.2vw,22px)/1 var(--mono);letter-spacing:.06em}
.slide .label em{font-style:normal;font-weight:600;font-size:.62em;letter-spacing:.12em;color:var(--print2)}
.slide .window{position:relative;align-self:center;width:86%;margin-top:4.5%;flex:none;border-radius:4px;
  box-shadow:0 0 0 1px rgba(0,0,0,.35),0 1px 0 1px rgba(255,255,255,.4)}
.slide .notes{margin:4.5% 0 6%;padding:0 7%;display:flex;justify-content:space-between;align-items:flex-end;gap:12px}
.slide .notes p{margin:0;font-size:clamp(12px,2.4vw,15px);line-height:1.3;color:var(--print2)}
.close{position:absolute;top:-12px;right:-12px;width:34px;height:34px;border-radius:50%;border:1px solid var(--line);background:var(--panel2);color:var(--fg);cursor:pointer;font-size:13px;z-index:3;box-shadow:0 4px 12px rgba(0,0,0,.5)}
.close:hover{background:#2a2622}
.hint{margin:0;font-size:13px;color:var(--muted)}
.compare{--split:50%;position:relative;border-radius:4px;overflow:hidden;aspect-ratio:3/2;background:#000;user-select:none;-webkit-user-select:none;touch-action:none;cursor:ew-resize}
.compare img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;display:block;-webkit-user-drag:none;pointer-events:none}
.compare .after{clip-path:inset(0 0 0 var(--split))}
.compare .handle{position:absolute;top:0;bottom:0;left:var(--split);width:2px;margin-left:-1px;background:rgba(246,236,214,.9);box-shadow:0 0 8px rgba(0,0,0,.5);pointer-events:none}
.compare .handle span{position:absolute;top:50%;left:50%;width:34px;height:34px;margin:-17px 0 0 -17px;border-radius:50%;
  background:radial-gradient(circle at 35% 30%,#fffaf0,#e4d6ba 70%,#c9b892);box-shadow:0 3px 10px rgba(0,0,0,.55),inset 0 -1px 2px rgba(0,0,0,.25)}
.compare .handle span::before{content:"‹ ›";position:absolute;inset:0;display:grid;place-items:center;font:700 15px/1 var(--mono);color:#5a4630}
.compare .tag{position:absolute;top:9px;font:700 10px/1 var(--mono);letter-spacing:.12em;color:#fff;text-shadow:0 1px 3px rgba(0,0,0,.7);pointer-events:none}
.compare .tag.left{left:11px}.compare .tag.right{right:11px}
.compare input[type=range]{position:absolute;inset:0;width:100%;height:100%;opacity:0;margin:0;pointer-events:none}
.compare:focus-within .handle span{outline:2px solid var(--edge);outline-offset:2px}
.compare .info{position:absolute;right:8px;bottom:8px;width:26px;height:26px;border-radius:50%;border:1px solid rgba(255,255,255,.35);background:rgba(0,0,0,.55);color:var(--fg);font:italic 700 13px/1 Georgia,serif;cursor:pointer;z-index:2}
.compare .info[aria-expanded=true]{background:var(--fg);color:#111}
.compare .credit{position:absolute;left:8px;right:42px;bottom:8px;margin:0;padding:7px 10px;border-radius:6px;background:rgba(10,8,6,.78);font-size:12px;line-height:1.35;color:#e8e1d4;z-index:2;cursor:auto}
.compare .credit a{color:var(--fg)}
@media (prefers-reduced-motion:reduce){.mount{transition:none}.mount:hover,.mount[aria-expanded=true]{transform:none}}
/* Long documents */
.doc p,.doc li{color:#d4d1cb}.doc ul{padding-left:20px}.doc li{margin:6px 0}
.doc .updated{font:600 12px/1 var(--mono);letter-spacing:.08em;color:var(--muted);margin-bottom:28px}
/* Forms */
.form{display:grid;gap:14px;margin:20px 0}
.form label{display:grid;gap:6px;font:600 12px/1 var(--mono);letter-spacing:.08em;color:var(--muted);text-transform:uppercase}
.form input,.form select,.form textarea{width:100%;padding:12px 14px;border-radius:12px;border:1px solid var(--line);background:var(--panel);font:16px/1.4 -apple-system,BlinkMacSystemFont,"Inter","Segoe UI",sans-serif;letter-spacing:0;text-transform:none}
.form input:focus,.form select:focus,.form textarea:focus{outline:2px solid var(--accent);outline-offset:1px}
.form textarea{min-height:160px;resize:vertical}
.hp{position:absolute;left:-9999px;width:1px;height:1px;overflow:hidden}
.notice{padding:14px 16px;border-radius:12px;background:rgba(232,118,46,.12);border:1px solid rgba(232,118,46,.4);margin:16px 0}
.notice.error{background:rgba(255,90,80,.1);border-color:rgba(255,90,80,.45)}
/* Inbox */
.msg{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:14px 16px;margin:10px 0}
.msg header{display:flex;justify-content:space-between;gap:10px;font:600 12px/1.4 var(--mono);color:var(--muted);flex-wrap:wrap}
.msg pre{white-space:pre-wrap;font:15px/1.5 -apple-system,BlinkMacSystemFont,sans-serif;margin:10px 0}
.msg button{padding:6px 12px;border-radius:999px;border:1px solid var(--line);background:var(--panel2);cursor:pointer}
.site-foot{border-top:1px solid var(--line);margin-top:24px;flex-wrap:wrap;font-size:13px;color:var(--muted)}
.site-foot nav{display:flex;gap:16px;flex-wrap:wrap}.site-foot a{color:var(--muted);text-decoration:none}.site-foot a:hover{color:var(--fg)}
@media (max-width:640px){.features{grid-template-columns:1fr}}
@media (max-width:520px){h1{font-size:36px}.nav{gap:12px}.nav .optional{display:none}.films{grid-template-columns:repeat(2,1fr);gap:14px 12px}.mount .label{font-size:12px}.mount .note{font-size:11px}}
`;

export function siteHeader() {
  return `<header class="site-head"><a class="brand" href="/"><i></i>FILM EXPOSURES</a>
<nav class="nav"><a class="optional" href="/#films">FILMS</a><a href="/support">SUPPORT</a></nav></header>`;
}

export function siteFooter(year = new Date().getUTCFullYear()) {
  return `<footer class="site-foot"><span>© ${year} ${OWNER}</span>
<nav><a href="/support">Support</a><a href="/privacy">Privacy</a><a href="/terms">Terms</a></nav></footer>`;
}

import { FILM_PREVIEWS } from './film-previews.js';

// Black & white first, then colour, as the home page shows (and numbers) them.
const SHOWN = [...FILM_PREVIEWS.filter((f) => !f.color), ...FILM_PREVIEWS.filter((f) => f.color)];

const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

/// A film as a 35mm slide in its mount: the name printed on the mount, the sample photo
/// through the film in the window, the film's description underneath.
function filmCard(f, n) {
  return `<button class="film mount ${f.color ? 'color' : 'bw'}" type="button" data-film="${esc(f.id)}" aria-expanded="false" aria-controls="film-open" aria-label="See ${esc(f.name)} before and after">
<span class="label">${esc(f.name)}<em>${String(n + 1).padStart(2, '0')}</em></span>
<span class="window"><img src="/films/thumbs/${esc(f.id)}.jpg" alt="" width="420" height="280" loading="lazy" decoding="async"></span>
<span class="note">${esc(f.blurb)}</span></button>`;
}

/// The before/after panel: opens in place, on the row under the tapped film, with the
/// photo as shot and through the film, a divider to drag, and the film's details under
/// it. Black & white films are shown on one photo and colour films on another.
function filmViewer() {
  const data = JSON.stringify(FILM_PREVIEWS.map(({ id, name, blurb, iso, color }) => ({ id, name, blurb, iso, color }))).replace(/</g, '\\u003c');
  return `<div class="film-open" id="film-open" hidden>
  <div class="slide" id="viewer-slide">
  <button class="close" type="button" id="viewer-close" aria-label="Close">✕</button>
  <div class="label"><span id="viewer-name"></span><em id="viewer-iso"></em></div>
  <div class="window">
  <div class="compare" id="compare">
    <img class="before" id="viewer-before" alt="The photo as shot" width="1200" height="800">
    <img class="after" id="viewer-after" alt="" width="1200" height="800">
    <div class="handle" aria-hidden="true"><span></span></div>
    <span class="tag left">AS SHOT</span><span class="tag right" id="viewer-tag"></span>
    <input type="range" id="slider" min="0" max="100" value="50" aria-label="Compare before and after">
    <button class="info" type="button" id="viewer-info" aria-label="About this photo" aria-expanded="false" aria-controls="viewer-credit">i</button>
    <p class="credit" id="viewer-credit" hidden></p>
  </div>
  </div>
  <div class="notes"><p id="viewer-blurb"></p></div>
  </div>
  <p class="hint">Drag across the photo to compare.</p>
</div>
<script>
(() => {
  const films = ${data};
  // The sample photos: black & white films on an Italian street, colour films on a coast.
  const credits = {
    bw: { name: 'Lou Levit', url: 'https://unsplash.com/photos/umcc42T8fD4' },
    color: { name: 'Stefan Kunze', url: 'https://unsplash.com/photos/_SmZSuZwkHg' },
  };
  const info = document.getElementById('viewer-info');
  const credit = document.getElementById('viewer-credit');
  const showCredit = (on) => { credit.hidden = !on; info.setAttribute('aria-expanded', String(on)); };
  info.addEventListener('pointerdown', (e) => e.stopPropagation());
  info.addEventListener('click', (e) => { e.stopPropagation(); showCredit(credit.hidden); });
  credit.addEventListener('pointerdown', (e) => e.stopPropagation());
  const panel = document.getElementById('film-open');
  const compare = document.getElementById('compare');
  const slider = document.getElementById('slider');
  let current = null;
  const set = (v) => compare.style.setProperty('--split', v + '%');
  const close = () => {
    panel.hidden = true;
    if (current) current.setAttribute('aria-expanded', 'false');
    current = null;
  };
  const open = (card) => {
    const f = films.find((x) => x.id === card.dataset.film);
    if (!f) return;
    if (current === card) { close(); return; }
    if (current) current.setAttribute('aria-expanded', 'false');
    current = card;
    card.setAttribute('aria-expanded', 'true');
    // Put the panel after the last card on the tapped card's row.
    let last = card;
    for (let n = card.nextElementSibling; n && n.matches('.film') && n.offsetTop === card.offsetTop; n = n.nextElementSibling) last = n;
    last.after(panel);
    document.getElementById('viewer-before').src = '/films/before-' + (f.color ? 'color' : 'bw') + '.jpg';
    const after = document.getElementById('viewer-after');
    after.src = '/films/' + f.id + '.jpg';
    after.alt = 'The photo through ' + f.name;
    document.getElementById('viewer-name').textContent = f.name;
    document.getElementById('viewer-blurb').textContent = f.blurb;
    document.getElementById('viewer-iso').textContent = (f.color ? 'COLOR' : 'B&W') + ' · ISO ' + f.iso;
    document.getElementById('viewer-slide').className = 'slide ' + (f.color ? 'color' : 'bw');
    document.getElementById('viewer-tag').textContent = f.name;
    const c = credits[f.color ? 'color' : 'bw'];
    credit.textContent = 'Sample photo by ';
    const link = document.createElement('a');
    link.href = c.url; link.textContent = c.name; link.target = '_blank'; link.rel = 'noopener';
    credit.append(link, " on Unsplash. The film is a preview of the app's look.");
    showCredit(false);
    slider.value = 50; set(50);
    panel.hidden = false;
    panel.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  };
  document.querySelectorAll('[data-film]').forEach((card) => card.addEventListener('click', () => open(card)));
  document.getElementById('viewer-close').onclick = close;
  slider.addEventListener('input', () => set(slider.value));
  // Drag (or tap) anywhere on the photo, with a finger or a mouse. The range input stays
  // for the keyboard and screen readers.
  let dragging = false;
  const follow = (e) => {
    const box = compare.getBoundingClientRect();
    const v = Math.min(100, Math.max(0, ((e.clientX - box.left) / box.width) * 100));
    slider.value = v; set(v);
  };
  compare.addEventListener('pointerdown', (e) => { dragging = true; compare.setPointerCapture(e.pointerId); follow(e); e.preventDefault(); });
  compare.addEventListener('pointermove', (e) => { if (dragging) follow(e); });
  const stop = () => { dragging = false; };
  compare.addEventListener('pointerup', stop);
  compare.addEventListener('pointercancel', stop);
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && current) close(); });
})();
</script>`;
}

export function homeBody(store) {
  const card = (f) => filmCard(f, SHOWN.indexOf(f));
  const bw = FILM_PREVIEWS.filter((f) => !f.color).map(card).join('');
  const color = FILM_PREVIEWS.filter((f) => f.color).map(card).join('');
  const get = store
    ? `<div class="inline-buttons"><a class="button primary" href="${store}">Get Film Exposures</a></div>`
    : '<div class="inline-buttons"><span class="button disabled">Coming soon to the App Store</span></div>';
  return `
<section class="hero">
  <div class="counter">ROLL 01 <b>01/36</b></div>
  <h1>A film camera<br>for your iPhone.</h1>
  <p class="lede">Load a roll of 36, shoot it on a film you choose, and let it develop: right away, when the roll is done, or the next morning, like dropping it at a lab.</p>
  ${get}
</section>
<section class="features">
  <div class="feature"><h3>Rolls of 36</h3><p>Every frame counts. Keep several rolls going, a food roll and a holiday roll, and switch between them. Each roll gets its own album in Photos.</p></div>
  <div class="feature"><h3>Develop later</h3><p>Instant, at the end of the roll, or the next morning at 9. No peeking, no retakes.</p></div>
  <div class="feature"><h3>Black &amp; white and color</h3><p>Seven black &amp; white films and seven cinematic color films, each with grain, glow and lens character. Make your own and save them.</p></div>
  <div class="feature"><h3>Share a film</h3><p>Send a film as a link. Everything travels with it, from curve and grade to grain and effects, so a friend loads exactly your look.</p></div>
</section>
<h2 id="films">The films</h2>
<p class="muted">Tap a film to see what it does to the same photo.</p>
<p class="shelf">Black &amp; white</p>
<div class="films">${bw}</div>
<p class="shelf">Color</p>
<div class="films">${color}</div>
<p class="muted small">Your photos stay on your phone. Nothing is uploaded unless you share a roll or put one on your profile.</p>
${filmViewer()}`;
}

export function privacyBody() {
  return `<article class="doc">
<p class="eyebrow">Legal</p><h1>Privacy policy</h1><p class="updated">EFFECTIVE ${EFFECTIVE.toUpperCase()}</p>
<p>This policy explains what information the Film Exposures app and the filmexposures.com website ("Film Exposures", "we", "us") collect, why, and the choices you have. We built Film Exposures to keep your photos on your phone. We don't show ads, we don't use analytics or tracking tools, and we don't sell or rent your information to anyone.</p>

<h2>On your phone</h2>
<p>The photos you take, your rolls, the films you make and your profile (name and headshot) are stored on your device. We can't see them. The app asks for:</p>
<ul>
<li><b>Camera</b>, to take photos.</li>
<li><b>Photos</b>, to save your developed frames and file each roll in its own album.</li>
</ul>
<p>The app doesn't use your location, contacts or microphone.</p>

<h2>When you share</h2>
<p>Nothing leaves your phone until you choose to share. Here is what each kind of sharing sends to our servers:</p>
<ul>
<li><b>Sharing a film</b> creates a link that contains the film's settings and name. Nothing is stored on our servers.</li>
<li><b>Sharing a roll</b> uploads its developed frames and a share card, the roll's title, the name and settings of the film it was shot on, the date it was started, and a random identifier for your phone that lets others block you. If you choose to show your name and headshot on cards, those are uploaded too. Anyone with the link can see the roll. Link shares are deleted automatically 30 days after you share them, and you can unshare at any time to delete them sooner.</li>
<li><b>Public rolls</b>, if you have an account, are shown on your public profile and can be seen and liked by anyone. They stay until you make them private or delete them, which deletes them from our servers.</li>
</ul>

<h2>Accounts</h2>
<p>An account is optional. You need one only to put rolls on a public profile and to like frames and rolls. You can sign in with Apple, Google or Facebook. We receive:</p>
<ul>
<li>An identifier for your Apple, Google or Facebook account. We store it only in a scrambled (one-way hashed) form, used to recognise you when you sign in again.</li>
<li>Your name, if the service provides it or you set one, and your profile photo from Google or Facebook, which you can replace or remove.</li>
</ul>
<p>We don't ask for your email address, contacts or friends list. We also store which frames and rolls you have liked, the time you agreed to our rules for public rolls, and sign-in sessions for your devices.</p>
<p><b>Likes are public.</b> When you like a frame or a roll, anyone who opens that roll in the app can see that you liked it, with your name and profile photo. Unlike it, or delete your account, and it's gone.</p>

<h2>Reports, blocks and support</h2>
<ul>
<li>When you <b>report</b> a roll, we store the roll, the reason you chose and the time. Rolls with several reports are hidden until they are reviewed.</li>
<li><b>Blocking</b> someone is stored only on your phone.</li>
<li>When you use the <b>support form</b>, we store the email address you give us (so we can reply), your name if you give it, the topic and your message. We keep these until your request is resolved, and for a reasonable time after in case you follow up.</li>
</ul>

<h2>Who processes your information</h2>
<ul>
<li><b>Cloudflare</b> hosts our website and servers and stores shared rolls, profiles and support messages. Like any web host, its systems process the IP address of visitors to deliver pages and protect against abuse.</li>
<li><b>Apple, Google and Meta</b> handle sign-in when you choose them. Their own privacy policies apply to what they do.</li>
<li><b>Apple</b> distributes the app through the App Store and TestFlight.</li>
</ul>
<p>We don't share your information with anyone else unless the law requires it, or to protect the safety of people using Film Exposures.</p>

<h2>Your choices and rights</h2>
<ul>
<li>Unshare a roll, or make a public roll private, to delete it from our servers.</li>
<li>Delete your account in the app (Profile, then Delete account). This deletes your profile, headshot, likes and every roll you shared while signed in.</li>
<li>Hide your name and headshot from share cards in your profile.</li>
<li>To ask for a copy of your information, or to have it corrected or deleted, contact us through the <a href="/support">support form</a>. Depending on where you live, you may have further rights under laws such as the GDPR or the CCPA, and we will honour them.</li>
</ul>

<h2>Security and retention</h2>
<p>Information is sent to our servers over encrypted connections. We keep information only as long as described above: link shares for 30 days, public rolls and accounts until you remove them, and support messages until resolved.</p>

<h2>Children</h2>
<p>Film Exposures is not directed at children under 13, and we don't knowingly collect information from them. If you believe a child has shared information with us, contact us and we will delete it.</p>

<h2>Changes</h2>
<p>If we change this policy, we will update the date at the top and, for significant changes, tell you in the app.</p>

<h2>Contact</h2>
<p>Questions about privacy: use the <a href="/support">support form</a> and choose "Privacy request".</p>
</article>`;
}

export function termsBody() {
  return `<article class="doc">
<p class="eyebrow">Legal</p><h1>Terms of use</h1><p class="updated">EFFECTIVE ${EFFECTIVE.toUpperCase()}</p>
<p>These terms are an agreement between you and ${OWNER} ("we", "us") about your use of the Film Exposures app and filmexposures.com (together, "Film Exposures"). By using Film Exposures you agree to them. If you don't agree, please don't use it.</p>

<h2>Who can use Film Exposures</h2>
<p>You must be at least 13 years old. If you are under the age of majority where you live, you may use Film Exposures only with the permission of a parent or guardian.</p>

<h2>Your account</h2>
<p>An account is optional. If you create one, you are responsible for what happens under it. Keep your Apple, Google or Facebook sign-in secure, and tell us through the <a href="/support">support form</a> if you think someone else is using your account. You can delete your account in the app at any time.</p>

<h2>Your photos</h2>
<p>You own the photos you take and the films you create. When you share a roll or put it on your public profile, you give us a worldwide, non-exclusive, royalty-free licence to store, copy, display and distribute it only as needed to run Film Exposures: for example, to show it to people with the link or on your profile, and to create share cards. This licence ends when you unshare the roll, make it private or delete your account, except for copies that take a short time to clear from our systems.</p>
<p>Only share photos you took or have the right to share, and only share photos of people who agreed to it.</p>

<h2>Our promises to photographers</h2>
<ul>
<li><b>We always credit photographers.</b> If we ever feature a photo that someone shared publicly, on our website or anywhere else, we will ask the photographer first and credit them by name. The sample photos on our website are credited the same way.</li>
<li><b>We never profit from selling photography or other people's art.</b> We don't sell, license or rent your photos, or anyone else's photos or artwork, to anyone.</li>
</ul>

<h2>Rules for what you share</h2>
<p>There is no tolerance for objectionable content or abusive users. Do not share:</p>
<ul>
<li>nudity or sexual content, or any content that sexualises minors;</li>
<li>violence, gore, or content that threatens or encourages harm;</li>
<li>hate, harassment or bullying;</li>
<li>spam, scams or misleading content;</li>
<li>photos of people who didn't agree to be shared, or content that infringes someone else's rights;</li>
<li>anything illegal.</li>
</ul>
<p>Anyone can report a roll, and you can block people whose rolls you don't want to see. We review reports, remove content that breaks these rules and remove accounts of people who share it, usually within 24 hours of a report. We may remove any content or suspend any account that we reasonably believe breaks these terms.</p>

<h2>Shared films</h2>
<p>Films you share as links carry their settings and name. Anyone with the link can load and use the film. Don't give a film a name that is offensive or that misleads people about who made it.</p>

<h2>Our app</h2>
<p>Film Exposures, its design, its built-in films and its code belong to us and are protected by intellectual property laws. You may not copy, modify, reverse engineer or resell the app, or use Film Exposures to build a competing service, except as the law allows. Feedback you send us may be used to improve Film Exposures, with no obligation to you.</p>

<h2>Apple</h2>
<p>If you got the app from the App Store, these terms are between you and us, not Apple. Apple's <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/">Licensed Application End User License Agreement</a> also applies. Apple has no obligation to provide maintenance or support for the app, and Apple is a third-party beneficiary of these terms and may enforce them.</p>

<h2>Changes and availability</h2>
<p>We may change or stop features of Film Exposures. Shared links expire as described in the app. If we make significant changes to these terms, we will update the date above and tell you in the app. Continuing to use Film Exposures after a change means you accept it.</p>

<h2>Disclaimers</h2>
<p>Film Exposures is provided "as is" and "as available", without warranties of any kind, express or implied, including fitness for a particular purpose and non-infringement. Keep your own copies of photos that matter to you: the app saves developed frames to Photos, but we can't guarantee that shared content will always be available.</p>

<h2>Limitation of liability</h2>
<p>To the fullest extent the law allows, we are not liable for any indirect, incidental, special, consequential or punitive damages, or for lost data, photos, profits or goodwill, arising from your use of Film Exposures. Our total liability for any claim is limited to the greater of the amount you paid us for Film Exposures in the 12 months before the claim, or US$50. Some places don't allow these limits, so they may not apply to you.</p>

<h2>Indemnity</h2>
<p>If you break these terms or the law, or infringe someone's rights through content you share, you agree to cover our reasonable costs of dealing with the resulting claims.</p>

<h2>Ending these terms</h2>
<p>You can stop using Film Exposures and delete your account at any time. We may suspend or end your access if you break these terms. Sections that by their nature should survive, such as ownership, disclaimers and limitation of liability, survive the end of these terms.</p>

<h2>Governing law</h2>
<p>These terms are governed by the laws of ${GOVERNING_LAW}, without regard to its conflict-of-law rules. Any dispute will be resolved in the state or federal courts located in Texas, unless the law where you live gives you the right to bring it elsewhere.</p>

<h2>Contact</h2>
<p>Questions about these terms: use the <a href="/support">support form</a>.</p>
</article>`;
}

export function supportBody({ sent = false, error = '' } = {}) {
  const topics = SUPPORT_TOPICS.map((t) => `<option>${t}</option>`).join('');
  return `<p class="eyebrow">Support</p><h1>How can we help?</h1>
<p class="lede">Send us a message and we'll reply by email, usually within a couple of days.</p>
${sent ? '<div class="notice">Thanks. Your message has been sent, and we\'ll get back to you by email.</div>' : ''}
${error ? `<div class="notice error">${error}</div>` : ''}
<form class="form" method="post" action="/api/support">
  <label>Your email<input type="email" name="email" required maxlength="200" autocomplete="email" placeholder="you@example.com"></label>
  <label>Name (optional)<input type="text" name="name" maxlength="80" autocomplete="name"></label>
  <label>Topic<select name="topic">${topics}</select></label>
  <label>Message<textarea name="message" required minlength="10" maxlength="4000" placeholder="What's going on? If it's about a shared roll or profile, include its link."></textarea></label>
  <div class="hp" aria-hidden="true"><label>Leave this empty<input type="text" name="website" tabindex="-1" autocomplete="off"></label></div>
  <button class="button primary" type="submit">Send message</button>
</form>
<h3>Quick answers</h3>
<p><b>Where are my photos?</b> On your phone, in Photos, in the Film Exposures folder, one album per roll. Frames that are still developing appear when the roll develops.</p>
<p><b>How do I delete my account?</b> In the app: Profile, then Delete account. It deletes everything you shared while signed in.</p>
<p><b>How do I take a roll off the internet?</b> Open the roll and tap Unshare, or Make private if it's on your profile.</p>
<p class="muted small">We use your email address only to reply to you. See our <a href="/privacy">privacy policy</a>.</p>`;
}

export function inboxBody() {
  return `<p class="eyebrow">Support inbox</p><h1>Messages</h1>
<form class="form" id="unlock"><label>Admin password<input type="password" id="token" autocomplete="current-password" required></label>
<button class="button primary" type="submit">Open inbox</button></form>
<div id="list"></div>
<script>
const list = document.getElementById('list');
const form = document.getElementById('unlock');
const input = document.getElementById('token');
try { input.value = sessionStorage.getItem('inbox-token') || ''; } catch {}
async function load() {
  const token = input.value.trim();
  const res = await fetch('/api/admin/support', { headers: { authorization: 'Bearer ' + token } });
  list.textContent = '';
  if (!res.ok) { list.textContent = res.status === 401 ? 'Wrong password.' : 'The inbox is not set up yet.'; return; }
  try { sessionStorage.setItem('inbox-token', token); } catch {}
  form.style.display = 'none';
  const { messages } = await res.json();
  if (!messages.length) { list.textContent = 'No messages.'; return; }
  for (const m of messages) {
    const box = document.createElement('div'); box.className = 'msg';
    const head = document.createElement('header');
    const who = document.createElement('span'); who.textContent = (m.name ? m.name + ' · ' : '') + m.email;
    const meta = document.createElement('span'); meta.textContent = m.topic + ' · ' + new Date(m.at).toLocaleString();
    head.append(who, meta);
    const body = document.createElement('pre'); body.textContent = m.message;
    const reply = document.createElement('a'); reply.textContent = 'Reply by email';
    reply.href = 'mailto:' + encodeURIComponent(m.email) + '?subject=' + encodeURIComponent('Re: Film Exposures support');
    const done = document.createElement('button'); done.textContent = 'Done'; done.style.marginLeft = '12px';
    done.onclick = async () => {
      const r = await fetch('/api/admin/support/' + m.id, { method: 'DELETE', headers: { authorization: 'Bearer ' + token } });
      if (r.ok) box.remove();
    };
    box.append(head, body, reply, done);
    list.append(box);
  }
}
form.addEventListener('submit', (e) => { e.preventDefault(); load(); });
if (input.value) load();
</script>`;
}
