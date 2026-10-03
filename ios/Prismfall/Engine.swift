// Prismfall rules: board, falling shapes, colour matching, gravity, cascades,
// swaps and special blocks. No UI dependencies.

import Foundation

enum Grid {
    static let cols = 7
    static let rows = 16
    static let count = cols * rows

    static func index(_ x: Int, _ y: Int) -> Int { y * cols + x }
    static func x(_ i: Int) -> Int { i % cols }
    static func y(_ i: Int) -> Int { i / cols }
    static func adjacent(_ a: Int, _ b: Int) -> Bool { abs(x(a) - x(b)) + abs(y(a) - y(b)) == 1 }
}

enum Rules {
    static let maxLevel = 25
    static let blocksPerLevel = 36
    static let maxTokens = 3
    static let meterMax = 40.0
    /// Seconds per row in calm mode, where the pace never changes.
    static let calmGravity = 1.0

    static func gravity(_ level: Int) -> Double { max(0.05, 0.9 * pow(0.86, Double(level - 1))) }
    static func palette(_ level: Int) -> Int { level >= 5 ? 6 : 5 }
    static func swapWindow(_ level: Int) -> Double { max(2.0, 4.2 - 0.12 * Double(level - 1)) }
    /// Swap meter points added each time a shape lands.
    static func landCharge(_ level: Int) -> Double { max(5, 10 - Double(level - 1) * 5 / 12) }
    static func groupPoints(_ n: Int) -> Int { 10 * n + 5 * (n - 3) * (n - 2) }
}

enum Timing {
    static let spawn = 0.07
    static let lockDelay = 0.5
    static let maxLockResets = 15
    static let softInterval = 0.028
    static let clear = 0.3
    static let clearFX = 0.44
    /// Rows per second squared for the post-clear gravity animation.
    static let dropAccel = 150.0
    static let dropSettle = 0.1
    static let swap = 0.14
}

enum Special: Int {
    case plain, lineH, lineV, bomb, prism

    var isLine: Bool { self == .lineH || self == .lineV }
    var bonus: Int { [0, 100, 100, 150, 250][rawValue] }
}

enum Combo {
    case cross, wide, mega, wipe, wipeLines, wipeBombs, wipe2

    var bonus: Int {
        switch self {
        case .cross, .wipe: 300
        case .wide, .mega: 500
        case .wipeLines: 800
        case .wipeBombs: 1000
        case .wipe2: 1200
        }
    }
}

/// A set of board cells packed into one word; the board has 112 of them.
struct CellSet: Sequence {
    private var bits: UInt128 = 0

    init() {}
    init(_ cells: some Sequence<Int>) { for i in cells { insert(i) } }

    var isEmpty: Bool { bits == 0 }
    var count: Int { bits.nonzeroBitCount }
    func contains(_ i: Int) -> Bool { bits >> UInt128(i) & 1 == 1 }
    mutating func insert(_ i: Int) { bits |= 1 << UInt128(i) }
    mutating func formUnion(_ other: CellSet) { bits |= other.bits }

    struct Iterator: IteratorProtocol {
        var bits: UInt128
        mutating func next() -> Int? {
            guard bits != 0 else { return nil }
            defer { bits &= bits - 1 }
            return bits.trailingZeroBitCount
        }
    }
    func makeIterator() -> Iterator { Iterator(bits: bits) }
}

struct Cell {
    let id: Int
    var color: Int
    var special = Special.plain
    /// Rows this cell is falling through during the drop phase.
    var fall = 0
}

struct Block {
    var x: Int
    var y: Int
    var color: Int
}

struct PieceDef: Codable, Equatable {
    var type: Int
    var colors: [Int]

    var isValid: Bool { Shape.all.indices.contains(type) && colors.count == 4 && colors.allSatisfy { (0..<6).contains($0) } }
}

struct Piece {
    let id: Int
    let def: PieceDef
    var blocks: [Block]
    var rot = 0
    var x: Int
    var y: Int

    var shape: Shape { Shape.all[def.type] }
}

/// The seven shapes in their SRS spawn orientation inside a `size` box.
/// Cells are listed in path order so colour segments stay contiguous.
struct Shape {
    let size: Int
    let cells: [(x: Int, y: Int)]

