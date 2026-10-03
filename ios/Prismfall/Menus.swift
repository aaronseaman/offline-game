// Menu, pause, game over, settings, guide and scores, layered over the scene.

import SwiftUI

private extension Font {
    static func display(_ size: CGFloat, black: Bool = false) -> Font {
        .custom(black ? "Unbounded-Black" : "Unbounded-Bold", fixedSize: size)
    }
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

private extension Color {
    static let ink = Theme.ink.color
    static let violet = Theme.violet.color
    static let cream = Theme.cream.color
    static let amber = Theme.amber.color
    static let faint = Theme.ink.color.opacity(0.07)
    static let muted = Theme.ink.color.opacity(0.62)
}

struct Screens: View {
    let model: AppModel

    var body: some View {
        ZStack {
            switch model.screen {
            case .play:
                EmptyView()
            case .menu:
                MenuScreen(model: model).transition(.opacity)
            case .pause:
                card { PauseCard(model: model) }
            case .over:
                card { OverCard(model: model) }
            case .settings:
                card { SettingsCard(model: model) }
            case .help:
                card { HelpCard(model: model) }
            case .scores:
                card { ScoresCard(model: model) }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: model.screen)
    }

    /// A cream card over a blurred, dimmed scene.
    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        ZStack {
            Rectangle().fill(.thinMaterial).ignoresSafeArea()
            VStack(spacing: 0, content: content)
                .padding(EdgeInsets(top: 26, leading: 22, bottom: 22, trailing: 22))
                .frame(maxWidth: 380)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
                    shape.fill(Color.amber).offset(y: 6)
                    shape.fill(LinearGradient(colors: [.white, .cream], startPoint: .top, endPoint: .bottom))
                    shape.strokeBorder(.white, lineWidth: 2)
                }
                .shadow(color: Theme.ink.color.opacity(0.35), radius: 26, y: 14)
                .padding(18)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .transition(.opacity)
    }
}

// MARK: Pieces

/// Raised button that presses down onto its lip.
private struct Chunky: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind = Kind.secondary
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 17, style: .continuous)
        let primary = kind == .primary
        configuration.label
            .font(.ui(17, .bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(primary ? .white : destructive ? Theme.alert.darker(0.15).color : kind == .quiet ? Color.muted : .ink)
            .frame(maxWidth: .infinity, minHeight: kind == .quiet ? 40 : 52)
            .background {
                if kind != .quiet {
                    shape.fill(LinearGradient(colors: primary ? [RGB(0x9A5CFF).color, RGB(0x6A27E0).color] : [.white, RGB(0xF1E8FF).color],
                                              startPoint: .top, endPoint: .bottom))
                    shape.strokeBorder(.white.opacity(primary ? 0.35 : 1), lineWidth: 1.5)
                }
            }
            .offset(y: configuration.isPressed && kind != .quiet ? 4 : 0)
            .background {
                if kind != .quiet { shape.fill(primary ? RGB(0x43149C).color : RGB(0xC9B4F2).color).offset(y: 4) }
            }
            .padding(.bottom, kind == .quiet ? 0 : 4)
            .opacity(configuration.isPressed && kind == .quiet ? 0.5 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct Press<Label: View>: View {
    var kind = Chunky.Kind.secondary
    var destructive = false
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button {
            Audio.shared.play(.ui)
            action()
        } label: {
            label
        }
        .buttonStyle(Chunky(kind: kind, destructive: destructive))
    }
}

private extension Press where Label == Text {
    init(_ title: String, _ kind: Chunky.Kind = .secondary, destructive: Bool = false, action: @escaping () -> Void) {
        self.init(kind: kind, destructive: destructive, action: action) { Text(title) }
    }
}

/// A button that asks for a second tap before doing something that cannot be undone.
private struct Confirm: View {
    let title: String
    let prompt: String
    var kind = Chunky.Kind.secondary
    var destructive = false
    let action: () -> Void
    @State private var armed = false

    var body: some View {
        Press(armed ? prompt : title, kind, destructive: destructive) {
            if armed {
                action()
            } else {
                armed = true
            }
        }
        .task(id: armed) {
            guard armed else { return }
            try? await Task.sleep(for: .seconds(3))
            armed = false
        }
    }
}

private struct BlockView: View {
    var color: Int
    var special = Special.plain
    var size: CGFloat = 30
    var symbol = false

    var body: some View {
        Image(decorative: Art.blockImage(color, special, symbol: symbol), scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// Classic or calm, with a pill that slides between them.
private struct ModePicker: View {
    @Binding var calm: Bool
    @Namespace private var pill

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 0) {
                ForEach([false, true], id: \.self) { mode in
                    Button {
                        guard calm != mode else { return }
                        Audio.shared.play(.select)
                        Haptics.tap()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { calm = mode }
                    } label: {
                        Label(mode ? "Calm" : "Classic", systemImage: mode ? "leaf.fill" : "bolt.fill")
                            .font(.ui(15, .bold))
                            .foregroundStyle(calm != mode ? Color.muted : mode ? .ink : .white)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background {
                                if calm == mode {
                                    Capsule()
                                        .fill(mode ? LinearGradient(colors: [RGB(0xFFD84A).color, RGB(0xFF9F1C).color], startPoint: .top, endPoint: .bottom)
                                                   : LinearGradient(colors: [RGB(0x9A5CFF).color, RGB(0x6A27E0).color], startPoint: .top, endPoint: .bottom))
                                        .matchedGeometryEffect(id: "pill", in: pill)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.faint, in: Capsule())
            Text(calm ? "A steady pace and all the time you need to swap." : "Faster drops and trickier shapes every level.")
                .font(.ui(13, .medium))
                .foregroundStyle(Color.muted)
        }
    }
}

private struct Title: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.display(22)).foregroundStyle(Color.ink).padding(.bottom, 14)
    }
}

private func eyebrow(_ text: String) -> some View {
    Text(text.uppercased()).font(.ui(12, .heavy)).kerning(1.4).foregroundStyle(Color.muted).padding(.bottom, 6)
}

// MARK: Menu

private struct MenuScreen: View {
    @Bindable var model: AppModel
    @State private var arrived = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            logo
            Text("Drop shapes. Match colors.\nChain the fall.")
                .font(.ui(16, .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.92))
                .padding(.top, 14)
            Spacer(minLength: 16)
            VStack(spacing: 12) {
                ModePicker(calm: $model.calm).padding(.bottom, 4)
                if let saved = model.saved {
                    Press(kind: .primary, action: { model.start(resume: true) }) {
                        VStack(spacing: 2) {
                            Text("Continue")
                            Text("\(saved.score.formatted()) pts · Lv \(saved.level)\(saved.calm ? " · Calm" : "")")
                                .font(.ui(12, .semibold))
                                .opacity(0.85)
                        }
                    }
                }
                Press(model.saved == nil ? "Play" : "New game", model.saved == nil ? .primary : .secondary) { model.play() }
                HStack(spacing: 12) {
                    Press("How to play") { model.open(.help) }
                    Press("Scores") { model.open(.scores) }
                }
                Press("Settings", .quiet) { model.open(.settings) }
            }
            .padding(EdgeInsets(top: 18, leading: 18, bottom: 10, trailing: 18))
            .frame(maxWidth: 360)
            .background {
                let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
                shape.fill(Color.amber).offset(y: 6)
                shape.fill(LinearGradient(colors: [.white, .cream], startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(.white, lineWidth: 2)
            }
            .shadow(color: RGB(0x16063D).color.opacity(0.45), radius: 22, y: 12)
            .offset(y: arrived ? 0 : 40)
            .opacity(arrived ? 1 : 0)
            Text(model.best.map { "Best \($0.formatted())" } ?? " ")
                .font(.ui(15, .bold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.88))
                .padding(.top, 18)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 22)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { arrived = true }
        }
    }

    /// The name, letter by letter, over a row of the six blocks.
    private var logo: some View {
        VStack(spacing: 2) {
            word("PRISM", start: 0, fill: LinearGradient(colors: [.white, RGB(0xFFF1CC).color], startPoint: .top, endPoint: .bottom))
            word("FALL", start: 5, fill: LinearGradient(colors: [RGB(0xFFE879).color, RGB(0xFFB21E).color], startPoint: .top, endPoint: .bottom))
            HStack(spacing: 5) {
                ForEach(0..<6) { k in
                    BlockView(color: k, size: 26)
                        .scaleEffect(arrived ? 1 : 0.01)
                        .animation(.spring(response: 0.36, dampingFraction: 0.55).delay(0.22 + Double(k) * 0.035), value: arrived)
                }
            }
            .padding(.top, 12)
        }
        .rotationEffect(.degrees(-3))
    }

    private func word(_ text: String, start: Int, fill: LinearGradient) -> some View {
        HStack(spacing: -1) {
            ForEach(Array(text.enumerated()), id: \.offset) { k, letter in
                Text(String(letter))
                    .font(.display(58, black: true))
                    .foregroundStyle(fill)
                    .shadow(color: Theme.ink.color.opacity(0.75), radius: 0, y: 3)
                    .shadow(color: .ink, radius: 0, y: 3)
                    .offset(y: arrived ? 0 : -46)
                    .opacity(arrived ? 1 : 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(Double(start + k) * 0.028), value: arrived)
            }
        }
        .minimumScaleFactor(0.6)
    }
}

// MARK: Pause and game over

private struct PauseCard: View {
    let model: AppModel

    var body: some View {
        let game = model.scene.game
        eyebrow("Paused")
        Text((game?.score ?? 0).formatted())
            .font(.display(40, black: true))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(Color.ink)
        Text("Level \(game?.level ?? 1)\(game?.calm == true ? " · Calm" : "")")
            .font(.ui(14))
            .foregroundStyle(Color.muted)
            .padding(.bottom, 18)
        VStack(spacing: 10) {
            Press("Resume", .primary) { model.resume() }
            Confirm(title: "Restart", prompt: "Tap again to restart") { model.start(resume: false) }
            HStack(spacing: 10) {
                Press("How to play") { model.open(.help) }
                Press("Settings") { model.open(.settings) }
            }
            Press("Save and quit", .quiet) { model.quit() }
        }
    }
}

private struct OverCard: View {
    let model: AppModel
    @State private var celebrate = false

    var body: some View {
        if let summary = model.summary {
            eyebrow("The well overflowed")
            Text(summary.isBest ? "New best!" : "Game over")
                .font(.display(22))
                .foregroundStyle(summary.isBest ? Theme.blocks[5].color : Color.ink)
                .scaleEffect(celebrate ? 1.12 : 1)
            Text(summary.score.formatted())
                .font(.display(42, black: true))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(Color.ink)
                .padding(.top, 2)
            Text(summary.isBest
                 ? (summary.previousBest > 0 ? "Previous best \(summary.previousBest.formatted())" : "First score on the board")
                 : "Best \(summary.previousBest.formatted())")
                .font(.ui(14))
                .monospacedDigit()
                .foregroundStyle(Color.muted)
                .padding(.bottom, 16)
            SwiftUI.Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    stat("Level", "\(summary.level)")
                    stat("Blocks", summary.cleared.formatted())
                    stat("Best chain", summary.stats.maxChain > 0 ? "×\(summary.stats.maxChain)" : "–")
                }
                GridRow {
                    stat("Specials", "\(summary.stats.specials)")
                    stat("Shapes", "\(summary.stats.pieces)")
                    stat("Time", Duration.seconds(summary.stats.time.rounded()).formatted(.time(pattern: .minuteSecond)))
                }
            }
            .padding(.bottom, 18)
            VStack(spacing: 10) {
                Press("Play again", .primary) { model.start(resume: false) }
                Press("Main menu", .quiet) { model.quit() }
            }
            .onAppear {
                guard summary.isBest else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.35).repeatCount(3, autoreverses: true).delay(0.25)) { celebrate = true }
            }
        }
    }

    private func stat(_ name: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(name.uppercased()).font(.ui(10.5, .heavy)).kerning(0.6).foregroundStyle(Color.muted)
            Text(value).font(.display(16)).monospacedDigit().foregroundStyle(Color.ink)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.faint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: Settings and scores

private struct SettingsCard: View {
    @Bindable var model: AppModel

    var body: some View {
        Title("Settings")
        VStack(spacing: 0) {
            row("Sound effects", nil, $model.settings.sound)
            row("Haptics", "Taps and thumps as you play", $model.settings.haptics)
            row("Ghost piece", "Shows where the shape will land", $model.settings.ghost)
            row("Color symbols", "A mark on each color, for color-blind play", $model.settings.symbols)
            row("Untimed swaps", "Classic waits until you swap or skip", $model.settings.relaxed, last: true)
        }
        .padding(.bottom, 16)
        VStack(spacing: 8) {
            Press("Done", .primary) { model.close() }
            Confirm(title: "Reset high scores", prompt: "Tap again to clear scores", kind: .quiet, destructive: true) { model.resetScores() }
        }
    }

    private func row(_ name: String, _ detail: String?, _ value: Binding<Bool>, last: Bool = false) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.ui(16)).foregroundStyle(Color.ink)
                if let detail { Text(detail).font(.ui(12.5, .medium)).foregroundStyle(Color.muted) }
            }
        }
        .tint(.violet)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(Color.faint).frame(height: 1) }
        }
    }
}

