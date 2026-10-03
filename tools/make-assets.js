/*
 * Renders the app icons and iOS launch screens with headless Chromium.
 * Usage: NODE_PATH="$(npm root -g)" node tools/make-assets.js
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = path.resolve(__dirname, '..');
const fontData = fs.readFileSync(path.join(ROOT, 'fonts/unbounded-latin.woff2')).toString('base64');

const PAGE = `<!doctype html><html><head><style>
@font-face { font-family: 'Unbounded'; font-weight: 200 900; src: url(data:font/woff2;base64,${fontData}) format('woff2'); }
body { margin: 0; background: #000; }
</style></head><body><script>
${fs.readFileSync(path.join(ROOT, 'js/art.js'), 'utf8')}
const COLORS = window.PFArt.COLORS.map(v => v.hex);
function rr(c, x, y, w, h, r) { c.beginPath(); c.roundRect(x, y, w, h, r); }
function block(c, x, y, s, hex, gem) {
  c.save(); c.translate(x, y); window.PFArt.paintBlock(c, s, hex, gem ? 4 : 0, -1); c.restore();
}
function background(c, S) {
  const g = c.createLinearGradient(0, 0, S, S);
  g.addColorStop(0, '#20a4ff'); g.addColorStop(1, '#b78aff');
  c.fillStyle = g; c.fillRect(0, 0, S, S);
}
// Same molded pieces and studio lighting as gameplay.
function mark(c, cx, cy, s) {
  const x0 = cx - s * 1.5, y0 = cy - s;
  block(c, x0, y0 + s, s, COLORS[0]);
  block(c, x0 + s, y0 + s, s, COLORS[1]);
  block(c, x0 + s * 2, y0 + s, s, COLORS[2]);
  block(c, x0 + s, y0, s, COLORS[4], true);
}
window.icon = (S, opts) => {
  const cv = document.createElement('canvas'); cv.width = cv.height = S;
  const c = cv.getContext('2d');
  background(c, S);
  const scale = opts && opts.maskable ? 0.17 : 0.235;
  mark(c, S / 2, S * 0.47, S * scale);
  return cv.toDataURL('image/png');
};
window.splash = async (w, h) => {
  await document.fonts.load('900 40px Unbounded');
  const cv = document.createElement('canvas'); cv.width = w; cv.height = h;
  const c = cv.getContext('2d');
  // Paint the soft background small and scale it up: smooth, and far smaller as a PNG than a dithered full-size gradient.
  const k = 16, sw = Math.ceil(w / k), sh = Math.ceil(h / k);
  const bg = document.createElement('canvas'); bg.width = sw; bg.height = sh;
  const b = bg.getContext('2d');
  const g = b.createLinearGradient(0, 0, 0, sh); g.addColorStop(0, '#20a4ff'); g.addColorStop(1, '#b78aff');
  b.fillStyle = g; b.fillRect(0, 0, sw, sh);
  const rg = b.createRadialGradient(sw / 2, sh * 0.42, 0, sw / 2, sh * 0.42, sw * 0.8);
  rg.addColorStop(0, 'rgba(255,253,247,0.22)'); rg.addColorStop(1, 'rgba(0,0,0,0)');
  b.fillStyle = rg; b.fillRect(0, 0, sw, sh);
  c.imageSmoothingEnabled = true; c.imageSmoothingQuality = 'high';
  c.drawImage(bg, 0, 0, w, h);
  const s = w * 0.12;
  mark(c, w / 2, h * 0.42, s);
  c.textAlign = 'center'; c.textBaseline = 'alphabetic';
  c.font = '900 ' + Math.round(w * 0.105) + 'px Unbounded';
  c.fillStyle = '#ffffff';
  c.fillText('PRISMFALL', w / 2, h * 0.42 + s * 3.0);
  return cv.toDataURL('image/png');
};
</script></body></html>`;

const FAVICON = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<defs><linearGradient id="bg" x2="1" y2="1"><stop stop-color="#20a4ff"/><stop offset="1" stop-color="#b78aff"/></linearGradient></defs>
<rect width="64" height="64" rx="14" fill="url(#bg)"/>
<rect x="8" y="30" width="16" height="17" rx="4" fill="#ff239d"/>
<rect x="24" y="30" width="16" height="17" rx="4" fill="#ffc817"/>
<rect x="40" y="30" width="16" height="17" rx="4" fill="#08cfee"/>
<rect x="24" y="14" width="16" height="17" rx="4" fill="#b232ff"/>
<path d="M28 19h8l2 3-6 6-6-6z" fill="#f9f4ed"/>
</svg>`;

(async () => {
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
  const page = await browser.newPage();
  await page.setContent(PAGE);
  const save = (rel, dataUrl) => {
    const file = path.join(ROOT, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, Buffer.from(dataUrl.split(',')[1], 'base64'));
    console.log('wrote', rel);
  };
  for (const [rel, size, maskable] of [
    ['icons/icon-32.png', 32],
    ['icons/apple-touch-icon.png', 180],
    ['icons/icon-192.png', 192],
    ['icons/icon-512.png', 512],
    ['icons/icon-maskable-512.png', 512, true],
  ]) {
    save(rel, await page.evaluate(([s, m]) => window.icon(s, { maskable: m }), [size, !!maskable]));
  }
  fs.writeFileSync(path.join(ROOT, 'icons/favicon.svg'), FAVICON);
  for (const [w, h] of [
    [1320, 2868],
    [1260, 2736],
    [1206, 2622],
    [1290, 2796],
    [1179, 2556],
    [1170, 2532],
  ]) {
    save(`splash/splash-${w}x${h}.png`, await page.evaluate(([a, b]) => window.splash(a, b), [w, h]));
  }
  await browser.close();
})();
