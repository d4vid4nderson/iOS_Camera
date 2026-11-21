const { chromium } = require('playwright');
(async () => {
  const [, , url, out, scale] = process.argv;
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 2622, height: 1475 }, deviceScaleFactor: Number(scale) });
  await p.goto(url, { waitUntil: 'networkidle' });
  await p.evaluate(() => document.fonts.ready);
  await p.screenshot({ path: out });
  await b.close();
})();