private struct ScoresCard: View {
    @Bindable var model: AppModel

    var body: some View {
        Title("High scores")
        ModePicker(calm: $model.calm).padding(.bottom, 10)
        let scores = model.scores[model.calm ? 1 : 0]
        VStack(spacing: 0) {
            if scores.isEmpty {
                Text("No games yet. Your top ten will appear here.")
                    .font(.ui(15, .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.muted)
                    .padding(.vertical, 22)
            }
            ForEach(Array(scores.enumerated()), id: \.element.id) { rank, entry in
                HStack(spacing: 10) {
                    Text("\(rank + 1)").font(.ui(14, .heavy)).foregroundStyle(Color.muted).frame(width: 22, alignment: .leading)
                    Text(entry.score.formatted())
                        .font(.display(16))
                        .foregroundStyle(rank == 0 ? Theme.blocks[5].color : Color.ink)
                    Spacer()
                    Text("Lv \(entry.level)\(entry.chain > 1 ? " · ×\(entry.chain)" : "") · \(entry.date.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.ui(12, .medium))
                        .foregroundStyle(Color.muted)
                }
                .monospacedDigit()
                .padding(.vertical, 8)
                .overlay(alignment: .top) {
                    if rank > 0 { Rectangle().fill(Color.faint).frame(height: 1) }
                }
            }
        }
        .padding(.bottom, 14)
        Press("Done", .primary) { model.close() }
    }
}

// MARK: Guide

private struct HelpCard: View {
    let model: AppModel
    @State private var page = 0

    var body: some View {
        HStack {
            Text("How to play").font(.display(18)).foregroundStyle(Color.ink)
            Spacer()
            Button {
                Audio.shared.play(.ui)
                model.close()
            } label: {
                Image(systemName: "xmark").font(.ui(14, .heavy)).foregroundStyle(Color.ink)
                    .frame(width: 36, height: 36).background(Color.faint, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        VStack(alignment: .leading, spacing: 0) {
            switch page {
            case 0:
                art { ControlsArt() }
                heading("Steer the shape")
                point("**Drag** left or right to move.")
                point("**Tap** the right half to turn clockwise, the left half to turn back.")
                point("**Drag down** to soft drop. **Flick down** to drop at once.")
                point("**Flick up** or tap **HOLD** to keep a shape for later.")
            case 1:
                art { MatchArt() }
                heading("Match colors, not rows")
                point("Line up **3 or more** blocks of one color in a row or column to clear them. Full rows do nothing.")
                point("Blocks above fall straight down and can match again. Each cascade step multiplies your points.")
                point("Classic speeds up every level and adds a sixth color at level 5. Calm keeps one steady pace.")
            case 2:
                art { SwapArt() }
                heading("Swap to finish a match")
                point("When a shape lands and you have a **swap** banked, glowing blocks show every swap that makes a match.")
                point("Tap a block, then a neighbor, or drag it across. Tap empty space to skip.")
                point("Landings and cleared blocks fill the **gold meter**. A full meter is one swap; you can bank 3.")
            default:
                heading("Special blocks").padding(.top, 2)
                special(.lineH, 3, "**4 in a line → Line blaster.** Clears its whole row or column, along its arrows.")
                special(.bomb, 0, "**L or T shape → Bomb.** Clears a 3×3 area.")
                special(.prism, 4, "**5 in a line → Prism.** Clears every block of its color. Swap it with any block to take that color instead.")
                Text("Swap two specials into each other for a bigger blast: crosses, 5×5 explosions, or whole colors at once.")
                    .font(.ui(12.5, .medium))
                    .foregroundStyle(Color.muted)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 318, alignment: .topLeading)
        .id(page)
        .transition(.opacity)
        HStack(spacing: 12) {
            Press("Back") { withAnimation(.easeOut(duration: 0.18)) { page -= 1 } }
                .disabled(page == 0)
                .opacity(page == 0 ? 0.35 : 1)
            HStack(spacing: 6) {
                ForEach(0..<4) { k in
                    Circle().fill(k == page ? Color.violet : Color.ink.opacity(0.18)).frame(width: 7, height: 7)
                }
            }
            Press(page == 3 ? "Done" : "Next", .primary) {
                if page == 3 { model.close() } else { withAnimation(.easeOut(duration: 0.18)) { page += 1 } }
            }
        }
        .padding(.top, 12)
    }

    private func art(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 116)
            .background(LinearGradient(colors: [RGB(0x1D0F3C).color, RGB(0x2F1759).color], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, 12)
    }
    private func heading(_ text: String) -> some View {
        Text(text).font(.display(16)).foregroundStyle(Color.ink).padding(.top, 14).padding(.bottom, 6)
    }
    private func point(_ markdown: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Color.violet).frame(width: 5, height: 5).offset(y: -3)
            Text(markdown).font(.ui(14.5, .medium)).foregroundStyle(Color.ink.opacity(0.85))
        }
        .padding(.top, 6)
    }
    private func special(_ kind: Special, _ color: Int, _ markdown: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            BlockView(color: color, special: kind, size: 38, symbol: model.settings.symbols)
            Text(markdown).font(.ui(14.5, .medium)).foregroundStyle(Color.ink.opacity(0.85))
        }
        .padding(.top, 10)
    }
}

private let hint = Color(red: 0.86, green: 0.82, blue: 1)

private struct ControlsArt: View {
    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 16) {
                Image(systemName: "arrow.left")
                SwiftUI.Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        Color.clear.frame(width: 28, height: 28)
                        BlockView(color: 3, size: 28)
                        Color.clear.frame(width: 28, height: 28)
                    }
                    GridRow {
                        BlockView(color: 0, size: 28)
                        BlockView(color: 0, size: 28)
                        BlockView(color: 3, size: 28)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.clockwise").offset(x: 6, y: -4)
                }
                Image(systemName: "arrow.right")
            }
            Image(systemName: "arrow.down")
        }
        .font(.ui(17, .heavy))
        .foregroundStyle(hint)
    }
}

