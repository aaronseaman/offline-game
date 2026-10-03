/* Prismfall: rendering, input, audio, screens and app lifecycle. */
(function () {
  'use strict';

  const PF = window.PFCore;
  const { Game, COLS, ROWS, SP, T } = PF;

  // ===================================================================
  // Palette and helpers
  // ===================================================================
  const COLORS = window.PFArt.COLORS;
  const DEAD = '#3a3f5e';
  const GOLD = '#ffd66b';
  const FD = 'Unbounded, ui-rounded, "SF Pro Rounded", system-ui, sans-serif';
  const FU = 'ui-rounded, "SF Pro Rounded", -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif';
  const SPECIAL_NAMES = { [SP.LINE_H]: 'LINE', [SP.LINE_V]: 'LINE', [SP.BOMB]: 'BOMB', [SP.PRISM]: 'PRISM' };
  const COMBO_NAMES = {
    cross: 'CROSSFIRE',
    wide: 'WIDE CROSS',
    mega: 'MEGA BLAST',
    wipe: 'COLOR WIPE',
    wipeLines: 'LINE STORM',
    wipeBombs: 'BOMB STORM',
    wipe2: 'DOUBLE WIPE',
  };

  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const lerp = (a, b, t) => a + (b - a) * t;
  const easeOutCubic = (t) => 1 - Math.pow(1 - t, 3);
  const easeOutBack = (t) => {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
  };
  const fmt = (n) => Math.round(n).toLocaleString('en-US');

  function hexRgb(h) {
    const n = parseInt(h.slice(1), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }
  function mix(h, t, a) {
    const c = hexRgb(h);
    const d = hexRgb(t);
    return 'rgb(' + c.map((v, i) => Math.round(v + (d[i] - v) * a)).join(',') + ')';
  }
  const lighten = (h, a) => mix(h, '#ffffff', a);
  const darken = (h, a) => mix(h, '#000000', a);
  function rgba(h, a) {
    const c = hexRgb(h);
    return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')';
  }
  function makeCanvas(w, h) {
    const c = document.createElement('canvas');
    c.width = Math.max(1, Math.round(w));
    c.height = Math.max(1, Math.round(h));
    return c;
  }
  function rr(c, x, y, w, h, r) {
    r = Math.max(0, Math.min(r, w / 2, h / 2));
    c.beginPath();
    c.moveTo(x + r, y);
    c.arcTo(x + w, y, x + w, y + h, r);
    c.arcTo(x + w, y + h, x, y + h, r);
    c.arcTo(x, y + h, x, y, r);
    c.arcTo(x, y, x + w, y, r);
    c.closePath();
  }

  // ===================================================================
  // Storage and settings
  // ===================================================================
  const store = {
    get(k, d) {
      try {
        const v = localStorage.getItem(k);
        return v == null ? d : JSON.parse(v);
      } catch (e) {
        return d;
      }
    },
    set(k, v) {
      try {
        localStorage.setItem(k, JSON.stringify(v));
      } catch (e) {
        /* storage unavailable */
      }
    },
    del(k) {
      try {
        localStorage.removeItem(k);
      } catch (e) {
        /* storage unavailable */
      }
    },
  };
  const DEFAULTS = { sound: true, haptics: true, ghost: true, symbols: true, relaxed: false };
  const settings = Object.assign({}, DEFAULTS, store.get('pf.settings', {}));
  const saveSettings = () => store.set('pf.settings', settings);
  const reducedMotion = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  const coarsePointer = window.matchMedia && matchMedia('(pointer: coarse)').matches;

  // ===================================================================
  // Audio: tiny WebAudio synth, no files needed
  // ===================================================================
  const Sound = (() => {
    let ac = null;
    let master = null;
    let noiseBuf = null;
    function ensure() {
      if (!ac) {
        const AC = window.AudioContext || window.webkitAudioContext;
        if (!AC) return;
        try {
          // Respect the ring/silent switch and mix with the player's own music.
          if (navigator.audioSession) navigator.audioSession.type = 'ambient';
        } catch (e) {
          /* not supported */
        }
        ac = new AC();
        master = ac.createGain();
        master.gain.value = 0.6;
        const comp = ac.createDynamicsCompressor();
        comp.threshold.value = -12;
        comp.ratio.value = 5;
        master.connect(comp);
        comp.connect(ac.destination);
        noiseBuf = ac.createBuffer(1, ac.sampleRate, ac.sampleRate);
        const d = noiseBuf.getChannelData(0);
        for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
      }
      if (ac.state === 'suspended') ac.resume().catch(() => {});
    }
    const ok = () => settings.sound && ac && ac.state === 'running';
    function tone(f, dur, o) {
      if (!ok()) return;
      o = o || {};
      const t0 = ac.currentTime + (o.delay || 0);
      const osc = ac.createOscillator();
      osc.type = o.type || 'sine';
      osc.frequency.setValueAtTime(f, t0);
      if (o.to) osc.frequency.exponentialRampToValueAtTime(o.to, t0 + dur);
      const g = ac.createGain();
      const v = o.vol == null ? 0.15 : o.vol;
      g.gain.setValueAtTime(0.0001, t0);
      g.gain.exponentialRampToValueAtTime(v, t0 + (o.attack || 0.006));
      g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
      osc.connect(g);
      g.connect(master);
      osc.start(t0);
      osc.stop(t0 + dur + 0.03);
    }
    function noise(dur, o) {
      if (!ok()) return;
      o = o || {};
      const t0 = ac.currentTime + (o.delay || 0);
      const src = ac.createBufferSource();
      src.buffer = noiseBuf;
      const f = ac.createBiquadFilter();
      f.type = o.ftype || 'lowpass';
      f.frequency.setValueAtTime(o.freq || 1000, t0);
      if (o.to) f.frequency.exponentialRampToValueAtTime(o.to, t0 + dur);
      const g = ac.createGain();
      g.gain.setValueAtTime(0.0001, t0);
      g.gain.exponentialRampToValueAtTime(o.vol || 0.1, t0 + 0.01);
      g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
      src.connect(f);
      f.connect(g);
      g.connect(master);
      src.start(t0);
      src.stop(t0 + dur + 0.03);
    }
    const P = [523.25, 587.33, 659.25, 783.99, 880, 1046.5, 1174.66, 1318.51, 1567.98, 1760, 2093, 2349.3, 2637];
    const sfx = {
      move: () => tone(950, 0.025, { type: 'square', vol: 0.018 }),
      rotate: () => tone(600, 0.05, { type: 'triangle', vol: 0.06, to: 900 }),
      land: () => tone(200, 0.05, { vol: 0.05 }),
      bump: () => tone(150, 0.045, { type: 'triangle', vol: 0.035 }),
      lock: () => {
        tone(160, 0.09, { vol: 0.12, to: 90 });
        noise(0.05, { vol: 0.04, freq: 1600 });
      },
      hard: () => {
        tone(130, 0.18, { vol: 0.22, to: 48 });
        noise(0.14, { vol: 0.1, freq: 900, to: 160 });
      },
      hold: () => noise(0.2, { vol: 0.07, ftype: 'bandpass', freq: 500, to: 2600 }),
      clear: (chain) => {
        const b = Math.min(chain - 1, 7);
        [0, 2, 4].forEach((k, j) => tone(P[b + k], 0.24, { type: 'triangle', vol: 0.1, delay: j * 0.045 }));
        tone(P[b] * 2, 0.32, { vol: 0.035, delay: 0.1 });
      },
      special: () => [2, 4, 6, 9].forEach((k, j) => tone(P[k], 0.16, { vol: 0.06, delay: 0.12 + j * 0.035 })),
      line: () => {
        tone(1500, 0.3, { type: 'sawtooth', vol: 0.045, to: 160 });
        noise(0.26, { vol: 0.05, ftype: 'highpass', freq: 3200, to: 500 });
      },
      bomb: () => {
        tone(95, 0.5, { vol: 0.28, to: 32 });
        noise(0.45, { vol: 0.18, freq: 1400, to: 90 });
      },
      prism: () => {
        for (let k = 0; k < 7; k++) tone(P[4 + k], 0.4, { vol: 0.04, delay: k * 0.028 });
        noise(0.35, { vol: 0.035, ftype: 'highpass', freq: 5200 });
      },
      swap: () => {
        tone(520, 0.07, { type: 'triangle', vol: 0.07, to: 780 });
        tone(780, 0.07, { type: 'triangle', vol: 0.05, delay: 0.06, to: 520 });
      },
      fail: () => {
        tone(150, 0.1, { type: 'square', vol: 0.045 });
        tone(115, 0.13, { type: 'square', vol: 0.045, delay: 0.09 });
      },
      token: () => {
        tone(1318.5, 0.25, { vol: 0.08 });
        tone(1975.5, 0.35, { vol: 0.06, delay: 0.08 });
      },
      level: () => [0, 2, 4, 5, 7].forEach((k, j) => tone(P[k], 0.22, { type: 'triangle', vol: 0.09, delay: j * 0.07 })),
      over: () => [7, 5, 4, 2, 0].forEach((k, j) => tone(P[k] / 2, 0.4, { type: 'triangle', vol: 0.1, delay: j * 0.15 })),
      swapOpen: () => tone(1046.5, 0.09, { vol: 0.035 }),
      select: () => tone(1250, 0.03, { type: 'triangle', vol: 0.04 }),
      ui: () => tone(720, 0.04, { type: 'triangle', vol: 0.04 }),
    };
    return { ensure, sfx };
  })();
  const sfx = Sound.sfx;

  // ===================================================================
  // Haptics: Vibration API where present; iOS 18+ ticks via a hidden switch
  // ===================================================================
  const Haptics = (() => {
    const coarse = window.matchMedia && matchMedia('(pointer: coarse)').matches;
    let label = null;
    function tap() {
      if (!settings.haptics) return;
      try {
        if (navigator.vibrate) {
          navigator.vibrate(8);
          return;
        }
        if (!coarse) return;
        if (!label) {
          label = document.createElement('label');
          label.setAttribute('aria-hidden', 'true');
          label.style.display = 'none';
          const input = document.createElement('input');
          input.type = 'checkbox';
          input.setAttribute('switch', '');
          input.tabIndex = -1;
          label.appendChild(input);
          document.body.appendChild(label);
        }
        label.click();
      } catch (e) {
        /* haptics unavailable */
      }
    }
    return { tap };
  })();

  // ===================================================================
  // DOM
  // ===================================================================
  const $ = (id) => document.getElementById(id);
  const canvas = $('game');
  const ctx = canvas.getContext('2d');
  const pauseBtn = $('pause-btn');
  const saProbe = $('sa-probe');

  // ===================================================================
  // Layout
  // ===================================================================
  let L = null;
  let DPR = 1;
  let W = 0;
  let H = 0;

  function safeArea() {
    const cs = getComputedStyle(saProbe);
    return {
      t: parseFloat(cs.paddingTop) || 0,
      r: parseFloat(cs.paddingRight) || 0,
      b: parseFloat(cs.paddingBottom) || 0,
      l: parseFloat(cs.paddingLeft) || 0,
    };
  }

  function computeLayout() {
    W = window.innerWidth;
    H = window.innerHeight;
    DPR = Math.min(window.devicePixelRatio || 1, 3);
    const sa = safeArea();
    const snap = (v) => Math.round(v * DPR) / DPR;
    const out = { W, H, sa, portrait: W / H < 0.8 };
    if (out.portrait) {
      const gut = clamp(Math.round(W * 0.03), 8, 16);
      const left = sa.l + gut;
      const right = W - sa.r - gut;
      const top = sa.t + 6;
      const hudH = clamp(Math.round(W * 0.175), 60, 92);
      const bottom = H - Math.max(sa.b, 8) - 4;
      const boardTop = top + hudH + 12;
      const availH = bottom - boardTop;
      const availW = right - left;
      const cell = Math.floor(Math.min(availW / COLS, availH / ROWS) * DPR) / DPR;
      out.cell = cell;
      out.bw = cell * COLS;
      out.bh = cell * ROWS;
      out.bx = snap((W - out.bw) / 2);
      out.by = snap(boardTop + Math.max(0, (availH - out.bh) * 0.4));
      const smallW = Math.round(hudH * 0.56);
      const smallH = (hudH - 6) / 2;
      out.hold = { x: left, y: top, w: hudH, h: hudH };
      const n0x = right - smallW - 6 - hudH;
      out.next = [
        { x: n0x, y: top, w: hudH, h: hudH },
        { x: right - smallW, y: top, w: smallW, h: smallH },
        { x: right - smallW, y: top + smallH + 6, w: smallW, h: smallH },
      ];
      const ix = left + hudH + 12;
      out.info = { x: ix, y: top, w: n0x - 12 - ix, h: hudH };
      out.pause = { x: out.info.x + out.info.w - 34, y: top - 2, w: 36, h: 36 };
    } else {
      const top = sa.t + 14;
      const bottom = H - sa.b - 14;
      const availH = bottom - top;
      const colW = clamp(Math.round(W * 0.15), 108, 190);
      const gap = clamp(Math.round(W * 0.02), 12, 30);
      const availW = W - sa.l - sa.r - 2 * (colW + gap) - 24;
      const cell = Math.floor(Math.min(availW / COLS, availH / ROWS) * DPR) / DPR;
      out.cell = cell;
      out.bw = cell * COLS;
      out.bh = cell * ROWS;
      out.bx = snap((W - out.bw) / 2);
      out.by = snap(top + (availH - out.bh) / 2);
      const lx = out.bx - gap - colW;
      const rx = out.bx + out.bw + gap;
      const boxH = Math.round(colW * 0.78);
      out.hold = { x: lx, y: out.by, w: colW, h: boxH };
      out.info = { x: lx, y: out.by + boxH + 16, w: colW, h: Math.min(out.bh - boxH - 16, 260) };
      const smallH = Math.round(colW * 0.56);
      out.next = [
        { x: rx, y: out.by, w: colW, h: boxH },
        { x: rx, y: out.by + boxH + 10, w: colW, h: smallH },
        { x: rx, y: out.by + boxH + 20 + smallH, w: colW, h: smallH },
      ];
      out.pause = { x: rx, y: out.by + out.bh - 44, w: 44, h: 44 };
    }
    return out;
  }

  // ===================================================================
  // Block sprites (pre-rendered per size)
  // ===================================================================
  const SPR = { s: 0, blocks: [], dead: [], ghost: [], glow: [], white: null };

  const paintBlock = window.PFArt.paintBlock;

  function buildSprites() {
    const s = Math.max(4, Math.round(L.cell * DPR));
    SPR.s = s;
    SPR.blocks = COLORS.map((col, k) =>
      [0, 1, 2, 3, 4].map((sp) => {
        const cv = makeCanvas(s, s);
        paintBlock(cv.getContext('2d'), s, col.hex, sp, settings.symbols ? k : -1);
        return cv;
      })
    );
    SPR.dead = [0, 1, 2, 3, 4].map((sp) => {
      const cv = makeCanvas(s, s);
      paintBlock(cv.getContext('2d'), s, DEAD, sp, -1);
      return cv;
    });
    SPR.ghost = COLORS.map((col) => {
      const cv = makeCanvas(s, s);
      const c = cv.getContext('2d');
      const g = s * 0.09;
      rr(c, g, g, s - 2 * g, s - 2 * g, s * 0.18);
      c.fillStyle = rgba(col.hex, 0.13);
      c.fill();
      c.lineWidth = Math.max(1.5, s * 0.055);
      c.strokeStyle = rgba(col.hex, 0.8);
      c.stroke();
      return cv;
    });
    SPR.glow = COLORS.map((col) => {
      const cv = makeCanvas(s * 2, s * 2);
      const c = cv.getContext('2d');
      const rg = c.createRadialGradient(s, s, s * 0.2, s, s, s);
      rg.addColorStop(0, rgba(col.hex, 0.75));
      rg.addColorStop(1, rgba(col.hex, 0));
      c.fillStyle = rg;
      c.fillRect(0, 0, s * 2, s * 2);
      return cv;
    });
    const wv = makeCanvas(s, s);
    const wc = wv.getContext('2d');
    rr(wc, s * 0.045, s * 0.045, s * 0.91, s * 0.91, s * 0.2);
    wc.fillStyle = '#ffffff';
    wc.fill();
    SPR.white = wv;
  }

  // ===================================================================
  // Static backgrounds
  // ===================================================================
  let bgMenu = null;
  let bgPlay = null;

  function paintBase(c) {
    const sky=c.createLinearGradient(0,0,W*.3,H);
    sky.addColorStop(0,'#169bff');sky.addColorStop(.48,'#72dcff');sky.addColorStop(1,'#c6a6ff');
    c.fillStyle=sky;c.fillRect(0,0,W,H);
    // Broad, simple cloud forms share the pieces' glossy shape language.
    for(const [x,y,r] of [[-.08,.23,.3],[1.12,.51,.38],[-.03,.88,.28],[.98,.97,.25]]) {
      const radius=W*r,g=c.createRadialGradient(W*x-radius*.25,H*y-radius*.3,0,W*x,H*y,radius);
      g.addColorStop(0,'rgba(255,255,255,.8)');g.addColorStop(.6,'rgba(239,236,255,.4)');g.addColorStop(1,'rgba(230,224,255,0)');
      c.fillStyle=g;c.beginPath();c.arc(W*x,H*y,radius,0,Math.PI*2);c.fill();
    }
    c.fillStyle='rgba(255,255,255,.55)';
    for(let k=0;k<18;k++){const x=((k*137.51)%W),y=((k*213.7+80)%H);c.beginPath();c.arc(x,y,k%3===0?2:1,0,Math.PI*2);c.fill();}
  }

  function tracked(c, text, x, y, spacing) {
    let cx = x;
    for (const ch of text) {
      c.fillText(ch, cx, y);
      cx += c.measureText(ch).width + spacing;
    }
  }

  function paintPanel(c, r, label) {
    c.save();
    c.shadowColor = 'rgba(49,13,108,.4)'; c.shadowBlur = 7; c.shadowOffsetY = 3;
    rr(c, r.x, r.y, r.w, r.h, Math.min(16, r.h * .22));
    const material = c.createLinearGradient(r.x, r.y, r.x+r.w, r.y+r.h);
    material.addColorStop(0, '#6648c9'); material.addColorStop(1, '#332277');
    c.fillStyle = material; c.fill(); c.shadowBlur=0; c.strokeStyle='rgba(255,220,255,.65)';c.lineWidth=1.5;c.stroke(); c.restore();
    if (label) {
      const fs = clamp(r.h * .13, 8.5, 11);
      c.font = '700 ' + fs + 'px ' + FU;
      c.fillStyle = '#ecdcff'; c.textBaseline = 'alphabetic';
      tracked(c, label, r.x + fs * .9, r.y + fs * 1.5, fs * .14);
    }
  }

  function buildBackgrounds() {
    bgMenu = makeCanvas(W * DPR, H * DPR);
    const m = bgMenu.getContext('2d');
    m.scale(DPR, DPR);
    paintBase(m);

    bgPlay = makeCanvas(W * DPR, H * DPR);
    const c = bgPlay.getContext('2d');
    c.scale(DPR, DPR);
    paintBase(c);
    const s = L.cell;
    const pad = Math.max(5, s * .22);
    c.save();
    c.shadowColor = 'rgba(176,31,255,.65)'; c.shadowBlur = s*.45; c.shadowOffsetY = s*.18;
    rr(c,L.bx-pad,L.by-pad,L.bw+pad*2,L.bh+pad*2,s*.4);
    const rim=c.createLinearGradient(L.bx,L.by,L.bx+L.bw,L.by+L.bh);
    rim.addColorStop(0,'#fff3af'); rim.addColorStop(.5,'#ff81e8'); rim.addColorStop(1,'#7b36bb');
    c.fillStyle=rim; c.fill();
    c.shadowBlur=0;c.lineWidth=2;c.strokeStyle='rgba(255,249,231,.85)';c.stroke();
    rr(c,L.bx-pad*.45,L.by-pad*.45,L.bw+pad*.9,L.bh+pad*.9,s*.27);
    c.lineWidth=Math.max(1,pad*.22);c.strokeStyle='rgba(114,31,148,.55)';c.stroke();c.restore();
    rr(c,L.bx-1,L.by-1,L.bw+2,L.bh+2,s*.2);
    c.fillStyle='#58256b'; c.fill();
    const well=c.createLinearGradient(0,L.by,0,L.by+L.bh);
    well.addColorStop(0,'#171d43'); well.addColorStop(.12,'#23234d'); well.addColorStop(1,'#35204f');
    rr(c,L.bx,L.by,L.bw,L.bh,s*.18); c.fillStyle=well; c.fill();
    c.strokeStyle='rgba(191,156,255,.13)'; c.lineWidth=1/DPR;
    for(let y=0;y<ROWS;y++) for(let x=0;x<COLS;x++) {
      rr(c,L.bx+x*s+s*.07,L.by+y*s+s*.07,s*.86,s*.86,s*.17); c.stroke();
    }
    paintPanel(c, L.hold, 'HOLD');
    paintPanel(c, L.next[0], 'NEXT');
    paintPanel(c, L.next[1], '');
    paintPanel(c, L.next[2], '');
  }

  // ===================================================================
  // App + game state
  // ===================================================================
  let game = null;
  let app = 'menu'; // menu | play | paused | dying | over
  let overT = 0;
  let sel = -1;
  let kcur = -1;
  let keyMode = false;
  let dirty = true;
  // Visual-only state for the falling piece: position easing, rotation tween, wall bump, spawn fade.
  const vis = { id: 0, x: 0, y: 0, rot: 0, bumpX: 0, bumpV: 0, wiggle: 0, wiggleV: 0, spawnT: 1 };
  // Small action animations: board thump, HUD pops. All scale with MOTION.
  const MOTION = reducedMotion ? 0 : 1;
  const anim = { kick: 0, kickV: 0, kickStyle: '', holdPop: 0, queuePop: 0, queueHead: null, scorePop: 0, levelPop: 0, pips: [1, 1, 1], tokens: -1 };
  const disp = { score: 0 };
  let firstGame = !store.get('pf.played', false);

  const fx = {
    particles: [],
    effects: [],
    texts: [],
    trails: [],
    banners: [],
    flashes: new Map(),
    pops: new Map(),
    shake: 0,
    rain: [],
    rainAcc: 0,
    tokenPulse: 0,
    failCells: null,
    failT: 0,
    squash: new Map(),
    hardLock: false,
  };
  function resetFx() {
    fx.particles.length = 0;
    fx.effects.length = 0;
    fx.texts.length = 0;
    fx.trails.length = 0;
    fx.banners.length = 0;
    fx.flashes.clear();
    fx.pops.clear();
    fx.squash.clear();
    fx.shake = 0;
    fx.hardLock = false;
    anim.kick = anim.kickV = anim.holdPop = anim.queuePop = anim.scorePop = anim.levelPop = 0;
    anim.queueHead = null;
    anim.tokens = -1;
  }

  // Damped spring toward zero; used for the wall bump, rotation wiggle and board thump.
  function spring(o, key, vkey, dt, k, c) {
    o[vkey] += (-k * o[key] - c * o[vkey]) * dt;
    o[key] += o[vkey] * dt;
    if (Math.abs(o[key]) < 1e-3 && Math.abs(o[vkey]) < 1e-2) o[key] = o[vkey] = 0;
  }
  function bumpWall(dir) {
    if (!MOTION || !game || game.phase !== 'fall') return;
    if (Math.abs(vis.bumpX) < 0.03 && Math.abs(vis.bumpV) < 0.6) {
      vis.bumpV = dir * 3.4;
      sfx.bump();
    }
  }
  function wiggle(dir) {
    if (!MOTION) return;
    vis.wiggleV = dir * 4.5;
    sfx.bump();
  }
  // a short puff where a hard-dropped shape hits
  function dust(x, y) {
    for (let k = 0; k < 3; k++) {
      fx.particles.push({
        x: x + (Math.random() - 0.5) * L.cell * 0.7,
        y,
        vx: (Math.random() - 0.5) * L.cell * 3.2,
        vy: -L.cell * (0.6 + Math.random() * 1.2),
        t: 0,
        life: 0.28 + Math.random() * 0.16,
        size: L.cell * (0.07 + Math.random() * 0.06),
        rot: 0,
        vr: 0,
        color: 'rgba(244,240,232,0.85)',
        g: 0.12,
        round: true,
      });
    }
  }

  const cellX = (i) => L.bx + (i % COLS) * L.cell;
  const cellY = (i) => L.by + ((i / COLS) | 0) * L.cell;

  function addText(text, x, y, o) {
    o = o || {};
    fx.texts.push({ text, x, y, t: 0, life: o.life || 1.0, size: o.size || L.cell * 0.55, color: o.color || '#ffffff', rise: o.rise == null ? L.cell * 1.4 : o.rise });
  }
  function addBanner(text, sub, color) {
    fx.banners = fx.banners.filter((b) => b.t < b.life * 0.6);
    fx.banners.push({ text, sub, color: color || '#ffffff', t: 0, life: 1.3 });
  }
  function shake(a) {
    if (reducedMotion) return;
    fx.shake = Math.max(fx.shake, a);
  }

  function burst(i, hex, n) {
    const x = cellX(i) + L.cell / 2;
    const y = cellY(i) + L.cell / 2;
    for (let k = 0; k < Math.ceil(n * 0.6); k++) {
      const a = Math.random() * Math.PI * 2;
      const sp = L.cell * (2 + Math.random() * 5);
      fx.particles.push({
        x,
        y,
        vx: Math.cos(a) * sp,
        vy: Math.sin(a) * sp - L.cell * 3,
        t: 0,
        life: 0.45 + Math.random() * 0.45,
        size: L.cell * (0.1 + Math.random() * 0.14),
        rot: Math.random() * 6,
        vr: (Math.random() - 0.5) * 14,
        color: Math.random() < 0.25 ? '#ffffff' : lighten(hex, 0.2),
      });
    }
    if (fx.particles.length > 700) fx.particles.splice(0, fx.particles.length - 700);
  }

  function lightningPath(x0, y0, x1, y1) {
    const pts = [[x0, y0]];
    const segs = 5;
    const dx = x1 - x0;
    const dy = y1 - y0;
    const len = Math.hypot(dx, dy) || 1;
    const nx = -dy / len;
    const ny = dx / len;
    for (let k = 1; k < segs; k++) {
      const t = k / segs;
      const off = (Math.random() - 0.5) * L.cell * 0.9;
      pts.push([x0 + dx * t + nx * off, y0 + dy * t + ny * off]);
    }
    pts.push([x1, y1]);
    return pts;
  }

  // ===================================================================
  // Game events -> sound, haptics, effects
  // ===================================================================
  function handleEvents() {
    const evs = game.drain();
    for (const e of evs) {
      switch (e.type) {
        case 'spawn':
          vis.id = e.piece.id;
          vis.x = e.piece.x;
          vis.y = e.piece.y;
          vis.rot = vis.wiggle = vis.wiggleV = vis.bumpX = vis.bumpV = 0;
          vis.spawnT = MOTION ? 0 : 1;
          if (game.queue[0] !== anim.queueHead) {
            anim.queueHead = game.queue[0];
            anim.queuePop = MOTION;
          }
          saveGame();
          break;
        case 'move':
          sfx.move();
          break;
        case 'rotate':
          sfx.rotate();
          // the cells are already turned; start the drawing a quarter turn back and ease it in
          if (MOTION) vis.rot = clamp(vis.rot - e.dir * (Math.PI / 2), -Math.PI, Math.PI);
          break;
        case 'land':
          sfx.land();
          break;
        case 'harddrop': {
          sfx.hard();
          anim.kickV = L.cell * 2.6 * MOTION;
          fx.hardLock = true;
          const p = e.piece;
          const bottoms = new Map();
          for (const c of p.cells) {
            fx.trails.push({ x: p.x + c.x, y0: e.fromY + c.y, y1: p.y + c.y, c: c.c, t: 0 });
            const bx = p.x + c.x;
            bottoms.set(bx, Math.max(bottoms.has(bx) ? bottoms.get(bx) : -99, p.y + c.y));
          }
          if (MOTION && e.dist > 0) for (const [bx, by] of bottoms) dust(L.bx + (bx + 0.5) * L.cell, L.by + (by + 1) * L.cell);
          break;
        }
        case 'lock': {
          sfx.lock();
          const now = performance.now();
          const amp = (fx.hardLock ? 0.2 : 0.12) * MOTION;
          fx.hardLock = false;
          for (const i of e.cells) {
            if (!game.board[i]) continue;
            fx.flashes.set(game.board[i].id, now);
            if (amp) fx.squash.set(game.board[i].id, { t: now, amp });
          }
          break;
        }
        case 'hold':
          sfx.hold();
          anim.holdPop = MOTION;
          break;
        case 'clear':
          onClear(e);
          break;
        case 'cleared': {
          const n = clamp(Math.round(160 / Math.max(1, e.removed.length)), 2, 8);
          for (const r of e.removed) burst(r.i, COLORS[r.c].hex, n);
          const now = performance.now();
          for (const m of e.made) fx.pops.set(m.id, now);
          break;
        }
        case 'levelup': {
          sfx.level();
          anim.levelPop = 1;
          const sub = e.newColor ? 'New color: ' + COLORS[game.paletteSize() - 1].name : 'Faster drops';
          addBanner('LEVEL ' + e.level, sub, '#ffffff');
          break;
        }
        case 'swapGained':
          sfx.token();
          fx.tokenPulse = 1;
          addText('+' + e.count + ' SWAP', L.bx + L.bw / 2, L.by + L.bh * 0.32, { color: GOLD, size: L.cell * 0.5 });
          break;
        case 'swapPhase':
          sfx.swapOpen();
          sel = -1;
          if (keyMode) kcur = nearestLegal(kcur);
          break;
        case 'swap':
          sfx.swap();
          Haptics.tap();
          break;
        case 'swapFail':
          sfx.fail();
          fx.failCells = [e.from, e.to];
          fx.failT = 0;
          break;
        case 'swapSkip':
        case 'swapTimeout':
          sel = -1;
          break;
        case 'gameover':
          onGameOver();
          break;
      }
    }
  }

  function onClear(e) {
    sfx.clear(e.chain);
    anim.scorePop = 1;
    if (e.cells.length >= 6 || e.chain >= 2) Haptics.tap();
    let sx = 0;
    let sy = 0;
    for (const c of e.cells) {
      sx += cellX(c.i);
      sy += cellY(c.i);
    }
    const n = Math.max(1, e.cells.length);
    const mx = sx / n + L.cell / 2;
    const my = sy / n + L.cell / 2;
    addText('+' + fmt(e.points), mx, my, { size: clamp(L.cell * (0.45 + e.chain * 0.06), 12, 34) });
    if (e.combo) {
      addBanner(COMBO_NAMES[e.combo] || 'COMBO', 'Special swap', GOLD);
      shake(L.cell * 0.35);
    } else if (e.chain >= 2) {
      addBanner('CHAIN ×' + e.chain, e.chain >= 3 ? 'Cascade!' : '', e.chain >= 4 ? GOLD : '#ffffff');
    }
    if (e.created.length) {
      sfx.special();
      for (const sp of e.created) {
        addText(SPECIAL_NAMES[sp.s], cellX(sp.idx) + L.cell / 2, cellY(sp.idx), { color: lighten(COLORS[sp.c].hex, 0.35), size: L.cell * 0.42, life: 0.9 });
      }
    }
    let line = false;
    let bomb = false;
    let prism = false;
    const now = performance.now();
    for (const ef of e.effects) {
      const item = Object.assign({ t0: now }, ef);
      if (ef.t === 'lineH' || ef.t === 'lineV') line = true;
      if (ef.t === 'bomb') bomb = true;
      if (ef.t === 'prism') {
        prism = true;
        const x0 = (ef.x + 0.5) * L.cell;
        const y0 = (ef.y + 0.5) * L.cell;
        item.paths = ef.targets.slice(0, 48).map((k) => lightningPath(x0, y0, ((k % COLS) + 0.5) * L.cell, (((k / COLS) | 0) + 0.5) * L.cell));
      }
      fx.effects.push(item);
    }
    if (line) {
      sfx.line();
      shake(L.cell * 0.15);
    }
    if (bomb) {
      sfx.bomb();
      shake(L.cell * 0.3);
    }
    if (prism) {
      sfx.prism();
      shake(L.cell * 0.25);
    }
    if (e.chain >= 3) shake(L.cell * 0.08 * e.chain);
  }

  // ===================================================================
  // Rendering
  // ===================================================================
  // `pop` runs 0 -> 1 after a change; the shape grows in with a little overshoot.
  function drawPieceIn(r, def, alpha, labelSpace, pop) {
    if (!def) return;
    const t = pop == null ? 1 : clamp(pop, 0, 1);
    if (t <= 0) return;
    const sc = t >= 1 ? 1 : 0.55 + 0.45 * easeOutBack(t);
    const sh = PF.SHAPES[def.type];
    const xs = sh.cells.map((c) => c[0]);
    const ys = sh.cells.map((c) => c[1]);
    const minX = Math.min.apply(null, xs);
    const maxX = Math.max.apply(null, xs);
    const minY = Math.min.apply(null, ys);
    const maxY = Math.max.apply(null, ys);
    const cw = maxX - minX + 1;
    const ch = maxY - minY + 1;
    const top = labelSpace ? r.h * 0.16 : 0;
    const s = Math.min((r.w * 0.78) / Math.max(cw, 3), ((r.h - top) * 0.72) / Math.max(ch, 2), L.cell * 0.9);
    const ox = r.x + (r.w - cw * s) / 2;
    const oy = r.y + top + (r.h - top - ch * s) / 2;
    ctx.save();
    if (sc !== 1) {
      const mx = ox + (cw * s) / 2;
      const my = oy + (ch * s) / 2;
      ctx.translate(mx, my);
      ctx.scale(sc, sc);
      ctx.translate(-mx, -my);
    }
    ctx.globalAlpha = alpha * Math.min(1, t * 1.6);
    sh.cells.forEach((c, k) => {
      ctx.drawImage(SPR.blocks[def.colors[k]][0], ox + (c[0] - minX) * s, oy + (c[1] - minY) * s, s, s);
    });
    ctx.restore();
  }

  function fitFont(text, weight, family, size, maxW) {
    ctx.font = weight + ' ' + size + 'px ' + family;
    const w = ctx.measureText(text).width;
    if (w > maxW) {
      size = Math.max(8, (size * maxW) / w);
      ctx.font = weight + ' ' + size + 'px ' + family;
    }
    return size;
  }

  function drawSwapIcon(x, y, s, color) {
    ctx.save();
    ctx.strokeStyle = color;
    ctx.fillStyle = color;
    ctx.lineWidth = Math.max(1.4, s * 0.13);
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(x - s * 0.45, y - s * 0.2);
    ctx.lineTo(x + s * 0.35, y - s * 0.2);
    ctx.moveTo(x + s * 0.45, y + s * 0.2);
    ctx.lineTo(x - s * 0.35, y + s * 0.2);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(x + s * 0.5, y - s * 0.2);
    ctx.lineTo(x + s * 0.22, y - s * 0.44);
    ctx.lineTo(x + s * 0.22, y + s * 0.04);
    ctx.closePath();
    ctx.moveTo(x - s * 0.5, y + s * 0.2);
    ctx.lineTo(x - s * 0.22, y - s * 0.04);
    ctx.lineTo(x - s * 0.22, y + s * 0.44);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  function drawPip(x, y, r, filled) {
    ctx.beginPath();
    ctx.moveTo(x, y - r);
    ctx.lineTo(x + r, y);
    ctx.lineTo(x, y + r);
    ctx.lineTo(x - r, y);
    ctx.closePath();
    if (filled) {
      ctx.fillStyle = '#684100';
      ctx.fill();
    } else {
      ctx.strokeStyle = 'rgba(139,102,30,0.45)';
      ctx.lineWidth = 1.2;
      ctx.stroke();
    }
  }

  function drawLevelPill(x, y, w, h) {
    const pulse = MOTION ? Math.sin(Math.PI * (1 - anim.levelPop)) * Math.min(1, anim.levelPop * 3) : 0;
    ctx.save();
    if (pulse > 0.001) {
      ctx.translate(x + w / 2, y + h / 2);
      ctx.scale(1 + 0.1 * pulse, 1 + 0.1 * pulse);
      ctx.translate(-(x + w / 2), -(y + h / 2));
    }
    rr(ctx, x, y, w, h, h / 2);
    ctx.fillStyle = 'rgba(64,79,85,' + (0.055 + 0.12 * anim.levelPop) + ')';
    ctx.fill();
    const fs = h * 0.5;
    ctx.textBaseline = 'middle';
    ctx.font = '700 ' + fs * 0.85 + 'px ' + FU;
    ctx.fillStyle = '#40316b';
    ctx.fillText('LV', x + h * 0.45, y + h * 0.48);
    const lw = ctx.measureText('LV').width;
    ctx.font = '700 ' + fs + 'px ' + FD;
    ctx.fillStyle = '#322163';
    ctx.fillText(String(game.level), x + h * 0.45 + lw + 4, y + h * 0.5);
    const bx = x + w * 0.55;
    const bw = w * 0.45 - h * 0.45;
    rr(ctx, bx, y + h / 2 - 2, bw, 4, 2);
    ctx.fillStyle = 'rgba(64,79,85,0.12)';
    ctx.fill();
    const p = game.levelProgress();
    if (p > 0) {
      const g = ctx.createLinearGradient(bx, 0, bx + bw, 0);
      g.addColorStop(0, '#ec31ff');
      g.addColorStop(0.5, '#ec31ff');
      g.addColorStop(1, '#7435ff');
      rr(ctx, bx, y + h / 2 - 2, Math.max(4, bw * p), 4, 2);
      ctx.fillStyle = g;
      ctx.fill();
    }
    ctx.textBaseline = 'alphabetic';
    ctx.restore();
  }

  function drawSwapPill(x, y, w, h) {
    rr(ctx, x, y, w, h, h / 2);
    ctx.fillStyle = 'rgba(139,102,30,' + (0.07 + fx.tokenPulse * 0.25) + ')';
    ctx.fill();
    drawSwapIcon(x + h * 0.62, y + h * 0.48, h * 0.6, '#684100');
    const pr = h * 0.18;
    const px0 = x + h * 1.3;
    for (let k = 0; k < PF.MAX_TOKENS; k++) {
      const filled = k < game.tokens;
      const t = filled ? clamp(anim.pips[k], 0, 1) : 1;
      if (filled && t < 1) drawPip(px0 + k * pr * 2.7, y + h * 0.42, pr, false);
      drawPip(px0 + k * pr * 2.7, y + h * 0.42, pr * (t < 1 ? easeOutBack(t) * 1.15 : 1), filled);
    }
    const mx = px0 - pr;
    const mw = x + w - h * 0.4 - mx;
    rr(ctx, mx, y + h * 0.74, mw, 2.5, 1.25);
    ctx.fillStyle = 'rgba(139,102,30,0.16)';
    ctx.fill();
    const mp = game.tokens >= PF.MAX_TOKENS ? 1 : game.meter / PF.METER_MAX;
    if (mp > 0) {
      rr(ctx, mx, y + h * 0.74, Math.max(2.5, mw * mp), 2.5, 1.25);
      ctx.fillStyle = '#684100';
      ctx.fill();
    }
  }

  // Score text swells briefly when points land, anchored at its left baseline.
  function drawScoreText(text, x, y) {
    const pop = MOTION ? Math.sin(Math.PI * (1 - anim.scorePop)) * anim.scorePop : 0;
    if (pop <= 0.001) {
      ctx.fillText(text, x, y);
      return;
    }
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(1 + 0.12 * pop, 1 + 0.12 * pop);
    ctx.fillText(text, 0, 0);
    ctx.restore();
  }

  function drawHUD() {
    drawPieceIn(L.hold, game.hold, game.holdUsed ? 0.3 : 1, true, 1 - anim.holdPop);
    // the queue shuffles forward in a quick stagger after each spawn
    const qp = 1 - anim.queuePop;
    for (let k = 0; k < 3; k++) drawPieceIn(L.next[k], game.queue[k], [1, 0.85, 0.7][k], k === 0, qp * 1.35 - k * 0.17);

    const I = L.info;
    const scoreText = fmt(disp.score);
    ctx.textBaseline = 'alphabetic';
    if (L.portrait) {
      const lf = clamp(I.h * 0.13, 8.5, 11);
      ctx.font = '700 ' + lf + 'px ' + FU;
      ctx.fillStyle = '#40316b';
      tracked(ctx, 'SCORE', I.x, I.y + lf * 1.3, lf * 0.14);
      const size = fitFont(scoreText, '700', FD, clamp(I.h * 0.36, 18, 32), I.w - 42);
      ctx.fillStyle = '#322163';
      drawScoreText(scoreText, I.x, I.y + lf * 1.5 + size * 1.05);
      const ph = clamp(I.h * 0.28, 17, 24);
      const py = I.y + I.h - ph;
      const lw = I.w * 0.44;
      drawLevelPill(I.x, py, lw, ph);
      drawSwapPill(I.x + lw + 6, py, I.w - lw - 6, ph);
    } else {
      const lf = 11;
      let y = I.y;
      ctx.font = '700 ' + lf + 'px ' + FU;
      ctx.fillStyle = '#40316b';
      tracked(ctx, 'SCORE', I.x + 2, y + 12, 1.5);
      const size = fitFont(scoreText, '700', FD, 26, I.w);
      ctx.fillStyle = '#322163';
      drawScoreText(scoreText, I.x + 2, y + 16 + size);
      y += 24 + size + 14;
      drawLevelPill(I.x, y, I.w, 26);
      y += 36;
      drawSwapPill(I.x, y, I.w, 26);
      y += 40;
      ctx.font = '600 11px ' + FU;
      ctx.fillStyle = '#40316b';
      ctx.fillText('Blocks ' + fmt(game.cleared), I.x + 2, y + 6);
    }
  }

  // Draws a block scaled about its center; `sq` squashes it onto its bottom edge (landing impact).
  function cellRect(x, y, s, scale, sq) {
    const w = s * scale * (1 + sq * 0.6);
    const h = s * scale * (1 - sq);
    return [x + (s - w) / 2, y + (s + s * scale) / 2 - h, w, h];
  }
  function drawCellAt(c, x, y, s, scale, deadNow, sq) {
    const spr = deadNow ? SPR.dead[c.s] : SPR.blocks[c.c][c.s];
    if (scale === 1 && !sq) ctx.drawImage(spr, x, y, s, s);
    else {
      const r = cellRect(x, y, s, scale, sq || 0);
      ctx.drawImage(spr, r[0], r[1], r[2], r[3]);
    }
  }

  function drawBoard(now, dt) {
    const g = game;
    const s = L.cell;
    let ox = 0;
    let oy = 0;
    if (fx.shake > 0.2) {
      ox = (Math.random() - 0.5) * fx.shake;
      oy = (Math.random() - 0.5) * fx.shake;
    }
    ctx.save();
    ctx.translate(L.bx + ox, L.by + oy);

    const swapPhase = g.phase === 'swap' || g.phase === 'swapBack';
    if (swapPhase) {
      const pulse = 0.5 + 0.5 * Math.sin(now / 160);
      rr(ctx, -2, -2, L.bw + 4, L.bh + 4, s * 0.2);
      ctx.strokeStyle = 'rgba(255,214,107,' + (0.35 + 0.35 * pulse) + ')';
      ctx.lineWidth = 2;
      ctx.stroke();
    }

    ctx.save();
    ctx.beginPath();
    ctx.rect(0, 0, L.bw, L.bh);
    ctx.clip();

    // danger glow near the top
    const hi = g.highestRow();
    if (hi <= 3 && app !== 'menu') {
      const a = (0.18 + 0.12 * Math.sin(now / 180)) * (1 - hi / 4);
      const dg = ctx.createLinearGradient(0, 0, 0, s * 3);
      dg.addColorStop(0, 'rgba(255,40,80,' + a + ')');
      dg.addColorStop(1, 'rgba(255,40,80,0)');
      ctx.fillStyle = dg;
      ctx.fillRect(0, 0, L.bw, s * 3);
    }

    // column guides under the falling piece
    const p = g.phase === 'fall' ? g.piece : null;
    if (p) {
      const gy = g.ghostY();
      const cols = new Map();
      for (const c of p.cells) {
        const x = p.x + c.x;
        const yb = gy + c.y;
        if (!cols.has(x) || cols.get(x) < yb) cols.set(x, yb);
      }
      for (const [x, yb] of cols) {
        const top = Math.max(0, (vis.y + 1) * s);
        const gr = ctx.createLinearGradient(0, top, 0, (yb + 1) * s);
        gr.addColorStop(0, 'rgba(255,255,255,0)');
        gr.addColorStop(1, 'rgba(255,255,255,0.05)');
        ctx.fillStyle = gr;
        ctx.fillRect(x * s, top, s, (yb + 1) * s - top);
      }
    }

    // hard drop trails
    for (const tr of fx.trails) {
      const a = 1 - tr.t / 0.22;
      if (a <= 0) continue;
      const y0 = tr.y0 * s;
      const y1 = (tr.y1 + 1) * s;
      const gr = ctx.createLinearGradient(0, y0, 0, y1);
      gr.addColorStop(0, rgba(COLORS[tr.c].hex, 0));
      gr.addColorStop(1, rgba(COLORS[tr.c].hex, 0.35 * a));
      ctx.fillStyle = gr;
      ctx.fillRect(tr.x * s + s * 0.15, y0, s * 0.7, y1 - y0);
    }

    // board cells
    const clearing = g.phase === 'clear' ? g.clearing : null;
    const cp = clearing ? 1 - g.timer / g.phaseDur : 0;
    const dropping = g.phase === 'drop';
    const swapping = g.phase === 'swapAnim' || g.phase === 'swapBack';
    let sp = swapping ? clamp(1 - g.timer / g.phaseDur, 0, 1) : 0;
    if (g.phase === 'swapBack') sp = sp < 0.5 ? sp * 2 : (1 - sp) * 2;
    const spE = easeOutCubic(sp);
    const dyingRows = app === 'dying' || app === 'over' ? Math.floor((overT / 0.9) * ROWS) : -1;
    const pulse = 0.5 + 0.5 * Math.sin(now / 220);
    // lift over the whole move: out and back for an illegal swap, across for a legal one
    const arc = swapping ? Math.sin(Math.PI * clamp(1 - g.timer / g.phaseDur, 0, 1)) * MOTION : 0;
    // the block the player moved; it is drawn last so it passes over its partner
    const movedIdx = g.phase === 'swapAnim' ? g.swapB : g.phase === 'swapBack' ? g.swapA : -1;
    let deferred = null;

    for (let i = 0; i < COLS * ROWS; i++) {
      const c = g.board[i];
      if (!c) continue;
      const col = i % COLS;
      const row = (i / COLS) | 0;
      let x = col * s;
      let y = row * s;
      if (dropping && c.fall) {
        const off = Math.max(0, c.fall - 0.5 * T.DROP_ACCEL * g.dropT * g.dropT);
        y -= off * s;
        // small rebound once it lands
        const tLand = Math.sqrt((2 * c.fall) / T.DROP_ACCEL);
        const u = (g.dropT - tLand) / 0.1;
        if (u > 0 && u < 1) y -= Math.sin(u * Math.PI) * s * 0.06 * Math.min(1, c.fall / 2) * MOTION;
      }
      if (swapping && (i === g.swapA || i === g.swapB)) {
        let from;
        let to;
        if (g.phase === 'swapAnim') {
          from = i === g.swapA ? g.swapB : g.swapA;
          to = i;
        } else {
          from = i;
          to = i === g.swapA ? g.swapB : g.swapA;
        }
        x = lerp((from % COLS) * s, (to % COLS) * s, spE);
        y = lerp(((from / COLS) | 0) * s, ((to / COLS) | 0) * s, spE);
      }
      let scale = 1;
      let flash = 0;
      let sq = 0;
      if (swapping && (i === g.swapA || i === g.swapB)) scale = i === movedIdx ? 1 + 0.13 * arc : 1 - 0.08 * arc;
      if (clearing && clearing.cells.has(i)) {
        if (cp < 0.3) {
          scale = 1 + 0.14 * (cp / 0.3);
          flash = cp / 0.3;
        } else {
          const q = (cp - 0.3) / 0.7;
          scale = 1.14 * (1 - q * q);
          flash = 1 - q * 0.6;
        }
      }
      const popT = fx.pops.get(c.id);
      if (popT !== undefined) {
        const q = (now - popT) / 280;
        if (q >= 1) fx.pops.delete(c.id);
        else scale *= q < 0.6 ? easeOutBack(q / 0.6) * 1.05 : 1.05 - 0.05 * ((q - 0.6) / 0.4);
      }
      const lockT = fx.flashes.get(c.id);
      if (lockT !== undefined) {
        const q = (now - lockT) / 200;
        if (q >= 1) fx.flashes.delete(c.id);
        else flash = Math.max(flash, 0.55 * (1 - q));
      }
      const squash = fx.squash.get(c.id);
      if (squash) {
        const q = (now - squash.t) / 240;
        if (q >= 1) fx.squash.delete(c.id);
        else sq = squash.amp * Math.sin(q * Math.PI * 1.5) * (1 - q);
      }
      if (fx.failCells && fx.failT < 0.3 && (i === fx.failCells[0] || i === fx.failCells[1]) && g.phase !== 'swapBack') {
        x += Math.sin(fx.failT * 60) * s * 0.08 * (1 - fx.failT / 0.3);
      }
      if (i === sel && g.phase === 'swap') scale *= 1.08 + 0.025 * Math.sin(now / 130) * MOTION;
      // special glow
      if (c.s && !(clearing && clearing.cells.has(i))) {
        ctx.globalAlpha = 0.35 + 0.35 * pulse;
        ctx.drawImage(SPR.glow[c.c], x - s * 0.5, y - s * 0.5, s * 2, s * 2);
        ctx.globalAlpha = 1;
      }
      const deadNow = dyingRows >= 0 && ROWS - 1 - row < dyingRows;
      if (i === movedIdx) {
        deferred = [c, x, y, scale, deadNow, flash];
        continue;
      }
      drawCellAt(c, x, y, s, scale, deadNow, sq);
      if (flash > 0.01) {
        ctx.globalAlpha = flash * 0.85;
        const r = cellRect(x, y, s, scale, sq);
        ctx.drawImage(SPR.white, r[0], r[1], r[2], r[3]);
        ctx.globalAlpha = 1;
      }
    }
    if (deferred) {
      const [c, x, y, scale, deadNow] = deferred;
      // soft contact shadow under the lifted block
      ctx.globalAlpha = 0.25 * arc;
      ctx.fillStyle = '#10181e';
      rr(ctx, x + s * 0.12, y + s * 0.2, s * 0.8, s * 0.8, s * 0.2);
      ctx.fill();
      ctx.globalAlpha = 1;
      drawCellAt(c, x, y - s * 0.06 * arc, s, scale, deadNow, 0);
    }

    // specials about to be created
    if (clearing) {
      for (const cr of clearing.created) {
        const x = (cr.idx % COLS) * s;
        const y = ((cr.idx / COLS) | 0) * s;
        ctx.globalAlpha = cp;
        ctx.drawImage(SPR.glow[cr.c], x - s * 0.5, y - s * 0.5, s * 2, s * 2);
        ctx.globalAlpha = 1;
      }
    }

    // ghost and falling piece
    if (p) {
      if (vis.id !== p.id) {
        vis.id = p.id;
        vis.x = p.x;
        vis.y = p.y;
      }
      const k = Math.min(1, dt * 32);
      vis.x += (p.x - vis.x) * k;
      vis.y += (p.y - vis.y) * Math.min(1, dt * 38);
      if (Math.abs(p.x - vis.x) < 0.02) vis.x = p.x;
      if (Math.abs(p.y - vis.y) < 0.02) vis.y = p.y;
      if (settings.ghost) {
        const gy = g.ghostY();
        if (gy !== p.y) for (const c of p.cells) ctx.drawImage(SPR.ghost[c.c], (p.x + c.x) * s, (gy + c.y) * s, s, s);
      }
      const lockGlow = g.grounded ? clamp(g.lockTimer / T.LOCK_DELAY, 0, 1) : 0;
      const n = PF.SHAPES[p.type].n;
      const appear = easeOutCubic(clamp(vis.spawnT, 0, 1));
      const ox = (vis.x + vis.bumpX) * s;
      const oy = (vis.y - (1 - appear) * 0.6) * s;
      const ang = vis.rot + vis.wiggle;
      const cosA = Math.cos(ang);
      const sinA = Math.sin(ang);
      const half = (n * s) / 2;
      const alpha = 0.25 + 0.75 * appear;
      for (const c of p.cells) {
        // rotate each cell center about the shape's box center (the SRS pivot)
        const dx = (c.x + 0.5) * s - half;
        const dy = (c.y + 0.5) * s - half;
        const cx = ox + half + dx * cosA - dy * sinA;
        const cy = oy + half + dx * sinA + dy * cosA;
        ctx.save();
        ctx.translate(cx, cy);
        if (ang) ctx.rotate(ang);
        ctx.globalAlpha = alpha * .22;
        ctx.drawImage(SPR.glow[c.c], -s, -s, s * 2, s * 2);
        ctx.globalAlpha = alpha;
        ctx.drawImage(SPR.blocks[c.c][0], -s / 2, -s / 2, s, s);
        if (lockGlow > 0) {
          ctx.globalAlpha = lockGlow * 0.3;
          ctx.drawImage(SPR.white, -s / 2, -s / 2, s, s);
        }
        ctx.restore();
      }
    }

    // swap phase highlights
    if (swapPhase) {
      ctx.lineWidth = Math.max(1.5, s * 0.06);
      const a = 0.22 + 0.3 * pulse;
      for (const i of g.legalCells) {
        if (i === sel) continue;
        rr(ctx, (i % COLS) * s + 2, ((i / COLS) | 0) * s + 2, s - 4, s - 4, s * 0.2);
        ctx.strokeStyle = 'rgba(255,255,255,' + a + ')';
        ctx.stroke();
      }
      if (sel >= 0 && g.board[sel]) {
        const sx = (sel % COLS) * s;
        const sy = ((sel / COLS) | 0) * s;
        rr(ctx, sx - 1, sy - 1, s + 2, s + 2, s * 0.24);
        ctx.strokeStyle = '#ffffff';
        ctx.lineWidth = Math.max(2, s * 0.08);
        ctx.stroke();
        for (const j of g.partnersOf(sel)) {
          const jx = (j % COLS) * s;
          const jy = ((j / COLS) | 0) * s;
          rr(ctx, jx + 1, jy + 1, s - 2, s - 2, s * 0.22);
          ctx.strokeStyle = GOLD;
          ctx.lineWidth = Math.max(2, s * 0.07);
          ctx.stroke();
          // chevron pointing from the selection toward the partner
          const mx = (sx + jx) / 2 + s / 2;
          const my = (sy + jy) / 2 + s / 2;
          const ang = Math.atan2(jy - sy, jx - sx);
          ctx.save();
          ctx.translate(mx, my);
          ctx.rotate(ang);
          ctx.beginPath();
          ctx.moveTo(-s * 0.1, -s * 0.16);
          ctx.lineTo(s * 0.08, 0);
          ctx.lineTo(-s * 0.1, s * 0.16);
          ctx.strokeStyle = '#ffffff';
          ctx.lineWidth = Math.max(2, s * 0.07);
          ctx.lineCap = 'round';
          ctx.lineJoin = 'round';
          ctx.stroke();
          ctx.restore();
        }
      }
      if (keyMode && kcur >= 0) {
        ctx.setLineDash([s * 0.18, s * 0.12]);
        rr(ctx, (kcur % COLS) * s + 1, ((kcur / COLS) | 0) * s + 1, s - 2, s - 2, s * 0.22);
        ctx.strokeStyle = '#9fd4ff';
        ctx.lineWidth = Math.max(2, s * 0.07);
        ctx.stroke();
        ctx.setLineDash([]);
      }
      if (g.stats.swaps < 3 && hi >= 3) {
        ctx.textAlign = 'center';
        ctx.font = '600 ' + clamp(s * 0.36, 11, 15) + 'px ' + FU;
        ctx.fillStyle = 'rgba(230,232,255,0.75)';
        ctx.fillText('Tap a glowing block, then a neighbor', L.bw / 2, s * 1.35);
        ctx.fillStyle = 'rgba(230,232,255,0.5)';
        ctx.fillText('Tap empty space to skip', L.bw / 2, s * 1.95);
        ctx.textAlign = 'left';
      }
    }

    // first-game control hints, kept just above the stack
    const ghostTop = p ? g.ghostY() + Math.min.apply(null, p.cells.map((c) => c.y)) : ROWS;
    const hintBase = Math.min(L.bh - s * 0.5, Math.min(hi, ghostTop) * s - s * 0.6);
    if (firstGame && p && g.stats.pieces < 4 && hintBase > s * 4) {
      const base = hintBase;
      ctx.font = '600 ' + clamp(s * 0.34, 10, 14) + 'px ' + FU;
      ctx.fillStyle = 'rgba(230,232,255,0.45)';
      if (coarsePointer) {
        ctx.textAlign = 'left';
        ctx.fillText('⟲ tap left', s * 0.4, base);
        ctx.textAlign = 'right';
        ctx.fillText('tap right ⟳', L.bw - s * 0.4, base);
        ctx.textAlign = 'center';
        ctx.fillText('drag to move · flick down to drop', L.bw / 2, base - s * 0.7);
      } else {
        ctx.textAlign = 'center';
        ctx.fillText('← → move · ↑ rotate · Space drop', L.bw / 2, base);
        ctx.fillText('C hold · P pause', L.bw / 2, base - s * 0.7);
      }
      ctx.textAlign = 'left';
    }

    drawEffects(now);
    ctx.restore(); // clip

    ctx.restore();

    if (swapPhase) drawSwapBanner(now);
  }

  function drawEffects(now) {
    const s = L.cell;
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    fx.effects = fx.effects.filter((e) => {
      const t = (now - e.t0) / 1000;
      if (e.t === 'lineH' || e.t === 'lineV') {
        const life = 0.45;
        if (t > life) return false;
        const q = t / life;
        const th = s * (e.wide ? 1.0 : 0.9) * (1 - q) + 2;
        const col = COLORS[e.c].hex;
        ctx.globalAlpha = 1 - q;
        if (e.t === 'lineH') {
          if (e.y < 0 || e.y >= ROWS) return true;
          const y = (e.y + 0.5) * s;
          ctx.fillStyle = rgba(col, 0.7);
          ctx.fillRect(0, y - th / 2, L.bw, th);
          ctx.fillStyle = '#ffffff';
          ctx.fillRect(0, y - th / 6, L.bw, th / 3);
        } else {
          if (e.x < 0 || e.x >= COLS) return true;
          const x = (e.x + 0.5) * s;
          ctx.fillStyle = rgba(col, 0.7);
          ctx.fillRect(x - th / 2, 0, th, L.bh);
          ctx.fillStyle = '#ffffff';
          ctx.fillRect(x - th / 6, 0, th / 3, L.bh);
        }
        return true;
      }
      if (e.t === 'bomb') {
        const life = 0.55;
        if (t > life) return false;
        const q = t / life;
        const x = (e.x + 0.5) * s;
        const y = (e.y + 0.5) * s;
        const R = s * (e.r + 0.7) * (0.4 + 1.2 * easeOutCubic(q));
        ctx.globalAlpha = (1 - q) * 0.9;
        const rg = ctx.createRadialGradient(x, y, 0, x, y, R);
        rg.addColorStop(0, 'rgba(255,255,255,0.9)');
        rg.addColorStop(0.5, rgba(COLORS[e.c].hex, 0.55));
        rg.addColorStop(1, rgba(COLORS[e.c].hex, 0));
        ctx.fillStyle = rg;
        ctx.beginPath();
        ctx.arc(x, y, R, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = 'rgba(255,255,255,0.8)';
        ctx.lineWidth = s * 0.12 * (1 - q) + 1;
        ctx.beginPath();
        ctx.arc(x, y, R * 1.05, 0, Math.PI * 2);
        ctx.stroke();
        return true;
      }
      if (e.t === 'prism') {
        const life = 0.6;
        if (t > life) return false;
        const q = t / life;
        const col = COLORS[e.c].hex;
        ctx.globalAlpha = 1 - q;
        ctx.lineJoin = 'round';
        for (const path of e.paths) {
          ctx.beginPath();
          ctx.moveTo(path[0][0], path[0][1]);
          for (let k = 1; k < path.length; k++) ctx.lineTo(path[k][0], path[k][1]);
          ctx.strokeStyle = rgba(col, 0.55);
          ctx.lineWidth = s * 0.16;
          ctx.stroke();
          ctx.strokeStyle = '#ffffff';
          ctx.lineWidth = Math.max(1, s * 0.05);
          ctx.stroke();
        }
        const x = (e.x + 0.5) * s;
        const y = (e.y + 0.5) * s;
        const R = s * (0.8 + q * 1.6);
        const rg = ctx.createRadialGradient(x, y, 0, x, y, R);
        rg.addColorStop(0, 'rgba(255,255,255,0.95)');
        rg.addColorStop(1, rgba(col, 0));
        ctx.fillStyle = rg;
        ctx.beginPath();
        ctx.arc(x, y, R, 0, Math.PI * 2);
        ctx.fill();
        return true;
      }
      return false;
    });
    ctx.restore();
  }

  function drawSwapBanner(now) {
    const g = game;
    const h = clamp(L.cell * 0.66, 22, 30);
    const w = Math.min(L.bw * 0.8, 250);
    const x = L.bx + (L.bw - w) / 2;
    const y = L.by - h * 0.3;
    rr(ctx, x, y, w, h, h / 2);
    ctx.fillStyle = 'rgba(24,18,46,0.94)';
    ctx.fill();
    ctx.strokeStyle = 'rgba(255,214,107,0.7)';
    ctx.lineWidth = 1.5;
    ctx.stroke();
    const n = g.swapsAvailable();
    const label = n > 1 ? 'SWAP  ×' + n : 'SWAP';
    drawSwapIcon(x + h * 0.7, y + h / 2, h * 0.55, GOLD);
    ctx.font = '800 ' + h * 0.5 + 'px ' + FU;
    ctx.fillStyle = '#fff3d1';
    ctx.textBaseline = 'middle';
    ctx.textAlign = 'center';
    ctx.fillText(label, x + w / 2 + h * 0.3, y + h / 2 + 0.5);
    ctx.textAlign = 'left';
    ctx.textBaseline = 'alphabetic';
    if (g.phase === 'swap' && isFinite(g.phaseDur)) {
      const q = clamp(g.timer / g.phaseDur, 0, 1);
      rr(ctx, x + h * 0.5, y + h - 4, (w - h) * q, 2.5, 1.25);
      ctx.fillStyle = q < 0.3 && Math.sin(now / 70) > 0 ? '#ff7a7a' : GOLD;
      ctx.fill();
    }
  }

  function drawOverlayFx(dt) {
    // particles
    for (const p of fx.particles) {
      const a = 1 - p.t / p.life;
      if (a <= 0) continue;
      ctx.globalAlpha = a;
      ctx.fillStyle = p.color;
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.rotate(p.rot);
      rr(ctx, -p.size / 2, -p.size / 2, p.size, p.size, p.round ? p.size / 2 : p.size * .35);
      ctx.fill();
      ctx.restore();
    }
    ctx.globalAlpha = 1;
    // floating texts
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    for (const t of fx.texts) {
      const q = t.t / t.life;
      if (q >= 1) continue;
      const a = q < 0.7 ? 1 : 1 - (q - 0.7) / 0.3;
      const sc = q < 0.12 ? easeOutBack(q / 0.12) : 1;
      const y = t.y - t.rise * easeOutCubic(q);
      ctx.globalAlpha = a;
      ctx.font = '800 ' + t.size * sc + 'px ' + FD;
      ctx.lineWidth = t.size * 0.2;
      ctx.strokeStyle = 'rgba(8,8,24,0.75)';
      ctx.lineJoin = 'round';
      ctx.strokeText(t.text, t.x, y);
      ctx.fillStyle = t.color;
      ctx.fillText(t.text, t.x, y);
    }
    // banners
    for (const b of fx.banners) {
      const q = b.t / b.life;
      if (q >= 1) continue;
      const a = q < 0.75 ? 1 : 1 - (q - 0.75) / 0.25;
      const sc = q < 0.18 ? easeOutBack(q / 0.18) : 1;
      const cx = L.bx + L.bw / 2;
      const cy = L.by + L.bh * 0.42;
      ctx.globalAlpha = a;
      const size = fitFont(b.text, '900', FD, L.cell * 1.05 * sc, L.bw * 0.92);
      ctx.lineWidth = size * 0.16;
      ctx.strokeStyle = 'rgba(8,8,24,0.8)';
      ctx.strokeText(b.text, cx, cy);
      ctx.fillStyle = b.color;
      ctx.fillText(b.text, cx, cy);
      if (b.sub) {
        ctx.font = '700 ' + L.cell * 0.4 + 'px ' + FU;
        ctx.lineWidth = L.cell * 0.1;
        ctx.strokeText(b.sub, cx, cy + size * 0.85);
        ctx.fillStyle = 'rgba(235,236,255,0.9)';
        ctx.fillText(b.sub, cx, cy + size * 0.85);
      }
    }
    ctx.globalAlpha = 1;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'alphabetic';
    void dt;
  }

  function updateFx(dt) {
    const G = L.cell * 22;
    for (const p of fx.particles) {
      p.t += dt;
      p.vy += G * (p.g == null ? 1 : p.g) * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rot += p.vr * dt;
    }
    fx.particles = fx.particles.filter((p) => p.t < p.life);
    for (const t of fx.texts) t.t += dt;
    fx.texts = fx.texts.filter((t) => t.t < t.life);
    for (const b of fx.banners) b.t += dt;
    fx.banners = fx.banners.filter((b) => b.t < b.life);
    for (const tr of fx.trails) tr.t += dt;
    fx.trails = fx.trails.filter((tr) => tr.t < 0.22);
    fx.shake *= Math.pow(0.0005, dt);
    vis.rot *= Math.exp(-dt * 24);
    if (Math.abs(vis.rot) < 0.002) vis.rot = 0;
    vis.spawnT = Math.min(1, vis.spawnT + dt / 0.16);
    spring(vis, 'bumpX', 'bumpV', dt, 900, 38);
    spring(vis, 'wiggle', 'wiggleV', dt, 900, 38);
    spring(anim, 'kick', 'kickV', dt, 700, 30);
    anim.holdPop = Math.max(0, anim.holdPop - dt / 0.28);
    anim.queuePop = Math.max(0, anim.queuePop - dt / 0.34);
    anim.scorePop = Math.max(0, anim.scorePop - dt / 0.3);
    anim.levelPop = Math.max(0, anim.levelPop - dt / 0.6);
    if (game) {
      if (anim.tokens < 0) anim.tokens = game.tokens;
      for (let k = anim.tokens; k < game.tokens; k++) anim.pips[k] = MOTION ? 0 : 1;
      anim.tokens = game.tokens;
      for (let k = 0; k < anim.pips.length; k++) anim.pips[k] = Math.min(1, anim.pips[k] + dt / 0.3);
    }
    // the whole console dips a few pixels on a hard drop
    const kickStyle = Math.abs(anim.kick) > 0.05 ? 'translate3d(0,' + anim.kick.toFixed(2) + 'px,0)' : '';
    if (kickStyle !== anim.kickStyle) {
      anim.kickStyle = kickStyle;
      canvas.style.transform = kickStyle;
    }
    fx.tokenPulse = Math.max(0, fx.tokenPulse - dt * 1.5);
    if (fx.failCells) {
      fx.failT += dt;
      if (fx.failT > 0.4) fx.failCells = null;
    }
    if (game) {
      const target = game.score;
      if (disp.score < target) disp.score = Math.min(target, disp.score + Math.max(1, (target - disp.score) * Math.min(1, dt * 9)));
      else disp.score = target;
    }
  }

  function drawRain(dt) {
    const s = L.cell * 0.9;
    fx.rainAcc += dt;
    while (fx.rainAcc > 0.65) {
      fx.rainAcc -= 0.65;
      fx.rain.push({ x: Math.random() * W, y: -s * 2, vy: H * (0.08 + Math.random() * 0.1), c: (Math.random() * 6) | 0, sp: Math.random() < 0.08 ? 1 + ((Math.random() * 4) | 0) : 0, sc: 0.6 + Math.random() * 0.9 });
    }
    for (const d of fx.rain) {
      d.y += d.vy * dt;
      ctx.globalAlpha = 0.32 + d.sc * 0.12;
      ctx.drawImage(SPR.blocks[d.c][d.sp], d.x, d.y, s * d.sc, s * d.sc);
    }
    ctx.globalAlpha = 1;
    fx.rain = fx.rain.filter((d) => d.y < H + s);
  }

  function render(now, dt) {
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    if (app === 'menu' || !game) {
      ctx.drawImage(bgMenu, 0, 0, W, H);
      drawRain(dt);
      return;
    }
    ctx.drawImage(bgPlay, 0, 0, W, H);
    drawHUD();
    drawBoard(now, dt);
    drawOverlayFx(dt);
  }

  // ===================================================================
  // Input
  // ===================================================================
  const inp = { id: null, mode: null, sx: 0, sy: 0, st: 0, samples: [], anchor: 0, rows: 0, pieceId: 0, press: -1, wasSel: false, drag: false, moved: false };

  function pos(e) {
    const r = canvas.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  }
  const inRect = (r, x, y, pad) => {
    pad = pad || 0;
    return x >= r.x - pad && x <= r.x + r.w + pad && y >= r.y - pad && y <= r.y + r.h + pad;
  };
  function cellAt(x, y) {
    const c = Math.floor((x - L.bx) / L.cell);
    const r = Math.floor((y - L.by) / L.cell);
    if (c < 0 || c >= COLS || r < 0 || r >= ROWS) return -1;
    return r * COLS + c;
  }
  function neighbor(i, dir) {
    const x = i % COLS;
    const y = (i / COLS) | 0;
    if (dir === 0 && x < COLS - 1) return i + 1;
    if (dir === 1 && y < ROWS - 1) return i + COLS;
    if (dir === 2 && x > 0) return i - 1;
    if (dir === 3 && y > 0) return i - COLS;
    return -1;
  }
  function nearestLegal(from) {
    const cells = Array.from(game.legalCells);
    if (!cells.length) return -1;
    if (from < 0) return cells[cells.length - 1];
    let best = cells[0];
    let bd = Infinity;
    for (const c of cells) {
      const d = Math.abs((c % COLS) - (from % COLS)) + Math.abs(((c / COLS) | 0) - ((from / COLS) | 0));
      if (d < bd) {
        bd = d;
        best = c;
      }
    }
    return best;
  }

  function doSwap(a, b) {
    const res = game.trySwap(a, b);
    sel = -1;
    return res;
  }
  function doHold() {
    if (game.holdPiece()) Haptics.tap();
  }

  function beginPieceGesture(x, y) {
    inp.mode = 'piece';
    inp.sx = x;
    inp.sy = y;
    inp.anchor = game.piece.x;
    inp.pieceId = game.piece.id;
    inp.rows = 0;
  }

  function onDown(e) {
    if (app !== 'play' || inp.id !== null) return;
    Sound.ensure();
    keyMode = false;
    inp.id = e.pointerId;
    try {
      canvas.setPointerCapture(e.pointerId);
    } catch (err) {
      /* ignore */
    }
    const { x, y } = pos(e);
    inp.sx = x;
    inp.sy = y;
    inp.st = performance.now();
    inp.samples = [{ x, y, t: inp.st }];
    inp.moved = false;
    inp.drag = false;
    inp.press = -1;
    if (inRect(L.hold, x, y, 4) && game.phase === 'fall') {
      inp.mode = 'hud';
      doHold();
      return;
    }
    if (game.phase === 'fall' && game.piece) beginPieceGesture(x, y);
    else if (game.phase === 'swap') {
      inp.mode = 'swap';
      game.swapHold = true;
      const i = cellAt(x, y);
      inp.press = i >= 0 && game.board[i] ? i : -1;
      inp.wasSel = inp.press >= 0 && inp.press === sel;
      if (inp.press >= 0 && !(sel >= 0 && Game.adjacent(sel, inp.press))) {
        if (sel !== inp.press) sfx.select();
        sel = inp.press;
      }
    } else inp.mode = 'wait';
  }

  function onMove(e) {
    if (e.pointerId !== inp.id) return;
    const { x, y } = pos(e);
    const now = performance.now();
    inp.samples.push({ x, y, t: now });
    while (inp.samples.length > 2 && now - inp.samples[0].t > 250) inp.samples.shift();
    let dx = x - inp.sx;
    let dy = y - inp.sy;
    if (Math.abs(dx) > 9 || Math.abs(dy) > 9) inp.moved = true;
    if (inp.mode === 'wait' && game.phase === 'fall' && game.piece) {
      beginPieceGesture(x, y);
      dx = 0;
      dy = 0;
    }
    if (inp.mode === 'piece') {
      const p = game.piece;
      if (!p || p.id !== inp.pieceId || game.phase !== 'fall') {
        inp.mode = 'done';
        return;
      }
      const step = L.cell * 0.88;
      const target = inp.anchor + Math.round(dx / step);
      let guard = COLS;
      while (p.x !== target && guard-- > 0) {
        const dir = Math.sign(target - p.x);
        if (!game.move(dir)) {
          bumpWall(dir);
          inp.anchor = p.x - Math.round(dx / step);
          break;
        }
      }
      const dead = L.cell * 0.9;
      if (dy > dead && dy > Math.abs(dx) * 0.9) {
        const rows = Math.floor((dy - dead) / (L.cell * 0.7));
        while (inp.rows < rows) {
          if (!game.softDropStep()) break;
          inp.rows++;
        }
      }
    } else if (inp.mode === 'swap' && inp.press >= 0 && !inp.drag) {
      const th = L.cell * 0.45;
      if (Math.abs(dx) > th || Math.abs(dy) > th) {
        inp.drag = true;
        const dir = Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 0 : 2) : dy > 0 ? 1 : 3;
        const t = neighbor(inp.press, dir);
        if (t >= 0 && game.board[t]) doSwap(inp.press, t);
        else sel = -1;
      }
    }
  }

  // Peak speed over the last 150 ms of motion, each reading spanning at least 24 ms to smooth out jitter.
  function velocity() {
    const s = inp.samples;
    let best = { vx: 0, vy: 0 };
    if (s.length < 2) return best;
    const end = s[s.length - 1].t;
    for (let k = s.length - 1; k > 0; k--) {
      const b = s[k];
      if (end - b.t > 150) break;
      let j = k - 1;
      while (j > 0 && b.t - s[j].t < 24) j--;
      const a = s[j];
      const dt = Math.max(1, b.t - a.t);
      const vy = (b.y - a.y) / dt;
      if (Math.abs(vy) > Math.abs(best.vy)) best = { vx: (b.x - a.x) / dt, vy };
    }
    return best;
  }

  function onUp(e) {
    if (e.pointerId !== inp.id) return;
    const { x, y } = pos(e);
    const last = inp.samples[inp.samples.length - 1];
    if (!last || last.x !== x || last.y !== y) inp.samples.push({ x, y, t: performance.now() });
    const dx = x - inp.sx;
    const dy = y - inp.sy;
    const dur = performance.now() - inp.st;
    const v = velocity();
    if (inp.mode === 'piece' && game.piece && game.piece.id === inp.pieceId && game.phase === 'fall') {
      if (!inp.moved && dur < 350) {
        const dir = x < L.bx + L.bw / 2 ? -1 : 1;
        if (!game.rotate(dir)) wiggle(dir);
        Haptics.tap();
      } else if (dy > L.cell * 1.2 && v.vy > 0.6 && Math.abs(dy) > Math.abs(dx)) {
        game.hardDrop();
        Haptics.tap();
      } else if (dy < -L.cell * 1.2 && v.vy < -0.6 && Math.abs(dy) > Math.abs(dx)) {
        doHold();
      }
    } else if (inp.mode === 'swap') {
      game.swapHold = false;
      if (game.phase === 'swap' && !inp.drag) {
        if (inp.moved) {
          if (inp.press < 0 && dy > L.cell * 1.2) game.skipSwap();
        } else if (inp.press >= 0) {
          if (sel >= 0 && sel !== inp.press && Game.adjacent(sel, inp.press)) doSwap(sel, inp.press);
          else if (inp.wasSel) sel = -1;
        } else if (sel >= 0) sel = -1;
        else game.skipSwap();
      }
    } else if (inp.mode === 'wait' && !inp.moved && game.phase === 'swap') {
      game.skipSwap();
    }
    endPointer();
  }
  function endPointer() {
    if (game) game.swapHold = false;
    inp.id = null;
    inp.mode = null;
  }

  canvas.addEventListener('pointerdown', onDown);
  canvas.addEventListener('pointermove', onMove);
  canvas.addEventListener('pointerup', onUp);
  canvas.addEventListener('pointercancel', endPointer);
  canvas.addEventListener('touchstart', (e) => e.preventDefault(), { passive: false });
  canvas.addEventListener('contextmenu', (e) => e.preventDefault());
  document.addEventListener('gesturestart', (e) => e.preventDefault());

  // keyboard
  const keys = { dasDir: 0, dasT: 0, arrT: 0, left: false, right: false };
  const DAS = 0.16;
  const ARR = 0.045;
  function keyDown(e) {
    const k = e.key;
    if (app === 'menu' || app === 'over' || app === 'dying') {
      if ((k === 'Enter' || k === ' ') && app === 'over' && !$('over').hidden && document.activeElement === document.body) {
        e.preventDefault();
        startGame(false);
      }
      return;
    }
    if (app === 'paused') {
      if ((k === 'Escape' || k === 'p' || k === 'P') && !$('pause').hidden) {
        e.preventDefault();
        resumeGame();
      }
      return;
    }
    Sound.ensure();
    const handled = ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', ' ', 'Enter', 'Escape', 'p', 'P', 'z', 'Z', 'x', 'X', 'c', 'C', 'Shift'];
    if (handled.includes(k)) e.preventDefault();
    if (k === 'Escape' || k === 'p' || k === 'P') {
      if (k === 'Escape' && game.phase === 'swap' && sel >= 0) sel = -1;
      else pauseGame();
      return;
    }
    if (game.phase === 'swap') {
      keyMode = true;
      if (kcur < 0) kcur = nearestLegal(-1);
      const dirs = { ArrowRight: 0, ArrowDown: 1, ArrowLeft: 2, ArrowUp: 3 };
      if (k in dirs) {
        if (sel >= 0) {
          const t = neighbor(sel, dirs[k]);
          if (t >= 0 && game.board[t]) {
            doSwap(sel, t);
            kcur = t;
          }
        } else {
          const t = neighbor(kcur < 0 ? 0 : kcur, dirs[k]);
          if (t >= 0) kcur = t;
        }
      } else if (k === 'Enter' || k === 'x' || k === 'X' || k === 'z' || k === 'Z') {
        if (sel === kcur) sel = -1;
        else if (kcur >= 0 && game.board[kcur]) {
          sel = kcur;
          sfx.select();
        }
      } else if (k === ' ') game.skipSwap();
      return;
    }
    if (e.repeat && (k === 'ArrowLeft' || k === 'ArrowRight' || k === 'ArrowDown')) return;
    switch (k) {
      case 'ArrowLeft':
        keys.left = true;
        keys.dasDir = -1;
        keys.dasT = 0;
        keys.arrT = 0;
        if (!game.move(-1)) bumpWall(-1);
        break;
      case 'ArrowRight':
        keys.right = true;
        keys.dasDir = 1;
        keys.dasT = 0;
        keys.arrT = 0;
        if (!game.move(1)) bumpWall(1);
        break;
      case 'ArrowDown':
        game.setSoftDrop(true);
        break;
      case 'ArrowUp':
      case 'x':
      case 'X':
        if (!e.repeat && !game.rotate(1)) wiggle(1);
        break;
      case 'z':
      case 'Z':
        if (!e.repeat && !game.rotate(-1)) wiggle(-1);
        break;
      case ' ':
        if (!e.repeat) game.hardDrop();
        break;
      case 'c':
      case 'C':
      case 'Shift':
        game.holdPiece();
        break;
    }
  }
  function keyUp(e) {
    if (!game) return;
    switch (e.key) {
      case 'ArrowLeft':
        keys.left = false;
        if (keys.dasDir === -1) keys.dasDir = keys.right ? 1 : 0;
        keys.dasT = 0;
        break;
      case 'ArrowRight':
        keys.right = false;
        if (keys.dasDir === 1) keys.dasDir = keys.left ? -1 : 0;
        keys.dasT = 0;
        break;
      case 'ArrowDown':
        game.setSoftDrop(false);
        break;
    }
  }
  function updateKeys(dt) {
    if (!keys.dasDir || game.phase !== 'fall') return;
    keys.dasT += dt;
    if (keys.dasT < DAS) return;
    keys.arrT += dt;
    while (keys.arrT >= ARR) {
      keys.arrT -= ARR;
      if (!game.move(keys.dasDir)) {
        keys.arrT = 0;
        break;
      }
    }
  }
  window.addEventListener('keydown', keyDown);
  window.addEventListener('keyup', keyUp);

  // ===================================================================
  // Screens
  // ===================================================================
  const OVERLAYS = ['menu', 'pause', 'over', 'settings', 'help', 'scores'];
  let returnTo = 'menu';
  function showOverlay(id) {
    for (const o of OVERLAYS) $(o).hidden = o !== id;
    pauseBtn.hidden = id !== null || app !== 'play';
    dirty = true;
    if (id) {
      const first = $(id).querySelector('[data-autofocus]') || $(id).querySelector('button:not([hidden])');
      if (first && !matchMedia('(pointer: coarse)').matches) first.focus({ preventScroll: true });
    }
  }

  function loadSave() {
    const s = store.get('pf.save', null);
    return s && s.v === 2 ? s : null;
  }
  function saveGame() {
    if (game && game.phase !== 'over') store.set('pf.save', game.serialize());
  }

  function refreshMenu() {
    const save = loadSave();
    const cont = $('btn-continue');
    const play = $('btn-new');
    if (save) {
      cont.hidden = false;
      $('continue-score').textContent = fmt(save.score) + ' pts · Lv ' + save.level;
      play.textContent = 'New game';
      play.classList.remove('primary');
    } else {
      cont.hidden = true;
      play.textContent = 'Play';
      play.classList.add('primary');
    }
    const scores = store.get('pf.scores', []);
    $('menu-best').textContent = scores.length ? 'Best ' + fmt(scores[0].score) : '';
  }

  let wakeLock = null;
  async function requestWake() {
    try {
      if ('wakeLock' in navigator && !wakeLock) {
        wakeLock = await navigator.wakeLock.request('screen');
        wakeLock.addEventListener('release', () => {
          wakeLock = null;
        });
      }
    } catch (e) {
      wakeLock = null;
    }
  }
  function releaseWake() {
    try {
      if (wakeLock) wakeLock.release();
    } catch (e) {
      /* ignore */
    }
    wakeLock = null;
  }

  function startGame(resume) {
    Sound.ensure();
    let g = null;
    if (resume) g = Game.restore(loadSave(), { relaxed: settings.relaxed });
    if (!g) {
      g = new Game({ relaxed: settings.relaxed });
      store.del('pf.save');
    }
    game = g;
    disp.score = game.score;
    resetFx();
    sel = -1;
    kcur = -1;
    keys.dasDir = 0;
    endPointer();
    app = 'play';
    showOverlay(null);
    positionPause();
    requestWake();
    lastT = performance.now();
  }
  function pauseGame() {
    if (app !== 'play') return;
    app = 'paused';
    game.setSoftDrop(false);
    keys.dasDir = 0;
    endPointer();
    saveGame();
    $('pause-score').textContent = fmt(game.score);
    $('pause-level').textContent = 'Level ' + game.level;
    showOverlay('pause');
    releaseWake();
  }
  function resumeGame() {
    if (app !== 'paused') return;
    app = 'play';
    showOverlay(null);
    requestWake();
    lastT = performance.now();
  }
  function quitToMenu() {
    if (game && app === 'paused') saveGame();
    app = 'menu';
    game = null;
    releaseWake();
    refreshMenu();
    showOverlay('menu');
  }

  function onGameOver() {
    app = 'dying';
    overT = 0;
    sfx.over();
    shake(L.cell * 0.3);
    store.del('pf.save');
    store.set('pf.played', true);
    firstGame = false;
    releaseWake();
    const scores = store.get('pf.scores', []);
    const prevBest = scores.length ? scores[0].score : 0;
    const entry = { score: game.score, level: game.level, chain: game.stats.maxChain, date: Date.now() };
    scores.push(entry);
    scores.sort((a, b) => b.score - a.score);
    store.set('pf.scores', scores.slice(0, 10));
    const st = game.stats;
    $('over-score').textContent = fmt(game.score);
    const best = game.score > prevBest && game.score > 0;
    $('over-title').textContent = best ? 'New best!' : 'Game over';
    $('over-best').textContent = best ? (prevBest ? 'Previous best ' + fmt(prevBest) : 'First score on the board') : 'Best ' + fmt(prevBest);
    $('st-level').textContent = game.level;
    $('st-cleared').textContent = fmt(game.cleared);
    $('st-chain').textContent = st.maxChain ? '×' + st.maxChain : '–';
    $('st-specials').textContent = st.specials;
    $('st-pieces').textContent = st.pieces;
    const sec = Math.round(st.time);
    $('st-time').textContent = Math.floor(sec / 60) + ':' + String(sec % 60).padStart(2, '0');
    $('over').classList.toggle('is-best', best);
  }

  function positionPause() {
    if (!L) return;
    pauseBtn.style.left = L.pause.x + 'px';
    pauseBtn.style.top = L.pause.y + 'px';
    pauseBtn.style.width = L.pause.w + 'px';
    pauseBtn.style.height = L.pause.h + 'px';
  }

  function renderScores() {
    const list = $('score-list');
    list.textContent = '';
    const scores = store.get('pf.scores', []);
    if (!scores.length) {
      const li = document.createElement('li');
      li.className = 'empty';
      li.textContent = 'No games yet. Your top ten will appear here.';
      list.appendChild(li);
      return;
    }
    scores.forEach((s, k) => {
      const li = document.createElement('li');
      const d = new Date(s.date);
      li.innerHTML = '<span class="rank">' + (k + 1) + '</span><span class="pts">' + fmt(s.score) + '</span><span class="meta">Lv ' + s.level + (s.chain > 1 ? ' · ×' + s.chain : '') + '<br>' + d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) + '</span>';
      list.appendChild(li);
    });
  }

  // settings UI
  const SETTING_IDS = { sound: 'set-sound', haptics: 'set-haptics', ghost: 'set-ghost', symbols: 'set-symbols', relaxed: 'set-relaxed' };
  function syncSettingsUI() {
    for (const k in SETTING_IDS) $(SETTING_IDS[k]).checked = !!settings[k];
  }
  for (const k in SETTING_IDS) {
    $(SETTING_IDS[k]).addEventListener('change', (e) => {
      settings[k] = e.target.checked;
      saveSettings();
      if (k === 'symbols' && L) {
        buildSprites();
        drawHelpArt();
      }
      if (k === 'relaxed' && game) {
        game.relaxed = settings.relaxed;
        if (game.phase === 'swap') game.timer = game.phaseDur = game.swapWindow();
      }
      if (k === 'sound' && settings.sound) {
        Sound.ensure();
        sfx.ui();
      }
      if (k === 'haptics' && settings.haptics) Haptics.tap();
    });
  }

  // help pages
  let helpPage = 0;
  const helpCards = Array.from(document.querySelectorAll('.help-card'));
  function setHelpPage(n) {
    helpPage = clamp(n, 0, helpCards.length - 1);
    helpCards.forEach((c, k) => (c.hidden = k !== helpPage));
    const dots = $('help-dots');
    dots.textContent = '';
    helpCards.forEach((_, k) => {
      const d = document.createElement('span');
      if (k === helpPage) d.className = 'on';
      dots.appendChild(d);
    });
    $('help-prev').disabled = helpPage === 0;
    $('help-next').textContent = helpPage === helpCards.length - 1 ? 'Done' : 'Next';
  }

  function drawHelpArt() {
    const dpr = Math.min(window.devicePixelRatio || 1, 3);
    document.querySelectorAll('canvas.sp-icon').forEach((cv) => {
      const size = 36;
      cv.width = size * dpr;
      cv.height = size * dpr;
      cv.style.width = size + 'px';
      cv.style.height = size + 'px';
      const c = cv.getContext('2d');
      c.clearRect(0, 0, cv.width, cv.height);
      paintBlock(c, size * dpr, COLORS[+cv.dataset.c].hex, +cv.dataset.sp, settings.symbols ? +cv.dataset.c : -1);
    });
    document.querySelectorAll('canvas.help-art').forEach((cv) => {
      const w = cv.clientWidth || 280;
      const h = cv.clientHeight || 112;
      cv.width = w * dpr;
      cv.height = h * dpr;
      const c = cv.getContext('2d');
      c.scale(dpr, dpr);
      c.clearRect(0, 0, w, h);
      const s = Math.min(30, h / 3.6);
      const blk = (col, sp, x, y, a) => {
        const tmp = makeCanvas(s * dpr, s * dpr);
        paintBlock(tmp.getContext('2d'), s * dpr, COLORS[col].hex, sp || 0, settings.symbols ? col : -1);
        c.globalAlpha = a == null ? 1 : a;
        c.drawImage(tmp, x, y, s, s);
        c.globalAlpha = 1;
      };
      const arrow = (x0, y0, x1, y1) => {
        c.strokeStyle = '#c9cdf5';
        c.fillStyle = '#c9cdf5';
        c.lineWidth = 2;
        c.lineCap = 'round';
        c.beginPath();
        c.moveTo(x0, y0);
        c.lineTo(x1, y1);
        c.stroke();
        const a = Math.atan2(y1 - y0, x1 - x0);
        c.beginPath();
        c.moveTo(x1 + Math.cos(a) * 3, y1 + Math.sin(a) * 3);
        c.lineTo(x1 + Math.cos(a + 2.5) * 8, y1 + Math.sin(a + 2.5) * 8);
        c.lineTo(x1 + Math.cos(a - 2.5) * 8, y1 + Math.sin(a - 2.5) * 8);
        c.closePath();
        c.fill();
      };
      const kind = cv.dataset.art;
      const cxm = w / 2;
      if (kind === 'controls') {
        const x0 = cxm - s * 1.5;
        const y0 = h / 2 - s;
        blk(0, 0, x0, y0 + s);
        blk(0, 0, x0 + s, y0 + s);
        blk(3, 0, x0 + s, y0);
        blk(3, 0, x0 + s * 2, y0 + s);
        arrow(x0 - 10, y0 + s * 1.5, x0 - 40, y0 + s * 1.5);
        arrow(x0 + s * 3 + 10, y0 + s * 1.5, x0 + s * 3 + 40, y0 + s * 1.5);
        arrow(cxm, y0 + s * 2 + 8, cxm, h - 4);
        c.strokeStyle = '#c9cdf5';
        c.lineWidth = 2;
        c.beginPath();
        c.arc(cxm, y0 + s * 0.2, s * 0.9, -2.6, -0.5);
        c.stroke();
        c.beginPath();
        const ex = cxm + Math.cos(-0.5) * s * 0.9;
        const ey = y0 + s * 0.2 + Math.sin(-0.5) * s * 0.9;
        c.moveTo(ex + 5, ey - 3);
        c.lineTo(ex - 2, ey - 7);
        c.lineTo(ex - 1, ey + 3);
        c.closePath();
        c.fill();
      } else if (kind === 'match') {
        const x0 = cxm - s * 2.5;
        const y0 = h - s - 8;
        [3, 0, 0, 0, 2].forEach((col, k) => blk(col, 0, x0 + k * s, y0));
        c.strokeStyle = '#ffffff';
        c.lineWidth = 2;
        rr(c, x0 + s - 2, y0 - 2, s * 3 + 4, s + 4, 8);
        c.stroke();
        blk(1, 0, x0 + s, y0 - s * 1.2, 0.85);
        blk(4, 0, x0 + s * 2, y0 - s * 1.2, 0.85);
        blk(1, 0, x0 + s * 3, y0 - s * 1.2, 0.85);
        arrow(x0 + s * 1.5, y0 - s * 2.2 + 2, x0 + s * 1.5, y0 - s * 1.35);
        arrow(x0 + s * 3.5, y0 - s * 2.2 + 2, x0 + s * 3.5, y0 - s * 1.35);
      } else if (kind === 'swap') {
        const x0 = cxm - s * 2;
        const y0 = h / 2 - s / 2 + 6;
        blk(2, 0, x0, y0);
        blk(2, 0, x0 + s, y0);
        blk(4, 0, x0 + s * 2, y0);
        blk(2, 0, x0 + s * 3, y0 - s);
        blk(4, 0, x0 + s * 3, y0);
        c.strokeStyle = '#ffffff';
        c.lineWidth = 2;
        rr(c, x0 + s * 2 - 1, y0 - 1, s + 2, s + 2, 7);
        c.stroke();
        c.strokeStyle = GOLD;
        rr(c, x0 + s * 3 - 1, y0 - s - 1, s + 2, s + 2, 7);
        c.stroke();
        c.strokeStyle = GOLD;
        c.beginPath();
        c.arc(x0 + s * 3, y0, s * 0.75, -Math.PI * 0.95, -Math.PI * 0.55);
        c.stroke();
        c.fillStyle = '#c9cdf5';
        c.font = '600 12px ' + FU;
        c.textAlign = 'center';
        c.fillText('swap these two → green row of 3', cxm, h - 4);
        c.textAlign = 'left';
      }
    });
  }

  function openHelp(from) {
    returnTo = from;
    showOverlay('help');
    setHelpPage(0);
    requestAnimationFrame(drawHelpArt);
  }
  function closeSub() {
    if (returnTo === 'pause') showOverlay('pause');
    else {
      refreshMenu();
      showOverlay('menu');
    }
  }

  const on = (id, fn) =>
    $(id).addEventListener('click', (e) => {
      Sound.ensure();
      sfx.ui();
      fn(e);
    });
  on('btn-continue', () => startGame(true));
  on('btn-new', () => {
    if (!store.get('pf.seenHelp', false)) {
      store.set('pf.seenHelp', true);
      returnTo = 'start';
      showOverlay('help');
      setHelpPage(0);
      requestAnimationFrame(drawHelpArt);
      return;
    }
    startGame(false);
  });
  on('btn-help', () => openHelp('menu'));
  on('btn-scores', () => {
    renderScores();
    showOverlay('scores');
  });
  on('btn-settings', () => {
    returnTo = 'menu';
    syncSettingsUI();
    showOverlay('settings');
  });
  on('btn-scores-done', () => showOverlay('menu'));
  on('btn-settings-done', closeSub);
  on('help-prev', () => setHelpPage(helpPage - 1));
  on('help-next', () => {
    if (helpPage < helpCards.length - 1) setHelpPage(helpPage + 1);
    else if (returnTo === 'start') startGame(false);
    else closeSub();
  });
  on('help-close', () => {
    if (returnTo === 'start') startGame(false);
    else closeSub();
  });
  on('btn-resume', resumeGame);
  let restartArmed = 0;
  on('btn-restart', () => {
    const b = $('btn-restart');
    if (performance.now() - restartArmed < 3000) {
      restartArmed = 0;
      b.textContent = 'Restart';
      store.del('pf.save');
      startGame(false);
    } else {
      restartArmed = performance.now();
      b.textContent = 'Tap again to restart';
      setTimeout(() => {
        if (performance.now() - restartArmed >= 2900) b.textContent = 'Restart';
      }, 3000);
    }
  });
  on('btn-p-help', () => openHelp('pause'));
  on('btn-p-settings', () => {
    returnTo = 'pause';
    syncSettingsUI();
    showOverlay('settings');
  });
  on('btn-quit', quitToMenu);
  on('btn-again', () => startGame(false));
  on('btn-over-menu', () => {
    app = 'menu';
    game = null;
    refreshMenu();
    showOverlay('menu');
  });
  let resetArmed = 0;
  on('btn-reset-scores', () => {
    const b = $('btn-reset-scores');
    if (performance.now() - resetArmed < 3000) {
      store.del('pf.scores');
      b.textContent = 'High scores cleared';
      resetArmed = 0;
    } else {
      resetArmed = performance.now();
      b.textContent = 'Tap again to clear scores';
      setTimeout(() => {
        if (resetArmed && performance.now() - resetArmed >= 2900) b.textContent = 'Reset high scores';
      }, 3000);
    }
  });
  pauseBtn.addEventListener('click', () => {
    Sound.ensure();
    pauseGame();
  });

  // install hints
  const isIOS = /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const standalone = navigator.standalone === true || (window.matchMedia && matchMedia('(display-mode: standalone)').matches);
  let embedded = false;
  try {
    embedded = window.self !== window.top;
  } catch (e) {
    embedded = true;
  }
  if (isIOS && !standalone && !embedded) $('install-hint').hidden = false;
  let deferredPrompt = null;
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredPrompt = e;
    $('btn-install').hidden = false;
  });
  on('btn-install', async () => {
    if (!deferredPrompt) return;
    deferredPrompt.prompt();
    try {
      await deferredPrompt.userChoice;
    } catch (e) {
      /* ignore */
    }
    deferredPrompt = null;
    $('btn-install').hidden = true;
  });

  // lifecycle
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      if (app === 'play') pauseGame();
      else if (app === 'paused') saveGame();
    }
  });
  window.addEventListener('pagehide', () => {
    if (app === 'play' || app === 'paused') saveGame();
  });
  window.addEventListener('blur', () => {
    if (app === 'play' && !matchMedia('(pointer: coarse)').matches) pauseGame();
  });

  // ===================================================================
  // Resize + loop
  // ===================================================================
  function resize() {
    L = computeLayout();
    canvas.width = Math.round(W * DPR);
    canvas.height = Math.round(H * DPR);
    canvas.style.width = W + 'px';
    canvas.style.height = H + 'px';
    buildSprites();
    buildBackgrounds();
    positionPause();
    vis.x = game && game.piece ? game.piece.x : 0;
    dirty = true;
  }
  let resizeQueued = false;
  function queueResize() {
    if (resizeQueued) return;
    resizeQueued = true;
    requestAnimationFrame(() => {
      resizeQueued = false;
      resize();
    });
  }
  window.addEventListener('resize', queueResize);
  window.addEventListener('orientationchange', () => setTimeout(resize, 250));
  if (window.visualViewport) window.visualViewport.addEventListener('resize', queueResize);

  // Safe-area insets can settle after the first layout (rotation, standalone launch); re-measure now and then.
  let insetCheckT = 0;
  function checkInsets(dt) {
    insetCheckT += dt;
    if (insetCheckT < 0.75) return;
    insetCheckT = 0;
    const sa = safeArea();
    if (!L || sa.t !== L.sa.t || sa.b !== L.sa.b || sa.l !== L.sa.l || sa.r !== L.sa.r || window.innerWidth !== W || window.innerHeight !== H) resize();
  }

  let lastT = performance.now();
  function frame(now) {
    const dt = Math.min(0.05, Math.max(0, (now - lastT) / 1000));
    lastT = now;
    checkInsets(dt);
    if (app === 'play') {
      updateKeys(dt);
      game.update(dt);
      handleEvents();
    } else if (app === 'dying') {
      overT += dt;
      if (overT > 1.15) {
        app = 'over';
        showOverlay('over');
      }
    }
    const idle = (app === 'paused' || app === 'over') && !fx.particles.length && !fx.texts.length && !fx.banners.length;
    if (!idle || dirty) {
      updateFx(dt);
      render(now, dt);
      dirty = false;
    }
    requestAnimationFrame(frame);
  }

  // ===================================================================
  // Boot
  // ===================================================================
  resize();
  refreshMenu();
  syncSettingsUI();
  showOverlay('menu');
  if (document.fonts && document.fonts.load) {
    document.fonts.load('700 20px Unbounded').then(() => {
      dirty = true;
    }, () => {});
  }
  requestAnimationFrame((t) => {
    lastT = t;
    requestAnimationFrame(frame);
  });

  if ('serviceWorker' in navigator && (location.protocol === 'https:' || location.hostname === 'localhost' || location.hostname === '127.0.0.1') && !embedded) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('sw.js').catch(() => {});
    });
  }

  // Debug/testing hook (harmless in production)
  window.__prismfall = {
    get game() {
      return game;
    },
    get app() {
      return app;
    },
    get layout() {
      return L;
    },
    start: startGame,
    pause: pauseGame,
    resume: resumeGame,
    select(i) {
      sel = i;
    },
  };
})();
