// The game on screen: layout, board and HUD rendering, effects, touch and keyboard input.

import GameController
import SpriteKit

private enum Z {
    static let rain: CGFloat = 1
    static let frame: CGFloat = 10
    static let grid: CGFloat = 11
    static let hud: CGFloat = 12
    static let under: CGFloat = 13
    static let tile: CGFloat = 16
    static let ghost: CGFloat = 19
    static let piece: CGFloat = 21
    static let lifted: CGFloat = 25
    static let highlight: CGFloat = 28
    static let fx: CGFloat = 30
    static let hint: CGFloat = 32
    static let confetti: CGFloat = 40
    static let text: CGFloat = 41
    static let banner: CGFloat = 42
}

private nonisolated func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }
private nonisolated func cubicOut(_ t: CGFloat) -> CGFloat { 1 - pow(1 - t, 3) }
private nonisolated func backOut(_ t: CGFloat) -> CGFloat { 1 + 2.70158 * pow(t - 1, 3) + 1.70158 * pow(t - 1, 2) }

/// Scene coordinates run y-up from the top-left corner; layout maths runs y-down.
private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: -y) }

private extension SKAction {
    func eased(_ curve: @escaping @Sendable (CGFloat) -> CGFloat) -> SKAction {
        timingFunction = { Float(curve(CGFloat($0))) }
        return self
    }
    /// Run, then leave the scene.
    var once: SKAction { .sequence([self, .removeFromParent()]) }
}

private final class Tile: SKSpriteNode {
    var stamp = 0
    var spent = false
    private(set) var glow: SKSpriteNode?
    private var flash: SKSpriteNode?

    init(_ texture: SKTexture, side: CGFloat) {
        super.init(texture: texture, color: .clear, size: CGSize(width: side, height: side))
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func setGlow(_ texture: SKTexture, _ color: RGB) {
        if glow == nil {
            let node = SKSpriteNode(texture: texture, size: CGSize(width: size.width * 2, height: size.height * 2))
            node.zPosition = -1
            node.colorBlendFactor = 1
            addChild(node)
            glow = node
        }
        glow?.color = color.ui
    }
    func setFlash(_ alpha: CGFloat, _ texture: SKTexture) {
        guard alpha > 0.01 else {
            flash?.isHidden = true
            return
        }
        if flash == nil {
            let node = SKSpriteNode(texture: texture, size: size)
            node.zPosition = 1
            addChild(node)
            flash = node
        }
        flash?.isHidden = false
        flash?.alpha = alpha
    }
}

private struct Layout {
    var cell: CGFloat = 0
    var board = CGRect.zero
    var hold = CGRect.zero
    var next = [CGRect](repeating: .zero, count: 3)
    var info = CGRect.zero
    var pause = CGRect.zero

    init() {}
    init(size: CGSize, insets: UIEdgeInsets, scale: CGFloat) {
        let gutter = clamp((size.width * 0.03).rounded(), 8, 16)
        let left = insets.left + gutter
        let right = size.width - insets.right - gutter
        let top = insets.top + 6
        let hud = clamp((size.width * 0.175).rounded(), 60, 92)
        let boardTop = top + hud + 16
        let roomH = size.height - max(insets.bottom, 8) - 6 - boardTop
        cell = floor(min((right - left) / CGFloat(Grid.cols), roomH / CGFloat(Grid.rows)) * scale) / scale
        let snap = { (v: CGFloat) in (v * scale).rounded() / scale }
        let w = cell * CGFloat(Grid.cols)
        let h = cell * CGFloat(Grid.rows)
        board = CGRect(x: snap((size.width - w) / 2), y: snap(boardTop + max(0, (roomH - h) * 0.4)), width: w, height: h)
        let smallW = (hud * 0.56).rounded()
        let smallH = (hud - 6) / 2
        hold = CGRect(x: left, y: top, width: hud, height: hud)
        let firstX = right - smallW - 6 - hud
        next = [
            CGRect(x: firstX, y: top, width: hud, height: hud),
            CGRect(x: right - smallW, y: top, width: smallW, height: smallH),
            CGRect(x: right - smallW, y: top + smallH + 6, width: smallW, height: smallH),
        ]
        let infoX = left + hud + 12
        info = CGRect(x: infoX, y: top, width: firstX - 12 - infoX, height: hud)
        pause = CGRect(x: info.maxX - 38, y: top - 1, width: 38, height: 38)
    }
}

final class GameScene: SKScene {
    enum State { case menu, playing, paused, dying, over }

    weak var model: AppModel?
    private(set) var game: Game?
    private(set) var state = State.menu
    /// Taken at each spawn. Saving this replays the current piece from the top.
    private(set) var checkpoint: Game.Snapshot?

    private var insets = UIEdgeInsets.zero
    private var displayScale: CGFloat = 3
    private var needsBuild = true
    private var L = Layout()
    private var sheet: BlockSheet?
    private var sheetKey = ""
    private var paintingKey = ""
    private var symbols = true
    private var cell: CGFloat { L.cell }
    private var motion = true

    // nodes, rebuilt with the layout
    private var rain = SKNode()
    private var root = SKNode()
    private var board = SKNode()
    private var tileLayer = SKNode()
    private var fx = SKNode()
    private var floating = SKNode()
    private var highlights = SKNode()
    private var legalMarks = SKNode()
    private var slots: [SKNode] = []
    private var tiles: [Int: Tile] = [:]
    private var pieceTiles: [Tile] = []
    private var ghosts: [SKSpriteNode] = []
    private var guides: [SKSpriteNode] = []
    private var liftShadow = SKSpriteNode()
    private var danger = SKSpriteNode()
    private var scoreLabel = SKLabelNode()
    private var levelLabel = SKLabelNode()
    private var levelPill = SKNode()
    private var levelBar = SKSpriteNode()
    private var meterBar = SKSpriteNode()
    private var swapGlow = SKSpriteNode()
    private var pips: [SKSpriteNode] = []
    private var pipTextures: [SKTexture] = []
    private var barSlice: NineSlice?
    private var barWidths = (level: CGFloat(0), meter: CGFloat(0))
    private var swapBanner = SKNode()
    private var swapLabel = SKLabelNode()
    private var swapTimer = SKSpriteNode()
    private var swapHints: [SKLabelNode] = []
    private var controlHints: [SKLabelNode] = []

    // visual-only state for the falling piece: easing, turn tween, wall bump, spawn fade
    private var vis = (id: 0, x: 0.0, y: 0.0, rot: 0.0, bumpX: 0.0, bumpV: 0.0, wiggle: 0.0, wiggleV: 0.0, spawnT: 1.0)
    private var kick = 0.0
    private var kickV = 0.0
    private var shake = 0.0
    private var scorePop = 0.0
    private var levelPop = 0.0
    private var tokenPulse = 0.0
    private var shownScore = 0.0
    private var hardLock = false
    private var pieceShown = true
    private var flashes: [Int: Double] = [:]
    private var pops: [Int: Double] = [:]
    private var squashes: [Int: (start: Double, amount: Double)] = [:]
    private var fail: (a: Int, b: Int, t: Double)?
    private var overT = 0.0
    private var now = 0.0
    private var lastTime = 0.0
    private var tick = 0
    private var wasAnimating = true
    private var tilesDirty = true
    private var queueHead: PieceDef?
    private var shown = (score: -1, level: -1, progress: -1.0, tokens: -1, meter: -1.0, swaps: -1)
    private var hurried = false
    private var inDanger = false
    private var firstGame = false
    private var guideBottoms = [Int](repeating: -1, count: Grid.cols)

    // input
    private enum Gesture { case none, piece, swap, wait, hud }
    private var touch: UITouch?
    private var gesture = Gesture.none
    private var touchStart = CGPoint.zero
    private var touchTime = 0.0
    private var samples: [(p: CGPoint, t: Double)] = []
    private var anchor = 0
    private var droppedRows = 0
    private var pieceID = 0
    private var pressed = -1
    private var wasSelected = false
    private var dragged = false
    private var moved = false
    private var selection = -1
    private var cursor = -1
    private var keyMode = false
    private var watchingKeyboard = false
    private var held = (left: false, right: false, dir: 0, delay: 0.0, tick: 0.0)

    override init() {
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0, y: 1)
        backgroundColor = Theme.sky[1].ui
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func play(_ sfx: SFX) { Audio.shared.play(sfx) }

    // MARK: Lifecycle

    func setMetrics(_ insets: UIEdgeInsets, scale: CGFloat) {
        self.insets = insets
        displayScale = scale
        needsBuild = true
    }
    override func didChangeSize(_ oldSize: CGSize) { needsBuild = true }
    /// Settings changed: new artwork if the colour symbols toggled, and the swap timer follows `relaxed`.
    func settingsChanged() {
        guard let settings = model?.settings else { return }
        if settings.symbols != symbols { needsBuild = true }
        guard let game, game.relaxed != settings.relaxed else { return }
        game.relaxed = settings.relaxed
        if game.phase == .swap {
            game.timer = game.swapWindow
            game.phaseDur = game.timer
        }
    }