private struct MatchArt: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                BlockView(color: 1, size: 28).overlay(alignment: .top) { arrow }
                BlockView(color: 4, size: 28)
                BlockView(color: 1, size: 28).overlay(alignment: .top) { arrow }
            }
            .opacity(0.85)
            .padding(.top, 16)
            HStack(spacing: 0) {
                BlockView(color: 3, size: 28)
                HStack(spacing: 0) {
                    ForEach(0..<3) { _ in BlockView(color: 0, size: 28) }
                }
                .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white, lineWidth: 2).padding(-2) }
                BlockView(color: 2, size: 28)
            }
        }
    }
    private var arrow: some View {
        Image(systemName: "arrow.down").font(.ui(13, .heavy)).foregroundStyle(hint).offset(y: -17)
    }
}

private struct SwapArt: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 0) {
                BlockView(color: 2, size: 28)
                BlockView(color: 2, size: 28)
                VStack(spacing: 0) {
                    BlockView(color: 2, size: 28).overlay { outline(Theme.gold.color) }
                    BlockView(color: 4, size: 28).overlay { outline(.white) }
                }
                Image(systemName: "arrow.up.arrow.down").font(.ui(16, .heavy)).foregroundStyle(Theme.gold.color)
                    .padding(.leading, 10).padding(.bottom, 20)
            }
            Text("Swap these two for a row of three").font(.ui(12, .semibold)).foregroundStyle(hint)
        }
    }
    private func outline(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(color, lineWidth: 2)
    }
}
