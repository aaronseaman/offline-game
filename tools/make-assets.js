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
const COLORS = ['#ff3f66', '#ffc83a', '#2fd98a', '#3c8dff', '#b264ff', '#ff8327'];
function hexRgb(h) { const n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
function mix(h, t, a) { const c = hexRgb(h), d = hexRgb(t); return 'rgb(' + c.map((v, i) => Math.round(v + (d[i] - v) * a)).join(',') + ')'; }
function rr(c, x, y, w, h, r) { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath(); }
function block(c, x, y, s, hex, gem) {
  const g = s * 0.045, w = s - 2 * g, r = s * 0.2;
  const base = gem ? mix(hex, '#141030', 0.38) : hex;
  c.save();
  c.shadowColor = 'rgba(0,0,0,0.45)'; c.shadowBlur = s * 0.18; c.shadowOffsetY = s * 0.06;
  rr(c, x + g, y + g, w, w, r);
  const grad = c.createLinearGradient(0, y + g, 0, y + g + w);
  grad.addColorStop(0, mix(base, '#ffffff', 0.32)); grad.addColorStop(0.55, base); grad.addColorStop(1, mix(base, '#000000', 0.3));
  c.fillStyle = grad; c.fill();
  c.restore();
  c.save(); rr(c, x + g, y + g, w, w, r); c.clip();
  rr(c, x + g + w * 0.1, y + g + w * 0.06, w * 0.8, w * 0.36, r * 0.75);
  const gl = c.createLinearGradient(0, y + g + w * 0.06, 0, y + g + w * 0.42);
  gl.addColorStop(0, 'rgba(255,255,255,0.6)'); gl.addColorStop(1, 'rgba(255,255,255,0.03)');
  c.fillStyle = gl; c.fill(); c.restore();
  rr(c, x + g, y + g, w, w, r); c.lineWidth = Math.max(1, s * 0.03); c.strokeStyle = mix(base, '#000000', 0.45); c.stroke();
  if (gem) {
    const P = (px, py) => [x + px * s, y + py * s];
    const crown = [P(0.27, 0.38), P(0.38, 0.2), P(0.62, 0.2), P(0.73, 0.38)], tip = P(0.5, 0.84);
    c.beginPath(); c.moveTo(crown[0][0], crown[0][1]); for (const p of crown) c.lineTo(p[0], p[1]); c.lineTo(tip[0], tip[1]); c.closePath();
    const gg = c.createLinearGradient(x + s * 0.25, y + s * 0.2, x + s * 0.75, y + s * 0.84);
    gg.addColorStop(0, '#ffffff'); gg.addColorStop(0.5, mix(hex, '#ffffff', 0.55)); gg.addColorStop(1, '#ffffff');
    c.fillStyle = gg; c.fill(); c.lineJoin = 'round'; c.lineWidth = s * 0.022; c.strokeStyle = mix(hex, '#000000', 0.2); c.stroke();
    c.beginPath(); c.moveTo(crown[0][0], crown[0][1]); c.lineTo(crown[3][0], crown[3][1]);
    c.moveTo(crown[1][0], crown[1][1]); c.lineTo(x + s * 0.44, y + s * 0.38); c.lineTo(tip[0], tip[1]);
    c.moveTo(crown[2][0], crown[2][1]); c.lineTo(x + s * 0.56, y + s * 0.38); c.lineTo(tip[0], tip[1]);
    c.strokeStyle = 'rgba(0,0,0,0.25)'; c.stroke();
    rr(c, x + g + s * 0.03, y + g + s * 0.03, w - s * 0.06, w - s * 0.06, r * 0.85);
    const rim = c.createConicGradient(0, x + s / 2, y + s / 2);
    ['#ff3f66', '#ffc83a', '#2fd98a', '#3c8dff', '#b264ff', '#ff3f66'].forEach((col, i) => rim.addColorStop(i / 5, col));
    c.strokeStyle = rim; c.lineWidth = s * 0.06; c.stroke();
  }
}
function background(c, S) {
  const g = c.createLinearGradient(0, 0, S, S);
  g.addColorStop(0, '#221a5c'); g.addColorStop(0.55, '#0e1131'); g.addColorStop(1, '#070816');
  c.fillStyle = g; c.fillRect(0, 0, S, S);
  const blob = (x, y, r, col) => { const rg = c.createRadialGradient(x, y, 0, x, y, r); rg.addColorStop(0, col); rg.addColorStop(1, 'rgba(0,0,0,0)'); c.fillStyle = rg; c.fillRect(0, 0, S, S); };
  blob(S * 0.5, S * 0.42, S * 0.55, 'rgba(178,100,255,0.28)');
  blob(S * 0.85, S * 0.95, S * 0.5, 'rgba(47,217,138,0.12)');
}
// The mark: a multi-colored T shape with a prism on top, plus a light spectrum underneath.
function mark(c, cx, cy, s) {
  const x0 = cx - s * 1.5, y0 = cy - s;
  // spectrum beam
  const bw = s * 3.3, bh = s * 0.12, by = y0 + s * 2 + s * 0.38;
  const sg = c.createLinearGradient(cx - bw / 2, 0, cx + bw / 2, 0);
  ['#ff3f66', '#ff8327', '#ffc83a', '#2fd98a', '#3c8dff', '#b264ff'].forEach((col, i) => sg.addColorStop(i / 5, col));
  c.save(); c.shadowColor = 'rgba(178,100,255,0.8)'; c.shadowBlur = s * 0.35;
  rr(c, cx - bw / 2, by, bw, bh, bh / 2); c.fillStyle = sg; c.fill(); c.restore();
  block(c, x0, y0 + s, s, COLORS[0]);
  block(c, x0 + s, y0 + s, s, COLORS[1]);
  block(c, x0 + s * 2, y0 + s, s, COLORS[3]);
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
  const g = b.createLinearGradient(0, 0, 0, sh); g.addColorStop(0, '#0d1029'); g.addColorStop(1, '#05060e');
  b.fillStyle = g; b.fillRect(0, 0, sw, sh);
  const rg = b.createRadialGradient(sw / 2, sh * 0.42, 0, sw / 2, sh * 0.42, sw * 0.8);
  rg.addColorStop(0, 'rgba(118,78,255,0.22)'); rg.addColorStop(1, 'rgba(0,0,0,0)');
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
<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#221a5c"/><stop offset="1" stop-color="#080a1a"/></linearGradient></defs>
<rect width="64" height="64" rx="14" fill="url(#bg)"/>
<rect x="9" y="29" width="15" height="15" rx="3.5" fill="#ff3f66"/>
<rect x="24.5" y="29" width="15" height="15" rx="3.5" fill="#ffc83a"/>
<rect x="40" y="29" width="15" height="15" rx="3.5" fill="#3c8dff"/>
<rect x="24.5" y="13.5" width="15" height="15" rx="3.5" fill="#b264ff"/>
<path d="M27.5 18.5h9l2 3-6.5 6.5-6.5-6.5z" fill="#fff"/>
<rect x="9" y="48" width="46" height="3" rx="1.5" fill="#b264ff"/>
</svg>`;

(async () => {
  const browser = await chromium.launch();
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
