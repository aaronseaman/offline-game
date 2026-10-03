import SpriteKit
import SwiftUI

@main struct PrismfallApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.suspend() }
        }
    }
}

struct RootView: View {
    let model: AppModel
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SpriteView(scene: model.scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder, .shouldCullNonVisibleNodes])
                    .ignoresSafeArea()
                if model.ready {
                    Screens(model: model)
                } else {
                    // continues the launch screen until the artwork is painted
                    ZStack {
                        Color.black
                        Image(.launchLogo)
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: model.ready)
            .onChange(of: geometry.safeAreaInsets, initial: true) { _, insets in
                model.scene.setMetrics(UIEdgeInsets(top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing), scale: displayScale)
            }
        }
        .preferredColorScheme(.light)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // drags and flicks run to the screen edges
        .defersSystemGestures(on: .all)
    }
}

struct Settings: Codable, Equatable {
    var sound = true
    var haptics = true
    var ghost = true
    var symbols = true
    var relaxed = false
}

struct Score: Codable, Identifiable {
    var score: Int
    var level: Int
    var chain: Int
    var date: Date

    var id: Date { date }
}

/// What the game-over card shows.
struct Summary {
    var score: Int
    var level: Int
    var cleared: Int
    var stats: Stats
    var previousBest: Int
    var isBest: Bool
}

/// App state: which screen is up, settings, scores and the saved game.
@Observable final class AppModel {
    enum Screen { case menu, play, pause, over, settings, help, scores }

    private(set) var screen = Screen.menu {
        // SpriteView's own pause only stops the scene's logic; this stops the view drawing at all
        didSet { scene.view?.isPaused = frozen }
    }
    /// The scene has painted its artwork and built its first frame.
    var ready = false
    var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            Self.store(settings, "settings")
            applySettings()
            if settings.sound && !oldValue.sound { Audio.shared.play(.ui) }
            if settings.haptics && !oldValue.haptics { Haptics.tap() }
        }
    }
    /// The mode a new game starts in. Every launch opens on classic.
    var calm = false
    /// Top ten for classic, then calm.
    private(set) var scores: [[Score]]
    private(set) var saved: Game.Snapshot?
    private(set) var summary: Summary?

    @ObservationIgnored let scene = GameScene()
    /// The screen that settings and help return to.
    @ObservationIgnored private var origin = Screen.menu
    @ObservationIgnored private var startAfterHelp = false

    private static let scoreKeys = ["scores.classic", "scores.calm"]

    init() {
        settings = Self.load("settings") ?? Settings()
        scores = Self.scoreKeys.map { Self.load($0) ?? [] }
        saved = Self.load("save")
        scene.model = self
        applySettings()
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
    private static func store(_ value: some Encodable, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private func applySettings() {
        Audio.shared.setEnabled(settings.sound)
        Haptics.enabled = settings.haptics
        scene.settingsChanged()
    }

    /// First-game control hints show until one game has been finished.
    var firstGame: Bool { !UserDefaults.standard.bool(forKey: "played") }
    var best: Int? { scores[calm ? 1 : 0].first?.score }
    /// A card is covering a game that is not moving, so the view stops drawing.
    var frozen: Bool {
        switch screen {
        case .pause, .over: true
        case .settings, .help: origin == .pause
        default: false
        }
    }

    // MARK: Flow

    /// Play from the menu. The first ever game opens the guide on the way in.
    func play() {
        if UserDefaults.standard.bool(forKey: "seenHelp") {
            start(resume: false)
        } else {
            UserDefaults.standard.set(true, forKey: "seenHelp")
            startAfterHelp = true
            open(.help)
        }
    }
    func start(resume: Bool) {
        if !resume {
            saved = nil
            UserDefaults.standard.removeObject(forKey: "save")
        }
        scene.start(saved, calm: calm)
        screen = .play
        UIApplication.shared.isIdleTimerDisabled = true
    }
    func pause() {
        guard screen == .play, scene.state == .playing else { return }
        scene.pause()
        persist()
        Audio.shared.play(.pause)
        screen = .pause
        UIApplication.shared.isIdleTimerDisabled = false
    }
    func resume() {
        guard screen == .pause else { return }
        scene.resume()
        Audio.shared.play(.resume)
        screen = .play
        UIApplication.shared.isIdleTimerDisabled = true
    }
    func quit() {
        scene.showMenu()
        screen = .menu
    }
    func open(_ sub: Screen) {
        origin = screen
        screen = sub
    }
    /// Leave settings, help or scores.
    func close() {
        if startAfterHelp {
            startAfterHelp = false
            start(resume: false)
        } else {
            screen = origin
        }
    }
    /// The app is leaving the foreground.
    func suspend() {
        if screen == .play && scene.state == .playing { pause() } else { persist() }
    }
    private func persist() {
        guard let checkpoint = scene.checkpoint else { return }
        saved = checkpoint
        Self.store(checkpoint, "save")
    }

    // MARK: Results

    /// The well overflowed: record the score while the board greys out.
    func finish(_ game: Game) {
        let mode = game.calm ? 1 : 0
        let previous = scores[mode].first?.score ?? 0
        let entry = Score(score: game.score, level: game.level, chain: game.stats.maxChain, date: .now)
        scores[mode] = Array((scores[mode] + [entry]).sorted { $0.score > $1.score }.prefix(10))
        Self.store(scores[mode], Self.scoreKeys[mode])
        summary = Summary(score: game.score, level: game.level, cleared: game.cleared, stats: game.stats,
                          previousBest: previous, isBest: game.score > previous && game.score > 0)
        saved = nil
        UserDefaults.standard.removeObject(forKey: "save")
        UserDefaults.standard.set(true, forKey: "played")
        UIApplication.shared.isIdleTimerDisabled = false
    }
    func showGameOver() {
        screen = .over
        if summary?.isBest == true { Audio.shared.play(.best) }
    }
    func resetScores() {
        scores = [[], []]
        Self.scoreKeys.forEach(UserDefaults.standard.removeObject)
    }
}
