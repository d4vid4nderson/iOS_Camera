// The filmexposures.com website: the home page, privacy policy, terms, support form and
// the support inbox. Styled like the app: near-black, copper accent, monospace labels,
// film tone strips.
//
// The privacy policy describes exactly what the app and this server collect. Keep it in
// step with the code (RetroCam/RollShare.swift, Account.swift, SocialSignIn.swift and
// worker.js) whenever either changes.

export const OWNER = 'Film Exposures';
export const EFFECTIVE = 'November 2, 2026';
export const GOVERNING_LAW = 'the State of Texas, United States';
export const SUPPORT_TOPICS = ['Help using the app', 'Account or sign-in', 'Report a problem', 'Report content', 'Privacy request', 'Something else'];

export const SITE_CSS = `
:root{--bg:#0e0e0f;--panel:#161617;--panel2:#1d1d1e;--fg:#f2f0ec;--muted:#8c8a86;--line:#2a2a2b;--accent:#e8762e;--accent-ink:#1a0f07;
--mono:ui-monospace,"SF Mono",SFMono-Regular,Menlo,Consolas,monospace}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 -apple-system,BlinkMacSystemFont,"Inter","Segoe UI",sans-serif}
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
.films{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:12px;margin:28px 0}
.film{background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:14px 14px 16px}
.film .tones{display:flex;gap:3px;margin-bottom:12px}.film .tones i{flex:1;height:12px;border-radius:3px}
.film b{display:block;font-size:17px;letter-spacing:-.01em}.film span{font-size:13px;color:var(--muted)}
.features{display:grid;grid-template-columns:repeat(2,1fr);gap:12px;margin:12px 0 28px}
.feature{background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:18px}
.feature h3{margin:0 0 8px;color:var(--accent)}.feature p{margin:0;color:#c9c6c0;font-size:15px}
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
@media (max-width:520px){h1{font-size:36px}.nav{gap:12px}.nav .optional{display:none}.films{grid-template-columns:repeat(2,1fr);gap:10px}.film b{font-size:15px}}
`;

export function siteHeader() {
  return `<header class="site-head"><a class="brand" href="/"><i></i>FILM EXPOSURES</a>
<nav class="nav"><a class="optional" href="/#films">FILMS</a><a href="/support">SUPPORT</a></nav></header>`;
}

export function siteFooter(year = new Date().getUTCFullYear()) {
  return `<footer class="site-foot"><span>© ${year} ${OWNER}</span>
<nav><a href="/support">Support</a><a href="/privacy">Privacy</a><a href="/terms">Terms</a></nav></footer>`;
}

// A few of the app's films, with their tone strips (black to white through each film).
const SHOWCASE = [
  ['PAN 50', 'Fine grain, smooth tones', ['#0b0b0b', '#2b2b2b', '#4f4f4f', '#777', '#a0a0a0', '#c9c9c9', '#efefef']],
  ['SEPIA', 'Warm-toned print', ['#120b05', '#3a2a1c', '#634a33', '#8c6c4e', '#b59371', '#d7bf9e', '#f3e7d1']],
  ['CYANOTYPE', 'Prussian blue on white', ['#08203f', '#1b3b63', '#33597f', '#55779a', '#8099b4', '#b3c4d3', '#eef1f1']],
  ['WARM 400', 'Warm skin, soft highlights', ['#120e0b', '#3a2f27', '#665546', '#927c68', '#b9a48e', '#d6c5b0', '#e6dacb']],
  ['EARTH 200', 'Tan and olive, clean whites', ['#0a0907', '#2a251c', '#4e4535', '#776a52', '#a09277', '#c9bfaa', '#f1efe9']],
  ['TIDE 200', 'Teal water, orange light', ['#041014', '#12303a', '#2f525a', '#6e7a78', '#b59f86', '#e0c3a1', '#f6e7d4']],
  ['NORTH 400', 'Blue shadows, a warm glow', ['#081422', '#1d3550', '#3d5a74', '#6c8396', '#a3b0b8', '#d6d4cc', '#f7f0e2']],
  ['MEADOW 400', 'Bright, hazy, sun-bleached', ['#211c15', '#4b4234', '#776a56', '#a19580', '#c8bea9', '#e6dfd0', '#fbf8f1']],
];

export function homeBody(store) {
  const films = SHOWCASE.map(([name, blurb, tones]) => `<div class="film"><div class="tones">${tones.map((c) => `<i style="background:${c}"></i>`).join('')}</div>
<b>${name}</b><span>${blurb}</span></div>`).join('');
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
  <div class="feature"><h3>Black &amp; white and color</h3><p>Classic monochrome, toned prints and cinematic color films, each with grain, glow and lens character. Make your own and save them.</p></div>
  <div class="feature"><h3>Share a film</h3><p>Send a film as a link. Everything travels with it, from curve and grade to grain and effects, so a friend loads exactly your look.</p></div>
</section>
<h2 id="films">Some of the films</h2>
<div class="films">${films}</div>
<p class="muted small">Your photos stay on your phone. Nothing is uploaded unless you share a roll or put one on your profile.</p>`;
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
<p>An account is optional. You need one only to put rolls on a public profile and to like frames. You can sign in with Apple, Google or Facebook. We receive:</p>
<ul>
<li>An identifier for your Apple, Google or Facebook account. We store it only in a scrambled (one-way hashed) form, used to recognise you when you sign in again.</li>
<li>Your name, if the service provides it or you set one, and your profile photo from Google or Facebook, which you can replace or remove.</li>
</ul>
<p>We don't ask for your email address, contacts or friends list. We also store which frames you have liked, the time you agreed to our rules for public rolls, and sign-in sessions for your devices.</p>

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
