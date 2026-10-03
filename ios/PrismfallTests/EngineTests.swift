import Foundation
import Testing
@testable import Prismfall

/// Deterministic generator so fixtures replay identically.
private func seeded(_ seed: UInt32) -> () -> Double {
    var s = seed
    return {
        s &+= 0x6d2b_79f5
        var t = s
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

/// Run the state machine until it waits on the player.
@MainActor @discardableResult
private func settle(_ g: Game) -> Game.Phase {
    for _ in 0..<2000 {
        if [.fall, .swap, .over].contains(g.phase) { return g.phase }
        g.update(0.05)
    }
    Issue.record("did not settle")
    return g.phase
}

extension Game {
    /// Rows of characters anchored to the floor: `.` is empty, digits are colours,
    /// and `h` `v` `b` `p` turn the digit before them into a special.
    func setBoard(_ lines: [String]) {
        board = [Cell?](repeating: nil, count: Grid.count)
        let marks: [Character: Special] = ["h": .lineH, "v": .lineV, "b": .bomb, "p": .prism]
        for (r, line) in lines.enumerated() {
            var x = 0
            for ch in line {
                if let special = marks[ch] {
                    board[Grid.index(x - 1, Grid.rows - lines.count + r)]?.special = special
                } else {
                    if let color = ch.wholeNumberValue {
                        let i = Grid.index(x, Grid.rows - lines.count + r)
                        board[i] = Cell(id: 10_000 + i, color: color)
                    }
                    x += 1
                }
            }
            precondition(x <= Grid.cols, "row \(r) is wider than \(Grid.cols) columns")
        }
    }

    var rowStrings: [String] {
        (0..<Grid.rows).map { y in
            (0..<Grid.cols).map { x in board[Grid.index(x, y)].map { String($0.color) } ?? "." }.joined()
        }
    }

    func openSwapPhase() {
        phase = .swap
        timer = 10
        phaseDur = 10
        computeLegal()
    }
}

@MainActor struct EngineTests {
    private let last = Grid.rows - 1

    @Test func newGameSpawnsACenteredPieceAtTheTop() {
        let g = Game(rng: seeded(1))
        #expect(settle(g) == .fall)
        #expect(g.piece!.blocks.map { g.piece!.y + $0.y }.min() == 0)
        for type in Shape.all.indices {
            let p = g.makePiece(PieceDef(type: type, colors: [0, 0, 0, 0]))
            let xs = p.blocks.map { p.x + $0.x }
            #expect(abs(xs.min()! - (Grid.cols - 1 - xs.max()!)) <= 1, "shape \(type) is off center")
        }
        #expect(g.queue.count == 5)
    }

    @Test func bagGivesEveryShapeOncePerSeven() {
        let g = Game(rng: seeded(7))
        g.bag = []
        #expect((0..<7).map { _ in g.genDef().type }.sorted() == Array(0..<7))
    }

    @Test func pieceColorsUseTheCurrentPalette() {
        let g = Game(rng: seeded(3))
        for _ in 0..<500 {
            let colors = g.genColors()
            #expect(colors.count == 4)
            #expect(colors.allSatisfy { (0..<5).contains($0) })
        }
        g.level = 6
        #expect((0..<500).contains { _ in g.genColors().contains(5) }, "sixth color appears from level 5")
    }

    @Test func rotationCarriesColorsAround() {
        let g = Game(rng: seeded(2))
        settle(g)
        g.piece = g.makePiece(PieceDef(type: 1, colors: [0, 1, 2, 3]))
        let key = { (g: Game) in g.piece!.blocks.map { "\($0.x),\($0.y),\($0.color)" } }
        let before = key(g)
        #expect(g.rotate(1))
        #expect(key(g) != before)
        #expect(g.piece!.blocks.map { "\($0.x),\($0.y)" }.sorted() == ["0,0", "0,1", "1,0", "1,1"])
        for _ in 0..<3 { g.rotate(1) }
        #expect(key(g) == before)
    }

    @Test func wallKickLetsAVerticalIRotateAgainstTheWall() {
        let g = Game(rng: seeded(4))
        settle(g)
        g.piece = g.makePiece(PieceDef(type: 0, colors: [0, 0, 0, 0]))
        g.rotate(1)
        while g.move(-1) {}
        #expect(g.rotate(1), "kicks off the left wall")
        #expect(g.piece!.blocks.allSatisfy { g.piece!.x + $0.x >= 0 })
    }

    @Test func horizontalRunClearsAndBlocksAboveFall() {
        let g = Game(rng: seeded(5))
        g.setBoard([".4.....", ".3.....", "111...."])
        g.resolve()
        #expect(g.phase == .clear)
        #expect(g.clearing?.cells.count == 3)
        settle(g)
        #expect(g.rowStrings[last] == ".3.....")
        #expect(g.rowStrings[last - 1] == ".4.....")
    }

    @Test func verticalRunsClearAndFullRowsDoNothing() {
        let g = Game(rng: seeded(6))
        g.setBoard(["2......", "2......", "2......", "0123401"])
        g.resolve()
        #expect(g.clearing?.cells.count == 3)
        settle(g)
        #expect(g.rowStrings[last] == "0123401", "full row stays")
    }

    @Test func cascadesRaiseTheChain() {
        let g = Game(rng: seeded(8))
        // Clearing 111 drops the 2 in column 2 into a row of three 2s.
        g.setBoard(["..2....", "11122.."])
        var chains: [Int] = []
        g.resolve()
        for _ in 0..<400 where g.phase != .spawn && g.phase != .swap {
            for case .clear(let clear) in g.drain() { chains.append(clear.chain) }
            g.update(0.05)
        }
        for case .clear(let clear) in g.drain() { chains.append(clear.chain) }
        #expect(chains == [1, 2])
    }

    @Test func fourInARowMakesALineBlasterAtTheMovedCell() {
        let g = Game(rng: seeded(9))
        g.setBoard(["3333..."])
        g.focus = [Grid.index(1, last)]
        g.resolve()
        #expect(g.clearing?.created.count == 1)
        #expect(g.clearing?.created.first?.special == .lineH)
        #expect(g.clearing?.created.first?.index == Grid.index(1, last))
        settle(g)
        #expect(g.board[Grid.index(1, last)]?.special == .lineH)
    }

    @Test func cornerMakesABombAndFiveMakesAPrism() {
        let g = Game(rng: seeded(10))
        g.setBoard(["1......", "1......", "111...."])
        g.resolve()
        #expect(g.clearing?.created.first?.special == .bomb)
        #expect(g.clearing?.created.first?.index == Grid.index(0, last))

        let h = Game(rng: seeded(11))
        h.setBoard(["22222.."])
        h.resolve()
        #expect(h.clearing?.created.first?.special == .prism)
    }

    @Test func matchedLineBlasterClearsItsRow() {
        let g = Game(rng: seeded(12))
        g.setBoard(["0123401", "1h110342"])
        g.resolve()
        #expect((0..<Grid.cols).allSatisfy { g.clearing!.cells.contains(Grid.index($0, last)) })
        guard case .clear(let clear)? = g.drain().first(where: { if case .clear = $0 { true } else { false } }) else {
            Issue.record("no clear event")
            return
        }
        #expect(clear.effects.contains { if case .lineH = $0 { true } else { false } })
    }

    @Test func matchedBombChainsIntoOtherSpecials() {
        let g = Game(rng: seeded(13))
        g.setBoard([".......", ".4v....", ".2b22..", "3333333"])
        g.resolve()
        let effects = g.drain().compactMap { if case .clear(let clear) = $0 { clear.effects } else { nil } }.joined()
        #expect(effects.contains { if case .bomb = $0 { true } else { false } })
        #expect(effects.contains { if case .lineV = $0 { true } else { false } })
    }

    @Test func matchedPrismRemovesEveryBlockOfItsColor() {
        let g = Game(rng: seeded(14))
        g.setBoard(["3..3..3", "1.2.1.2", "33p3..."])
        g.resolve()
        for i in g.board.indices where g.board[i]?.color == 3 {
            #expect(g.clearing!.cells.contains(i), "clears color 3 at \(i)")
        }
    }

    @Test func illegalSwapsBounceBackAndCostNothing() {
        let g = Game(rng: seeded(15))
        g.setBoard(["1......", "0122..."])
        g.openSwapPhase()
        #expect(g.trySwap(Grid.index(0, last), Grid.index(1, last)) == .illegal)
        #expect(g.phase == .swapBack)
        #expect(g.tokens == 1, "illegal swap is free")
        settle(g)
        #expect(g.phase == .swap)
        #expect(Array(g.rowStrings.suffix(2)) == ["1......", "0122..."])
        #expect(g.trySwap(Grid.index(0, last), Grid.index(2, last)) == .rejected, "not adjacent")
        #expect(g.trySwap(Grid.index(5, last), Grid.index(6, last)) == .rejected, "empty")
    }

    @Test func legalSwapSpendsABankedSwap() {
        let g = Game(rng: seeded(16))
        g.setBoard(["1131..."])
        g.openSwapPhase()
        #expect(g.legalCells.contains(Grid.index(2, last)) && g.legalCells.contains(Grid.index(3, last)))
        #expect(g.partners(of: Grid.index(3, last)) == [Grid.index(2, last)])
        #expect(g.trySwap(Grid.index(3, last), Grid.index(2, last)) == .ok)
        #expect(g.tokens == 0)
        g.update(1)
        #expect(g.phase == .clear)
        #expect(g.clearing?.cells.count == 3)
    }

    @Test func landingsAndClearsChargeTheSwapMeter() {
        let g = Game(rng: seeded(26))
        #expect(g.tokens == 1, "games start with one swap banked")
        g.tokens = 0
        g.charge(Rules.meterMax + 5)
        #expect(g.tokens == 1)
        #expect(g.meter == 5)
        g.charge(Rules.meterMax * 10)
        #expect(g.tokens == Rules.maxTokens)
        #expect(g.meter <= Rules.meterMax)
        g.setBoard(["1131..."])
        g.tokens = 2
        g.openSwapPhase()
        #expect(g.trySwap(Grid.index(3, last), Grid.index(2, last)) == .ok)
        #expect(g.tokens == 1)
    }

    @Test func prismSwappedWithAnyBlockWipesThatColor() {
        let g = Game(rng: seeded(17))
        g.setBoard(["2..2..2", "0p2...."])
        g.openSwapPhase()
        #expect(g.board[Grid.index(0, last)]?.special == .prism)
        #expect(g.trySwap(Grid.index(0, last), Grid.index(1, last)) == .ok)
        g.update(1)
        #expect(g.phase == .clear)
        #expect(g.clearing!.cells.filter { g.board[$0]?.color == 2 }.count == 4)
    }

    @Test func twoLineBlastersFireACross() {
        let g = Game(rng: seeded(18))
        g.setBoard(["0123401", "1234012", "23h4v0123"])
        g.openSwapPhase()
        let a = Grid.index(1, last)
        let b = Grid.index(2, last)
        #expect(g.board[a]?.special == .lineH)
        #expect(g.board[b]?.special == .lineV)
        #expect(g.trySwap(a, b) == .ok)
        g.update(1)
        #expect(g.phase == .clear)
        #expect((0..<Grid.cols).allSatisfy { g.clearing!.cells.contains(Grid.index($0, last)) })
        #expect((last - 2...last).allSatisfy { g.clearing!.cells.contains(Grid.index(2, $0)) })
        #expect(g.drain().contains { if case .clear(let clear) = $0 { clear.combo == .cross } else { false } })
    }

    @Test func bombPlusBombDetonatesFiveByFive() {
        let g = Game(rng: seeded(25))
        var lines = (0..<7).map { $0 % 2 == 1 ? "1234012" : "0123401" }
        lines[6] = "01b2b4012"
        g.setBoard(lines)
        g.openSwapPhase()
        #expect(g.trySwap(Grid.index(1, last), Grid.index(2, last)) == .ok)
        g.update(1)
        for y in last - 2...last {
            #expect((0...4).allSatisfy { g.clearing!.cells.contains(Grid.index($0, y)) })
        }
    }

    @Test func droppedShapeResolvesToAPlayablePhase() {
        let g = Game(rng: seeded(19))
        settle(g)
        g.setBoard(["0123401"])
        g.piece = g.makePiece(PieceDef(type: 1, colors: [0, 0, 0, 0]))
        g.piece!.x = 0
        g.hardDrop()
        #expect([.fall, .swap].contains(settle(g)))
        #expect(g.board[Grid.index(0, last)] == nil, "column of three 0s cleared")
    }

    @Test func gameEndsWhenANewShapeCannotEnter() {
        let g = Game(rng: seeded(20))
        settle(g)
        // alternating colors, so nothing matches
        g.setBoard((0..<Grid.rows).map { y in (0..<Grid.cols).map { String($0 % 2 + 2 * (y % 2)) }.joined() })
        g.phase = .spawn
        g.timer = 0
        g.update(0.01)
        #expect(g.phase == .over)
        #expect(g.drain().contains { if case .gameOver = $0 { true } else { false } })
    }

    @Test func holdSwapsTheCurrentShapeOncePerLanding() {
        let g = Game(rng: seeded(21))
        settle(g)
        let first = g.piece!.def
        #expect(g.holdPiece())
        #expect(g.hold == first)
        #expect(!g.holdPiece(), "second hold blocked")
        g.hardDrop()
        settle(g)
        if g.phase == .swap { g.skipSwap() }
        settle(g)
        #expect(g.holdPiece())
        #expect(g.piece?.def == first)
    }

    @Test func snapshotRoundTripsTheState() throws {
        let g = Game(rng: seeded(22))
        settle(g)
        g.hardDrop()
        settle(g)
        if g.phase == .swap { g.skipSwap() }
        settle(g)
        let data = try JSONEncoder().encode(g.snapshot)
        let r = try #require(Game(restoring: JSONDecoder().decode(Game.Snapshot.self, from: data), rng: seeded(1)))
        #expect(r.score == g.score)
        #expect(r.rowStrings == g.rowStrings)
        #expect(r.piece?.def == g.piece?.def)
        #expect(r.queue == g.queue)
        #expect(r.phase == .fall)

        var stale = g.snapshot
        stale.version = 99
        #expect(Game(restoring: stale) == nil)
        var short = g.snapshot
        short.board = Array(short.board.dropLast())
        #expect(Game(restoring: short) == nil, "a board of another size is ignored")
    }

    @Test func longerRunsAndChainsAreWorthMore() {
        let score = { (line: String, chain: Int) in
            let g = Game(rng: seeded(23))
            g.setBoard([line])
            g.chain = chain
            g.beginClear(g.findGroups())
            return g.score
        }
        let three = score("111....", 1)
        #expect(three == 30)
        #expect(score("1111...", 1) > three)
        #expect(score("111....", 3) == three * 3)
    }

    @Test func levelsArriveEveryThirtySixBlocks() {
        let g = Game(rng: seeded(27))
        g.cleared = Rules.blocksPerLevel - 3
        g.setBoard(["111...."])
        g.resolve()
        #expect(g.level == 2)
        #expect(g.gravity < Rules.gravity(1))
        #expect(g.drain().contains { if case .levelUp(2, false) = $0 { true } else { false } })
    }

    @Test func calmModeNeverSpeedsUpOrTimesASwap() {
        let g = Game(calm: true, rng: seeded(28))
        g.cleared = Rules.blocksPerLevel * 9 - 3
        g.setBoard(["111...."])
        g.resolve()
        #expect(g.level == 10, "levels still count for score")
        #expect(g.gravity == Rules.calmGravity)
        #expect(g.paletteSize == 5)
        #expect(g.swapWindow == .infinity)
        for _ in 0..<200 { #expect(!g.genColors().contains(5)) }
        g.setBoard(["1131..."])
        g.openSwapPhase()
        g.update(600)
        #expect(g.phase == .swap, "the swap window waits")
    }

    @Test func randomPlayAlwaysSettles() {
        for seed in UInt32(1)...30 {
            let rng = seeded(seed * 977)
            let g = Game(rng: seeded(seed))
            var steps = 0
            while g.phase != .over && steps < 20000 {
                steps += 1
                switch g.phase {
                case .fall:
                    switch rng() {
                    case ..<0.2: g.move(-1)
                    case ..<0.4: g.move(1)
                    case ..<0.55: g.rotate(rng() < 0.5 ? 1 : -1)
                    case ..<0.6: g.holdPiece()
                    case ..<0.7: g.hardDrop()
                    default: g.update(0.05)
                    }
                case .swap:
                    if rng() < 0.7, !g.legal.isEmpty {
                        let (a, b) = g.legal[Int(rng() * Double(g.legal.count))]
                        #expect(g.trySwap(a, b) == .ok)
                    } else if rng() < 0.5 {
                        let i = Int(rng() * Double(Grid.count))
                        g.trySwap(i, i + (rng() < 0.5 ? 1 : Grid.cols))
                        g.update(0.05)
                    } else {
                        g.skipSwap()
                    }
                default:
                    g.update(0.05)
                }
                _ = g.drain()
                if g.phase == .fall || g.phase == .swap {
                    #expect(g.findGroups().isEmpty, "stable board has no matches")
                }
            }
            #expect(g.board.allSatisfy { $0.map { (0..<6).contains($0.color) } ?? true })
        }
    }
}
