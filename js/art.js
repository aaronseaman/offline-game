/* Shared molded-plastic artwork. Rasterized only when cached sprites are built. */
(function () {
  'use strict';
  const COLORS = [
    { name: 'Coral', hex: '#cf6b61' },
    { name: 'Honey', hex: '#dbb354' },
    { name: 'Turquoise', hex: '#53a8ad' },
    { name: 'Blue', hex: '#527bb8' },
    { name: 'Plum', hex: '#99749f' },
    { name: 'Apricot', hex: '#de8b48' },
  ];
  const SP = { NONE: 0, LINE_H: 1, LINE_V: 2, BOMB: 3, PRISM: 4 };
  const hexRgb = h => { const n = parseInt(h.slice(1), 16); return [n >> 16 & 255, n >> 8 & 255, n & 255]; };
  const mix = (h, t, a) => 'rgb(' + hexRgb(h).map((v, i) => Math.round(v + (hexRgb(t)[i] - v) * a)).join(',') + ')';
  const lighten = (h, a) => mix(h, '#ffffff', a);
  const darken = (h, a) => mix(h, '#000000', a);
  const rgba = (h, a) => 'rgba(' + hexRgb(h).join(',') + ',' + a + ')';
  function rr(c, x, y, w, h, r) {
    c.beginPath(); c.roundRect(x, y, w, h, Math.max(0, Math.min(r, w / 2, h / 2)));
  }
  // Rounded-box height field: a broad crown, rolled bevel, and one large studio key.
  // No textures, network requests, or per-frame lighting calculations.
  function paintBody(c, s, hex) {
    const cv = document.createElement('canvas'); cv.width = cv.height = Math.ceil(s);
    const cx = cv.getContext('2d'), im = cx.createImageData(cv.width, cv.height);
    const rgb = hexRgb(hex), edge = 0.055, radius = 0.19, bevel = 0.095;
    const distance = (x, y) => {
      const qx = Math.abs(x - 0.5) - (0.5 - edge - radius);
      const qy = Math.abs(y - 0.475) - (0.475 - edge - radius);
      return radius - Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) - Math.min(Math.max(qx, qy), 0);
    };
    const height = (x, y) => {
      const d = distance(x, y), t = Math.max(0, Math.min(1, d / bevel));
      return bevel * Math.sqrt(1 - (1-t)*(1-t)) + 0.024 * Math.max(0, 1 - ((x-.5)**2 + (y-.475)**2)*2.7);
    };
    const eps = 0.001;
    for (let y=0; y<cv.height; y++) for (let x=0; x<cv.width; x++) {
      const u=(x+.5)/s, v=(y+.5)/s, d=distance(u,v);
      const a=Math.max(0,Math.min(1,d*s+.5)); if (!a) continue;
      let nx=-(height(u+eps,v)-height(u-eps,v))/(eps*2);
      let ny=-(height(u,v+eps)-height(u,v-eps))/(eps*2);
      const len=Math.hypot(nx,ny,1); nx/=len; ny/=len; const nz=1/len;
      const diffuse=Math.max(0,nx*-.43+ny*-.55+nz*.715);
      const spec=Math.pow(Math.max(0,nx*-.23+ny*-.295+nz*.927),18)*0.13;
      const shade=.54+.46*diffuse, i=(y*cv.width+x)*4;
      for(let k=0;k<3;k++) im.data[i+k]=Math.min(255,rgb[k]*shade+(255-rgb[k]*shade)*spec);
      im.data[i+3]=Math.round(a*255);
    }
    cx.putImageData(im,0,0);
    c.save();
    c.shadowColor='rgba(20,27,31,0.24)'; c.shadowBlur=s*.045; c.shadowOffsetY=s*.025;
    rr(c,s*.065,s*.095,s*.87,s*.855,s*.19); c.fillStyle=darken(hex,.29); c.fill();
    c.restore(); c.drawImage(cv,0,0,s,s);
  }
  function drawSymbol(c, k, x, y, r) {
    c.beginPath();
    switch (k) {
      case 0:
        c.arc(x, y, r * 0.78, 0, Math.PI * 2);
        break;
      case 1:
        for (let i = 0; i < 3; i++) {
          const a = -Math.PI / 2 + (i * Math.PI * 2) / 3;
          const px = x + Math.cos(a) * r * 1.02;
          const py = y + r * 0.12 + Math.sin(a) * r * 1.02;
          if (i) c.lineTo(px, py);
          else c.moveTo(px, py);
        }
        c.closePath();
        break;
      case 2:
        rr(c, x - r * 0.7, y - r * 0.7, r * 1.4, r * 1.4, r * 0.22);
        break;
      case 3:
        c.moveTo(x, y - r);
        c.lineTo(x + r * 0.78, y);
        c.lineTo(x, y + r);
        c.lineTo(x - r * 0.78, y);
        c.closePath();
        break;
      case 4:
        for (let i = 0; i < 10; i++) {
          const a = -Math.PI / 2 + (i * Math.PI) / 5;
          const rad = i % 2 ? r * 0.45 : r * 1.02;
          const px = x + Math.cos(a) * rad;
          const py = y + r * 0.06 + Math.sin(a) * rad;
          if (i) c.lineTo(px, py);
          else c.moveTo(px, py);
        }
        c.closePath();
        break;
      case 5: {
        const t = r * 0.32;
        c.moveTo(x - t, y - r * 0.85);
        c.lineTo(x + t, y - r * 0.85);
        c.lineTo(x + t, y - t);
        c.lineTo(x + r * 0.85, y - t);
        c.lineTo(x + r * 0.85, y + t);
        c.lineTo(x + t, y + t);
        c.lineTo(x + t, y + r * 0.85);
        c.lineTo(x - t, y + r * 0.85);
        c.lineTo(x - t, y + t);
        c.lineTo(x - r * 0.85, y + t);
        c.lineTo(x - r * 0.85, y - t);
        c.lineTo(x - t, y - t);
        c.closePath();
        break;
      }
    }
    c.fill();
  }

  function paintBlock(c, s, hex, sp, sym) {
    const g = Math.max(1, s * 0.045);
    const w = s - 2 * g;
    const r = s * 0.2;
    paintBody(c, s, hex);
    c.save();
    rr(c, g, g, w, w, r);
    c.clip();
    if (sp === SP.LINE_H || sp === SP.LINE_V) {
      const horiz = sp === SP.LINE_H;
      const th = s * 0.075;
      for (const k of [0.3, 0.5, 0.7]) {
        c.fillStyle = 'rgba(0,0,0,0.22)';
        if (horiz) rr(c, g + w * 0.12, k * s - th / 2 + s * 0.015, w * 0.76, th, th / 2);
        else rr(c, k * s - th / 2 + s * 0.015, g + w * 0.12, th, w * 0.76, th / 2);
        c.fill();
        c.fillStyle = 'rgba(255,255,255,0.92)';
        if (horiz) rr(c, g + w * 0.12, k * s - th / 2, w * 0.76, th, th / 2);
        else rr(c, k * s - th / 2, g + w * 0.12, th, w * 0.76, th / 2);
        c.fill();
      }
    }
    c.restore();

    if (sp === SP.LINE_H || sp === SP.LINE_V) {
      // arrow tips show the blast direction
      c.fillStyle = '#ffffff';
      const a = s * 0.09;
      const m = s / 2;
      c.beginPath();
      if (sp === SP.LINE_H) {
        c.moveTo(g + 1, m);
        c.lineTo(g + 1 + a, m - a);
        c.lineTo(g + 1 + a, m + a);
        c.closePath();
        c.moveTo(s - g - 1, m);
        c.lineTo(s - g - 1 - a, m - a);
        c.lineTo(s - g - 1 - a, m + a);
        c.closePath();
      } else {
        c.moveTo(m, g + 1);
        c.lineTo(m - a, g + 1 + a);
        c.lineTo(m + a, g + 1 + a);
        c.closePath();
        c.moveTo(m, s - g - 1);
        c.lineTo(m - a, s - g - 1 - a);
        c.lineTo(m + a, s - g - 1 - a);
        c.closePath();
      }
      c.fill();
    } else if (sp === SP.BOMB) {
      const bx = s / 2;
      const by = s * 0.54;
      const br = s * 0.25;
      c.beginPath();
      c.arc(bx, by, br + s * 0.035, 0, Math.PI * 2);
      c.fillStyle = lighten(hex, 0.55);
      c.fill();
      const bg = c.createRadialGradient(bx - br * 0.35, by - br * 0.4, br * 0.1, bx, by, br);
      bg.addColorStop(0, '#68717a');
      bg.addColorStop(1, '#303942');
      c.beginPath();
      c.arc(bx, by, br, 0, Math.PI * 2);
      c.fillStyle = bg;
      c.fill();
      c.beginPath();
      c.ellipse(bx - br * 0.35, by - br * 0.4, br * 0.28, br * 0.17, -0.6, 0, Math.PI * 2);
      c.fillStyle = 'rgba(255,255,255,0.22)';
      c.fill();
      c.strokeStyle = '#f4e4c0';
      c.lineWidth = s * 0.04;
      c.lineCap = 'round';
      c.beginPath();
      c.moveTo(bx + br * 0.45, by - br * 0.85);
      c.quadraticCurveTo(bx + br * 0.8, by - br * 1.35, bx + br * 1.15, by - br * 1.3);
      c.stroke();
      c.fillStyle = '#fff6c8';
      drawSymbol(c, 4, bx + br * 1.18, by - br * 1.32, s * 0.08);
    } else if (sp === SP.PRISM) {
      const P = (x, y) => [x * s, y * s];
      const crown = [P(0.27, 0.38), P(0.38, 0.2), P(0.62, 0.2), P(0.73, 0.38)];
      const tip = P(0.5, 0.84);
      c.beginPath();
      c.moveTo(crown[0][0], crown[0][1]);
      for (const p of crown) c.lineTo(p[0], p[1]);
      c.lineTo(tip[0], tip[1]);
      c.closePath();
      const gg = c.createLinearGradient(s * 0.25, s * 0.2, s * 0.75, s * 0.84);
      gg.addColorStop(0, '#ffffff');
      gg.addColorStop(0.5, lighten(hex, 0.55));
      gg.addColorStop(1, '#ffffff');
      c.fillStyle = gg;
      c.fill();
      c.strokeStyle = darken(hex, 0.2);
      c.lineWidth = Math.max(1, s * 0.022);
      c.lineJoin = 'round';
      c.stroke();
      c.beginPath();
      c.moveTo(crown[0][0], crown[0][1]);
      c.lineTo(crown[3][0], crown[3][1]);
      c.moveTo(crown[1][0], crown[1][1]);
      c.lineTo(s * 0.44, s * 0.38);
      c.lineTo(tip[0], tip[1]);
      c.moveTo(crown[2][0], crown[2][1]);
      c.lineTo(s * 0.56, s * 0.38);
      c.lineTo(tip[0], tip[1]);
      c.strokeStyle = rgba(hex, 0.24);
      c.stroke();
      // spectral rim
      rr(c, g + s * 0.03, g + s * 0.03, w - s * 0.06, w - s * 0.06, r * 0.85);
      let rim;
      if (c.createConicGradient) {
        rim = c.createConicGradient(0, s / 2, s / 2);
        [...COLORS.slice(0, 5).map(v => v.hex), COLORS[0].hex].forEach((col, i) => rim.addColorStop(i / 5, col));
      } else {
        rim = c.createLinearGradient(0, 0, s, s);
        COLORS.slice(0, 5).map(v => v.hex).forEach((col, i) => rim.addColorStop(i / 4, col));
      }
      c.strokeStyle = rim;
      c.lineWidth = s * 0.035;
      c.stroke();
    }

    if (sym >= 0) {
      const special = sp !== SP.NONE;
      const sx = special ? s * 0.26 : s / 2;
      const sy = special ? s * 0.26 : s * 0.53;
      const sr = special ? s * 0.09 : s * 0.17;
      if (special && sp !== SP.PRISM) {
        c.beginPath();
        c.arc(sx, sy, sr * 1.55, 0, Math.PI * 2);
        c.fillStyle = darken(hex, 0.35);
        c.fill();
        c.fillStyle = 'rgba(255,255,255,0.9)';
        drawSymbol(c, sym, sx, sy, sr);
      } else if (!special) {
        c.fillStyle = 'rgba(255,255,255,0.32)';
        drawSymbol(c, sym, sx, sy + s * 0.018, sr);
        c.fillStyle = darken(hex, 0.36);
        c.globalAlpha = 0.72;
        drawSymbol(c, sym, sx, sy, sr);
        c.globalAlpha = 1;
      }
    }
  }

  window.PFArt = Object.freeze({ COLORS, paintBlock, paintBody });
})();
