/*
 * Prismfall core: board, falling shapes, colour matching, gravity, cascades,
 * swaps and special blocks. No DOM access, so it runs in the browser and in Node.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.PFCore = api;
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const COLS = 10;
  const ROWS = 20;
  const MAX_LEVEL = 25;
  const BLOCKS_PER_LEVEL = 45;

  // Special block kinds
  const SP = { NONE: 0, LINE_H: 1, LINE_V: 2, BOMB: 3, PRISM: 4 };

  // Timings (seconds)
  const T = {
    SPAWN: 0.07,
    LOCK_DELAY: 0.5,
    MAX_LOCK_RESETS: 15,
    SOFT_INTERVAL: 0.028,
    CLEAR: 0.3,
    CLEAR_FX: 0.44,
    DROP_ACCEL: 150, // rows / s^2 for the post-clear gravity animation
    DROP_SETTLE: 0.05,
    SWAP: 0.14,
  };

  const MAX_TOKENS = 3;
  const METER_MAX = 40;

  // Shapes in their SRS spawn orientation inside an n x n box.
  // Cells are listed in path order so colour segments stay contiguous.
  const SHAPES = {
    I: { n: 4, cells: [[0, 1], [1, 1], [2, 1], [3, 1]] },
    O: { n: 2, cells: [[0, 0], [1, 0], [1, 1], [0, 1]] },
    T: { n: 3, cells: [[0, 1], [1, 1], [1, 0], [2, 1]] },
    S: { n: 3, cells: [[0, 1], [1, 1], [1, 0], [2, 0]] },
    Z: { n: 3, cells: [[0, 0], [1, 0], [1, 1], [2, 1]] },
    J: { n: 3, cells: [[0, 0], [0, 1], [1, 1], [2, 1]] },
    L: { n: 3, cells: [[2, 0], [2, 1], [1, 1], [0, 1]] },
  };
  const TYPES = ['I', 'O', 'T', 'S', 'Z', 'J', 'L'];

  // SRS wall kicks, (x, y) with y pointing up as in the published tables.
  const KICKS_JLSTZ = {
    '0>1': [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
    '1>0': [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
    '1>2': [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
    '2>1': [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
    '2>3': [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
    '3>2': [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
    '3>0': [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
    '0>3': [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
  };
  const KICKS_I = {
    '0>1': [[0, 0], [-2, 0], [1, 0], [-2, -1], [1, 2]],
    '1>0': [[0, 0], [2, 0], [-1, 0], [2, 1], [-1, -2]],
    '1>2': [[0, 0], [-1, 0], [2, 0], [-1, 2], [2, -1]],
    '2>1': [[0, 0], [1, 0], [-2, 0], [1, -2], [-2, 1]],
    '2>3': [[0, 0], [2, 0], [-1, 0], [2, 1], [-1, -2]],
    '3>2': [[0, 0], [-2, 0], [1, 0], [-2, -1], [1, 2]],
    '3>0': [[0, 0], [1, 0], [-2, 0], [1, -2], [-2, 1]],
    '0>3': [[0, 0], [-1, 0], [2, 0], [-1, 2], [2, -1]],
  };

  const SPECIAL_BONUS = { [SP.LINE_H]: 100, [SP.LINE_V]: 100, [SP.BOMB]: 150, [SP.PRISM]: 250 };
  const COMBO_BONUS = { cross: 300, wide: 500, mega: 500, wipe: 300, wipeLines: 800, wipeBombs: 1000, wipe2: 1200 };

  const idx = (x, y) => y * COLS + x;
  const cx = (i) => i % COLS;
  const cy = (i) => (i / COLS) | 0;
  const isLine = (s) => s === SP.LINE_H || s === SP.LINE_V;

  function gravityFor(level) {
    return Math.max(0.05, 0.9 * Math.pow(0.86, level - 1));
  }
  function paletteFor(level) {
    return level >= 5 ? 6 : 5;
  }
  function swapWindowFor(level) {
    return Math.max(2.0, 4.2 - 0.12 * (level - 1));
  }
  // Swap meter points added each time a shape lands.
  function landChargeFor(level) {
    return Math.max(5, 10 - ((level - 1) * 5) / 12);
  }
  function groupPoints(n) {
    return 10 * n + 5 * (n - 3) * (n - 2);
  }

  class Game {
    constructor(opts) {
      opts = opts || {};
      this.rng = opts.rng || Math.random;
      this.relaxed = !!opts.relaxed;
      this.events = [];
      this.reset();
    }

    reset() {
      this.board = new Array(COLS * ROWS).fill(null);
      this.nextId = 1;
      this.score = 0;
      this.level = 1;
      this.cleared = 0;
      this.stats = { pieces: 0, maxChain: 0, specials: 0, swaps: 0, bestClear: 0, time: 0 };
      this.bag = [];
      this.queue = [];
      this.hold = null;
      this.holdUsed = false;
      this.tokens = 1;
      this.meter = 0;
      this.piece = null;
      this.chain = 0;
      this.focus = [];
      this.clearing = null;
      this.legal = [];
      this.legalCells = new Set();
      this.swapA = -1;
      this.swapB = -1;
      this.swapHold = false;
      this.softDropping = false;
      this.events.length = 0;
      while (this.queue.length < 5) this.queue.push(this.genDef());
      this.phase = 'spawn';
      this.timer = 0.25;
      this.phaseDur = 0.25;
    }

    emit(type, data) {
      const e = data || {};
      e.type = type;
      this.events.push(e);
    }
    drain() {
      const out = this.events;
      this.events = [];
      return out;
    }

    // ---------- generation ----------
    rand(n) {
      return Math.floor(this.rng() * n);
    }
    shuffle(a) {
      for (let i = a.length - 1; i > 0; i--) {
        const j = this.rand(i + 1);
        const t = a[i];
        a[i] = a[j];
        a[j] = t;
      }
      return a;
    }
    genDef() {
      if (!this.bag.length) this.bag = this.shuffle(TYPES.slice());
      const type = this.bag.pop();
      return { type, colors: this.genColors() };
    }
    genColors() {
      const nColors = paletteFor(this.level);
      const t = Math.min(1, (this.level - 1) / 12);
      const lerp = (a, b) => a + (b - a) * t;
      const w = [lerp(0.3, 0.08), lerp(0.55, 0.4), lerp(0.15, 0.37), lerp(0, 0.15)];
      let r = this.rng() * (w[0] + w[1] + w[2] + w[3]);
      let k = 1;
      for (let i = 0; i < 4; i++) {
        if (r < w[i]) {
          k = i + 1;
          break;
        }
        r -= w[i];
      }
      // split the 4-cell path into k contiguous segments
      const cutPoints = this.shuffle([1, 2, 3]).slice(0, k - 1).sort((a, b) => a - b);
      const palette = this.shuffle(Array.from({ length: nColors }, (_, i) => i)).slice(0, k);
      const colors = [];
      let seg = 0;
      for (let i = 0; i < 4; i++) {
        if (seg < cutPoints.length && i === cutPoints[seg]) seg++;
        colors.push(palette[seg]);
      }
      return colors;
    }
    mkCell(c, s) {
      return { id: this.nextId++, c, s: s || SP.NONE, fall: 0 };
    }

    // ---------- derived values ----------
    gravity() {
      return gravityFor(this.level);
    }
    paletteSize() {
      return paletteFor(this.level);
    }
    swapWindow() {
      return this.relaxed ? Infinity : swapWindowFor(this.level);
    }
    swapsAvailable() {
      return this.tokens;
    }
    /** Add swap-meter points; a full meter becomes a banked swap. */
    charge(pts) {
      const before = this.tokens;
      this.meter += pts;
      while (this.meter >= METER_MAX && this.tokens < MAX_TOKENS) {
        this.meter -= METER_MAX;
        this.tokens++;
      }
      if (this.tokens >= MAX_TOKENS) this.meter = Math.min(this.meter, METER_MAX);
      if (this.tokens > before) this.emit('swapGained', { count: this.tokens - before });
    }
    levelProgress() {
      if (this.level >= MAX_LEVEL) return 1;
      return (this.cleared % BLOCKS_PER_LEVEL) / BLOCKS_PER_LEVEL;
    }
    highestRow() {
      for (let i = 0; i < this.board.length; i++) if (this.board[i]) return cy(i);
      return ROWS;
    }

    // ---------- piece handling ----------
    makePiece(def) {
      const sh = SHAPES[def.type];
      const cells = sh.cells.map(([x, y], k) => ({ x, y, c: def.colors[k] }));
      const minY = Math.min.apply(null, cells.map((c) => c.y));
      return { type: def.type, def, cells, rot: 0, x: def.type === 'O' ? 4 : 3, y: -minY, id: this.nextId++ };
    }
    fits(cells, px, py) {
      for (const c of cells) {
        const bx = px + c.x;
        const by = py + c.y;
        if (bx < 0 || bx >= COLS || by >= ROWS) return false;
        if (by >= 0 && this.board[idx(bx, by)]) return false;
      }
      return true;
    }
    canPlace(p, dx, dy) {
      return this.fits(p.cells, p.x + dx, p.y + dy);
    }
    ghostY() {
      const p = this.piece;
      if (!p) return 0;
      let d = 0;
      while (this.canPlace(p, 0, d + 1)) d++;
      return p.y + d;
    }

    spawn() {
      this.spawnDef(this.queue.shift());
      while (this.queue.length < 5) this.queue.push(this.genDef());
    }
    spawnDef(def) {
      const p = this.makePiece(def);
      this.legal = [];
      this.legalCells = new Set();
      if (!this.canPlace(p, 0, 0)) {
        if (this.canPlace(p, 0, -1)) p.y -= 1;
        else {
          this.piece = p;
          this.gameOver();
          return;
        }
      }
      this.piece = p;
      this.phase = 'fall';
      this.fallAcc = 0;
      this.lockTimer = 0;
      this.lockResets = 0;
      this.lowestY = p.y;
      this.grounded = false;
      this.emit('spawn', { piece: p });
    }

    afterMove() {
      const p = this.piece;
      if (!this.canPlace(p, 0, 1)) {
        if (this.lockResets < T.MAX_LOCK_RESETS) {
          this.lockTimer = 0;
          this.lockResets++;
        }
      }
    }
    move(dx) {
      if (this.phase !== 'fall' || !this.piece) return false;
      if (!this.canPlace(this.piece, dx, 0)) return false;
      this.piece.x += dx;
      this.afterMove();
      this.emit('move', { dx });
      return true;
    }
    rotate(dir) {
      if (this.phase !== 'fall' || !this.piece) return false;
      const p = this.piece;
      const n = SHAPES[p.type].n;
      const cells = p.cells.map((c) =>
        dir > 0 ? { x: n - 1 - c.y, y: c.x, c: c.c } : { x: c.y, y: n - 1 - c.x, c: c.c }
      );
      const to = (p.rot + (dir > 0 ? 1 : 3)) % 4;
      const kicks = p.type === 'O' ? [[0, 0]] : (p.type === 'I' ? KICKS_I : KICKS_JLSTZ)[p.rot + '>' + to];
      for (const [kx, ky] of kicks) {
        if (this.fits(cells, p.x + kx, p.y - ky)) {
          p.cells = cells;
          p.x += kx;
          p.y -= ky;
          p.rot = to;
          this.afterMove();
          this.emit('rotate', { dir });
          return true;
        }
      }
      return false;
    }
    setSoftDrop(on) {
      this.softDropping = !!on;
    }
    softDropStep() {
      if (this.phase !== 'fall' || !this.piece) return false;
      if (!this.canPlace(this.piece, 0, 1)) return false;
      this.piece.y++;
      this.score += 1;
      this.onDescend();
      return true;
    }
    onDescend() {
      this.fallAcc = 0;
      this.lockTimer = 0;
      if (this.piece.y > this.lowestY) {
        this.lowestY = this.piece.y;
        this.lockResets = 0;
      }
    }
    hardDrop() {
      if (this.phase !== 'fall' || !this.piece) return false;
      const p = this.piece;
      const fromY = p.y;
      let d = 0;
      while (this.canPlace(p, 0, 1)) {
        p.y++;
        d++;
      }
      this.score += 2 * d;
      this.emit('harddrop', { dist: d, fromY, piece: p });
      this.lock();
      return true;
    }
    holdPiece() {
      if (this.phase !== 'fall' || !this.piece || this.holdUsed) return false;
      const def = this.piece.def;
      const prev = this.hold;
      this.hold = def;
      if (prev) this.spawnDef(prev);
      else this.spawn();
      this.holdUsed = true;
      this.emit('hold', {});
      return true;
    }

    updateFall(dt) {
      const p = this.piece;
      const g = this.gravity();
      const interval = this.softDropping ? Math.min(T.SOFT_INTERVAL, g) : g;
      this.fallAcc += dt;
      while (this.fallAcc >= interval) {
        this.fallAcc -= interval;
        if (this.canPlace(p, 0, 1)) {
          p.y++;
          if (this.softDropping) this.score += 1;
          const acc = this.fallAcc;
          this.onDescend();
          this.fallAcc = acc;
        } else {
          this.fallAcc = 0;
          break;
        }
      }
      if (!this.canPlace(p, 0, 1)) {
        if (!this.grounded) {
          this.grounded = true;
          this.emit('land', {});
        }
        this.lockTimer += dt;
        if (this.lockTimer >= T.LOCK_DELAY) this.lock();
      } else {
        this.grounded = false;
      }
    }

    lock() {
      const p = this.piece;
      const cells = [];
      let out = false;
      for (const c of p.cells) {
        const bx = p.x + c.x;
        const by = p.y + c.y;
        if (by < 0) {
          out = true;
          continue;
        }
        const i = idx(bx, by);
        this.board[i] = this.mkCell(c.c, SP.NONE);
        cells.push(i);
      }
      this.piece = null;
      this.softDropping = false;
      this.stats.pieces++;
      this.holdUsed = false;
      this.emit('lock', { cells });
      if (out) {
        this.gameOver();
        return;
      }
      this.charge(landChargeFor(this.level));
      this.focus = cells.slice();
      this.chain = 0;
      this.startResolve();
    }

    // ---------- matching ----------
    findRuns() {
      const b = this.board;
      const runs = [];
      for (let y = 0; y < ROWS; y++) {
        let x = 0;
        while (x < COLS) {
          const c = b[idx(x, y)];
          if (!c) {
            x++;
            continue;
          }
          let e = x + 1;
          while (e < COLS && b[idx(e, y)] && b[idx(e, y)].c === c.c) e++;
          if (e - x >= 3) {
            const cells = [];
            for (let k = x; k < e; k++) cells.push(idx(k, y));
            runs.push({ dir: 'h', cells, c: c.c });
          }
          x = e;
        }
      }
      for (let x = 0; x < COLS; x++) {
        let y = 0;
        while (y < ROWS) {
          const c = b[idx(x, y)];
          if (!c) {
            y++;
            continue;
          }
          let e = y + 1;
          while (e < ROWS && b[idx(x, e)] && b[idx(x, e)].c === c.c) e++;
          if (e - y >= 3) {
            const cells = [];
            for (let k = y; k < e; k++) cells.push(idx(x, k));
            runs.push({ dir: 'v', cells, c: c.c });
          }
          y = e;
        }
      }
      return runs;
    }
    findGroups() {
      const runs = this.findRuns();
      if (!runs.length) return [];
      const parent = runs.map((_, i) => i);
      const find = (i) => (parent[i] === i ? i : (parent[i] = find(parent[i])));
      const owner = new Map();
      runs.forEach((r, ri) => {
        for (const cell of r.cells) {
          if (owner.has(cell)) parent[find(ri)] = find(owner.get(cell));
          else owner.set(cell, ri);
        }
      });
      const groups = new Map();
      runs.forEach((r, ri) => {
        const root = find(ri);
        if (!groups.has(root)) groups.set(root, { cells: new Set(), runs: [], c: r.c });
        const g = groups.get(root);
        g.runs.push(r);
        for (const cell of r.cells) g.cells.add(cell);
      });
      return Array.from(groups.values());
    }
    pickFocus(cells, fallback) {
      for (const f of this.focus) if (cells.includes(f)) return f;
      return fallback;
    }
    specialFor(g) {
      let longest = g.runs[0];
      for (const r of g.runs) if (r.cells.length > longest.cells.length) longest = r;
      const hasH = g.runs.some((r) => r.dir === 'h');
      const hasV = g.runs.some((r) => r.dir === 'v');
      const len = longest.cells.length;
      let s = SP.NONE;
      if (len >= 5) s = SP.PRISM;
      else if (hasH && hasV) s = SP.BOMB;
      else if (len === 4) s = longest.dir === 'h' ? SP.LINE_H : SP.LINE_V;
      if (!s) return null;
      let pos;
      if (s === SP.BOMB) {
        const counts = new Map();
        for (const r of g.runs) for (const c of r.cells) counts.set(c, (counts.get(c) || 0) + 1);
        const inter = Array.from(counts.keys()).filter((c) => counts.get(c) > 1);
        pos = this.pickFocus(inter, inter[0]);
      } else {
        const cells = longest.cells;
        pos = this.pickFocus(cells, cells[(cells.length - 1) >> 1]);
      }
      return { idx: pos, c: g.c, s };
    }

    // ---------- resolution ----------
    startResolve() {
      const groups = this.findGroups();
      if (groups.length) {
        this.chain++;
        this.beginClear(groups, null);
      } else this.resolveDone();
    }

    detonate(i, s, color, effects) {
      const x = cx(i);
      const y = cy(i);
      const out = [];
      const b = this.board;
      if (s === SP.LINE_H) {
        for (let k = 0; k < COLS; k++) out.push(idx(k, y));
        effects.push({ t: 'lineH', x, y, c: color });
      } else if (s === SP.LINE_V) {
        for (let k = 0; k < ROWS; k++) out.push(idx(x, k));
        effects.push({ t: 'lineV', x, y, c: color });
      } else if (s === SP.BOMB) {
        for (let yy = y - 1; yy <= y + 1; yy++)
          for (let xx = x - 1; xx <= x + 1; xx++)
            if (xx >= 0 && xx < COLS && yy >= 0 && yy < ROWS) out.push(idx(xx, yy));
        effects.push({ t: 'bomb', x, y, r: 1, c: color });
      } else if (s === SP.PRISM) {
        for (let k = 0; k < b.length; k++) if (b[k] && b[k].c === color) out.push(k);
        effects.push({ t: 'prism', x, y, c: color, targets: out.slice() });
      }
      return out.filter((k) => b[k]);
    }

    /**
     * Start a clear step. `groups` are colour matches; `combo` is an optional
     * pre-computed swap combo { cells, triggered, overrides, effects, bonus, kind }.
     */
    beginClear(groups, combo) {
      const b = this.board;
      const toClear = new Set();
      const created = [];
      const effects = [];
      let base = 0;
      let groupBlocks = 0;
      for (const g of groups) {
        for (const i of g.cells) toClear.add(i);
        base += groupPoints(g.cells.size);
        groupBlocks += g.cells.size;
        const sp = this.specialFor(g);
        if (sp) created.push(sp);
      }
      const triggered = new Set();
      const overrides = new Map();
      const queue = [];
      if (combo) {
        for (const i of combo.cells) toClear.add(i);
        for (const i of combo.triggered) triggered.add(i);
        if (combo.overrides) for (const [k, v] of combo.overrides) overrides.set(k, v);
        for (const e of combo.effects) effects.push(e);
        if (combo.queue) for (const i of combo.queue) queue.push(i);
      }
      for (const i of toClear) if (b[i] && b[i].s && !triggered.has(i)) queue.push(i);
      while (queue.length) {
        const i = queue.shift();
        if (triggered.has(i) || !b[i]) continue;
        triggered.add(i);
        const s = overrides.has(i) ? overrides.get(i) : b[i].s;
        const area = this.detonate(i, s, b[i].c, effects);
        for (const j of area) {
          if (!toClear.has(j)) {
            toClear.add(j);
            if (b[j].s && !triggered.has(j)) queue.push(j);
          }
        }
      }
      const cells = Array.from(toClear).filter((i) => b[i]);
      const total = cells.length;
      const extra = Math.max(0, total - groupBlocks);
      let pts = base + extra * 15;
      if (groups.length > 1) pts *= 1 + 0.5 * (groups.length - 1);
      pts *= Math.max(1, this.chain);
      for (const sp of created) pts += SPECIAL_BONUS[sp.s];
      if (combo) pts += COMBO_BONUS[combo.kind] || 0;
      pts = Math.round(pts) * this.level;
      this.score += pts;

      // swap meter, tokens, stats
      this.charge(total * Math.max(1, this.chain) + created.length * 6);
      if ((this.chain === 3 || this.chain === 5) && this.tokens < MAX_TOKENS) {
        this.tokens++;
        this.emit('swapGained', { count: 1 });
      }
      this.stats.maxChain = Math.max(this.stats.maxChain, this.chain);
      this.stats.specials += created.length;
      this.stats.bestClear = Math.max(this.stats.bestClear, total);

      const oldLevel = this.level;
      this.cleared += total;
      this.level = Math.min(MAX_LEVEL, 1 + Math.floor(this.cleared / BLOCKS_PER_LEVEL));

      const info = cells.map((i) => ({ i, c: b[i].c, s: b[i].s }));
      this.clearing = { cells: new Set(cells), created, effects };
      this.phase = 'clear';
      this.phaseDur = this.timer = effects.length ? T.CLEAR_FX : T.CLEAR;
      this.emit('clear', {
        chain: this.chain,
        groups: groups.length,
        cells: info,
        created,
        effects,
        points: pts,
        total,
        combo: combo ? combo.kind : null,
      });
      if (this.level > oldLevel) {
        this.emit('levelup', { level: this.level, newColor: paletteFor(this.level) > paletteFor(oldLevel) });
      }
    }

    finishClear() {
      const b = this.board;
      const { cells, created } = this.clearing;
      const removed = [];
      for (const i of cells) {
        if (b[i]) removed.push({ i, c: b[i].c, s: b[i].s });
        b[i] = null;
      }
      const made = [];
      for (const sp of created) {
        b[sp.idx] = this.mkCell(sp.c, sp.s);
        made.push({ i: sp.idx, c: sp.c, s: sp.s, id: b[sp.idx].id });
      }
      this.clearing = null;
      this.emit('cleared', { removed, made });
      this.applyGravity();
    }

    applyGravity() {
      const b = this.board;
      let maxDist = 0;
      const moved = [];
      for (let x = 0; x < COLS; x++) {
        let write = ROWS - 1;
        for (let y = ROWS - 1; y >= 0; y--) {
          const c = b[idx(x, y)];
          if (!c) continue;
          if (y !== write) {
            b[idx(x, write)] = c;
            b[idx(x, y)] = null;
            c.fall = write - y;
            maxDist = Math.max(maxDist, c.fall);
            moved.push(idx(x, write));
          }
          write--;
        }
      }
      if (maxDist > 0) {
        this.focus = moved;
        this.phase = 'drop';
        this.dropT = 0;
        this.dropDur = Math.sqrt((2 * maxDist) / T.DROP_ACCEL) + T.DROP_SETTLE;
        this.phaseDur = this.dropDur;
      } else this.finishDrop();
    }

    finishDrop() {
      for (const c of this.board) if (c) c.fall = 0;
      const groups = this.findGroups();
      if (groups.length) {
        this.chain++;
        this.beginClear(groups, null);
      } else this.resolveDone();
    }

    resolveDone() {
      if (this.chain > 0) this.emit('chainEnd', { chain: this.chain });
      this.chain = 0;
      if (this.swapsAvailable() > 0) {
        this.computeLegal();
        if (this.legal.length) {
          this.phase = 'swap';
          this.timer = this.phaseDur = this.swapWindow();
          this.swapHold = false;
          this.emit('swapPhase', { count: this.legal.length });
          return;
        }
      }
      this.toSpawn();
    }

    toSpawn() {
      this.phase = 'spawn';
      this.timer = this.phaseDur = T.SPAWN;
      this.legal = [];
      this.legalCells = new Set();
    }

    // ---------- swaps ----------
    runLenAt(i) {
      const b = this.board;
      const c = b[i].c;
      const x = cx(i);
      const y = cy(i);
      let h = 1;
      for (let k = x - 1; k >= 0 && b[idx(k, y)] && b[idx(k, y)].c === c; k--) h++;
      for (let k = x + 1; k < COLS && b[idx(k, y)] && b[idx(k, y)].c === c; k++) h++;
      let v = 1;
      for (let k = y - 1; k >= 0 && b[idx(x, k)] && b[idx(x, k)].c === c; k--) v++;
      for (let k = y + 1; k < ROWS && b[idx(x, k)] && b[idx(x, k)].c === c; k++) v++;
      return Math.max(h, v);
    }
    swapKind(a, c) {
      const b = this.board;
      const A = b[a];
      const B = b[c];
      if (!A || !B) return null;
      if (A.s === SP.PRISM || B.s === SP.PRISM || (A.s && B.s)) return 'combo';
      if (A.c === B.c) return null;
      b[a] = B;
      b[c] = A;
      const ok = this.runLenAt(a) >= 3 || this.runLenAt(c) >= 3;
      b[a] = A;
      b[c] = B;
      return ok ? 'match' : null;
    }
    computeLegal() {
      const legal = [];
      const cells = new Set();
      for (let i = 0; i < this.board.length; i++) {
        if (!this.board[i]) continue;
        const x = cx(i);
        const y = cy(i);
        const nbrs = [];
        if (x < COLS - 1) nbrs.push(i + 1);
        if (y < ROWS - 1) nbrs.push(i + COLS);
        for (const j of nbrs) {
          if (this.board[j] && this.swapKind(i, j)) {
            legal.push([i, j]);
            cells.add(i);
            cells.add(j);
          }
        }
      }
      this.legal = legal;
      this.legalCells = cells;
      return legal;
    }
    partnersOf(i) {
      const out = [];
      for (const [a, b] of this.legal) {
        if (a === i) out.push(b);
        else if (b === i) out.push(a);
      }
      return out;
    }
    static adjacent(a, b) {
      const dx = Math.abs(cx(a) - cx(b));
      const dy = Math.abs(cy(a) - cy(b));
      return dx + dy === 1;
    }

    /** Swap the block at `from` into `to`. Returns 'ok', 'illegal', or a reason string. */
    trySwap(from, to) {
      if (this.phase !== 'swap') return 'phase';
      if (from < 0 || to < 0 || from >= this.board.length || to >= this.board.length) return 'range';
      if (!Game.adjacent(from, to)) return 'adjacent';
      if (!this.board[from] || !this.board[to]) return 'empty';
      if (this.swapsAvailable() <= 0) return 'none';
      const kind = this.swapKind(from, to);
      this.swapA = from;
      this.swapB = to;
      if (!kind) {
        this.swapRemain = this.timer;
        this.phase = 'swapBack';
        this.timer = this.phaseDur = T.SWAP * 2;
        this.emit('swapFail', { from, to });
        return 'illegal';
      }
      this.tokens--;
      this.stats.swaps++;
      const b = this.board;
      const t = b[from];
      b[from] = b[to];
      b[to] = t;
      this.pendingKind = kind;
      this.phase = 'swapAnim';
      this.timer = this.phaseDur = T.SWAP;
      this.emit('swap', { from, to, kind });
      return 'ok';
    }
    skipSwap() {
      if (this.phase !== 'swap') return false;
      this.emit('swapSkip', {});
      this.toSpawn();
      return true;
    }

    finishSwapAnim() {
      const a = this.swapA;
      const t = this.swapB;
      this.swapA = this.swapB = -1;
      this.chain = 1;
      if (this.pendingKind === 'combo') {
        this.beginClear([], this.buildCombo(t, a));
      } else {
        this.focus = [t, a];
        const groups = this.findGroups();
        if (groups.length) this.beginClear(groups, null);
        else this.resolveDone();
      }
    }

    /** `t` holds the block the player moved, `o` holds the other one. */
    buildCombo(t, o) {
      const b = this.board;
      const A = b[t];
      const B = b[o];
      const x = cx(t);
      const y = cy(t);
      const cells = new Set([t, o]);
      const triggered = new Set([t, o]);
      const overrides = new Map();
      const effects = [];
      const queue = [];
      let kind;
      const addRect = (x0, y0, x1, y1) => {
        for (let yy = Math.max(0, y0); yy <= Math.min(ROWS - 1, y1); yy++)
          for (let xx = Math.max(0, x0); xx <= Math.min(COLS - 1, x1); xx++)
            if (b[idx(xx, yy)]) cells.add(idx(xx, yy));
      };
      const addColor = (c) => {
        const list = [];
        for (let k = 0; k < b.length; k++)
          if (b[k] && b[k].c === c) {
            cells.add(k);
            list.push(k);
          }
        return list;
      };
      const pA = A.s === SP.PRISM;
      const pB = B.s === SP.PRISM;
      if (pA && pB) {
        kind = 'wipe2';
        const c1 = A.c;
        let c2 = B.c;
        if (c2 === c1) {
          const counts = new Map();
          for (const cell of b) if (cell && cell.c !== c1) counts.set(cell.c, (counts.get(cell.c) || 0) + 1);
          let best = -1;
          for (const [c, n] of counts) if (n > best) {
            best = n;
            c2 = c;
          }
        }
        const t1 = addColor(c1);
        effects.push({ t: 'prism', x, y, c: c1, targets: t1 });
        if (c2 !== c1) {
          const t2 = addColor(c2);
          effects.push({ t: 'prism', x: cx(o), y: cy(o), c: c2, targets: t2 });
        }
      } else if (pA || pB) {
        const P = pA ? A : B;
        const X = pA ? B : A;
        const pi = pA ? t : o;
        const target = X.c;
        const list = addColor(target);
        effects.push({ t: 'prism', x: cx(pi), y: cy(pi), c: target, targets: list });
        if (isLine(X.s)) {
          kind = 'wipeLines';
          for (const k of list) {
            if (triggered.has(k)) continue;
            overrides.set(k, this.rng() < 0.5 ? SP.LINE_H : SP.LINE_V);
            queue.push(k);
          }
        } else if (X.s === SP.BOMB) {
          kind = 'wipeBombs';
          for (const k of list) {
            if (triggered.has(k)) continue;
            overrides.set(k, SP.BOMB);
            queue.push(k);
          }
        } else kind = 'wipe';
        void P;
      } else if (isLine(A.s) && isLine(B.s)) {
        kind = 'cross';
        addRect(0, y, COLS - 1, y);
        addRect(x, 0, x, ROWS - 1);
        effects.push({ t: 'lineH', x, y, c: A.c }, { t: 'lineV', x, y, c: B.c });
      } else if ((isLine(A.s) && B.s === SP.BOMB) || (A.s === SP.BOMB && isLine(B.s))) {
        kind = 'wide';
        addRect(0, y - 1, COLS - 1, y + 1);
        addRect(x - 1, 0, x + 1, ROWS - 1);
        for (let k = -1; k <= 1; k++) {
          effects.push({ t: 'lineH', x, y: y + k, c: A.c, wide: true });
          effects.push({ t: 'lineV', x: x + k, y, c: B.c, wide: true });
        }
      } else {
        kind = 'mega';
        addRect(x - 2, y - 2, x + 2, y + 2);
        effects.push({ t: 'bomb', x, y, r: 2, c: A.c });
      }
      return { kind, cells, triggered, overrides, effects, queue };
    }

    // ---------- loop ----------
    update(dt) {
      if (this.phase === 'over') return;
      this.stats.time += dt;
      switch (this.phase) {
        case 'spawn':
          this.timer -= dt;
          if (this.timer <= 0) this.spawn();
          break;
        case 'fall':
          this.updateFall(dt);
          break;
        case 'clear':
          this.timer -= dt;
          if (this.timer <= 0) this.finishClear();
          break;
        case 'drop':
          this.dropT += dt;
          if (this.dropT >= this.dropDur) this.finishDrop();
          break;
        case 'swap':
          if (!this.relaxed && !this.swapHold) {
            this.timer -= dt;
            if (this.timer <= 0) {
              this.emit('swapTimeout', {});
              this.toSpawn();
            }
          }
          break;
        case 'swapAnim':
          this.timer -= dt;
          if (this.timer <= 0) this.finishSwapAnim();
          break;
        case 'swapBack':
          this.timer -= dt;
          if (this.timer <= 0) {
            this.swapA = this.swapB = -1;
            this.phase = 'swap';
            this.phaseDur = this.swapWindow();
            this.timer = Math.min(this.phaseDur, Math.max(this.swapRemain || 0, 1));
          }
          break;
      }
    }

    gameOver() {
      this.phase = 'over';
      this.emit('gameover', { score: this.score });
    }

    // ---------- persistence ----------
    /** Snapshot taken at spawn time: restoring it replays the current piece from the top. */
    serialize() {
      return {
        v: 1,
        board: this.board.map((c) => (c ? [c.c, c.s] : 0)),
        current: this.piece ? this.piece.def : null,
        hold: this.hold,
        holdUsed: this.holdUsed,
        queue: this.queue,
        bag: this.bag,
        score: this.score,
        level: this.level,
        cleared: this.cleared,
        tokens: this.tokens,
        meter: this.meter,
        stats: this.stats,
      };
    }
    static restore(data, opts) {
      const g = new Game(opts);
      if (!data || data.v !== 1 || !Array.isArray(data.board) || data.board.length !== COLS * ROWS) return null;
      g.board = data.board.map((v) => (v ? g.mkCell(v[0], v[1]) : null));
      g.hold = data.hold || null;
      g.holdUsed = !!data.holdUsed;
      g.queue = data.queue.slice();
      g.bag = data.bag.slice();
      g.score = data.score | 0;
      g.level = data.level | 0 || 1;
      g.cleared = data.cleared | 0;
      g.tokens = data.tokens | 0;
      g.meter = data.meter | 0;
      g.stats = Object.assign(g.stats, data.stats || {});
      while (g.queue.length < 5) g.queue.push(g.genDef());
      if (data.current) g.spawnDef(data.current);
      else g.spawn();
      g.events.length = 0;
      return g;
    }

    /** Deep copy for simulations (tests, demo bot). */
    clone() {
      const g = Object.create(Game.prototype);
      Object.assign(g, this);
      g.events = [];
      g.board = this.board.map((c) => (c ? Object.assign({}, c) : null));
      g.piece = this.piece
        ? Object.assign({}, this.piece, { cells: this.piece.cells.map((c) => Object.assign({}, c)) })
        : null;
      g.queue = this.queue.slice();
      g.bag = this.bag.slice();
      g.stats = Object.assign({}, this.stats);
      g.focus = this.focus.slice();
      g.legal = this.legal.slice();
      g.legalCells = new Set(this.legalCells);
      g.clearing = null;
      return g;
    }

    /** Test helper: rows of chars, '.' empty, digits are colours, letters h/v/b/p add specials to the previous digit. */
    setBoard(rows) {
      this.board.fill(null);
      const offset = ROWS - rows.length;
      rows.forEach((row, r) => {
        let x = 0;
        for (let k = 0; k < row.length; k++) {
          const ch = row[k];
          if (ch === '.') {
            x++;
            continue;
          }
          if (ch >= '0' && ch <= '9') {
            let s = SP.NONE;
            const nx = row[k + 1];
            if (nx === 'h') s = SP.LINE_H;
            else if (nx === 'v') s = SP.LINE_V;
            else if (nx === 'b') s = SP.BOMB;
            else if (nx === 'p') s = SP.PRISM;
            if (s) k++;
            this.board[idx(x, offset + r)] = this.mkCell(+ch, s);
            x++;
          }
        }
      });
    }
  }

  return {
    COLS,
    ROWS,
    SP,
    T,
    SHAPES,
    TYPES,
    MAX_TOKENS,
    METER_MAX,
    MAX_LEVEL,
    BLOCKS_PER_LEVEL,
    Game,
    idx,
    cx,
    cy,
    gravityFor,
    paletteFor,
    landChargeFor,
    swapWindowFor,
  };
});
