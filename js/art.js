/* Shared glossy jewel artwork. Rasterized only when cached sprites are built. */
(function () {
  'use strict';
  const COLORS = [
    { name: 'Ribbon', hex: '#ff239d' },
    { name: 'Halo', hex: '#ffc817' },
    { name: 'Moon', hex: '#08cfee' },
    { name: 'Wing', hex: '#3275ff' },
    { name: 'Bloom', hex: '#b232ff' },
    { name: 'Flare', hex: '#ff712b' },
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
      const spec=Math.pow(Math.max(0,nx*-.23+ny*-.295+nz*.927),32)*0.78;
      const shade=.42+.64*diffuse, i=(y*cv.width+x)*4;
      for(let k=0;k<3;k++) im.data[i+k]=Math.min(255,rgb[k]*shade+(255-rgb[k]*shade)*spec);
      im.data[i+3]=Math.round(a*255);
    }
    cx.putImageData(im,0,0);
    c.save();
    c.shadowColor='rgba(20,27,31,0.24)'; c.shadowBlur=s*.045; c.shadowOffsetY=s*.025;
    rr(c,s*.065,s*.095,s*.87,s*.855,s*.19); c.fillStyle=darken(hex,.29); c.fill();
    c.restore(); c.drawImage(cv,0,0,s,s);
    c.save();
    rr(c,s*.055,s*.055,s*.89,s*.84,s*.19); c.clip();
    const glaze=c.createLinearGradient(0,s*.05,s*.4,s*.5);
    glaze.addColorStop(0,'rgba(255,255,255,.83)'); glaze.addColorStop(.55,'rgba(255,255,255,.15)'); glaze.addColorStop(1,'rgba(255,255,255,0)');
    c.fillStyle=glaze; c.beginPath();
    c.moveTo(s*.1,s*.3); c.bezierCurveTo(s*.2,s*.05,s*.65,s*.035,s*.86,s*.16);
    c.bezierCurveTo(s*.65,s*.12,s*.44,s*.26,s*.1,s*.3); c.fill();
    const rim=c.createLinearGradient(0,0,s,s);
    rim.addColorStop(0,'rgba(255,255,255,.95)'); rim.addColorStop(.45,'rgba(255,255,255,.08)'); rim.addColorStop(1,'rgba(255,255,255,.65)');
    rr(c,s*.075,s*.07,s*.85,s*.80,s*.16);c.strokeStyle=rim;c.lineWidth=s*.021;c.stroke();
    c.beginPath();c.ellipse(s*.17,s*.13,s*.065,s*.022,-.55,0,Math.PI*2);c.fillStyle='rgba(255,255,255,.88)';c.fill();
    c.beginPath();c.ellipse(s*.77,s*.84,s*.06,s*.009,-.12,0,Math.PI*2);c.fillStyle='rgba(255,255,255,.6)';c.fill();
    c.restore();
  }
  // Six original molded emblems: ribbon loop, halo, crescent, wing, bloom, flare.
  // These are color identities, not copied candy, heart, clover or star pieces.
  function emblem(c, k) {
    c.beginPath();
    if(k===0) {
      c.moveTo(-.9,0);c.bezierCurveTo(-.9,-.85,-.12,-.85,.28,-.24);
      c.bezierCurveTo(.88,.4,.82,.83,.28,.79);c.bezierCurveTo(-.15,.78,-.23,.28,-.5,.28);
      c.bezierCurveTo(-.8,.28,-.92,.2,-.9,0);c.closePath();
      c.moveTo(-.49,-.22);c.bezierCurveTo(-.2,-.13,.12,.4,.37,.41);c.bezierCurveTo(.64,.4,.25,-.08,-.12,-.31);c.bezierCurveTo(-.4,-.5,-.68,-.5,-.49,-.22);c.closePath();
    } else if(k===1) {
      c.ellipse(0,0,.77,.88,.5,0,Math.PI*2);c.moveTo(.3,0);c.ellipse(0,0,.3,.43,.5,0,Math.PI*2,true);
    } else if(k===2) {
      c.moveTo(.55,-.73);c.bezierCurveTo(-.9,-1.05,-1.1,.68,-.05,.85);c.bezierCurveTo(.42,.94,.8,.63,.86,.34);c.bezierCurveTo(-.19,.65,-.43,-.31,.55,-.73);c.closePath();
    } else if(k===3) {
      c.moveTo(-.9,.55);c.quadraticCurveTo(-.55,-.45,.85,-.8);c.quadraticCurveTo(.46,-.22,.11,-.07);c.lineTo(.59,.04);c.quadraticCurveTo(.03,.54,-.42,.34);c.lineTo(-.9,.55);c.closePath();
    } else if(k===4) {
      for(let i=0;i<=120;i++){const t=i/120*Math.PI*2,r=.63+.2*Math.cos(3*t-Math.PI/2),x=Math.cos(t)*r,y=Math.sin(t)*r;i?c.lineTo(x,y):c.moveTo(x,y);}c.closePath();
    } else {
      c.moveTo(-.68,.67);c.quadraticCurveTo(-.77,-.32,-.18,-.87);c.quadraticCurveTo(-.04,-.45,.05,-.26);c.lineTo(.49,-.69);c.quadraticCurveTo(.4,-.23,.42,-.1);c.lineTo(.83,-.23);c.quadraticCurveTo(.77,.68,-.04,.81);c.closePath();
    }
  }
  function raised(c,s,hex,k,x=.5,y=.49,scale=.27) {
    c.save();c.translate(s*x,s*y);c.scale(s*scale,s*scale);
    const g=c.createLinearGradient(-.5,-1,.4,1);
    g.addColorStop(0,lighten(hex,.82));g.addColorStop(.38,lighten(hex,.37));g.addColorStop(1,hex);
    c.shadowColor=darken(hex,.5);c.shadowBlur=.08*s;c.shadowOffsetY=.027*s;
    emblem(c,k);c.fillStyle=g;c.fill('evenodd');c.shadowBlur=0;c.shadowOffsetY=0;
    c.lineWidth=.055;c.strokeStyle=lighten(hex,.7);c.stroke();c.restore();
  }
  function paintBlock(c,s,hex,sp,sym) {
    paintBody(c,s,hex);
    const colorIndex=COLORS.findIndex(v=>v.hex===hex);
    if(sp===SP.NONE) {
      if(colorIndex>=0)raised(c,s,hex,colorIndex);
    } else if(sp===SP.LINE_H || sp===SP.LINE_V) {
      c.save();c.translate(s*.5,s*.47);if(sp===SP.LINE_V)c.rotate(Math.PI/2);
      c.lineJoin='round';c.lineCap='round';c.lineWidth=s*.09;
      c.shadowColor=darken(hex,.45);c.shadowBlur=s*.045;c.shadowOffsetY=s*.035;
      c.strokeStyle='#fff6ef';
      for(const x of [-.20,.13]){c.beginPath();c.moveTo(s*(x-.12),-s*.18);c.lineTo(s*(x+.08),0);c.lineTo(s*(x-.12),s*.18);c.stroke();}
      c.restore();
    } else if(sp===SP.BOMB) {
      c.save();const x=s*.5,y=s*.47,r=s*.255;
      const g=c.createRadialGradient(x-r*.4,y-r*.5,0,x,y,r);
      g.addColorStop(0,'#fff7fc');g.addColorStop(.28,lighten(hex,.65));g.addColorStop(.65,hex);g.addColorStop(1,darken(hex,.5));
      c.shadowColor=lighten(hex,.6);c.shadowBlur=s*.11;c.beginPath();c.arc(x,y,r,0,Math.PI*2);c.fillStyle=g;c.fill();
      c.shadowBlur=0;c.strokeStyle='#fff5ed';c.lineWidth=s*.026;
      c.beginPath();c.ellipse(x,y,r*1.18,r*.42,-.55,0,Math.PI*2);c.stroke();c.restore();
    } else if(sp===SP.PRISM) {
      c.save();c.translate(s*.5,s*.47);
      c.shadowColor='#ffe9ff';c.shadowBlur=s*.1;
      for(let k=0;k<6;k++){
        const t=k*Math.PI/3; c.beginPath();c.moveTo(0,0);c.lineTo(Math.cos(t)*s*.29,Math.sin(t)*s*.29);c.lineTo(Math.cos(t+Math.PI/3)*s*.29,Math.sin(t+Math.PI/3)*s*.29);c.closePath();
        const g=c.createLinearGradient(0,0,Math.cos(t)*s*.29,Math.sin(t)*s*.29);g.addColorStop(0,'#ffffff');g.addColorStop(1,COLORS[k].hex);c.fillStyle=g;c.fill();
      }c.restore();
    }
    // Optional small high-contrast identity mark, also present on every special.
    if(sym>=0) {
      c.save();c.translate(s*.2,s*.21);c.scale(s*.083,s*.083);emblem(c,sym);
      c.lineWidth=.22;c.strokeStyle=darken(hex,.68);c.stroke();c.fillStyle='#ffffff';c.fill('evenodd');c.restore();
    }
  }
  window.PFArt = Object.freeze({ COLORS, paintBlock, paintBody });
})();