    static let all: [Shape] = [
        Shape(size: 4, cells: [(0, 1), (1, 1), (2, 1), (3, 1)]),  // I
        Shape(size: 2, cells: [(0, 0), (1, 0), (1, 1), (0, 1)]),  // O
        Shape(size: 3, cells: [(0, 1), (1, 1), (1, 0), (2, 1)]),  // T
        Shape(size: 3, cells: [(0, 1), (1, 1), (1, 0), (2, 0)]),  // S
        Shape(size: 3, cells: [(0, 0), (1, 0), (1, 1), (2, 1)]),  // Z
        Shape(size: 3, cells: [(0, 0), (0, 1), (1, 1), (2, 1)]),  // J
        Shape(size: 3, cells: [(2, 0), (2, 1), (1, 1), (0, 1)]),  // L
    ]

    // SRS wall kicks, (x, y) with y pointing up as in the published tables.
    // Indexed by `rot * 2`, plus one when turning counter-clockwise.
    static let kicks: [[(Int, Int)]] = [
        [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],  // 0>1
        [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],     // 0>3
        [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],      // 1>2
        [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],      // 1>0
        [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],     // 2>3
        [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],  // 2>1
        [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],   // 3>0
        [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],   // 3>2
    ]
    static let kicksI: [[(Int, Int)]] = [
        [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)],    // 0>1
        [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)],    // 0>3
        [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)],    // 1>2
        [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)],    // 1>0
        [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)],    // 2>3
        [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)],    // 2>1
        [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)],    // 3>0
        [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)],    // 3>2
    ]
}

struct Stats: Codable {
    var pieces = 0
    var maxChain = 0
    var specials = 0
    var swaps = 0
    var bestClear = 0
    var time = 0.0
}

enum Effect {
    case lineH(y: Int, color: Int, wide: Bool)
    case lineV(x: Int, color: Int, wide: Bool)
    case bomb(x: Int, y: Int, radius: Int, color: Int)
    case prism(x: Int, y: Int, color: Int, targets: [Int])
}

struct Created {
    let index: Int
    let color: Int
    let special: Special
}

struct Clear {
    let chain: Int
    let cells: [Int]
    let created: [Created]
    let effects: [Effect]
    let points: Int
    let combo: Combo?
}

enum Event {
    case spawn(Piece)
    case move
    case rotate(Int)
    case land
    case hardDrop(distance: Int, fromY: Int, piece: Piece)
    case lock([Int])
    case hold
    case clear(Clear)
    case cleared(removed: [(index: Int, color: Int)], made: [Int])
    case levelUp(level: Int, newColor: Bool)
    case swapGained(Int)
    case swapPhase
    case swap
    case swapFail(Int, Int)
    case swapEnded
    case gameOver
}

final class Game {
    enum Phase { case spawn, fall, clear, drop, swap, swapAnim, swapBack, over }
    enum SwapResult { case ok, illegal, rejected }

    struct Run {
        let horizontal: Bool
        let cells: [Int]
        let color: Int
    }
    struct Group {
        var cells = CellSet()
        var runs: [Run] = []
        let color: Int
    }
    struct Clearing {
        let cells: CellSet
        let created: [Created]
    }
    /// A swap of two specials (or a prism with anything), worked out before the clear starts.
    struct SwapCombo {
        var kind: Combo
        var cells: CellSet
        var triggered: CellSet
        var overrides: [Int: Special] = [:]
        var effects: [Effect] = []
        var queue: [Int] = []
    }

    /// Calm mode holds the pace, palette and colour mix at their opening values and never times a swap.
    let calm: Bool
    var relaxed: Bool
    var rng: () -> Double

    var board = [Cell?](repeating: nil, count: Grid.count)
    var score = 0
    var level = 1
    var cleared = 0
    var stats = Stats()
    var bag: [Int] = []
    var queue: [PieceDef] = []
    var hold: PieceDef?
    var holdUsed = false
    var tokens = 1
    var meter = 0.0
    var piece: Piece?
    var chain = 0
    var focus: [Int] = []
    var clearing: Clearing?
    var legal: [(Int, Int)] = []
    var legalCells = CellSet()
    var swapA = -1
    var swapB = -1
    /// Set while a finger is down during the swap phase, so the window cannot run out mid-gesture.
    var swapHold = false
    var softDropping = false
    var phase = Phase.spawn
    var timer = 0.25
    var phaseDur = 0.25
    var lockTimer = 0.0
    var grounded = false
    var dropT = 0.0

    private var events: [Event] = []
    private var nextID = 1
    private var fallAcc = 0.0
    private var lockResets = 0
    private var lowestY = 0
    private var dropDur = 0.0
    private var swapRemain = 0.0
    private var pendingCombo = false

