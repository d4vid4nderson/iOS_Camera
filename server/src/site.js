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
.brand img{width:28px;height:28px;display:block}
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
.rolls{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;margin:20px 0}
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
.hero .app-icon{width:104px;height:104px;display:block;margin:0 0 22px;filter:drop-shadow(0 10px 24px rgba(0,0,0,.45))}
.counter{display:inline-flex;align-items:baseline;gap:10px;font:700 15px/1 var(--mono);color:var(--muted);letter-spacing:.08em;margin-bottom:22px}
.counter b{font-size:30px;color:var(--accent);letter-spacing:0}
/* Home: hero with the phone */
.hero-grid{display:grid;grid-template-columns:minmax(0,1.15fr) minmax(0,.85fr);gap:40px;align-items:center}
.phone{--w:min(300px,78vw);position:relative;justify-self:center;width:var(--w);aspect-ratio:9/19.5;margin:0;padding:calc(var(--w)*.035);border-radius:calc(var(--w)*.16);
  background:linear-gradient(145deg,#3a3633,#1b1917 45%,#2c2926);box-shadow:inset 0 0 0 1.5px #4a4540,inset 0 0 0 4px #0c0b0a,0 40px 80px -30px rgba(0,0,0,.9),0 0 0 1px #000}
.phone .screen{--u:calc(var(--w) * .93 / 390);position:relative;height:100%;border-radius:calc(var(--w)*.13);overflow:hidden;background:#171717;
  display:flex;flex-direction:column;justify-content:flex-end;gap:calc(12*var(--u));padding:calc(59*var(--u)) 0 calc(42*var(--u));color:#fff;font-family:var(--mono)}
.phone .island{position:absolute;top:2.2%;left:50%;width:32%;height:3.6%;margin-left:-16%;border-radius:99px;background:#000;z-index:2}
.phone svg{width:calc(18*var(--u));height:calc(18*var(--u));fill:none;stroke:currentColor;stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round;display:block}
/* The app's camera screen (RetroCam/ContentView.swift): top plate, 3:4 viewfinder, icon bar, controls */
.phone .plate{display:flex;align-items:center;justify-content:space-between;height:calc(44*var(--u));padding:0 calc(16*var(--u))}
.phone .count{width:calc(90*var(--u));display:grid;gap:calc(1*var(--u))}
.phone .count span{font-size:calc(8*var(--u));font-weight:600;color:#8e8e93}
.phone .count b{font-size:calc(15*var(--u));color:var(--accent)}
.phone .stock{display:flex;align-items:center;gap:calc(6*var(--u));font-size:calc(12*var(--u));font-weight:600}
.phone .stock em{font-style:normal;font-size:calc(10*var(--u));font-weight:400;color:#8e8e93}
.phone .stock svg{width:calc(9*var(--u));height:calc(9*var(--u));color:#8e8e93;stroke-width:3}
.phone .me{width:calc(90*var(--u));display:flex;justify-content:flex-end}
.phone .me i{width:calc(40*var(--u));height:calc(40*var(--u));border-radius:50%;background:#2e2e2e;box-shadow:0 0 0 calc(1.5*var(--u)) #4d4d4d;display:grid;place-items:center;color:#808080}
.phone .me svg{width:calc(18*var(--u));height:calc(18*var(--u));fill:currentColor;stroke:none}
.phone .finder{position:relative;width:100%;aspect-ratio:3/4;background:#000;display:grid;place-items:center;overflow:hidden}
.phone .finder>img{width:100%;height:auto;aspect-ratio:3/2;object-fit:cover;display:block}
.phone .rotate{position:absolute;top:calc(10*var(--u));right:calc(10*var(--u));width:calc(38*var(--u));height:calc(38*var(--u));border-radius:50%;background:rgba(0,0,0,.55);display:grid;place-items:center}
.phone .rotate svg{width:calc(17*var(--u));height:calc(17*var(--u))}
.phone .bar{margin:0 calc(12*var(--u));padding:calc(4*var(--u));display:flex;gap:calc(2*var(--u));border-radius:calc(12*var(--u));background:#1f1f1f;box-shadow:inset 0 0 0 .5px #333}
.phone .bar span{flex:1;min-width:0;height:calc(46*var(--u));display:grid;justify-items:center;align-content:center;gap:calc(4*var(--u));color:#ccc;font-size:calc(9*var(--u));font-weight:600;white-space:nowrap}
.phone .bar span.on{color:var(--accent)}
.phone .bar svg{width:calc(19*var(--u));height:calc(19*var(--u));stroke-width:1.6}
.phone .controls{display:flex;align-items:center;justify-content:space-between;padding:0 calc(24*var(--u));margin-top:calc(4*var(--u))}
.phone .last{width:calc(56*var(--u));height:calc(56*var(--u));aspect-ratio:1;border-radius:calc(4*var(--u));object-fit:cover;display:block;background:#262626}
.phone .shutter{position:relative;width:calc(67*var(--u));height:calc(67*var(--u));border-radius:50%;background:linear-gradient(#080808,#171717);box-shadow:inset 0 calc(1.5*var(--u)) calc(3*var(--u)) rgba(0,0,0,.85),inset 0 calc(-.6*var(--u)) 0 rgba(255,255,255,.12)}
.phone .shutter::after{content:"";position:absolute;inset:calc(3.5*var(--u));border-radius:50%;
  background:linear-gradient(rgba(0,0,0,.45),transparent 45%),linear-gradient(rgb(235,110,33),rgb(204,94,28));
  box-shadow:inset 0 calc(1.2*var(--u)) 0 rgba(255,184,122,.45),inset 0 calc(-1.2*var(--u)) 0 rgba(107,43,10,.8)}
.phone .flip{width:calc(56*var(--u));height:calc(56*var(--u));border-radius:50%;background:#262626;display:grid;place-items:center}
.phone .flip svg{width:calc(22*var(--u));height:calc(22*var(--u))}
/* More phones: the app's other screens (RollViewer, UserProfileView, SocialView) */
.phones{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:28px;justify-items:center}
.phones figure{margin:0;display:grid;gap:14px;justify-items:center;text-align:center}
.phones figcaption{max-width:260px}
.phones figcaption b{display:block;font:700 12px/1.3 var(--mono);letter-spacing:.08em;margin-bottom:4px}
.phones figcaption span{font-size:14px;color:#c9c6c0}
.phone.small{--w:min(260px,78vw)}
.phone .screen.app{background:#0f0f0f;justify-content:flex-start;gap:calc(12*var(--u));padding:calc(62*var(--u)) calc(16*var(--u)) calc(30*var(--u))}
.phone .screen.app>*{flex:none}
.phone .ahead{display:flex;justify-content:space-between;align-items:flex-start}
.phone .ahead b{display:block;font-size:calc(15*var(--u));color:var(--accent)}
.phone .ahead small{display:block;margin-top:calc(3*var(--u));font-size:calc(9.5*var(--u));color:#8e8e93}
.phone .x{flex:none;width:calc(34*var(--u));height:calc(34*var(--u));border-radius:50%;background:#292929;display:grid;place-items:center}
.phone .x svg{width:calc(13*var(--u));height:calc(13*var(--u));stroke-width:2.6}
.phone .chips{display:flex;gap:calc(6*var(--u));overflow:hidden}
.phone .chips span{flex:none;padding:calc(6*var(--u)) calc(10*var(--u));border-radius:99px;background:#262626;font-size:calc(10*var(--u));font-weight:700;white-space:nowrap}
.phone .chips span.on{background:rgba(232,118,46,.18);box-shadow:inset 0 0 0 1px var(--accent);color:var(--accent)}
.phone .chips span.red{background:rgba(255,59,48,.1);color:#ff7366}
.phone .sheet{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:calc(10*var(--u)) calc(6*var(--u))}
.phone .sheet i{display:grid;gap:calc(4*var(--u));font-style:normal;font-size:calc(9*var(--u));font-weight:600;color:#8e8e93;text-align:center}
.phone .sheet i>span{position:relative;display:block;aspect-ratio:3/4;overflow:hidden;background:#1a1a1a}
.phone .sheet img{width:100%;height:100%;object-fit:cover;display:block}
.phone .sheet em{position:absolute;top:calc(4*var(--u));left:calc(4*var(--u));padding:calc(3*var(--u)) calc(5*var(--u));border-radius:3px;background:var(--accent);color:#000;font-style:normal;font-size:calc(8*var(--u));font-weight:700}
.phone .sheet .dev{display:grid;place-content:center;gap:calc(3*var(--u));background:#1a1a1a;box-shadow:inset 0 0 0 1px #383838;outline:1px dashed #383838;outline-offset:-1px}
.phone .sheet .dev b{font-size:calc(8*var(--u));color:#666}.phone .sheet .dev small{font-size:calc(7*var(--u));color:#4d4d4d}
.phone .who{display:flex;align-items:center;gap:calc(14*var(--u));margin:0}
.phone .face{flex:none;width:calc(72*var(--u));height:calc(72*var(--u));border-radius:50%;display:grid;place-items:center;font-size:calc(28*var(--u));font-weight:700;color:#fff;background:linear-gradient(145deg,#6c5a4a,#3a3029)}
.phone .face.s{width:calc(16*var(--u));height:calc(16*var(--u));font-size:calc(7*var(--u))}
.phone .who b{display:block;font-size:calc(16*var(--u));color:var(--accent)}
.phone .who small{display:block;margin-top:calc(4*var(--u));font-size:calc(11*var(--u));font-weight:600}
.phone .tiles{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:calc(8*var(--u))}
.phone .tiles span{display:grid;gap:calc(3*var(--u));padding:calc(10*var(--u)) 0;border-radius:calc(12*var(--u));background:#1c1c1c;text-align:center}
.phone .tiles b{font-size:calc(20*var(--u))}.phone .tiles small{font-size:calc(8*var(--u));font-weight:600;color:#8e8e93}
.phone .covers{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:calc(16*var(--u)) calc(10*var(--u))}
.phone .covers i{display:grid;gap:calc(6*var(--u));font-style:normal;text-align:left;min-width:0}
.phone .covers i>span{position:relative;display:block;aspect-ratio:3/4;border-radius:calc(9*var(--u));overflow:hidden;background:#1a1a1a}
.phone .covers img{width:100%;height:100%;object-fit:cover;display:block}
.phone .covers b{font-size:calc(11*var(--u));white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.phone .covers small{font-size:calc(9*var(--u));color:#8e8e93;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;display:flex;align-items:center;gap:calc(6*var(--u))}
.phone .covers em{position:absolute;top:calc(6*var(--u));right:calc(6*var(--u));width:calc(22*var(--u));height:calc(22*var(--u));border-radius:50%;background:rgba(0,0,0,.6);display:grid;place-items:center}
.phone .covers em svg{width:calc(11*var(--u));height:calc(11*var(--u));stroke-width:2.2}
@media (max-width:860px){.phones{grid-template-columns:1fr;gap:44px}}
/* Home: sections */
.section{margin:72px 0 0}
.section>h2{font-size:clamp(28px,4.2vw,40px);line-height:1.08;letter-spacing:-.02em;margin:0 0 10px}
.section>.lede{margin-bottom:28px}
.steps{list-style:none;padding:0;margin:0;display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px}
.steps li,.card3,.feature{background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:18px 18px 20px}
.steps b{display:block;font:700 26px/1 var(--mono);color:var(--accent);margin-bottom:12px}
.steps h3,.card3 h3,.feature h3{margin:0 0 8px;color:var(--fg)}
.steps p,.card3 p,.feature p{margin:0;color:#c9c6c0;font-size:15px}
.features{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px;margin:0}
.idea{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:32px;align-items:center}
.idea blockquote{margin:0;font-size:clamp(20px,2.6vw,26px);line-height:1.35;letter-spacing:-.01em;color:var(--fg)}
.idea blockquote span{color:var(--accent)}
.idea p{color:#c9c6c0;margin:0 0 12px}
.formats{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:12px;align-items:end}
.format{display:grid;grid-template-columns:minmax(0,1fr);gap:10px;justify-items:center;text-align:center}
.format .pic{width:100%;border-radius:3px;overflow:hidden;background:#000;box-shadow:0 0 0 1px var(--line)}
.format .pic img{width:100%;height:100%;object-fit:cover;display:block}
.format b{font:700 13px/1 var(--mono);letter-spacing:.06em}
.format span{font:600 11px/1.3 var(--mono);color:var(--muted)}
.format em{font:700 12px/1 var(--mono);font-style:normal;color:var(--accent)}
.borders{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px}
.border,.format,.steps li,.feature,.card3{min-width:0}
.border{display:grid;grid-template-columns:minmax(0,1fr);gap:10px;text-align:center;font:700 12px/1 var(--mono);letter-spacing:.08em;color:var(--muted)}
.border .print{aspect-ratio:1;display:grid;grid-template-columns:minmax(0,1fr);place-items:center;border-radius:6px;background:#1a1816}
.border .print img{min-width:0;max-width:100%;width:100%;height:auto;aspect-ratio:3/2;object-fit:cover;display:block}
.borders{align-items:center}
.border .print.none,.border .print.white,.border .print.black{aspect-ratio:auto;border-radius:3px}
.border .print.none{background:none}
.border .print.white{background:#f4f1ea;padding:7%}
.border .print.black{background:#060606;padding:7%;box-shadow:0 0 0 1px var(--line)}
.border .print.slide{--card:#ece3cf;background:linear-gradient(155deg,#ece3cf,#ddd1b6);border-radius:9px;align-content:center;gap:0;position:relative}
.border .print.slide img{width:74%;border-radius:2px;box-shadow:0 0 0 1px rgba(0,0,0,.35)}
.border .print.slide i{position:absolute;top:9%;left:13%;right:13%;display:flex;justify-content:space-between;font:800 10px/1 var(--mono);font-style:normal;color:#3a2d1f;letter-spacing:.05em}
.tools{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}
.tags{display:flex;flex-wrap:wrap;gap:6px;margin-top:12px}
.tags span{font:700 10px/1 var(--mono);letter-spacing:.08em;padding:6px 8px;border-radius:99px;background:var(--panel2);color:#d9d3c8}
.share3{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}
.card3 .who{display:inline-flex;margin:0 0 12px;padding:6px 10px;border-radius:99px;font:700 11px/1 var(--mono);letter-spacing:.1em;background:var(--panel2);color:var(--fg)}
.card3.on .who{background:rgba(232,118,46,.16);color:var(--accent)}
@media (max-width:860px){.hero-grid,.idea{grid-template-columns:1fr}.phone{margin:8px 0 40px}.steps{grid-template-columns:repeat(2,minmax(0,1fr))}.formats{grid-template-columns:repeat(3,minmax(0,1fr));row-gap:22px}.tools,.share3{grid-template-columns:1fr}}
@media (max-width:520px){.steps,.features{grid-template-columns:1fr}.borders{grid-template-columns:repeat(2,minmax(0,1fr))}}
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
@media (max-width:520px){h1{font-size:36px}.nav{gap:12px}.nav .optional{display:none}.films{grid-template-columns:repeat(2,minmax(0,1fr));gap:14px 12px}.mount .label{font-size:12px}.mount .note{font-size:11px}}
`;

export function siteHeader() {
  return `<header class="site-head"><a class="brand" href="/"><img src="/app-icon.png" alt="" width="28" height="28">FILM EXPOSURES</a>
<nav class="nav"><a class="optional" href="/#how">HOW IT WORKS</a><a class="optional" href="/#films">FILMS</a><a href="/support">SUPPORT</a></nav></header>`;
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
  // A frame in each format, cut from the same sample photo.
  const formats = [
    ['35MM', '3:2', 24, 3 / 2], ['6×4.5', '4:3', 36, 4 / 3], ['6×6', '1:1', 36, 1],
    ['4×5', '5:4', 50, 5 / 4], ['16:9', '16:9', 24, 16 / 9], ['XPAN', '65:24', 24, 65 / 24],
  ].map(([name, ratio, mp, r]) => `<div class="format"><div class="pic" style="aspect-ratio:${r}"><img src="/films/thumbs/golden100.jpg" alt="" loading="lazy" width="420" height="280"></div>
<b>${name}</b><span>${ratio}</span><em>UP TO ${mp} MP</em></div>`).join('');
  const border = (kind, label) => `<div class="border"><div class="print ${kind}">${kind === 'slide' ? '<i><span>CLASSIC 400</span><span>12</span></i>' : ''}<img src="/films/thumbs/classic400.jpg" alt="" loading="lazy" width="420" height="280"></div>${label}</div>`;
  const tags = (list) => `<div class="tags">${list.map((t) => `<span>${t}</span>`).join('')}</div>`;
  return `
<section class="hero">
<div class="hero-grid">
<div>
  <img class="app-icon" src="/app-icon.png" alt="The Film Exposures app icon" width="104" height="104">
  <div class="counter">ROLL 01 <b>01/36</b></div>
  <h1>A film camera<br>for your iPhone.</h1>
  <p class="lede">Load a roll of 36, shoot it on a film you choose, and let it develop: right away, when the roll is done, or the next morning, like dropping it at a lab.</p>
  ${get}
</div>
<figure class="phone" aria-label="Film Exposures on an iPhone: the roll counter at 12 of 36, Golden 100 loaded, a 35mm frame in the viewfinder, the settings bar and the copper shutter">
  <div class="screen">
    <span class="island"></span>
    <div class="plate">
      <div class="count"><span>ROLL 03</span><b>12/36</b></div>
      <div class="stock">GOLDEN 100<em>100</em><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 9l7 7 7-7"/></svg></div>
      <div class="me"><i><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4.2"/><path d="M3.5 21c.8-4.6 4.2-7 8.5-7s7.7 2.4 8.5 7z"/></svg></i></div>
    </div>
    <div class="finder">
      <img src="/films/golden100.jpg" alt="" width="1200" height="800">
      <span class="rotate"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="9" width="17" height="10" rx="1.5"/><path d="M7.5 6.5A7 7 0 0 1 16 5"/><path d="M14.5 3l1.8 2-2.2 1"/></svg></span>
    </div>
    <div class="bar"><span><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16M7 12h10"/><path d="M4.6 7.3h.8M4.6 10.4h.8M4.6 13.6h.8M4.6 16.7h.8M18.6 7.3h.8M18.6 10.4h.8M18.6 13.6h.8M18.6 16.7h.8" stroke-width="2.2"/></svg>GOLDEN</span><span><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3.5 6h9.5M17 6h3.5M3.5 12h3.5M11 12h9.5M3.5 18h7.5M15 18h5.5"/><circle cx="15" cy="6" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="13" cy="18" r="2"/></svg>EDIT</span><span><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 8.6L20.84 13.7M14.94 10.3L14.94 20.5M14.94 13.7L6.11 18.8M12 15.4L3.16 10.3M9.06 13.7L9.06 3.5M9.06 10.3L17.89 5.2"/></svg>35</span><span><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7v5.5M9.25 9.75h5.5M9.25 15.75h5.5"/></svg>±0</span><span><svg viewBox="0 0 24 24" aria-hidden="true"><g fill="currentColor" stroke="none"><circle cx="12" cy="12" r="1.35"/><circle cx="15.38" cy="13.95" r="1.15"/><circle cx="12" cy="15.9" r="1.15"/><circle cx="8.62" cy="13.95" r="1.15"/><circle cx="8.62" cy="10.05" r="1.15"/><circle cx="12" cy="8.1" r="1.15"/><circle cx="15.38" cy="10.05" r="1.15"/><circle cx="18.58" cy="15.8" r="0.85"/><circle cx="15.8" cy="18.58" r="0.85"/><circle cx="12" cy="19.6" r="0.85"/><circle cx="8.2" cy="18.58" r="0.85"/><circle cx="5.42" cy="15.8" r="0.85"/><circle cx="4.4" cy="12" r="0.85"/><circle cx="5.42" cy="8.2" r="0.85"/><circle cx="8.2" cy="5.42" r="0.85"/><circle cx="12" cy="4.4" r="0.85"/><circle cx="15.8" cy="5.42" r="0.85"/><circle cx="18.58" cy="8.2" r="0.85"/><circle cx="19.6" cy="12" r="0.85"/></g></svg>20%</span><span class="on"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="2.8" y="4" width="18.4" height="16" rx="1.2" stroke-width="2"/><rect x="5.8" y="7" width="12.4" height="10" rx=".4"/><path d="M6.2 16.6l3.8-4.6 2.8 3 1.8-1.9 3.4 3.5z" fill="currentColor" stroke="none"/><circle cx="14.6" cy="9.9" r="1.2" fill="currentColor" stroke="none"/></svg>3:2</span><span><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18.5 19.5L11 12" stroke-width="2.4"/><path d="M7.38 11.62L5.75 13.25M6.5 9.5L4.2 9.5M7.38 7.38L5.75 5.75M9.5 6.5L9.5 4.2M11.62 7.38L13.25 5.75"/></svg>OFF</span><span><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M13.2 2.8L6.6 13.2h4.8l-1 8 6.8-10.6h-4.8z"/><path d="M5 3.5l14 17" stroke-width="2"/></svg>OFF</span><span><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="4.5" width="17" height="15.5" rx="2.6"/><path d="M3.5 7.1a2.6 2.6 0 0 1 2.6-2.6h11.8a2.6 2.6 0 0 1 2.6 2.6v2.4h-17z" fill="currentColor" stroke="none"/><g fill="currentColor" stroke="none"><circle cx="10.5" cy="12.5" r=".85"/><circle cx="13.5" cy="12.5" r=".85"/><circle cx="16.5" cy="12.5" r=".85"/><circle cx="7.5" cy="15.2" r=".85"/><circle cx="10.5" cy="15.2" r=".85"/><circle cx="13.5" cy="15.2" r=".85"/><circle cx="16.5" cy="15.2" r=".85"/><circle cx="7.5" cy="17.9" r=".85"/><circle cx="10.5" cy="17.9" r=".85"/><circle cx="13.5" cy="17.9" r=".85"/><circle cx="16.5" cy="17.9" r=".85"/></g></svg>OFF</span></div>
    <div class="controls">
      <img class="last" src="/films/thumbs/warm400.jpg" alt="" width="420" height="280">
      <i class="shutter"></i>
      <span class="flip"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3.5 8.5h3.2L8.3 6h7.4l1.6 2.5h3.2V19h-17z"/><path d="M9 13.5a3 3 0 0 1 5.3-1.9M15 12.5a3 3 0 0 1-5.3 1.9"/><path d="M14.6 10.2v1.6H13M9.4 15.8v-1.6H11"/></svg></span>
    </div>
  </div>
</figure>
</div>
</section>

<section class="section" id="how">
<p class="eyebrow">How it works</p>
<h2>Shoot a roll. Wait for it.</h2>
<p class="lede">Film Exposures works like the camera you'd load with film, with your iPhone's lenses behind it.</p>
<ol class="steps">
  <li><b>01</b><h3>Load a roll</h3><p>Pick a film and how the roll develops. A roll is 36 frames. Keep several going, a food roll and a holiday roll, and switch between them.</p></li>
  <li><b>02</b><h3>Shoot</h3><p>Choose a format, a lens and a border, then press the shutter. The counter climbs toward 36, and every press uses a frame.</p></li>
  <li><b>03</b><h3>Develop</h3><p>Instantly, when the roll is done, or the next morning at 9. Can't wait? Tap one frame to develop it early, and hide it again if you'd rather be surprised.</p></li>
  <li><b>04</b><h3>Keep or share</h3><p>Developed frames go into the roll's own album in Photos. Keep the roll to yourself, or share it with a few people, your followers or everyone.</p></li>
</ol>
</section>

<section class="section" id="inside">
<p class="eyebrow">Inside the app</p>
<h2>Rolls, people, and nothing else.</h2>
<p class="lede">Look back through a roll like a contact sheet, open a friend's profile, and see what the people you follow have shot.</p>
<div class="phones">
<figure>
  <div class="phone small" aria-label="The roll viewer: a roll as a contact sheet, with its cover and two frames still developing">
    <div class="screen app">
      <span class="island"></span>
      <div class="ahead"><div><b>ROLL 03<svg viewBox="0 0 24 24" aria-hidden="true" style="display:inline-block;width:.75em;height:.75em;margin-left:.4em;color:#8e8e93;vertical-align:baseline"><path d="M4 20l1-4L16 5l3 3L8 19z"/></svg></b><small>09/36 FRAMES · OCT 12, 2026 · DEVELOPS TUE 9:00 AM</small></div><span class="x"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></span></div>
      <div class="chips"><span class="on">ROLL 03</span><span>ROLL 02</span><span>ROLL 01</span></div>
      <div class="sheet"><i><span><img src="/films/thumbs/golden100.jpg" alt="" loading="lazy" width="420" height="280" style="object-position:100% 40%;transform:scale(1.6)"><em>COVER</em></span>01</i><i><span><img src="/films/thumbs/golden100.jpg" alt="" loading="lazy" width="420" height="280" style="object-position:50% 100%;transform:scale(2.1)"></span>02</i><i><span><img src="/films/thumbs/golden100.jpg" alt="" loading="lazy" width="420" height="280" style="object-position:20% 80%;transform:scale(1.9)"></span>03</i><i><span><img src="/films/thumbs/golden100.jpg" alt="" loading="lazy" width="420" height="280" style="object-position:85% 15%;transform:scale(2.4)"></span>04</i><i><span><img src="/films/thumbs/golden100.jpg" alt="" loading="lazy" width="420" height="280" style="object-position:60% 60%;transform:scale(1.4)"></span>05</i><i><span><img src="/films/thumbs/golden100.jpg" alt="" loading="lazy" width="420" height="280" style="object-position:35% 25%;transform:scale(2.6)"></span>06</i><i><span><img src="/films/thumbs/golden100.jpg" alt="" loading="lazy" width="420" height="280" style="object-position:75% 90%;transform:scale(1.8)"></span>07</i><i><span class="dev"><b>DEVELOPING</b><small>TAP TO DEVELOP</small></span>08</i><i><span class="dev"><b>DEVELOPING</b><small>TAP TO DEVELOP</small></span>09</i></div>
      <div class="chips"><span class="on">SHARE ROLL</span><span>SHEET</span><span>RENAME</span></div>
    </div>
  </div>
  <figcaption><b>THE ROLL</b><span>Every frame, in order, like a contact sheet. Tap one that's still developing to see it early.</span></figcaption>
</figure>
<figure>
  <div class="phone small" aria-label="A profile: name and handle, rolls, frames, followers and following, and their rolls">
    <div class="screen app">
      <span class="island"></span>
      <div class="ahead"><div><small style="margin:0">PROFILE</small></div><span class="x"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></span></div>
      <div class="who"><span class="face">M</span><div><b>MARA LIND</b><small>@mara.lind</small></div></div>
      <div class="tiles"><span><b>4</b><small>ROLLS</small></span><span><b>114</b><small>FRAMES</small></span><span><b>23</b><small>FOLLOWERS</small></span><span><b>31</b><small>FOLLOWING</small></span></div>
      <div class="chips"><span class="on">FOLLOW</span><span>SHARE PROFILE</span><span>BLOCK</span></div>
      <div class="covers"><i><span><img src="/films/thumbs/golden100.jpg" alt="" loading="lazy" width="420" height="280" style="object-position:50% 100%;transform:scale(2.1)"></span><b>COAST WEEKEND</b><small>36 FRAMES · GOLDEN 100</small></i><i><span><img src="/films/thumbs/classic400.jpg" alt="" loading="lazy" width="420" height="280" style="object-position:20% 80%;transform:scale(1.9)"></span><b>ROME</b><small>36 FRAMES · CLASSIC 400</small></i><i><span><img src="/films/thumbs/dusk800.jpg" alt="" loading="lazy" width="420" height="280" style="object-position:85% 15%;transform:scale(2.4)"><em><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="8" cy="9" r="3"/><circle cx="16" cy="9" r="3"/><path d="M3 19c.5-3 2.5-5 5-5s4.5 2 5 5M11 19c.5-3 2.5-5 5-5s4.5 2 5 5"/></svg></em></span><b>SUMMER NIGHTS</b><small>24 FRAMES · DUSK 800</small></i><i><span><img src="/films/thumbs/pan50.jpg" alt="" loading="lazy" width="420" height="280" style="object-position:60% 60%;transform:scale(1.4)"></span><b>OLD TOWN</b><small>18 FRAMES · PAN 50</small></i></div>
    </div>
  </div>
  <figcaption><b>A PROFILE</b><span>Someone's rolls, the public ones and those for their followers. Follow, and they approve.</span></figcaption>
</figure>
<figure>
  <div class="phone small" aria-label="People: rolls from the people you follow">
    <div class="screen app">
      <span class="island"></span>
      <div class="ahead"><div><b>PEOPLE</b></div><span class="x"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></span></div>
      <div class="chips"><span class="on">FOLLOWING</span><span>SHARED WITH YOU</span><span>REQUESTS</span></div>
      <div class="covers"><i><span><img src="/films/thumbs/north400.jpg" alt="" loading="lazy" width="420" height="280" style="object-position:60% 60%;transform:scale(1.4)"></span><b>BLUE HOUR</b><small><span class="face s">J</span>JONAS ERIKSEN</small></i><i><span><img src="/films/thumbs/noir.jpg" alt="" loading="lazy" width="420" height="280" style="object-position:35% 25%;transform:scale(2.6)"><em><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="9" cy="9" r="3.2"/><path d="M3.5 19.5c.6-3.3 2.8-5.3 5.5-5.3s4.9 2 5.5 5.3"/><circle cx="17" cy="10" r="2.4"/><path d="M15.5 14.6c2.6.1 4.3 1.9 4.9 4.9"/></svg></em></span><b>MARKET DAY</b><small><span class="face s">A</span>ANA LIMA</small></i><i><span><img src="/films/thumbs/tide200.jpg" alt="" loading="lazy" width="420" height="280" style="object-position:75% 90%;transform:scale(1.8)"></span><b>LOW TIDE</b><small><span class="face s">M</span>MARA LIND</small></i><i><span><img src="/films/thumbs/silver100.jpg" alt="" loading="lazy" width="420" height="280" style="object-position:0% 50%;transform:scale(1.25)"></span><b>SUNDAY WALK</b><small><span class="face s">S</span>SAM OKAFOR</small></i></div>
    </div>
  </div>
  <figcaption><b>PEOPLE</b><span>Rolls from the people you follow, and the ones shared with just you. No comments, no ads.</span></figcaption>
</figure>
</div>
<p class="muted small">Illustrations of the app's screens. Names and photos are examples.</p>
</section>

<section class="section">
<div class="idea">
  <blockquote>Thirty-six frames make you <span>choose</span>. A day's wait makes you <span>forget</span>, so the roll comes back as a surprise.</blockquote>
  <div>
    <p>A phone camera never runs out, so most photos get taken, glanced at and lost in the library. A roll of film is different: you think before you press, and you find out later what you got.</p>
    <p>Film Exposures keeps that limit and that wait. A roll is a little project with a name, a film and a cover photo: a weekend, a city, one dinner party. Once it's developed, print it as a contact sheet or share it.</p>
  </div>
</div>
</section>

<section class="section">
<p class="eyebrow">Formats &amp; resolution</p>
<h2>From 35mm to a 4×5 sheet.</h2>
<p class="lede">Crop as you shoot, like changing cameras: square 6×6, wide XPAN, or a big 4×5. Larger formats keep more of your iPhone's detail. Shoot in landscape or portrait.</p>
<div class="formats">${formats}</div>
<p class="muted small">The most each format keeps. What you get depends on your iPhone's camera: on a 48 MP camera a 4×5 frame comes out around 46 MP, and an older 12 MP camera gives less. Photos are saved in Display P3 colour.</p>
</section>

<section class="section">
<p class="eyebrow">Borders</p>
<h2>Finish every frame.</h2>
<p class="lede">Print it edge to edge, give it a white or black border of the width you like, or mount it as a slide with the film's name and the frame number on the card.</p>
<div class="borders">${border('none', 'NONE')}${border('white', 'WHITE')}${border('black', 'BLACK')}${border('slide', 'SLIDE')}</div>
</section>

<section class="section">
<p class="eyebrow">Make it yours</p>
<h2>Edit a film, or make your own.</h2>
<div class="tools">
  <div class="feature"><h3>The film</h3><p>Change any film: exposure, contrast, black and white points, grain and its size, vignette, bloom, fog and soft edges. Tone black &amp; white prints, or grade colour with RGB curves, saturation and split toning.</p>
  ${tags(['SEPIA', 'SELENIUM', 'SPLIT', 'GOLD', 'PLATINUM', 'CYANO', 'TINTYPE'])}</div>
  <div class="feature"><h3>Lenses &amp; effects</h3><p>Classic lenses from 21 to 135mm, wherever your iPhone's cameras can crop to them cleanly. Lens and print effects for when a roll calls for something strange.</p>
  ${tags(['FISHEYE', 'SWIRL', 'TILT-SHIFT', 'ZOOM', 'DRAG', 'DOUBLE', 'PRISM', 'RIPPLE', 'KALEIDO', 'HALFTONE', 'ETCH'])}</div>
  <div class="feature"><h3>The camera</h3><p>A date back that burns the date, or date and time, into the corner. Seven shutter finishes, and the app icon changes to match. Send a film to a friend as a link, and they load your exact look.</p>
  ${tags(['COPPER', 'SILVER', 'BLACK', 'RED', 'COBALT', 'OLIVE', 'BRASS'])}</div>
</div>
</section>

<section class="section" id="sharing">
<p class="eyebrow">Sharing</p>
<h2>Your rolls, your call.</h2>
<p class="lede">Every roll starts private. Choose who sees each one, from a few friends to everyone, and change your mind whenever you like. Photos shared with followers or specific people only load for them.</p>
<div class="share3">
  <div class="card3 on"><span class="who">PRIVATE</span><h3>Just you</h3><p>Rolls live on your phone and in Photos. Nothing is uploaded unless you share it.</p></div>
  <div class="card3"><span class="who">SPECIFIC PEOPLE</span><h3>Only who you pick</h3><p>Choose people by their @handle. The roll shows up in their Shared with you, and nobody else can open it, not even with the link.</p></div>
  <div class="card3"><span class="who">FOLLOWERS</span><h3>People you approved</h3><p>Every follow is a request you approve. Rolls for followers appear in their feed, and you can remove a follower any time.</p></div>
  <div class="card3"><span class="who">PUBLIC</span><h3>Everyone</h3><p>On your public profile, for anyone to see and like, and to see who liked it.</p></div>
  <div class="card3"><span class="who">LINK</span><h3>Anyone with the link</h3><p>Send a roll as a link, even one you're still shooting: new frames appear as they develop. The link lasts 30 days, and you can unshare it any time.</p></div>
  <div class="card3"><span class="who">FIND PEOPLE</span><h3>Follow photographers</h3><p>Search by @handle or name and ask to follow. Block someone and they can't find you, follow you or see your rolls. Prefer not to be found? Turn search off.</p></div>
</div>
</section>

<section class="section">
<h2 id="films">The films</h2>
<p class="muted">Tap a film to see what it does to the same photo.</p>
<p class="shelf">Black &amp; white</p>
<div class="films">${bw}</div>
<p class="shelf">Color</p>
<div class="films">${color}</div>
<p class="muted small">Your photos stay on your phone. Nothing is uploaded unless you share a roll or put one on your profile.</p>
${filmViewer()}
</section>`;
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
<li><b>Rolls for your followers or for specific people</b> can be seen only by the followers you approved or the people you chose, signed in to their accounts. Their photos are sent through links that stop working within two hours. They stay until you change who can see them or delete them.</li>
</ul>

<h2>Accounts</h2>
<p>An account is optional. You need one only to put rolls on a public profile and to like frames and rolls. You can sign in with Apple, Google or Facebook. We receive:</p>
<ul>
<li>An identifier for your Apple, Google or Facebook account. We store it only in a scrambled (one-way hashed) form, used to recognise you when you sign in again.</li>
<li>Your name, if the service provides it or you set one, and your profile photo from Google or Facebook, which you can replace or remove.</li>
</ul>
<p>We don't ask for your email address, contacts or friends list. We also store which frames and rolls you have liked, the time you agreed to our rules for public rolls, and sign-in sessions for your devices.</p>
<p><b>Following and search.</b> If you choose a @handle, we store it with the people you follow, the people who follow you, follow requests, the people you block, and who you've shared rolls with. Your handle and name can be found in search unless you turn that off. Who follows whom is visible to signed-in users. Blocking someone ends following both ways and hides your rolls and profile from them.</p>
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
