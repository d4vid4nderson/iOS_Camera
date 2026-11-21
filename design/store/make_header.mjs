// Builds the App Store header page from the website's own phone mockups.
import { writeFileSync } from 'node:fs';
const site = await import(process.argv[2]);
const out = process.argv[3];
const body = site.homeBody('');
const hero = body.slice(body.indexOf('<figure class="phone"'), body.indexOf('</figure>', body.indexOf('<figure class="phone"')) + 9)
  .replace('<figure class="phone"', '<div class="phone hero"').replace(/<\/figure>$/, '</div>');
const smalls = [...body.matchAll(/<div class="phone small"[\s\S]*?\n  <\/div>\n  <figcaption>/g)].map((m) => m[0].replace(/\n  <figcaption>$/, ''));
if (smalls.length !== 3) throw new Error('expected 3 phones, got ' + smalls.length);
const html = `<!doctype html><html><head><meta charset="utf-8"><style>${site.SITE_CSS}
html,body{margin:0;width:2622px;height:1475px;overflow:hidden;background:#121212}
body{font-family:Inter,system-ui,sans-serif;color:#f2f2f2}
.phone .screen.app{font-family:Inter,system-ui,sans-serif}
.stage{position:absolute;inset:0;display:grid;grid-template-columns:760px 1fr;align-items:center;padding:0 200px 0 230px;gap:30px;
  background:radial-gradient(1200px 900px at 72% 55%,#232325 0%,#121212 70%)}
.copy{display:grid;gap:30px;align-content:center;padding-top:80px}
.copy img{width:150px;height:150px;border-radius:34px;box-shadow:0 10px 40px rgba(0,0,0,.5)}
.copy .name{margin:0;font:600 40px/1 Inter,sans-serif;letter-spacing:.01em;color:#c9c9cc}
.copy h1{margin:0;font:800 96px/1.03 Inter,sans-serif;letter-spacing:-.025em;color:#fff;width:max-content;max-width:780px}
.copy h1 span{color:#E8762E}
.copy .sub{margin:0;font:500 36px/1.35 Inter,sans-serif;color:#a5a5aa;max-width:700px}
.row{display:flex;align-items:center;justify-content:center;gap:34px}
.row .phone{margin:0;--w:296px}
.row .phone.hero{--w:344px}
.row .phone:nth-child(odd){transform:translateY(-26px)}
.row .phone:nth-child(even){transform:translateY(26px)}
</style></head><body><div class="stage">
<div class="copy">
  <img src="app-icon.png" alt="">
  <p class="name">Film Exposures</p>
  <h1>Share the roll,<br><span>not just the shot.</span></h1>
  <p class="sub">A film camera for your iPhone. Shoot a roll of 36, then share the whole roll.</p>
</div>
<div class="row">${hero}${smalls.join('')}</div>
</div></body></html>`;
writeFileSync(out, html);
console.log('wrote', out);
