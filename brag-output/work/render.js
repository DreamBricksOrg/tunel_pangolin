const puppeteer = require('puppeteer-core');
const fs = require('fs');
const path = require('path');

const TL = JSON.parse(fs.readFileSync(path.join(__dirname, 'timeline.json'), 'utf8'));
const only = process.argv[2] ? process.argv[2].split(',').map(Number) : null; // times for stills

(async () => {
  const browser = await puppeteer.launch({
    executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    headless: 'new',
    args: ['--no-sandbox', '--hide-scrollbars', '--force-device-scale-factor=1'],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: 1 });
  await page.evaluateOnNewDocument(tl => { window.TL = tl; }, TL);
  await page.goto('file:///' + path.join(__dirname, 'index.html').replace(/\\/g, '/'));
  await page.evaluate(() => document.fonts.ready);

  const dir = path.join(__dirname, only ? 'stills' : 'frames');
  fs.mkdirSync(dir, { recursive: true });

  if (only) {
    for (const t of only) {
      await page.evaluate(t => window.render(t), t);
      await page.screenshot({ path: path.join(dir, `t${t.toFixed(2)}.png`) });
    }
  } else {
    const n = Math.round(TL.dur * TL.fps);
    const from = Number(process.env.FROM || 0), to = Math.min(n, Number(process.env.TO || n));
    for (let i = from; i < to; i++) {
      await page.evaluate(t => window.render(t), i / TL.fps);
      await page.screenshot({ path: path.join(dir, `f${String(i).padStart(5, '0')}.png`) });
    }
  }
  await browser.close();
})();
