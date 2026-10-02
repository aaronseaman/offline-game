/*
 * Bundles the game into one self-contained HTML body (CSS, JS and font inlined)
 * for hosts that can't serve the multi-file PWA. Usage: node tools/build-artifact.js [out.html]
 */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const out = process.argv[2] || path.join(ROOT, 'dist/prismfall.html');

const font = fs.readFileSync(path.join(ROOT, 'fonts/unbounded-latin.woff2')).toString('base64');
const css = read('css/style.css').replace("url('../fonts/unbounded-latin.woff2')", 'url(data:font/woff2;base64,' + font + ')');
const html = read('index.html');
const body = html.slice(html.indexOf('<body>') + 6, html.indexOf('<script src="js/art.js">'));
// keep "</script" sequences inside the code from closing the inline tag early
const js = (f) => read(f).replace(/<\/script/gi, '<\\/script');

const page = `<title>Prismfall</title>
<meta name="color-scheme" content="light">
<style>
${css}
</style>
${body.trim()}
<script>
${js('js/art.js')}
</script>
<script>
${js('js/core.js')}
</script>
<script>
${js('js/main.js')}
</script>
`;
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, page);
console.log('wrote', out, (page.length / 1024).toFixed(0) + ' KB');