    init(calm: Bool = false, relaxed: Bool = false, rng: @escaping () -> Double = { .random(in: 0..<1) }) {
        self.calm = calm
        self.relaxed = relaxed
        self.rng = rng
        fillQueue()
    }

    private func emit(_ e: Event) { events.append(e) }
    func drain() -> [Event] {
        guard !events.isEmpty else { return [] }
        defer { events = [] }
        return events
    }

    // MARK: Generation

    private func rand(_ n: Int) -> Int { Int(rng() * Double(n)) }
    private func shuffle<T>(_ a: inout [T]) {
        for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, rand(i + 1)) }
    }
    private func fillQueue() {
        while queue.count < 5 { queue.append(genDef()) }
    }
    func genDef() -> PieceDef {
        if bag.isEmpty {
            bag = Array(Shape.all.indices)
            shuffle(&bag)
        }
        return PieceDef(type: bag.removeLast(), colors: genColors())
    }
    func genColors() -> [Int] {
        let t = min(1, Double(difficulty - 1) / 12)
        let w = [0.3 - 0.22 * t, 0.55 - 0.15 * t, 0.15 + 0.22 * t, 0.15 * t]
        var r = rng() * (w[0] + w[1] + w[2] + w[3])
        var k = 1
        for i in 0..<4 {
            if r < w[i] {
                k = i + 1
                break
            }
            r -= w[i]
        }
        // split the 4-cell path into k contiguous segments
        var cuts = [1, 2, 3]
        shuffle(&cuts)
        cuts = cuts.prefix(k - 1).sorted()
        var palette = Array(0..<paletteSize)
        shuffle(&palette)
        var seg = 0
        return (0..<4).map { i in
            if seg < cuts.count && i == cuts[seg] { seg += 1 }
            return palette[seg]
        }
    }
    private func makeCell(_ color: Int, _ special: Special = .plain) -> Cell {
        nextID += 1
        return Cell(id: nextID, color: color, special: special)
    }

    // MARK: Derived values

    private var difficulty: Int { calm ? 1 : level }
    var untimed: Bool { calm || relaxed }
    var gravity: Double { calm ? Rules.calmGravity : Rules.gravity(level) }
    var paletteSize: Int { Rules.palette(difficulty) }
    var swapWindow: Double { untimed ? .infinity : Rules.swapWindow(level) }
    var levelProgress: Double {
        level >= Rules.maxLevel ? 1 : Double(cleared % Rules.blocksPerLevel) / Double(Rules.blocksPerLevel)
    }
    var highestRow: Int { board.firstIndex { $0 != nil }.map(Grid.y) ?? Grid.rows }

    /// Add swap-meter points; a full meter becomes a banked swap.
    func charge(_ points: Double) {
        let before = tokens
        meter += points
        while meter >= Rules.meterMax && tokens < Rules.maxTokens {
            meter -= Rules.meterMax
            tokens += 1
        }
        if tokens >= Rules.maxTokens { meter = min(meter, Rules.meterMax) }
        if tokens > before { emit(.swapGained(tokens - before)) }
    }

    // MARK: Piece handling

    func makePiece(_ def: PieceDef) -> Piece {
        let shape = Shape.all[def.type]
        let blocks = shape.cells.enumerated().map { Block(x: $1.x, y: $1.y, color: def.colors[$0]) }
        nextID += 1
        // centered: 3-wide shapes in columns 2-4, the I in 1-4, the O in 2-3
        return Piece(id: nextID, def: def, blocks: blocks, x: (Grid.cols - shape.size) / 2, y: -blocks.map(\.y).min()!)
    }
    private func fits(_ blocks: [Block], _ px: Int, _ py: Int) -> Bool {
        for b in blocks {
            let x = px + b.x
            let y = py + b.y
            if x < 0 || x >= Grid.cols || y >= Grid.rows { return false }
            if y >= 0 && board[Grid.index(x, y)] != nil { return false }
        }
        return true
    }
    private func canPlace(dx: Int, dy: Int) -> Bool {
        guard let p = piece else { return false }
        return fits(p.blocks, p.x + dx, p.y + dy)
    }
    var ghostY: Int {
        guard let p = piece else { return 0 }
        var y = p.y
        while fits(p.blocks, p.x, y + 1) { y += 1 }
        return y
    }

    private func spawnNext() {
        spawn(queue.removeFirst())
        fillQueue()
    }
    private func spawn(_ def: PieceDef) {
        var p = makePiece(def)
        legal = []
        legalCells = CellSet()
        if !fits(p.blocks, p.x, p.y) {
            if fits(p.blocks, p.x, p.y - 1) {
                p.y -= 1
            } else {
                piece = p
                gameOver()
                return
            }
        }
        piece = p
        phase = .fall
        fallAcc = 0
        lockTimer = 0
        lockResets = 0
        lowestY = p.y
        grounded = false
        emit(.spawn(p))
    }

    private func afterMove() {
        if !canPlace(dx: 0, dy: 1) && lockResets < Timing.maxLockResets {
            lockTimer = 0
            lockResets += 1
        }
    }
    @discardableResult func move(_ dx: Int) -> Bool {
        guard phase == .fall, canPlace(dx: dx, dy: 0) else { return false }
        piece!.x += dx
        afterMove()
        emit(.move)
        return true
    }
    @discardableResult func rotate(_ dir: Int) -> Bool {
        guard phase == .fall, let p = piece else { return false }
        let n = p.shape.size
        let turned = p.blocks.map {
            dir > 0 ? Block(x: n - 1 - $0.y, y: $0.x, color: $0.color) : Block(x: $0.y, y: n - 1 - $0.x, color: $0.color)
        }
        let table = p.rot * 2 + (dir > 0 ? 0 : 1)
        let kicks = p.def.type == 1 ? [(0, 0)] : (p.def.type == 0 ? Shape.kicksI : Shape.kicks)[table]
        for (kx, ky) in kicks where fits(turned, p.x + kx, p.y - ky) {
            piece!.blocks = turned
            piece!.x += kx
            piece!.y -= ky
            piece!.rot = (p.rot + (dir > 0 ? 1 : 3)) % 4
            afterMove()
            emit(.rotate(dir))
            return true
        }
        return false
    }
    @discardableResult func softDropStep() -> Bool {
        guard phase == .fall, canPlace(dx: 0, dy: 1) else { return false }
        piece!.y += 1
        score += 1
        onDescend()
        return true
    }
    private func onDescend() {
        fallAcc = 0
        lockTimer = 0
        if piece!.y > lowestY {
            lowestY = piece!.y
            lockResets = 0
        }
    }
    @discardableResult func hardDrop() -> Bool {
        guard phase == .fall, var p = piece else { return false }
        let fromY = p.y
        p.y = ghostY
        piece = p
        score += 2 * (p.y - fromY)
        emit(.hardDrop(distance: p.y - fromY, fromY: fromY, piece: p))
        lock()
        return true
    }
    @discardableResult func holdPiece() -> Bool {
        guard phase == .fall, let p = piece, !holdUsed else { return false }
        let previous = hold
        hold = p.def
        if let previous { spawn(previous) } else { spawnNext() }
        holdUsed = true
        emit(.hold)
        return true
    }

    private func updateFall(_ dt: Double) {
        let interval = softDropping ? min(Timing.softInterval, gravity) : gravity
        fallAcc += dt
        while fallAcc >= interval {
            fallAcc -= interval
            guard canPlace(dx: 0, dy: 1) else {
                fallAcc = 0
                break
            }
            piece!.y += 1
            if softDropping { score += 1 }
            let carried = fallAcc
            onDescend()
            fallAcc = carried
        }
        if canPlace(dx: 0, dy: 1) {
            grounded = false
        } else {
            if !grounded {
                grounded = true
                emit(.land)
            }
            lockTimer += dt
            if lockTimer >= Timing.lockDelay { lock() }
        }
    }

    private func lock() {
        guard let p = piece else { return }
        var cells: [Int] = []
        var out = false
        for b in p.blocks {
            let y = p.y + b.y
            if y < 0 {
                out = true
                continue
            }
            let i = Grid.index(p.x + b.x, y)
            board[i] = makeCell(b.color)
            cells.append(i)
        }
        piece = nil
        softDropping = false
        stats.pieces += 1
        holdUsed = false
        emit(.lock(cells))
        if out {
            gameOver()
            return
        }
        charge(Rules.landCharge(difficulty))
        focus = cells
        chain = 0
        resolve()
    }

    // MARK: Matching

    private func findRuns() -> [Run] {
        var runs: [Run] = []
        func scan(_ outer: Int, _ inner: Int, horizontal: Bool) {
            for a in 0..<outer {
                let at = { (b: Int) in horizontal ? Grid.index(b, a) : Grid.index(a, b) }
                var start = 0
                while start < inner {
                    guard let c = board[at(start)] else {
                        start += 1
                        continue
                    }
                    var end = start + 1
                    while end < inner, board[at(end)]?.color == c.color { end += 1 }
                    if end - start >= 3 {
                        runs.append(Run(horizontal: horizontal, cells: (start..<end).map(at), color: c.color))
                    }
                    start = end
                }
            }
        }
        scan(Grid.rows, Grid.cols, horizontal: true)
        scan(Grid.cols, Grid.rows, horizontal: false)
        return runs
    }
    /// Runs that share a cell merge into one group.
    func findGroups() -> [Group] {
        let runs = findRuns()
        guard !runs.isEmpty else { return [] }
        var parent = Array(runs.indices)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        var owner = [Int](repeating: -1, count: Grid.count)
        for (ri, run) in runs.enumerated() {
            for cell in run.cells {
                if owner[cell] >= 0 { parent[find(ri)] = find(owner[cell]) } else { owner[cell] = ri }
            }
        }
        var groups: [Group] = []
        var slot = [Int](repeating: -1, count: runs.count)
        for (ri, run) in runs.enumerated() {
            let root = find(ri)
            if slot[root] < 0 {
                slot[root] = groups.count
                groups.append(Group(color: run.color))
            }
            groups[slot[root]].runs.append(run)
            groups[slot[root]].cells.formUnion(CellSet(run.cells))
        }
        return groups
    }
    /// The special block a group leaves behind, placed where the player last acted when possible.
    private func special(for group: Group) -> Created? {
        var longest = group.runs[0]
        for run in group.runs where run.cells.count > longest.cells.count { longest = run }
        let crossed = group.runs.contains { $0.horizontal } && group.runs.contains { !$0.horizontal }
        let special: Special
        switch longest.cells.count {
        case 5...: special = .prism
        case _ where crossed: special = .bomb
        case 4: special = longest.horizontal ? .lineH : .lineV
        default: return nil
        }
        let candidates: [Int]
        let fallback: Int
        if special == .bomb {
            var seen = [Int](repeating: 0, count: Grid.count)
            var order: [Int] = []
            for run in group.runs {
                for cell in run.cells {
                    if seen[cell] == 0 { order.append(cell) }
                    seen[cell] += 1
                }
            }
            candidates = order.filter { seen[$0] > 1 }
            fallback = candidates[0]
        } else {
            candidates = longest.cells
            fallback = candidates[(candidates.count - 1) / 2]
        }
        return Created(index: focus.first { candidates.contains($0) } ?? fallback, color: group.color, special: special)
    }

    // MARK: Resolution

    func resolve() {
        let groups = findGroups()
        if groups.isEmpty {
            resolveDone()
        } else {
            chain += 1
            beginClear(groups)
        }
    }

    private func isSpecial(_ i: Int) -> Bool { board[i].map { $0.special != .plain } ?? false }

    private func detonate(_ i: Int, _ special: Special, _ color: Int, _ effects: inout [Effect]) -> [Int] {
        let x = Grid.x(i)
        let y = Grid.y(i)
        var out: [Int] = []
        switch special {
        case .plain:
            break
        case .lineH:
            out = (0..<Grid.cols).map { Grid.index($0, y) }
            effects.append(.lineH(y: y, color: color, wide: false))
        case .lineV:
            out = (0..<Grid.rows).map { Grid.index(x, $0) }
            effects.append(.lineV(x: x, color: color, wide: false))
        case .bomb:
            for yy in max(0, y - 1)...min(Grid.rows - 1, y + 1) {
                for xx in max(0, x - 1)...min(Grid.cols - 1, x + 1) { out.append(Grid.index(xx, yy)) }
            }
            effects.append(.bomb(x: x, y: y, radius: 1, color: color))
        case .prism:
            out = board.indices.filter { board[$0]?.color == color }
            effects.append(.prism(x: x, y: y, color: color, targets: out))
        }
        return out.filter { board[$0] != nil }
    }

    /// Start a clear step from colour matches, a swap combo, or both.
    func beginClear(_ groups: [Group], combo: SwapCombo? = nil) {
        var toClear = CellSet()
        var created: [Created] = []
        var effects = combo?.effects ?? []
        var base = 0
        var groupBlocks = 0
        for group in groups {
            toClear.formUnion(group.cells)
            base += Rules.groupPoints(group.cells.count)
            groupBlocks += group.cells.count
            if let made = special(for: group) { created.append(made) }
        }
        var triggered = combo?.triggered ?? CellSet()
        var queue = combo?.queue ?? []
        if let combo { toClear.formUnion(combo.cells) }
        for i in toClear where isSpecial(i) && !triggered.contains(i) { queue.append(i) }
        var head = 0
        while head < queue.count {
            let i = queue[head]
            head += 1
            guard !triggered.contains(i), let cell = board[i] else { continue }
            triggered.insert(i)
            for j in detonate(i, combo?.overrides[i] ?? cell.special, cell.color, &effects) where !toClear.contains(j) {
                toClear.insert(j)
                if isSpecial(j) && !triggered.contains(j) { queue.append(j) }
            }
        }
        let cells = toClear.filter { board[$0] != nil }
        let total = cells.count
        var points = Double(base + max(0, total - groupBlocks) * 15)
        if groups.count > 1 { points *= 1 + 0.5 * Double(groups.count - 1) }
        points *= Double(max(1, chain))
        for made in created { points += Double(made.special.bonus) }
        if let combo { points += Double(combo.kind.bonus) }
        let awarded = Int(points.rounded()) * level
        score += awarded

        charge(Double(total * max(1, chain) + created.count * 6))
        if (chain == 3 || chain == 5) && tokens < Rules.maxTokens {
            tokens += 1
            emit(.swapGained(1))
        }
        stats.maxChain = max(stats.maxChain, chain)
        stats.specials += created.count
        stats.bestClear = max(stats.bestClear, total)

        let oldLevel = level
        cleared += total
        level = min(Rules.maxLevel, 1 + cleared / Rules.blocksPerLevel)

        clearing = Clearing(cells: CellSet(cells), created: created)
        phase = .clear
        timer = effects.isEmpty ? Timing.clear : Timing.clearFX
        phaseDur = timer
        emit(.clear(Clear(chain: chain, cells: cells, created: created, effects: effects, points: awarded, combo: combo?.kind)))
        if level > oldLevel {
            emit(.levelUp(level: level, newColor: !calm && Rules.palette(level) > Rules.palette(oldLevel)))
        }
    }

    private func finishClear() {
        guard let clearing else { return }
        var removed: [(index: Int, color: Int)] = []
        for i in clearing.cells {
            if let cell = board[i] { removed.append((i, cell.color)) }
            board[i] = nil
        }
        var made: [Int] = []
        for special in clearing.created {
            let cell = makeCell(special.color, special.special)
            board[special.index] = cell
            made.append(cell.id)
        }
        self.clearing = nil
        emit(.cleared(removed: removed, made: made))
        applyGravity()
    }

    private func applyGravity() {
        var maxDist = 0
        var moved: [Int] = []
        for x in 0..<Grid.cols {
            var write = Grid.rows - 1
            for y in stride(from: Grid.rows - 1, through: 0, by: -1) {
                guard var cell = board[Grid.index(x, y)] else { continue }
                if y != write {
                    cell.fall = write - y
                    board[Grid.index(x, write)] = cell
                    board[Grid.index(x, y)] = nil
                    maxDist = max(maxDist, cell.fall)
                    moved.append(Grid.index(x, write))
                }
                write -= 1
            }
        }
        if maxDist > 0 {
            focus = moved
            phase = .drop
            dropT = 0
            dropDur = (2 * Double(maxDist) / Timing.dropAccel).squareRoot() + Timing.dropSettle
            phaseDur = dropDur
        } else {
            finishDrop()
        }
    }

    private func finishDrop() {
        for i in board.indices where board[i] != nil { board[i]!.fall = 0 }
        resolve()
    }

    private func resolveDone() {
        chain = 0
        if tokens > 0 {
            computeLegal()
            if !legal.isEmpty {
                phase = .swap
                timer = swapWindow
                phaseDur = timer
                swapHold = false
                emit(.swapPhase)
                return
            }
        }
        toSpawn()
    }

    private func toSpawn() {
        phase = .spawn
        timer = Timing.spawn
        phaseDur = timer
        legal = []
        legalCells = CellSet()
    }

    // MARK: Swaps

    private func runLength(at i: Int) -> Int {
        let color = board[i]!.color
        func reach(_ step: Int, _ limit: Int) -> Int {
            var n = 0
            var k = i + step
            while n < limit, board[k]?.color == color {
                n += 1
                k += step
            }
            return n
        }
        let x = Grid.x(i)
        let y = Grid.y(i)
        let h = 1 + reach(-1, x) + reach(1, Grid.cols - 1 - x)
        let v = 1 + reach(-Grid.cols, y) + reach(Grid.cols, Grid.rows - 1 - y)
        return max(h, v)
    }
    /// True when the swap fires a special combo, false for a plain match, nil when it does nothing.
    private func swapMakesCombo(_ a: Int, _ b: Int) -> Bool? {
        guard let first = board[a], let second = board[b] else { return nil }
        if first.special == .prism || second.special == .prism { return true }
        if first.special != .plain && second.special != .plain { return true }
        if first.color == second.color { return nil }
        board.swapAt(a, b)
        defer { board.swapAt(a, b) }
        return runLength(at: a) >= 3 || runLength(at: b) >= 3 ? false : nil
    }
    func computeLegal() {
        legal = []
        legalCells = CellSet()
        for i in board.indices where board[i] != nil {
            let right = Grid.x(i) < Grid.cols - 1 ? i + 1 : -1
            let below = Grid.y(i) < Grid.rows - 1 ? i + Grid.cols : -1
            for j in [right, below] where j >= 0 && swapMakesCombo(i, j) != nil {
                legal.append((i, j))
                legalCells.insert(i)
                legalCells.insert(j)
            }
        }
    }
    func partners(of i: Int) -> [Int] {
        legal.compactMap { $0.0 == i ? $0.1 : $0.1 == i ? $0.0 : nil }
    }

    /// Swap the block at `from` into `to`. An illegal swap bounces back and costs nothing.
    @discardableResult func trySwap(_ from: Int, _ to: Int) -> SwapResult {
        guard phase == .swap, board.indices.contains(from), board.indices.contains(to), Grid.adjacent(from, to),
              board[from] != nil, board[to] != nil, tokens > 0 else { return .rejected }
        swapA = from
        swapB = to
        guard let combo = swapMakesCombo(from, to) else {
            swapRemain = timer
            phase = .swapBack
            timer = Timing.swap * 2
            phaseDur = timer
            emit(.swapFail(from, to))
            return .illegal
        }
        tokens -= 1
        stats.swaps += 1
        board.swapAt(from, to)
        pendingCombo = combo
        phase = .swapAnim
        timer = Timing.swap
        phaseDur = timer
        emit(.swap)
        return .ok
    }
    @discardableResult func skipSwap() -> Bool {
        guard phase == .swap else { return false }
        emit(.swapEnded)
        toSpawn()
        return true
    }

    private func finishSwapAnim() {
        let other = swapA
        let moved = swapB
        swapA = -1
        swapB = -1
        chain = 1
        if pendingCombo {
            beginClear([], combo: buildCombo(moved, other))
            return
        }
        focus = [moved, other]
        let groups = findGroups()
        if groups.isEmpty { resolveDone() } else { beginClear(groups) }
    }

    /// `t` holds the block the player moved, `o` holds the other one.
    private func buildCombo(_ t: Int, _ o: Int) -> SwapCombo {
        let a = board[t]!
        let b = board[o]!
        let x = Grid.x(t)
        let y = Grid.y(t)
        var combo = SwapCombo(kind: .mega, cells: CellSet([t, o]), triggered: CellSet([t, o]))
        func addRect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
            for yy in max(0, y0)...min(Grid.rows - 1, y1) {
                for xx in max(0, x0)...min(Grid.cols - 1, x1) where board[Grid.index(xx, yy)] != nil {
                    combo.cells.insert(Grid.index(xx, yy))
                }
            }
        }
        func addColor(_ color: Int) -> [Int] {
            let list = board.indices.filter { board[$0]?.color == color }
            combo.cells.formUnion(CellSet(list))
            return list
        }
        switch (a.special, b.special) {
        case (.prism, .prism):
            combo.kind = .wipe2
            var second = b.color
            if second == a.color {
                // two prisms of one colour also take the most common other colour
                var counts = [Int](repeating: 0, count: 6)
                var seen: [Int] = []
                for case let cell? in board where cell.color != a.color {
                    if counts[cell.color] == 0 { seen.append(cell.color) }
                    counts[cell.color] += 1
                }
                for color in seen where counts[color] > counts[second] || second == a.color { second = color }
            }
            combo.effects.append(.prism(x: x, y: y, color: a.color, targets: addColor(a.color)))
            if second != a.color {
                combo.effects.append(.prism(x: Grid.x(o), y: Grid.y(o), color: second, targets: addColor(second)))
            }
        case (.prism, _), (_, .prism):
            let partner = a.special == .prism ? b : a
            let prism = a.special == .prism ? t : o
            let list = addColor(partner.color)
            combo.effects.append(.prism(x: Grid.x(prism), y: Grid.y(prism), color: partner.color, targets: list))
            if partner.special == .plain {
                combo.kind = .wipe
            } else {
                // every block of the colour becomes a copy of the partner's special
                combo.kind = partner.special == .bomb ? .wipeBombs : .wipeLines
                for k in list where !combo.triggered.contains(k) {
                    combo.overrides[k] = partner.special == .bomb ? .bomb : rng() < 0.5 ? .lineH : .lineV
                    combo.queue.append(k)
                }
            }
        case (.bomb, .bomb):
            combo.kind = .mega
            addRect(x - 2, y - 2, x + 2, y + 2)
            combo.effects.append(.bomb(x: x, y: y, radius: 2, color: a.color))
        case (.bomb, _), (_, .bomb):
            combo.kind = .wide
            addRect(0, y - 1, Grid.cols - 1, y + 1)
            addRect(x - 1, 0, x + 1, Grid.rows - 1)
            for k in -1...1 {
                combo.effects.append(.lineH(y: y + k, color: a.color, wide: true))
                combo.effects.append(.lineV(x: x + k, color: b.color, wide: true))
            }
        default:
            combo.kind = .cross
            addRect(0, y, Grid.cols - 1, y)
            addRect(x, 0, x, Grid.rows - 1)
            combo.effects += [.lineH(y: y, color: a.color, wide: false), .lineV(x: x, color: b.color, wide: false)]
        }
        return combo
    }

    // MARK: Loop

    func update(_ dt: Double) {
        guard phase != .over else { return }
        stats.time += dt
        switch phase {
        case .spawn:
            timer -= dt
            if timer <= 0 { spawnNext() }
        case .fall:
            updateFall(dt)
        case .clear:
            timer -= dt
            if timer <= 0 { finishClear() }
        case .drop:
            dropT += dt
            if dropT >= dropDur { finishDrop() }
        case .swap:
            guard !untimed, !swapHold else { break }
            timer -= dt
            if timer <= 0 {
                emit(.swapEnded)
                toSpawn()
            }
        case .swapAnim:
            timer -= dt
            if timer <= 0 { finishSwapAnim() }
        case .swapBack:
            timer -= dt
            if timer <= 0 {
                swapA = -1
                swapB = -1
                phase = .swap
                phaseDur = swapWindow
                timer = min(phaseDur, max(swapRemain, 1))
            }
        case .over:
            break
        }
    }

    private func gameOver() {
        phase = .over
        emit(.gameOver)
    }

    // MARK: Persistence

    /// Restoring a snapshot replays its current piece from the top.
    struct Snapshot: Codable {
        static let currentVersion = 1

        var version = currentVersion
        var calm: Bool
        /// Zero for an empty cell, otherwise `1 + color * 5 + special`.
        var board: [Int]
        var current: PieceDef?
        var hold: PieceDef?
        var holdUsed: Bool
        var queue: [PieceDef]
        var bag: [Int]
        var score: Int
        var level: Int
        var cleared: Int
        var tokens: Int
        var meter: Double
        var stats: Stats
    }

    var snapshot: Snapshot {
        Snapshot(
            calm: calm, board: board.map { $0.map { 1 + $0.color * 5 + $0.special.rawValue } ?? 0 },
            current: piece?.def, hold: hold, holdUsed: holdUsed, queue: queue, bag: bag,
            score: score, level: level, cleared: cleared, tokens: tokens, meter: meter, stats: stats)
    }

    init?(restoring s: Snapshot, relaxed: Bool = false, rng: @escaping () -> Double = { .random(in: 0..<1) }) {
        guard s.version == Snapshot.currentVersion, s.board.count == Grid.count,
              s.board.allSatisfy({ (0...30).contains($0) }),
              (s.queue + [s.current, s.hold].compactMap { $0 }).allSatisfy(\.isValid),
              s.bag.allSatisfy(Shape.all.indices.contains) else { return nil }
        calm = s.calm
        self.relaxed = relaxed
        self.rng = rng
        board = s.board.map { $0 == 0 ? nil : makeCell(($0 - 1) / 5, Special(rawValue: ($0 - 1) % 5)!) }
        hold = s.hold
        holdUsed = s.holdUsed
        queue = s.queue
        bag = s.bag
        score = max(0, s.score)
        level = min(Rules.maxLevel, max(1, s.level))
        cleared = max(0, s.cleared)
        tokens = min(Rules.maxTokens, max(0, s.tokens))
        meter = min(Rules.meterMax, max(0, s.meter))
        stats = s.stats
        fillQueue()
        if let current = s.current { spawn(current) } else { spawnNext() }
        events.removeAll()
    }
}
