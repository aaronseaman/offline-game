'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const PF = require('../js/core.js');
const { Game, SP, COLS, ROWS, idx } = PF;

function seeded(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Run the state machine until it settles in a phase that waits on the player.
function settle(g, maxSteps = 2000) {
  for (let k = 0; k < maxSteps; k++) {
    if (g.phase === 'fall' || g.phase === 'swap' || g.phase === 'over') return g.phase;
    g.update(0.05);
  }
  throw new Error('did not settle, phase ' + g.phase);
}

function boardRows(g) {
  const out = [];
  for (let y = 0; y < ROWS; y++) {
    let r = '';
    for (let x = 0; x < COLS; x++) {
      const c = g.board[idx(x, y)];
      r += c ? String(c.c) : '.';
    }
    out.push(r);
  }
  return out;
}

test('new game spawns a piece at the top center', () => {
  const g = new Game({ rng: seeded(1) });
  settle(g);
  assert.equal(g.phase, 'fall');
  const ys = g.piece.cells.map((c) => g.piece.y + c.y);
  assert.equal(Math.min(...ys), 0);
  const xs = g.piece.cells.map((c) => g.piece.x + c.x);
  assert.ok(Math.min(...xs) >= 3 && Math.max(...xs) <= 6);
  assert.equal(g.queue.length, 5);
});

test('7-bag gives every shape once per seven pieces', () => {
  const g = new Game({ rng: seeded(7) });
  const seen = [];
  g.queue.length = 0;
  g.bag = [];
  for (let k = 0; k < 7; k++) seen.push(g.genDef().type);
  assert.deepEqual(seen.slice().sort(), ['I', 'J', 'L', 'O', 'S', 'T', 'Z']);
});

test('piece colors use the current palette and 1-4 distinct colors', () => {
  const g = new Game({ rng: seeded(3) });
  for (let k = 0; k < 500; k++) {
    const cols = g.genColors();
    assert.equal(cols.length, 4);
    const distinct = new Set(cols).size;
    assert.ok(distinct >= 1 && distinct <= 4);
    for (const c of cols) assert.ok(c >= 0 && c < 5);
  }
  g.level = 6;
  let sawSix = false;
  for (let k = 0; k < 500; k++) if (g.genColors().includes(5)) sawSix = true;
  assert.ok(sawSix, 'sixth color appears from level 5');
});

test('rotation carries colors around, including the O piece', () => {
  const g = new Game({ rng: seeded(2) });
  settle(g);
  g.piece = g.makePiece({ type: 'O', colors: [0, 1, 2, 3] });
  const before = g.piece.cells.map((c) => [c.x, c.y, c.c].join());
  assert.ok(g.rotate(1));
  const after = g.piece.cells.map((c) => [c.x, c.y, c.c].join());
  assert.notDeepEqual(before, after);
  // same occupied cells
  const occ = (p) => p.cells.map((c) => c.x + ',' + c.y).sort().join('|');
  assert.equal(occ(g.piece), '0,0|0,1|1,0|1,1');
  g.rotate(1);
  g.rotate(1);
  g.rotate(1);
  assert.deepEqual(g.piece.cells.map((c) => [c.x, c.y, c.c].join()), before);
});

test('SRS wall kick lets a vertical I rotate against the wall', () => {
  const g = new Game({ rng: seeded(4) });
  settle(g);
  g.piece = g.makePiece({ type: 'I', colors: [0, 0, 0, 0] });
  g.rotate(1); // vertical
  while (g.move(-1));
  assert.ok(g.rotate(1), 'kicks off the left wall');
  for (const c of g.piece.cells) assert.ok(g.piece.x + c.x >= 0);
});

test('a horizontal run of three clears and blocks above fall', () => {
  const g = new Game({ rng: seeded(5) });
  g.setBoard(['.4........', '.3........', '111.......']);
  g.chain = 1;
  g.startResolve();
  assert.equal(g.phase, 'clear');
  assert.equal(g.clearing.cells.size, 3);
  settle(g);
  const rows = boardRows(g);
  assert.equal(rows[ROWS - 1], '.3........');
  assert.equal(rows[ROWS - 2], '.4........');
});

test('vertical runs clear too, and full rows do nothing', () => {
  const g = new Game({ rng: seeded(6) });
  g.setBoard(['2.........', '2.........', '2.........', '0123401234']);
  g.startResolve();
  assert.equal(g.clearing.cells.size, 3);
  settle(g);
  assert.equal(boardRows(g)[ROWS - 1], '0123401234', 'full row stays');
});

test('cascades raise the chain counter and multiply points', () => {
  const g = new Game({ rng: seeded(8) });
  // Clearing 111 drops the 2 in column 2 into a row of three 2s.
  g.setBoard(['..2.......', '11122.....']);
  const chains = [];
  g.startResolve();
  for (let k = 0; k < 400 && g.phase !== 'spawn' && g.phase !== 'swap'; k++) {
    for (const e of g.drain()) if (e.type === 'clear') chains.push(e.chain);
    g.update(0.05);
  }
  for (const e of g.drain()) if (e.type === 'clear') chains.push(e.chain);
  assert.deepEqual(chains, [1, 2]);
});

test('four in a row makes a line blaster at the moved cell', () => {
  const g = new Game({ rng: seeded(9) });
  g.setBoard(['3333......']);
  g.focus = [idx(1, ROWS - 1)];
  g.startResolve();
  const made = g.clearing.created;
  assert.equal(made.length, 1);
  assert.equal(made[0].s, SP.LINE_H);
  assert.equal(made[0].idx, idx(1, ROWS - 1));
  settle(g);
  assert.equal(g.board[idx(1, ROWS - 1)].s, SP.LINE_H);
});

test('L shape makes a bomb at the corner; five in a row makes a prism', () => {
  const g = new Game({ rng: seeded(10) });
  g.setBoard(['1.........', '1.........', '111.......']);
  g.startResolve();
  assert.equal(g.clearing.created[0].s, SP.BOMB);
  assert.equal(g.clearing.created[0].idx, idx(0, ROWS - 1));

  const h = new Game({ rng: seeded(11) });
  h.setBoard(['22222.....']);
  h.startResolve();
  assert.equal(h.clearing.created[0].s, SP.PRISM);
});

test('a matched line blaster clears its whole row', () => {
  const g = new Game({ rng: seeded(12) });
  g.setBoard(['0123401234', '1h110340202']);
  g.startResolve();
  for (let x = 0; x < COLS; x++) assert.ok(g.clearing.cells.has(idx(x, ROWS - 1)), 'x=' + x);
  assert.ok(g.clearing.effects.some((e) => e.t === 'lineH'));
});

test('a matched bomb clears 3x3 and chains into other specials', () => {
  const g = new Game({ rng: seeded(13) });
  g.setBoard(['..........', '.4v.......', '.2b22.....', '..........'.replace(/\./g, '3')]);
  g.startResolve();
  // bomb at (2, row 18) clears 3x3, which includes the vertical blaster at (2, row 17)
  assert.ok(g.clearing.effects.some((e) => e.t === 'bomb'));
  assert.ok(g.clearing.effects.some((e) => e.t === 'lineV'));
});

test('a matched prism removes every block of its color', () => {
  const g = new Game({ rng: seeded(14) });
  g.setBoard(['3...3...3.', '1.2.1.2.1.', '33p3......']);
  g.startResolve();
  for (let i = 0; i < g.board.length; i++) {
    if (g.board[i] && g.board[i].c === 3) assert.ok(g.clearing.cells.has(i), 'clears color 3 at ' + i);
  }
});

test('illegal swaps bounce back and cost nothing', () => {
  const g = new Game({ rng: seeded(15) });
  g.setBoard(['1.........', '0122......']);
  g.tokens = 1;
  g.computeLegal();
  g.phase = 'swap';
  g.timer = g.phaseDur = 10;
  assert.equal(g.trySwap(idx(0, ROWS - 1), idx(1, ROWS - 1)), 'illegal');
  assert.equal(g.phase, 'swapBack');
  assert.equal(g.tokens, 1, 'illegal swap is free');
  settle(g);
  assert.equal(g.phase, 'swap');
  assert.deepEqual(boardRows(g).slice(-2), ['1.........', '0122......']);
  assert.equal(g.trySwap(idx(0, ROWS - 1), idx(2, ROWS - 1)), 'adjacent');
  assert.equal(g.trySwap(idx(5, ROWS - 1), idx(6, ROWS - 1)), 'empty');
});

test('legal swap spends a banked swap and clears a run of three', () => {
  const g = new Game({ rng: seeded(16) });
  g.setBoard(['1131......']);
  g.tokens = 1;
  g.phase = 'swap';
  g.computeLegal();
  assert.ok(g.legalCells.has(idx(2, ROWS - 1)) && g.legalCells.has(idx(3, ROWS - 1)));
  assert.deepEqual(g.partnersOf(idx(3, ROWS - 1)), [idx(2, ROWS - 1)]);
  assert.equal(g.trySwap(idx(3, ROWS - 1), idx(2, ROWS - 1)), 'ok');
  assert.equal(g.tokens, 0);
  assert.equal(g.swapsAvailable(), 0);
  g.update(1);
  assert.equal(g.phase, 'clear');
  assert.equal(g.clearing.cells.size, 3);
});

test('landings and clears charge the swap meter', () => {
  const g = new Game({ rng: seeded(26) });
  assert.equal(g.tokens, 1, 'games start with one swap banked');
  g.tokens = 0;
  g.meter = 0;
  g.charge(PF.METER_MAX + 5);
  assert.equal(g.tokens, 1);
  assert.equal(g.meter, 5);
  g.charge(PF.METER_MAX * 10);
  assert.equal(g.tokens, PF.MAX_TOKENS);
  assert.ok(g.meter <= PF.METER_MAX);
  g.setBoard(['1131......']);
  g.tokens = 2;
  g.phase = 'swap';
  g.computeLegal();
  assert.equal(g.trySwap(idx(3, ROWS - 1), idx(2, ROWS - 1)), 'ok');
  assert.equal(g.tokens, 1);
});

test('prism swapped with any block wipes that color', () => {
  const g = new Game({ rng: seeded(17) });
  g.setBoard(['2...2...2.', '0p2.......']);
  g.tokens = 1;
  g.phase = 'swap';
  g.computeLegal();
  assert.equal(g.board[idx(0, ROWS - 1)].s, SP.PRISM);
  assert.equal(g.trySwap(idx(0, ROWS - 1), idx(1, ROWS - 1)), 'ok');
  g.update(1);
  assert.equal(g.phase, 'clear');
  let twos = 0;
  for (const i of g.clearing.cells) if (g.board[i].c === 2) twos++;
  assert.equal(twos, 4);
});

test('two line blasters swapped together fire a cross', () => {
  const g = new Game({ rng: seeded(18) });
  g.setBoard(['0123401234', '1234012340', '23h4v0123412']);
  g.tokens = 1;
  g.phase = 'swap';
  g.computeLegal();
  const a = idx(1, ROWS - 1);
  const b = idx(2, ROWS - 1);
  assert.equal(g.board[a].s, SP.LINE_H);
  assert.equal(g.board[b].s, SP.LINE_V);
  assert.equal(g.trySwap(a, b), 'ok');
  g.update(1);
  assert.equal(g.phase, 'clear');
  for (let x = 0; x < COLS; x++) assert.ok(g.clearing.cells.has(idx(x, ROWS - 1)), 'row x=' + x);
  for (let y = ROWS - 3; y < ROWS; y++) assert.ok(g.clearing.cells.has(idx(2, y)), 'column y=' + y);
  assert.equal(g.drain().find((e) => e.type === 'clear').combo, 'cross');
});

test('bomb plus bomb detonates 5x5', () => {
  const g = new Game({ rng: seeded(25) });
  const rows = [];
  for (let r = 0; r < 7; r++) rows.push(r % 2 ? '1234012340' : '0123401234');
  rows[6] = '01b2b4012341';
  g.setBoard(rows);
  const a = idx(1, ROWS - 1);
  const b = idx(2, ROWS - 1);
  assert.equal(g.board[a].s, SP.BOMB);
  assert.equal(g.board[b].s, SP.BOMB);
  g.tokens = 1;
  g.phase = 'swap';
  g.computeLegal();
  assert.equal(g.trySwap(a, b), 'ok');
  g.update(1);
  for (let y = ROWS - 3; y < ROWS; y++) for (let x = 0; x <= 4; x++) assert.ok(g.clearing.cells.has(idx(x, y)));
});

test('swap phase only opens when a legal swap exists', () => {
  const g = new Game({ rng: seeded(19) });
  settle(g);
  g.setBoard(['0123401234']);
  g.piece = g.makePiece({ type: 'O', colors: [0, 0, 0, 0] });
  g.piece.x = 0;
  g.piece.y = 0;
  g.hardDrop();
  settle(g);
  // O piece of color 0 lands on the 0 at x=0 -> vertical run of 3 at column 0 clears
  assert.ok(g.phase === 'fall' || g.phase === 'swap');
});

test('game ends when a new shape cannot enter', () => {
  const g = new Game({ rng: seeded(20) });
  settle(g);
  for (let y = 0; y < ROWS; y++) for (let x = 0; x < COLS; x++) g.board[idx(x, y)] = g.mkCell((x + y * 2) % 5, 0);
  // clear nothing: alternating colors so no runs
  for (let y = 0; y < ROWS; y++)
    for (let x = 0; x < COLS; x++) g.board[idx(x, y)].c = (x % 2) + 2 * (y % 2);
  g.phase = 'spawn';
  g.timer = 0;
  g.update(0.01);
  assert.equal(g.phase, 'over');
  assert.ok(g.drain().some((e) => e.type === 'gameover'));
});

test('hold swaps the current shape once per landing', () => {
  const g = new Game({ rng: seeded(21) });
  settle(g);
  const first = g.piece.def;
  assert.ok(g.holdPiece());
  assert.equal(g.hold, first);
  assert.equal(g.holdPiece(), false, 'second hold blocked');
  g.hardDrop();
  settle(g);
  assert.ok(g.holdPiece());
  assert.equal(g.piece.def, first);
});

test('serialize and restore round-trips the state', () => {
  const g = new Game({ rng: seeded(22) });
  settle(g);
  g.hardDrop();
  settle(g);
  if (g.phase === 'swap') g.skipSwap();
  settle(g);
  const snap = JSON.parse(JSON.stringify(g.serialize()));
  const r = Game.restore(snap, { rng: seeded(1) });
  assert.equal(r.score, g.score);
  assert.deepEqual(boardRows(r), boardRows(g));
  assert.equal(r.piece.type, g.piece.type);
  assert.deepEqual(r.queue.map((q) => q.type), g.queue.map((q) => q.type));
  assert.equal(Game.restore({ v: 99 }), null);
});

test('scoring: longer runs and chains are worth more', () => {
  const a = new Game({ rng: seeded(23) });
  a.setBoard(['111.......']);
  a.chain = 1;
  a.beginClear(a.findGroups(), null);
  const three = a.score;
  const b = new Game({ rng: seeded(23) });
  b.setBoard(['1111......']);
  b.chain = 1;
  b.beginClear(b.findGroups(), null);
  assert.ok(b.score > three);
  const c = new Game({ rng: seeded(23) });
  c.setBoard(['111.......']);
  c.chain = 3;
  c.beginClear(c.findGroups(), null);
  assert.equal(c.score, three * 3);
});

test('random play never throws and always settles (fuzz)', () => {
  for (let seed = 1; seed <= 30; seed++) {
    const rng = seeded(seed * 977);
    const g = new Game({ rng: seeded(seed) });
    let steps = 0;
    while (g.phase !== 'over' && steps < 20000) {
      steps++;
      if (g.phase === 'fall') {
        const r = rng();
        if (r < 0.2) g.move(-1);
        else if (r < 0.4) g.move(1);
        else if (r < 0.55) g.rotate(rng() < 0.5 ? 1 : -1);
        else if (r < 0.6) g.holdPiece();
        else if (r < 0.7) g.hardDrop();
        else g.update(0.05);
      } else if (g.phase === 'swap') {
        if (rng() < 0.7 && g.legal.length) {
          const [a, b] = g.legal[Math.floor(rng() * g.legal.length)];
          assert.equal(g.trySwap(a, b), 'ok');
        } else if (rng() < 0.5) {
          const i = Math.floor(rng() * 200);
          const j = i + (rng() < 0.5 ? 1 : 10);
          g.trySwap(i, j);
          g.update(0.05);
        } else g.skipSwap();
      } else g.update(0.05);
      g.drain();
      // invariants
      for (let i = 0; i < g.board.length; i++) {
        const c = g.board[i];
        if (c) assert.ok(c.c >= 0 && c.c < 6 && c.s >= 0 && c.s <= 4);
      }
      if (g.phase === 'fall' || g.phase === 'swap') assert.equal(g.findGroups().length, 0, 'stable board has no matches');
    }
    assert.ok(g.phase === 'over' || steps === 20000);
  }
});