    func start(_ snapshot: Game.Snapshot?, calm: Bool) {
        let relaxed = model?.settings.relaxed ?? false
        game = snapshot.flatMap { Game(restoring: $0, relaxed: relaxed) } ?? Game(calm: calm, relaxed: relaxed)
        state = .playing
        motion = !UIAccessibility.isReduceMotionEnabled
        firstGame = model?.firstGame ?? false
        Audio.shared.setVolume(game?.calm == true ? 0.7 : 1)
        watchKeyboard()
        endTouch()
        held = (false, false, 0, 0, 0)
        selection = -1
        cursor = -1
        checkpoint = nil
        resync()
        play(.start)
    }
    func pause() {
        guard state == .playing else { return }
        state = .paused
        game?.softDropping = false
        held.dir = 0
        endTouch()
    }
    func resume() {
        if state == .paused { state = .playing }
    }
    func showMenu() {
        game = nil
        checkpoint = nil
        state = .menu
        resync()
    }

    // MARK: Building

    private func build() {
        needsBuild = false
        guard size.width > 0, size.height > 0 else { return }
        L = Layout(size: size, insets: insets, scale: displayScale)
        symbols = model?.settings.symbols ?? true
        let key = "\(cell) \(displayScale) \(symbols)"
        if key != sheetKey {
            // paint the blocks in the background, then come back and build; the old artwork stays up meanwhile
            guard key != paintingKey else { return }
            paintingKey = key
            Task { [cell, displayScale, symbols] in
                let bitmap = await Task.detached(priority: .userInitiated) {
                    BlockSheet.render(cell: cell, scale: displayScale, symbols: symbols)
                }.value
                guard paintingKey == key else { return }
                sheet = BlockSheet(bitmap)
                sheetKey = key
                needsBuild = true
            }
            return
        }
        guard let sheet else { return }
        removeAllChildren()
        let s = cell
        let bw = L.board.width
        let bh = L.board.height

        let backdrop = SKSpriteNode(texture: Art.backdrop(size), size: size)
        backdrop.anchorPoint = CGPoint(x: 0, y: 1)
        addChild(backdrop)
        rain = SKNode()
        rain.zPosition = Z.rain
        addChild(rain)
        root = SKNode()
        addChild(root)

        // board
        board = SKNode()
        root.addChild(board)
        let rim = max(5, s * 0.22)
        let well = Art.frame(cell: s, rim: rim, scale: displayScale).node(L.board.size)
        well.position = pt(bw / 2, bh / 2)
        well.zPosition = Z.frame
        board.addChild(well)
        let slot = SKTileGroup(tileDefinition: SKTileDefinition(texture: Art.gridCell(s, scale: displayScale), size: CGSize(width: s, height: s)))
        let grid = SKTileMapNode(tileSet: SKTileSet(tileGroups: [slot]), columns: Grid.cols, rows: Grid.rows,
                                 tileSize: CGSize(width: s, height: s), fillWith: slot)
        grid.position = pt(bw / 2, bh / 2)
        grid.zPosition = Z.grid
        board.addChild(grid)

        danger = SKSpriteNode(texture: Art.fade, size: CGSize(width: bw, height: s * 3))
        danger.yScale = -1
        danger.color = Theme.alert.ui
        danger.colorBlendFactor = 1
        danger.position = pt(bw / 2, s * 1.5)
        danger.zPosition = Z.under
        danger.isHidden = true
        board.addChild(danger)
        guides = (0..<4).map { _ in
            let guide = SKSpriteNode(texture: Art.fade)
            guide.alpha = 0.06
            guide.zPosition = Z.under
            guide.isHidden = true
            board.addChild(guide)
            return guide
        }
        tileLayer = SKNode()
        board.addChild(tileLayer)
        tiles = [:]
        liftShadow = SKSpriteNode(texture: sheet.white, size: CGSize(width: s * 0.9, height: s * 0.9))
        liftShadow.color = Theme.ink.darker(0.6).ui
        liftShadow.colorBlendFactor = 1
        liftShadow.zPosition = Z.lifted - 2
        liftShadow.isHidden = true
        board.addChild(liftShadow)
        ghosts = (0..<4).map { _ in
            let ghost = SKSpriteNode(texture: sheet.outline, size: CGSize(width: s, height: s))
            ghost.colorBlendFactor = 1
            ghost.zPosition = Z.ghost
            ghost.isHidden = true
            board.addChild(ghost)
            return ghost
        }
        pieceTiles = (0..<4).map { _ in
            let tile = Tile(sheet.blocks[0][0], side: s)
            tile.zPosition = Z.piece
            tile.isHidden = true
            board.addChild(tile)
            return tile
        }
        highlights = SKNode()
        highlights.zPosition = Z.highlight
        highlights.isHidden = true
        board.addChild(highlights)
        let swapBorder = SKShapeNode(path: Art.rr(-2, -bh - 2, bw + 4, bh + 4, s * 0.2))
        swapBorder.strokeColor = Theme.gold.ui
        swapBorder.lineWidth = 2
        swapBorder.fillColor = .clear
        swapBorder.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.5), .fadeAlpha(to: 0.8, duration: 0.5)])))
        highlights.addChild(swapBorder)
        legalMarks = SKNode()
        highlights.addChild(legalMarks)
        fx = SKNode()
        fx.zPosition = Z.fx
        board.addChild(fx)

        let hintFont = Theme.rounded(clamp(s * 0.36, 11, 15), .semibold)
        let hint = { (text: String, alpha: CGFloat, align: SKLabelHorizontalAlignmentMode) -> SKLabelNode in
            let label = self.label(text, hintFont, RGB(0xE9E4FF).ui.withAlphaComponent(alpha), align: align)
            label.zPosition = Z.hint
            label.isHidden = true
            self.board.addChild(label)
            return label
        }
        swapHints = [hint("Tap a glowing block, then a neighbor", 0.8, .center), hint("Tap empty space to skip", 0.55, .center)]
        swapHints[0].position = pt(bw / 2, s * 1.35)
        swapHints[1].position = pt(bw / 2, s * 1.95)
        controlHints = [hint("↺ tap left", 0.5, .left), hint("tap right ↻", 0.5, .right), hint("drag to move · flick down to drop", 0.5, .center)]

        // confetti, score pops and banners ride above the board without shaking
        floating = SKNode()
        floating.position = pt(L.board.minX, L.board.minY)
        root.addChild(floating)

        buildHUD(sheet)
        resync()
        model?.ready = true
    }

    private func label(_ text: String, _ font: UIFont, _ color: UIColor, align: SKLabelHorizontalAlignmentMode = .left, kern: CGFloat = 0) -> SKLabelNode {
        let label = SKLabelNode()
        label.horizontalAlignmentMode = align
        label.verticalAlignmentMode = .baseline
        label.attributedText = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern])
        return label
    }
    private func setText(_ label: SKLabelNode, _ text: String) {
        guard let current = label.attributedText, current.string != text, current.length > 0 else { return }
        label.attributedText = NSAttributedString(string: text, attributes: current.attributes(at: 0, effectiveRange: nil))
    }

    private func buildHUD(_ sheet: BlockSheet) {
        let add = { (node: SKNode, x: CGFloat, y: CGFloat) in
            node.position = pt(x, y)
            node.zPosition = Z.hud
            self.root.addChild(node)
        }
        let panel = Art.panel(scale: displayScale)
        slots = ([L.hold] + L.next).map { rect in
            let back = panel.node(rect.size)
            add(back, rect.midX, rect.midY)
            back.zPosition = Z.frame
            let slot = SKNode()
            add(slot, rect.midX, rect.midY)
            return slot
        }
        let captionSize = clamp(L.hold.height * 0.13, 8.5, 11)
        let caption = Theme.rounded(captionSize, .heavy)
        for (text, rect) in [("HOLD", L.hold), ("NEXT", L.next[0])] {
            add(label(text, caption, Theme.cream.ui.withAlphaComponent(0.85), kern: captionSize * 0.14), rect.minX + captionSize * 0.9, rect.minY + captionSize * 1.5)
        }

        let info = L.info
        add(label("SCORE", caption, Theme.cream.ui.withAlphaComponent(0.8), kern: captionSize * 0.14), info.minX, info.minY + captionSize * 1.3)
        let scoreSize = clamp(info.height * 0.36, 18, 32)
        scoreLabel = label("0", Theme.display(scoreSize), .white)
        add(scoreLabel, info.minX, info.minY + captionSize * 1.5 + scoreSize * 1.05)

        let pause = SKSpriteNode(texture: Art.pauseButton(L.pause.width, scale: displayScale), size: CGSize(width: L.pause.width, height: L.pause.height + 3))
        add(pause, L.pause.midX, L.pause.midY + 1.5)

        // level pill: "LV n" and progress to the next level
        let h = clamp(info.height * 0.28, 17, 24)
        let y = info.maxY - h
        let levelW = info.width * 0.44
        let dark = Art.capsule(height: h, fill: Theme.ink.cg(0.88), scale: displayScale)
        let bar = Art.capsule(height: 4, fill: RGB.white.cg(), scale: displayScale)
        barSlice = bar
        let track = { (width: CGFloat, height: CGFloat, filled: Bool) -> SKSpriteNode in
            let node = bar.node(CGSize(width: width, height: height))
            node.anchorPoint = CGPoint(x: 0, y: 0.5)
            node.color = filled ? Theme.gold.ui : .white
            node.colorBlendFactor = 1
            node.alpha = filled ? 1 : 0.2
            return node
        }
        levelPill = SKNode()
        add(levelPill, info.minX + levelW / 2, y + h / 2)
        levelPill.addChild(dark.node(CGSize(width: levelW, height: h)))
        let tag = label("LV", Theme.rounded(h * 0.44, .heavy), Theme.cream.ui.withAlphaComponent(0.75))
        tag.verticalAlignmentMode = .center
        tag.position = CGPoint(x: -levelW / 2 + h * 0.42, y: 0)
        tag.zPosition = 1
        levelPill.addChild(tag)
        levelLabel = label("1", Theme.display(h * 0.5), Theme.cream.ui)
        levelLabel.verticalAlignmentMode = .center
        levelLabel.position = CGPoint(x: tag.position.x + tag.frame.width + 3, y: 0)
        levelLabel.zPosition = 1
        levelPill.addChild(levelLabel)
        let levelTrackW = levelW * 0.45 - h * 0.45
        for filled in [false, true] {
            let node = track(levelTrackW, 4, filled)
            node.position = CGPoint(x: levelW * 0.05, y: 0)
            node.zPosition = filled ? 2 : 1
            levelPill.addChild(node)
            if filled { levelBar = node }
        }
        barWidths.level = levelTrackW

        // swap pill: banked swaps as diamonds over the gold charge meter
        let swapX = info.minX + levelW + 6
        let swapW = info.width - levelW - 6
        add(dark.node(CGSize(width: swapW, height: h)), swapX + swapW / 2, y + h / 2)
        swapGlow = Art.capsule(height: h, fill: Theme.gold.cg(), scale: displayScale).node(CGSize(width: swapW, height: h))
        swapGlow.alpha = 0
        add(swapGlow, swapX + swapW / 2, y + h / 2)
        let icon = SKSpriteNode(texture: Art.swapIcon(h * 0.6, color: Theme.gold.cg(), scale: displayScale), size: CGSize(width: h * 0.72, height: h * 0.72))
        add(icon, swapX + h * 0.62, y + h * 0.5)
        let r = h * 0.18
        pipTextures = [Art.pip(r, filled: false, scale: displayScale), Art.pip(r, filled: true, scale: displayScale)]
        let firstPip = swapX + h * 1.3
        pips = (0..<Rules.maxTokens).map { k in
            let pip = SKSpriteNode(texture: pipTextures[0], size: CGSize(width: r * 2 + 2, height: r * 2 + 2))
            add(pip, firstPip + CGFloat(k) * r * 2.7, y + h * 0.42)
            return pip
        }
        let meterW = swapX + swapW - h * 0.4 - (firstPip - r)
        for filled in [false, true] {
            let node = track(meterW, 2.5, filled)
            add(node, firstPip - r, y + h * 0.76)
            if filled { meterBar = node }
        }
        barWidths.meter = meterW
        for node in [icon, meterBar] + pips { node.zPosition = Z.hud + 1 }

        // banner over the top edge of the board while a swap is on offer
        let bannerH = clamp(cell * 0.66, 22, 30)
        let bannerW = min(L.board.width * 0.8, 250)
        swapBanner = SKNode()
        add(swapBanner, L.board.midX, L.board.minY + bannerH * 0.2)
        swapBanner.zPosition = Z.hint
        swapBanner.isHidden = true
        swapBanner.addChild(Art.capsule(height: bannerH, fill: Theme.ink.cg(0.96), stroke: Theme.gold.cg(0.8), scale: displayScale).node(CGSize(width: bannerW, height: bannerH)))
        let bannerIcon = SKSpriteNode(texture: Art.swapIcon(bannerH * 0.55, color: Theme.gold.cg(), scale: displayScale), size: CGSize(width: bannerH * 0.66, height: bannerH * 0.66))
        bannerIcon.position = CGPoint(x: -bannerW / 2 + bannerH * 0.7, y: 0)
        swapLabel = label("SWAP", Theme.rounded(bannerH * 0.5, .heavy), Theme.cream.ui, align: .center)
        swapLabel.verticalAlignmentMode = .center
        swapLabel.position = CGPoint(x: bannerH * 0.3, y: 0)
        swapTimer = SKSpriteNode(color: Theme.gold.ui, size: CGSize(width: bannerW - bannerH, height: 2.5))
        swapTimer.anchorPoint = CGPoint(x: 0, y: 0.5)
        swapTimer.position = CGPoint(x: -bannerW / 2 + bannerH * 0.5, y: -bannerH / 2 + 4)
        for node in [bannerIcon, swapLabel, swapTimer] {
            node.zPosition = 1
            swapBanner.addChild(node)
        }
    }

    /// Rebuild everything that mirrors the model, after a new game, a restore or a rebuilt layout.
    private func resync() {
        guard let sheet, !needsBuild else { return }
        for tile in tiles.values { tile.removeFromParent() }
        tiles = [:]
        flashes = [:]
        pops = [:]
        squashes = [:]
        fail = nil
        fx.removeAllChildren()
        floating.removeAllChildren()
        legalMarks.removeAllChildren()
        shake = 0
        kick = 0
        kickV = 0
        scorePop = 0
        levelPop = 0
        tokenPulse = 0
        hardLock = false
        overT = 0
        hurried = false
        inDanger = false
        tilesDirty = true
        shown = (-1, -1, -1, -1, -1, -1)
        root.isHidden = game == nil
        rain.removeAllActions()
        rain.removeAllChildren()
        guard let game else {
            // menu: blocks drift down behind the title
            let drop = SKAction.run { [weak self] in self?.dropRainBlock(sheet) }
            rain.run(.repeatForever(.sequence([drop, .wait(forDuration: 0.6)])))
            for k in 0..<7 { dropRainBlock(sheet, progress: CGFloat(k) / 7) }
            return
        }
        shownScore = Double(game.score)
        queueHead = game.queue.first
        vis.id = 0
        if let piece = game.piece { showPiece(piece, sheet, animated: false) }
        checkpoint = checkpoint ?? game.snapshot
        refreshSlots(animated: false)
        refreshHighlights()
    }

    private func dropRainBlock(_ sheet: BlockSheet, progress: CGFloat = 0) {
        let scale = CGFloat.random(in: 0.6...1.45)
        let side = cell * 0.9 * scale
        let special = Double.random(in: 0..<1) < 0.1 ? Int.random(in: 1...4) : 0
        let block = SKSpriteNode(texture: sheet.blocks[Int.random(in: 0..<6)][special], size: CGSize(width: side, height: side))
        let travel = size.height + side * 3
        block.position = pt(.random(in: 0...size.width), -side * 1.5 + travel * progress)
        block.alpha = 0.3 + scale * 0.22
        block.zRotation = .random(in: -0.5...0.5)
        let duration = Double(travel / (size.height * .random(in: 0.07...0.15)))
        block.run(.group([
            SKAction.moveBy(x: 0, y: -travel * (1 - progress), duration: duration * Double(1 - progress)).once,
            .rotate(byAngle: .random(in: -1.2...1.2), duration: duration),
        ]))
        rain.addChild(block)
    }

    // MARK: Frame

    override func update(_ currentTime: TimeInterval) {
        let dt = clamp(currentTime - lastTime, 0, 0.05)
        lastTime = currentTime
        now = currentTime
        if model?.frozen == true {
            // SpriteKit restarts a paused view whenever the app returns to the foreground
            view?.isPaused = true
            return
        }
        if needsBuild { build() }
        guard let game, sheet != nil else { return }
        switch state {
        case .playing:
            updateKeys(dt)
            game.update(dt)
            handle(game.drain())
        case .dying:
            overT += dt
            if overT > 1.15 {
                state = .over
                model?.showGameOver()
            }
        default:
            break
        }
        animate(dt)
        render(dt)
    }

    /// Damped spring toward zero: wall bump, turn wiggle and the hard-drop kick.
    private func spring(_ x: Double, _ v: Double, _ dt: Double, stiffness: Double, damping: Double) -> (Double, Double) {
        let v = v + (-stiffness * x - damping * v) * dt
        let x = x + v * dt
        return abs(x) < 1e-3 && abs(v) < 1e-2 ? (0, 0) : (x, v)
    }

    private func animate(_ dt: Double) {
        shake *= pow(0.0005, dt)
        vis.rot *= exp(-dt * 24)
        if abs(vis.rot) < 0.002 { vis.rot = 0 }
        vis.spawnT = min(1, vis.spawnT + dt / 0.16)
        (vis.bumpX, vis.bumpV) = spring(vis.bumpX, vis.bumpV, dt, stiffness: 900, damping: 38)
        (vis.wiggle, vis.wiggleV) = spring(vis.wiggle, vis.wiggleV, dt, stiffness: 900, damping: 38)
        (kick, kickV) = spring(kick, kickV, dt, stiffness: 700, damping: 30)
        scorePop = max(0, scorePop - dt / 0.3)
        levelPop = max(0, levelPop - dt / 0.6)
        tokenPulse = max(0, tokenPulse - dt * 1.5)
        if fail != nil {
            fail!.t += dt
            if fail!.t > 0.4 { fail = nil }
        }
        if let game {
            let target = Double(game.score)
            shownScore = shownScore < target ? min(target, shownScore + max(1, (target - shownScore) * min(1, dt * 9))) : target
        }
    }

    private func render(_ dt: Double) {
        guard let game else { return }
        root.position = pt(0, kick)
        let jitter = shake > 0.2 ? CGPoint(x: .random(in: -0.5...0.5) * shake, y: .random(in: -0.5...0.5) * shake) : .zero
        board.position = pt(L.board.minX + jitter.x, L.board.minY + jitter.y)

        let resolving = switch game.phase {
        case .clear, .drop, .swapAnim, .swapBack: true
        default: false
        }
        // the settled board is static, so its sprites are only touched while something moves
        let animating = resolving || !flashes.isEmpty || !pops.isEmpty || !squashes.isEmpty || fail != nil
            || (game.phase == .swap && selection >= 0) || state == .dying
        if animating || wasAnimating || tilesDirty { syncTiles(game) }
        wasAnimating = animating
        tilesDirty = false
        syncPiece(game, dt)
        syncHUD(game)

        // danger wash while the stack is near the top
        let top = game.highestRow
        let threatened = top <= 3 && state != .over
        danger.isHidden = !threatened
        if threatened { danger.alpha = CGFloat(0.26 + 0.14 * sin(now / 0.18)) * (1 - CGFloat(top) / 4) }
        if top <= 2 && !inDanger && state == .playing { play(.danger) }
        inDanger = top <= 2 ? true : top >= 5 ? false : inDanger

        // swap phase chrome
        let swapping = game.phase == .swap || game.phase == .swapBack
        highlights.isHidden = game.phase != .swap
        swapBanner.isHidden = !swapping
        if swapping {
            let timed = game.phase == .swap && game.phaseDur.isFinite
            swapTimer.isHidden = !timed
            if timed {
                let left = clamp(game.timer / game.phaseDur, 0, 1)
                swapTimer.xScale = CGFloat(left)
                swapTimer.color = left < 0.3 && sin(now / 0.07) > 0 ? Theme.alert.ui : Theme.gold.ui
                if left < 0.3 && !hurried {
                    hurried = true
                    play(.hurry)
                }
            }
        }
        let teach = swapping && game.stats.swaps < 3 && top >= 3
        for hint in swapHints { hint.isHidden = !teach }

        // first-game control hints, kept just above the stack
        var hintY: CGFloat = 0
        if firstGame, game.phase == .fall, let piece = game.piece, game.stats.pieces < 4 {
            let ghostTop = game.ghostY + piece.blocks.map(\.y).min()!
            hintY = min(L.board.height - cell * 0.5, CGFloat(min(top, ghostTop)) * cell - cell * 0.6)
        }
        let showControls = hintY > cell * 4
        for hint in controlHints { hint.isHidden = !showControls }
        if showControls {
            controlHints[0].position = pt(cell * 0.4, hintY)
            controlHints[1].position = pt(L.board.width - cell * 0.4, hintY)
            controlHints[2].position = pt(L.board.width / 2, hintY - cell * 0.7)
        }
    }

    // MARK: Board

    private func syncTiles(_ game: Game) {
        guard let sheet else { return }
        tick += 1
        let s = cell
        let clearing = game.phase == .clear ? game.clearing : nil
        let cp = clearing == nil ? 0 : CGFloat(1 - game.timer / game.phaseDur)
        let dropping = game.phase == .drop
        let swapping = game.phase == .swapAnim || game.phase == .swapBack
        var sp = swapping ? CGFloat(clamp(1 - game.timer / game.phaseDur, 0, 1)) : 0
        // lift over the whole move: out and back for an illegal swap, across for a legal one
        let arc = swapping && motion ? sin(.pi * sp) : 0
        if game.phase == .swapBack { sp = sp < 0.5 ? sp * 2 : (1 - sp) * 2 }
        let slide = cubicOut(sp)
        let spentRows = state == .dying || state == .over ? Int(overT / 0.9 * Double(Grid.rows)) : -1
        // the block the player moved is drawn last so it passes over its partner
        let movedIndex = game.phase == .swapAnim ? game.swapB : game.phase == .swapBack ? game.swapA : -1
        liftShadow.isHidden = true
        var seen = 0

        for i in 0..<Grid.count {
            guard let c = game.board[i] else { continue }
            let tile: Tile
            if let existing = tiles[c.id] {
                tile = existing
            } else {
                tile = Tile(sheet.blocks[c.color][c.special.rawValue], side: s)
                if c.special != .plain {
                    tile.setGlow(sheet.glow, Theme.blocks[c.color])
                    tile.glow?.alpha = 0.35
                    tile.glow?.run(.repeatForever(.sequence([.fadeAlpha(to: 0.7, duration: 0.69), .fadeAlpha(to: 0.35, duration: 0.69)])))
                }
                tileLayer.addChild(tile)
                tiles[c.id] = tile
            }
            tile.stamp = tick
            seen += 1
            let column = i % Grid.cols
            let row = i / Grid.cols
            var x = CGFloat(column) * s
            var y = CGFloat(row) * s
            if dropping && c.fall > 0 {
                let fall = Double(c.fall)
                y -= CGFloat(max(0, fall - 0.5 * Timing.dropAccel * game.dropT * game.dropT)) * s
                // small rebound once it lands
                let u = (game.dropT - (2 * fall / Timing.dropAccel).squareRoot()) / 0.1
                if motion && u > 0 && u < 1 { y -= CGFloat(sin(u * .pi) * 0.06 * min(1, fall / 2)) * s }
            }
            var scale: CGFloat = 1
            var flash: CGFloat = 0
            var squash: CGFloat = 0
            if swapping && (i == game.swapA || i == game.swapB) {
                let other = i == game.swapA ? game.swapB : game.swapA
                let (from, to) = game.phase == .swapAnim ? (other, i) : (i, other)
                x = (CGFloat(from % Grid.cols) + CGFloat(to % Grid.cols - from % Grid.cols) * slide) * s
                y = (CGFloat(from / Grid.cols) + CGFloat(to / Grid.cols - from / Grid.cols) * slide) * s
                scale = i == movedIndex ? 1 + 0.13 * arc : 1 - 0.08 * arc
            }
            let isClearing = clearing?.cells.contains(i) == true
            if isClearing {
                if cp < 0.3 {
                    scale = 1 + 0.14 * (cp / 0.3)
                    flash = cp / 0.3
                } else {
                    let q = (cp - 0.3) / 0.7
                    scale = 1.14 * (1 - q * q)
                    flash = 1 - q * 0.6
                }
            }
            if let start = pops[c.id] {
                let q = CGFloat((now - start) / 0.28)
                if q >= 1 { pops[c.id] = nil } else { scale *= q < 0.6 ? backOut(q / 0.6) * 1.05 : 1.05 - 0.05 * ((q - 0.6) / 0.4) }
            }
            if let start = flashes[c.id] {
                let q = CGFloat((now - start) / 0.2)
                if q >= 1 { flashes[c.id] = nil } else { flash = max(flash, 0.55 * (1 - q)) }
            }
            if let hit = squashes[c.id] {
                let q = (now - hit.start) / 0.24
                if q >= 1 { squashes[c.id] = nil } else { squash = CGFloat(hit.amount * sin(q * .pi * 1.5) * (1 - q)) }
            }
            if let fail, fail.t < 0.3, i == fail.a || i == fail.b, game.phase != .swapBack {
                x += CGFloat(sin(fail.t * 60) * 0.08 * (1 - fail.t / 0.3)) * s
            }
            if i == selection && game.phase == .swap { scale *= 1.08 + (motion ? 0.025 * CGFloat(sin(now / 0.13)) : 0) }

            let spent = spentRows >= 0 && Grid.rows - 1 - row < spentRows
            if spent != tile.spent {
                tile.spent = spent
                tile.texture = spent ? sheet.spent[c.special.rawValue] : sheet.blocks[c.color][c.special.rawValue]
            }
            tile.glow?.isHidden = isClearing || spent
            tile.setFlash(flash * 0.85, sheet.white)
            // scaled about its center, squashed onto its bottom edge
            let height = scale * (1 - squash)
            tile.xScale = scale * (1 + squash * 0.6)
            tile.yScale = height
            var cy = y + s * (1 + scale) / 2 - s * height / 2
            if i == movedIndex {
                liftShadow.isHidden = false
                liftShadow.alpha = 0.3 * arc
                liftShadow.position = pt(x + s / 2, y + s * 0.6)
                cy -= s * 0.06 * arc
            }
            tile.zPosition = i == movedIndex ? Z.lifted : Z.tile
            tile.position = pt(x + s / 2, cy)
        }
        if seen != tiles.count {
            tiles = tiles.filter {
                if $0.value.stamp == tick { return true }
                $0.value.removeFromParent()
                return false
            }
        }
    }

    private func showPiece(_ piece: Piece, _ sheet: BlockSheet, animated: Bool) {
        vis = (piece.id, Double(piece.x), Double(piece.y), 0, 0, 0, 0, 0, animated && motion ? 0 : 1)
        for (k, block) in piece.blocks.enumerated() {
            pieceTiles[k].texture = sheet.blocks[block.color][0]
            pieceTiles[k].setGlow(sheet.glow, Theme.blocks[block.color])
            pieceTiles[k].glow?.alpha = 0.22
            ghosts[k].color = Theme.blocks[block.color].ui
        }
    }

    private func syncPiece(_ game: Game, _ dt: Double) {
        guard let sheet, game.phase == .fall, let piece = game.piece, vis.id == piece.id else {
            if pieceShown {
                pieceShown = false
                for node in pieceTiles { node.isHidden = true }
                for node in ghosts + guides { node.isHidden = true }
            }
            return
        }
        pieceShown = true
        let s = cell
        vis.x += (Double(piece.x) - vis.x) * min(1, dt * 32)
        vis.y += (Double(piece.y) - vis.y) * min(1, dt * 38)
        if abs(Double(piece.x) - vis.x) < 0.02 { vis.x = Double(piece.x) }
        if abs(Double(piece.y) - vis.y) < 0.02 { vis.y = Double(piece.y) }
        let landing = game.ghostY

        // column guides under the falling piece
        for x in guideBottoms.indices { guideBottoms[x] = -1 }
        for block in piece.blocks { guideBottoms[piece.x + block.x] = max(guideBottoms[piece.x + block.x], landing + block.y) }
        let guideTop = max(0, CGFloat(vis.y + 1) * s)
        var used = 0
        for (x, bottom) in guideBottoms.enumerated() where bottom >= 0 && used < guides.count {
            let height = CGFloat(bottom + 1) * s - guideTop
            guard height > 0 else { continue }
            guides[used].isHidden = false
            guides[used].size = CGSize(width: s, height: height)
            guides[used].position = pt((CGFloat(x) + 0.5) * s, guideTop + height / 2)
            used += 1
        }
        for guide in guides[used...] { guide.isHidden = true }

        let ghostOn = model?.settings.ghost != false && landing != piece.y
        let appear = cubicOut(CGFloat(vis.spawnT))
        let originX = CGFloat(vis.x + vis.bumpX) * s
        let originY = (CGFloat(vis.y) - (1 - appear) * 0.6) * s
        let angle = CGFloat(vis.rot + vis.wiggle)
        let half = CGFloat(piece.shape.size) * s / 2
        let lockGlow = game.grounded ? CGFloat(clamp(game.lockTimer / Timing.lockDelay, 0, 1)) : 0
        for (k, block) in piece.blocks.enumerated() {
            ghosts[k].isHidden = !ghostOn || landing + block.y < 0
            ghosts[k].position = pt((CGFloat(piece.x + block.x) + 0.5) * s, (CGFloat(landing + block.y) + 0.5) * s)
            // turn each cell about the shape's box center (the SRS pivot)
            let dx = (CGFloat(block.x) + 0.5) * s - half
            let dy = (CGFloat(block.y) + 0.5) * s - half
            let tile = pieceTiles[k]
            tile.position = pt(originX + half + dx * cos(angle) - dy * sin(angle), originY + half + dx * sin(angle) + dy * cos(angle))
            tile.zRotation = -angle
            tile.alpha = 0.25 + 0.75 * appear
            tile.isHidden = -tile.position.y < -s * 0.45
            tile.setFlash(lockGlow * 0.3, sheet.white)
        }
    }

    // MARK: HUD

    /// The shape in a hold or next slot, sized to fit and centered under the caption.
    private func fill(_ slot: SKNode, with def: PieceDef?, in rect: CGRect, alpha: CGFloat, captioned: Bool) {
        slot.removeAllChildren()
        slot.removeAllActions()
        slot.setScale(1)
        slot.alpha = alpha
        guard let def, let sheet else { return }
        let cells = Shape.all[def.type].cells
        let minX = cells.map(\.x).min()!
        let minY = cells.map(\.y).min()!
        let w = CGFloat(cells.map(\.x).max()! - minX + 1)
        let h = CGFloat(cells.map(\.y).max()! - minY + 1)
        let top = captioned ? rect.height * 0.16 : 0
        let s = min(rect.width * 0.78 / max(w, 3), (rect.height - top) * 0.72 / max(h, 2), cell * 0.9)
        slot.position = pt(rect.midX, rect.midY + top / 2)
        for (k, c) in cells.enumerated() {
            let block = SKSpriteNode(texture: sheet.blocks[def.colors[k]][0], size: CGSize(width: s, height: s))
            block.position = pt((CGFloat(c.x - minX) + 0.5 - w / 2) * s, (CGFloat(c.y - minY) + 0.5 - h / 2) * s)
            slot.addChild(block)
        }
    }
    /// Grow in with a little overshoot.
    private func pop(_ node: SKNode, delay: Double = 0) {
        guard motion else { return }
        let alpha = node.alpha
        node.setScale(0.55)
        node.alpha = 0
        node.run(.sequence([.wait(forDuration: delay), .group([
            SKAction.scale(to: 1, duration: 0.26).eased(backOut), .fadeAlpha(to: alpha, duration: 0.14),
        ])]))
    }
    private func refreshSlots(animated: Bool) {
        guard let game, slots.count == 4 else { return }
        fill(slots[0], with: game.hold, in: L.hold, alpha: game.holdUsed ? 0.3 : 1, captioned: true)
        for k in 0..<3 {
            fill(slots[k + 1], with: game.queue[k], in: L.next[k], alpha: [1, 0.85, 0.7][k], captioned: k == 0)
            // the queue shuffles forward in a quick stagger after each spawn
            if animated { pop(slots[k + 1], delay: Double(k) * 0.05) }
        }
    }

    private func syncHUD(_ game: Game) {
        let score = Int(shownScore.rounded())
        if score != shown.score || scorePop > 0 {
            if score != shown.score {
                shown.score = score
                setText(scoreLabel, score.formatted())
            }
            // the score swells briefly when points land, and shrinks to fit when it gets long
            let width = scoreLabel.attributedText?.size().width ?? 0
            let swell = motion ? CGFloat(sin(.pi * (1 - scorePop)) * scorePop) : 0
            scoreLabel.setScale(min(1, (L.info.width - 44) / max(1, width)) * (1 + 0.12 * swell))
        }
        if game.level != shown.level {
            shown.level = game.level
            setText(levelLabel, String(game.level))
        }
        if levelPop > 0 || levelPill.xScale != 1 {
            levelPill.setScale(1 + (motion ? CGFloat(0.1 * sin(.pi * (1 - levelPop)) * min(1, levelPop * 3)) : 0))
        }
        if game.levelProgress != shown.progress {
            shown.progress = game.levelProgress
            levelBar.isHidden = game.levelProgress <= 0
            barSlice?.resize(levelBar, CGSize(width: max(4, barWidths.level * game.levelProgress), height: 4))
        }
        let meter = game.tokens >= Rules.maxTokens ? 1 : game.meter / Rules.meterMax
        if meter != shown.meter {
            shown.meter = meter
            meterBar.isHidden = meter <= 0
            barSlice?.resize(meterBar, CGSize(width: max(2.5, barWidths.meter * meter), height: 2.5))
        }
        if game.tokens != shown.tokens {
            for (k, pip) in pips.enumerated() {
                pip.texture = pipTextures[k < game.tokens ? 1 : 0]
                if shown.tokens >= 0 && k >= shown.tokens && k < game.tokens && motion {
                    pip.setScale(0)
                    pip.run(SKAction.scale(to: 1, duration: 0.3).eased(backOut))
                }
            }
            shown.tokens = game.tokens
        }
        if tokenPulse > 0 || swapGlow.alpha > 0 { swapGlow.alpha = CGFloat(tokenPulse * 0.55) }
        if game.tokens != shown.swaps && (game.phase == .swap || game.phase == .swapBack) {
            shown.swaps = game.tokens
            setText(swapLabel, game.tokens > 1 ? "SWAP  ×\(game.tokens)" : "SWAP")
        }
    }

    /// Outlines for every swap that would make a match, and arrows from the selected block to its partners.
    private func refreshHighlights() {
        legalMarks.removeAllChildren()
        legalMarks.removeAllActions()
        guard let game, let sheet, game.phase == .swap else { return }
        let s = cell
        let center = { (i: Int) in pt((CGFloat(i % Grid.cols) + 0.5) * s, (CGFloat(i / Grid.cols) + 0.5) * s) }
        let mark = { (i: Int, color: UIColor, scale: CGFloat, parent: SKNode) in
            let node = SKSpriteNode(texture: sheet.outline, size: CGSize(width: s * scale, height: s * scale))
            node.color = color
            node.colorBlendFactor = 1
            node.position = center(i)
            parent.addChild(node)
        }
        let pulsing = SKNode()
        pulsing.alpha = 0.35
        pulsing.run(.repeatForever(.sequence([.fadeAlpha(to: 0.8, duration: 0.69), .fadeAlpha(to: 0.35, duration: 0.69)])))
        legalMarks.addChild(pulsing)
        for i in game.legalCells where i != selection { mark(i, .white, 1.08, pulsing) }
        if selection >= 0 && game.board[selection] != nil {
            mark(selection, .white, 1.24, legalMarks)
            for partner in game.partners(of: selection) {
                mark(partner, Theme.gold.ui, 1.2, legalMarks)
                let from = center(selection)
                let to = center(partner)
                let arrow = SKSpriteNode(texture: Art.chevron(s, scale: displayScale), size: CGSize(width: s * 0.5, height: s * 0.5))
                arrow.position = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                arrow.zRotation = atan2(to.y - from.y, to.x - from.x)
                arrow.zPosition = 1
                legalMarks.addChild(arrow)
            }
        }
        if keyMode && cursor >= 0 { mark(cursor, Theme.blocks[2].ui, 1.16, legalMarks) }
    }
    private func select(_ i: Int) {
        guard i != selection else { return }
        selection = i
        refreshHighlights()
    }

    // MARK: Events

    private func handle(_ events: [Event]) {
        guard let game, let sheet else { return }
        let s = cell
        for event in events {
            switch event {
            case .spawn(let piece):
                showPiece(piece, sheet, animated: true)
                refreshSlots(animated: game.queue.first != queueHead)
                queueHead = game.queue.first
                checkpoint = game.snapshot
            case .move:
                play(.move)
            case .rotate(let dir):
                play(.rotate)
                // the cells are already turned; start the drawing a quarter turn back and ease it in
                if motion { vis.rot = clamp(vis.rot - Double(dir) * .pi / 2, -.pi, .pi) }
            case .land:
                play(.land)
            case .hardDrop(let distance, let fromY, let piece):
                play(.hardDrop)
                Haptics.thump()
                hardLock = true
                if motion { kickV = Double(s) * 2.6 }
                for block in piece.blocks {
                    let top = CGFloat(fromY + block.y) * s
                    let bottom = CGFloat(piece.y + block.y + 1) * s
                    let trail = SKSpriteNode(texture: Art.fade, size: CGSize(width: s * 0.7, height: bottom - top))
                    trail.color = Theme.blocks[block.color].ui
                    trail.colorBlendFactor = 1
                    trail.alpha = 0.4
                    trail.position = pt((CGFloat(piece.x + block.x) + 0.5) * s, (top + bottom) / 2)
                    trail.zPosition = Z.under - Z.fx
                    trail.run(SKAction.fadeOut(withDuration: 0.22).once)
                    fx.addChild(trail)
                }
                // a short puff where the shape hits
                if motion && distance > 0 {
                    for x in Set(piece.blocks.map(\.x)) {
                        let bottom = piece.blocks.filter { $0.x == x }.map(\.y).max()!
                        for _ in 0..<3 {
                            confetti(x: (CGFloat(piece.x + x) + .random(in: 0.15...0.85)) * s, y: CGFloat(piece.y + bottom + 1) * s,
                                     vx: s * .random(in: -1.6...1.6), vy: -s * .random(in: 0.6...1.8), life: .random(in: 0.28...0.44),
                                     side: s * .random(in: 0.07...0.13), color: Theme.cream.ui, texture: sheet.dot, gravity: 0.12)
                        }
                    }
                }
            case .lock(let cells):
                play(.lock)
                for i in cells {
                    guard let c = game.board[i] else { continue }
                    flashes[c.id] = now
                    if motion { squashes[c.id] = (now, hardLock ? 0.2 : 0.12) }
                }
                hardLock = false
                tilesDirty = true
            case .hold:
                play(.hold)
                refreshSlots(animated: false)
                pop(slots[0])
            case .clear(let clear):
                onClear(clear)
            case .cleared(let removed, let made):
                let each = clamp(Int((160 / Double(max(1, removed.count))).rounded()), 2, 8)
                for cellInfo in removed { burst(cellInfo.index, Theme.blocks[cellInfo.color], count: Int((Double(each) * 0.6).rounded(.up))) }
                for id in made { pops[id] = now }
                tilesDirty = true
            case .levelUp(let level, let newColor):
                play(.level)
                Haptics.notify(.success)
                levelPop = 1
                let detail = newColor ? "New color: \(Theme.blockNames[game.paletteSize - 1])" : game.calm ? "Points ×\(level)" : "Faster drops"
                banner("LEVEL \(level)", detail, .white, at: 0.24, name: "level")
            case .swapGained(let count):
                play(.token)
                tokenPulse = 1
                floatText("+\(count) SWAP", x: L.board.width / 2, y: L.board.height * 0.32, size: s * 0.5, color: Theme.gold)
            case .swapPhase:
                play(.swapOpen)
                selection = -1
                hurried = false
                shown.swaps = -1
                if keyMode { cursor = nearestLegal(to: cursor) }
                refreshHighlights()
            case .swap:
                play(.swap)
                Haptics.snap()
                tilesDirty = true
            case .swapFail(let a, let b):
                play(.fail)
                Haptics.tap()
                fail = (a, b, 0)
            case .swapEnded:
                selection = -1
            case .gameOver:
                state = .dying
                overT = 0
                checkpoint = nil
                play(.over)
                Haptics.notify(.error)
                if motion { shake = max(shake, Double(s) * 0.3) }
                model?.finish(game)
            }
        }
    }

    private func jolt(_ amount: CGFloat) {
        if motion { shake = max(shake, Double(amount)) }
    }

    private func onClear(_ clear: Clear) {
        let s = cell
        play(.clear(chain: clear.chain))
        scorePop = 1
        if clear.cells.count >= 6 || clear.chain >= 2 { Haptics.snap(min(1, 0.5 + 0.15 * CGFloat(clear.chain))) }
        let count = CGFloat(max(1, clear.cells.count))
        let cx = clear.cells.reduce(0) { $0 + CGFloat($1 % Grid.cols) } / count
        let cy = clear.cells.reduce(0) { $0 + CGFloat($1 / Grid.cols) } / count
        floatText("+\(clear.points.formatted())", x: (cx + 0.5) * s, y: (cy + 0.5) * s, size: clamp(s * (0.45 + CGFloat(clear.chain) * 0.06), 12, 34))
        if let combo = clear.combo {
            play(.combo)
            banner(combo.title, "Special swap", Theme.gold)
            jolt(s * 0.35)
        } else if clear.chain >= 2 {
            banner("CHAIN ×\(clear.chain)", clear.chain >= 3 ? "Cascade!" : "", clear.chain >= 4 ? Theme.gold : .white)
        }
        if !clear.created.isEmpty { play(.special) }
        for made in clear.created {
            floatText(["", "LINE", "LINE", "BOMB", "PRISM"][made.special.rawValue], x: (CGFloat(made.index % Grid.cols) + 0.5) * s,
                      y: CGFloat(made.index / Grid.cols) * s, size: s * 0.42, color: Theme.blocks[made.color].lighter(0.35), life: 0.9)
        }
        var kinds = (line: false, bomb: false, prism: false)
        for effect in clear.effects {
            switch effect {
            case .lineH(let y, let color, let wide):
                kinds.line = true
                guard (0..<Grid.rows).contains(y) else { continue }
                beam(pt(L.board.width / 2, (CGFloat(y) + 0.5) * s), CGSize(width: L.board.width, height: s * (wide ? 1 : 0.9)), color, horizontal: true)
            case .lineV(let x, let color, let wide):
                kinds.line = true
                guard (0..<Grid.cols).contains(x) else { continue }
                beam(pt((CGFloat(x) + 0.5) * s, L.board.height / 2), CGSize(width: s * (wide ? 1 : 0.9), height: L.board.height), color, horizontal: false)
            case .bomb(let x, let y, let radius, let color):
                kinds.bomb = true
                blast(pt((CGFloat(x) + 0.5) * s, (CGFloat(y) + 0.5) * s), radius: s * (CGFloat(radius) + 0.7), color)
            case .prism(let x, let y, let color, let targets):
                kinds.prism = true
                lightning(from: CGPoint(x: (CGFloat(x) + 0.5) * s, y: (CGFloat(y) + 0.5) * s), to: targets, color)
            }
        }
        if kinds.line {
            play(.line)
            jolt(s * 0.15)
        }
        if kinds.bomb {
            play(.bomb)
            Haptics.thump()
            jolt(s * 0.3)
        }
        if kinds.prism {
            play(.prism)
            jolt(s * 0.25)
        }
        if clear.chain >= 3 { jolt(s * 0.08 * CGFloat(clear.chain)) }
    }

    // MARK: Effects

    private func glowing(_ node: SKNode, life: Double, _ actions: [SKAction] = []) {
        (node as? SKSpriteNode)?.blendMode = .add
        (node as? SKShapeNode)?.blendMode = .add
        node.run(SKAction.group(actions + [.fadeOut(withDuration: life)]).once)
        fx.addChild(node)
    }

    private func beam(_ center: CGPoint, _ size: CGSize, _ color: Int, horizontal: Bool) {
        let core = horizontal ? CGSize(width: size.width, height: size.height / 3) : CGSize(width: size.width / 3, height: size.height)
        let layers: [(CGSize, UIColor)] = [(size, Theme.blocks[color].ui.withAlphaComponent(0.75)), (core, .white)]
        for (size, tint) in layers {
            let node = SKSpriteNode(color: tint, size: size)
            node.position = center
            glowing(node, life: 0.45, [horizontal ? .scaleY(to: 0.04, duration: 0.45) : .scaleX(to: 0.04, duration: 0.45)])
        }
    }

    private func blast(_ center: CGPoint, radius: CGFloat, _ color: Int) {
        guard let sheet else { return }
        let layers: [(CGFloat, UIColor)] = [(radius * 2.6, Theme.blocks[color].ui), (radius * 1.5, .white)]
        for (size, tint) in layers {
            let flare = SKSpriteNode(texture: sheet.glow, size: CGSize(width: size, height: size))
            flare.color = tint
            flare.colorBlendFactor = 1
            flare.position = center
            flare.setScale(0.4)
            glowing(flare, life: 0.55, [SKAction.scale(to: 1.6, duration: 0.55).eased(cubicOut)])
        }
    }

    /// Jagged bolts from a prism to every block it takes.
    private func lightning(from origin: CGPoint, to targets: [Int], _ color: Int) {
        guard let sheet else { return }
        let s = cell
        let path = CGMutablePath()
        for target in targets.prefix(48) {
            let end = CGPoint(x: (CGFloat(target % Grid.cols) + 0.5) * s, y: (CGFloat(target / Grid.cols) + 0.5) * s)
            let dx = end.x - origin.x
            let dy = end.y - origin.y
            let length = max(1, hypot(dx, dy))
            path.move(to: pt(origin.x, origin.y))
            for k in 1..<5 {
                let t = CGFloat(k) / 5
                let offset = CGFloat.random(in: -0.45...0.45) * s
                path.addLine(to: pt(origin.x + dx * t - dy / length * offset, origin.y + dy * t + dx / length * offset))
            }
            path.addLine(to: pt(end.x, end.y))
        }
        let layers: [(CGFloat, UIColor)] = [(s * 0.16, Theme.blocks[color].ui.withAlphaComponent(0.6)), (max(1, s * 0.05), .white)]
        for (width, tint) in layers {
            let bolts = SKShapeNode(path: path)
            bolts.strokeColor = tint
            bolts.lineWidth = width
            bolts.lineJoin = .round
            glowing(bolts, life: 0.6)
        }
        let core = SKSpriteNode(texture: sheet.glow, size: CGSize(width: s * 2, height: s * 2))
        core.position = pt(origin.x, origin.y)
        glowing(core, life: 0.6, [.scale(to: 2.6, duration: 0.6)])
    }

    private func confetti(x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, life: Double, side: CGFloat, color: UIColor, texture: SKTexture, gravity: CGFloat = 1) {
        guard floating.children.count < 320 else { return }
        let bit = SKSpriteNode(texture: texture, size: CGSize(width: side, height: side))
        bit.color = color
        bit.colorBlendFactor = 1
        bit.position = pt(x, y)
        bit.zPosition = Z.confetti
        bit.zRotation = .random(in: 0...6)
        let t = CGFloat(life)
        // ballistic arc: a straight drift plus a quadratic fall
        bit.run(SKAction.group([
            .moveBy(x: vx * t, y: -vy * t, duration: life),
            SKAction.moveBy(x: 0, y: -0.5 * cell * 22 * gravity * t * t, duration: life).eased { $0 * $0 },
            .rotate(byAngle: .random(in: -7...7) * t, duration: life),
            .fadeOut(withDuration: life),
        ]).once)
        floating.addChild(bit)
    }

    private func burst(_ index: Int, _ color: RGB, count: Int) {
        guard let sheet else { return }
        let s = cell
        let x = (CGFloat(index % Grid.cols) + 0.5) * s
        let y = (CGFloat(index / Grid.cols) + 0.5) * s
        for _ in 0..<count {
            let angle = CGFloat.random(in: 0..<(2 * .pi))
            let speed = s * .random(in: 2...7)
            confetti(x: x, y: y, vx: cos(angle) * speed, vy: sin(angle) * speed - s * 3, life: .random(in: 0.45...0.9),
                     side: s * .random(in: 0.12...0.26), color: Double.random(in: 0..<1) < 0.25 ? .white : color.lighter(0.2).ui, texture: sheet.white)
        }
    }

    private func floatText(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, color: RGB = .white, life: Double = 1) {
        guard let art = Art.text(string, font: Theme.display(size, black: true), fill: color.cg(), outline: Theme.ink.darker(0.4).cg(0.85),
                                 width: size * 0.22, scale: displayScale) else { return }
        let node = SKSpriteNode(texture: art.texture, size: art.size)
        node.position = pt(x, y)
        node.zPosition = Z.text
        node.setScale(motion ? 0.01 : 1)
        node.run(SKAction.group([
            SKAction.scale(to: 1, duration: life * 0.12).eased(backOut),
            SKAction.moveBy(x: 0, y: cell * 1.4, duration: life).eased(cubicOut),
            .sequence([.wait(forDuration: life * 0.7), .fadeOut(withDuration: life * 0.3)]),
        ]).once)
        floating.addChild(node)
    }

    private func banner(_ title: String, _ detail: String, _ color: RGB, at height: CGFloat = 0.42, name: String = "banner") {
        let s = cell
        let outline = Theme.ink.darker(0.4).cg(0.88)
        guard let art = Art.text(title, font: Theme.display(s * 1.05, black: true), fill: color.cg(), outline: outline, width: s * 0.17, scale: displayScale) else { return }
        floating.childNode(withName: name)?.removeFromParent()
        let node = SKNode()
        node.name = name
        node.position = pt(L.board.width / 2, L.board.height * height)
        node.zPosition = Z.banner
        let fit = min(1, L.board.width * 0.92 / art.size.width)
        let headline = SKSpriteNode(texture: art.texture, size: CGSize(width: art.size.width * fit, height: art.size.height * fit))
        node.addChild(headline)
        if let sub = Art.text(detail, font: Theme.rounded(s * 0.4, .heavy), fill: Theme.cream.cg(), outline: outline, width: s * 0.1, scale: displayScale) {
            let line = SKSpriteNode(texture: sub.texture, size: sub.size)
            line.position = CGPoint(x: 0, y: -headline.size.height / 2 - sub.size.height / 2 - 1)
            node.addChild(line)
        }
        node.setScale(motion ? 0.01 : 1)
        node.run(SKAction.sequence([
            SKAction.scale(to: 1, duration: 0.23).eased(backOut), .wait(forDuration: 0.74), .fadeOut(withDuration: 0.33),
        ]).once)
        floating.addChild(node)
    }

    // MARK: Touch

    private func canvasPoint(_ touch: UITouch) -> CGPoint {
        let p = touch.location(in: self)
        return CGPoint(x: p.x, y: -p.y)
    }
    private func cellAt(_ p: CGPoint) -> Int {
        let column = Int(floor((p.x - L.board.minX) / cell))
        let row = Int(floor((p.y - L.board.minY) / cell))
        return (0..<Grid.cols).contains(column) && (0..<Grid.rows).contains(row) ? Grid.index(column, row) : -1
    }
    /// Direction 0 is right, then down, left and up.
    private func neighbor(_ i: Int, _ direction: Int) -> Int {
        let x = Grid.x(i)
        let y = Grid.y(i)
        switch direction {
        case 0 where x < Grid.cols - 1: return i + 1
        case 1 where y < Grid.rows - 1: return i + Grid.cols
        case 2 where x > 0: return i - 1
        case 3 where y > 0: return i - Grid.cols
        default: return -1
        }
    }
    private func nearestLegal(to from: Int) -> Int {
        guard let game else { return -1 }
        var best = -1
        var bestDistance = Int.max
        for i in game.legalCells {
            let distance = from < 0 ? -i : abs(Grid.x(i) - Grid.x(from)) + abs(Grid.y(i) - Grid.y(from))
            if distance < bestDistance {
                bestDistance = distance
                best = i
            }
        }
        return best
    }

    private func swap(_ a: Int, _ b: Int) {
        game?.trySwap(a, b)
        select(-1)
    }
    private func hold() {
        if game?.holdPiece() == true { Haptics.tap() }
    }
    private func bumpWall(_ dir: Int) {
        guard motion, game?.phase == .fall, abs(vis.bumpX) < 0.03, abs(vis.bumpV) < 0.6 else { return }
        vis.bumpV = Double(dir) * 3.4
        play(.bump)
    }
    private func rotate(_ dir: Int) {
        guard game?.rotate(dir) == false, motion else { return }
        vis.wiggleV = Double(dir) * 4.5
        play(.bump)
    }
    private func beginPieceGesture(_ p: CGPoint, _ piece: Piece) {
        gesture = .piece
        touchStart = p
        anchor = piece.x
        pieceID = piece.id
        droppedRows = 0
    }
    private func endTouch() {
        game?.swapHold = false
        touch = nil
        gesture = .none
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard state == .playing, touch == nil, let first = touches.first, let game else { return }
        touch = first
        keyMode = false
        let p = canvasPoint(first)
        touchStart = p
        touchTime = first.timestamp
        samples = [(p, first.timestamp)]
        moved = false
        dragged = false
        pressed = -1
        gesture = .hud
        if L.pause.insetBy(dx: -8, dy: -8).contains(p) {
            model?.pause()
        } else if L.hold.insetBy(dx: -4, dy: -4).contains(p) && game.phase == .fall {
            hold()
        } else if game.phase == .fall, let piece = game.piece {
            beginPieceGesture(p, piece)
        } else if game.phase == .swap {
            gesture = .swap
            game.swapHold = true
            let i = cellAt(p)
            pressed = i >= 0 && game.board[i] != nil ? i : -1
            wasSelected = pressed >= 0 && pressed == selection
            if pressed >= 0 && !(selection >= 0 && Grid.adjacent(selection, pressed)) {
                if selection != pressed { play(.select) }
                select(pressed)
            }
        } else {
            gesture = .wait
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch, touches.contains(touch), let game else { return }
        let p = canvasPoint(touch)
        samples.append((p, touch.timestamp))
        while samples.count > 2 && touch.timestamp - samples[0].t > 0.25 { samples.removeFirst() }
        var dx = p.x - touchStart.x
        var dy = p.y - touchStart.y
        if abs(dx) > 9 || abs(dy) > 9 { moved = true }
        if gesture == .wait, game.phase == .fall, let piece = game.piece {
            beginPieceGesture(p, piece)
            dx = 0
            dy = 0
        }
        if gesture == .piece {
            guard game.phase == .fall, let piece = game.piece, piece.id == pieceID else {
                gesture = .none
                return
            }
            let step = cell * 0.88
            let target = anchor + Int((dx / step).rounded())
            while let x = game.piece?.x, x != target {
                let dir = (target - x).signum()
                if !game.move(dir) {
                    bumpWall(dir)
                    anchor = x - Int((dx / step).rounded())
                    break
                }
            }
            let dead = cell * 0.9
            if dy > dead && dy > abs(dx) * 0.9 {
                let rows = Int((dy - dead) / (cell * 0.7))
                while droppedRows < rows, game.softDropStep() { droppedRows += 1 }
            }
        } else if gesture == .swap && pressed >= 0 && !dragged {
            let threshold = cell * 0.45
            guard abs(dx) > threshold || abs(dy) > threshold else { return }
            dragged = true
            let target = neighbor(pressed, abs(dx) > abs(dy) ? (dx > 0 ? 0 : 2) : dy > 0 ? 1 : 3)
            if target >= 0 && game.board[target] != nil { swap(pressed, target) } else { select(-1) }
        }
    }

    /// Peak vertical speed over the last 150 ms, each reading spanning at least 24 ms to smooth out jitter.
    private func flickSpeed() -> CGFloat {
        guard samples.count >= 2, let end = samples.last?.t else { return 0 }
        var best: CGFloat = 0
        for k in stride(from: samples.count - 1, to: 0, by: -1) {
            let b = samples[k]
            if end - b.t > 0.15 { break }
            var j = k - 1
            while j > 0 && b.t - samples[j].t < 0.024 { j -= 1 }
            let speed = (b.p.y - samples[j].p.y) / CGFloat(max(0.001, b.t - samples[j].t))
            if abs(speed) > abs(best) { best = speed }
        }
        return best
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch, touches.contains(touch), let game else { return }
        let p = canvasPoint(touch)
        samples.append((p, touch.timestamp))
        let dx = p.x - touchStart.x
        let dy = p.y - touchStart.y
        let speed = flickSpeed()
        switch gesture {
        case .piece where game.phase == .fall && game.piece?.id == pieceID:
            if !moved && touch.timestamp - touchTime < 0.35 {
                rotate(p.x < L.board.midX ? -1 : 1)
                Haptics.tap()
            } else if dy > cell * 1.2 && speed > 600 && abs(dy) > abs(dx) {
                game.hardDrop()
            } else if dy < -cell * 1.2 && speed < -600 && abs(dy) > abs(dx) {
                hold()
            }
        case .swap:
            game.swapHold = false
            guard game.phase == .swap, !dragged else { break }
            if moved {
                if pressed < 0 && dy > cell * 1.2 { game.skipSwap() }
            } else if pressed >= 0 {
                if selection >= 0 && selection != pressed && Grid.adjacent(selection, pressed) {
                    swap(selection, pressed)
                } else if wasSelected {
                    select(-1)
                }
            } else if selection >= 0 {
                select(-1)
            } else {
                game.skipSwap()
            }
        case .wait where !moved && game.phase == .swap:
            game.skipSwap()
        default:
            break
        }
        endTouch()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch, touches.contains(touch) { endTouch() }
    }

    // MARK: Keyboard

    /// Hooked up when the first game starts, to keep the controller framework out of launch.
    private func watchKeyboard() {
        guard !watchingKeyboard else { return }
        watchingKeyboard = true
        attachKeyboard()
        NotificationCenter.default.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.attachKeyboard() }
        }
    }
    private func attachKeyboard() {
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = { [weak self] _, _, key, down in
            MainActor.assumeIsolated { self?.key(key, down: down) }
        }
    }

    private func key(_ key: GCKeyCode, down: Bool) {
        guard let model else { return }
        guard state == .playing, let game else {
            guard down else { return }
            if model.screen == .pause && (key == .escape || key == .keyP) { model.resume() }
            if model.screen == .over && (key == .returnOrEnter || key == .spacebar) { model.start(resume: false) }
            return
        }
        guard down else {
            switch key {
            case .leftArrow:
                held.left = false
                if held.dir == -1 { held.dir = held.right ? 1 : 0 }
                held.delay = 0
            case .rightArrow:
                held.right = false
                if held.dir == 1 { held.dir = held.left ? -1 : 0 }
                held.delay = 0
            case .downArrow:
                game.softDropping = false
            default:
                break
            }
            return
        }
        if key == .escape && game.phase == .swap && selection >= 0 {
            select(-1)
        } else if key == .escape || key == .keyP {
            model.pause()
        } else if game.phase == .swap {
            keyMode = true
            if cursor < 0 { cursor = nearestLegal(to: -1) }
            let directions: [GCKeyCode: Int] = [.rightArrow: 0, .downArrow: 1, .leftArrow: 2, .upArrow: 3]
            if let direction = directions[key] {
                if selection >= 0 {
                    let target = neighbor(selection, direction)
                    if target >= 0 && game.board[target] != nil {
                        swap(selection, target)
                        cursor = target
                    }
                } else {
                    let target = neighbor(max(cursor, 0), direction)
                    if target >= 0 { cursor = target }
                }
            } else if [.returnOrEnter, .keyX, .keyZ].contains(key) {
                if selection == cursor {
                    selection = -1
                } else if cursor >= 0 && game.board[cursor] != nil {
                    selection = cursor
                    play(.select)
                }
            } else if key == .spacebar {
                game.skipSwap()
            }
            refreshHighlights()
        } else {
            switch key {
            case .leftArrow, .rightArrow:
                let dir = key == .leftArrow ? -1 : 1
                if dir < 0 { held.left = true } else { held.right = true }
                held.dir = dir
                held.delay = 0
                held.tick = 0
                if !game.move(dir) { bumpWall(dir) }
            case .downArrow: game.softDropping = true
            case .upArrow, .keyX: rotate(1)
            case .keyZ: rotate(-1)
            case .spacebar: game.hardDrop()
            case .keyC, .leftShift, .rightShift: hold()
            default: break
            }
        }
    }

    /// Auto-repeat for a held arrow key: a short delay, then a steady slide.
    private func updateKeys(_ dt: Double) {
        guard held.dir != 0, let game, game.phase == .fall else { return }
        held.delay += dt
        guard held.delay >= 0.16 else { return }
        held.tick += dt
        while held.tick >= 0.045 {
            held.tick -= 0.045
            if !game.move(held.dir) {
                held.tick = 0
                break
            }
        }
    }
}

private extension Combo {
    var title: String {
        switch self {
        case .cross: "CROSSFIRE"
        case .wide: "WIDE CROSS"
        case .mega: "MEGA BLAST"
        case .wipe: "COLOR WIPE"
        case .wipeLines: "LINE STORM"
        case .wipeBombs: "BOMB STORM"
        case .wipe2: "DOUBLE WIPE"
        }
    }
}
