// Sound effects, synthesized once at launch so the app ships no audio files, and haptics.

import AVFoundation
import UIKit

nonisolated enum SFX: Int, CaseIterable, Sendable {
    case move, rotate, land, bump, lock, hardDrop, hold, special, line, bomb, prism, swap, fail, token, level, over
    case swapOpen, select, ui, start, best, combo, pause, resume, hurry, danger
    case clear1, clear2, clear3, clear4, clear5, clear6, clear7, clear8

    /// The clear chime climbs the scale with each cascade step.
    static func clear(chain: Int) -> SFX { SFX(rawValue: clear1.rawValue + min(max(chain, 1), 8) - 1)! }
}

/// A tiny offline synth: enveloped oscillators and filtered noise mixed into one buffer.
nonisolated struct Synth {
    enum Wave { case sine, triangle, square, saw }
    enum Filter { case lowpass, highpass, bandpass }

    static let rate = 44_100.0
    private static let silence = 0.0001
    /// C major pentatonic from C5.
    private static let scale = [523.25, 587.33, 659.25, 783.99, 880, 1046.5, 1174.66, 1318.51, 1567.98, 1760, 2093, 2349.3, 2637]

    private var samples: [Float] = []

    private mutating func reserve(_ end: Int) {
        if samples.count < end { samples.append(contentsOf: repeatElement(0, count: end - samples.count)) }
    }

    mutating func tone(_ freq: Double, _ dur: Double, _ wave: Wave = .sine, vol: Double = 0.15, to: Double? = nil, delay: Double = 0) {
        let start = Int(delay * Self.rate)
        let count = Int(dur * Self.rate)
        let rise = Int(0.006 * Self.rate)
        reserve(start + count)
        let glide = pow((to ?? freq) / freq, 1 / Double(count))
        let up = pow(vol / Self.silence, 1 / Double(rise))
        let down = pow(Self.silence / vol, 1 / Double(count - rise))
        var f = freq
        var gain = Self.silence
        var phase = 0.0
        for i in 0..<count {
            let x = phase - phase.rounded(.down)
            let osc: Double
            switch wave {
            case .sine: osc = sin(2 * .pi * x)
            case .triangle: osc = 4 * abs(x - 0.5) - 1
            case .square: osc = x < 0.5 ? 1 : -1
            case .saw: osc = 2 * x - 1
            }
            samples[start + i] += Float(osc * gain)
            phase += f / Self.rate
            f *= glide
            gain *= i < rise ? up : down
        }
    }

    mutating func noise(_ dur: Double, vol: Double = 0.1, _ filter: Filter = .lowpass, freq: Double = 1000, to: Double? = nil) {
        let count = Int(dur * Self.rate)
        let rise = Int(0.01 * Self.rate)
        reserve(count)
        let glide = pow((to ?? freq) / freq, 1 / Double(count))
        let up = pow(vol / Self.silence, 1 / Double(rise))
        let down = pow(Self.silence / vol, 1 / Double(count - rise))
        var f = freq
        var gain = Self.silence
        var seed: UInt32 = 0x9E37_79B9
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in 0..<count {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let x = Double(seed >> 8) / 8_388_608 - 1
            // biquad with a gliding cutoff
            let w = 2 * .pi * min(f, Self.rate * 0.45) / Self.rate
            let alpha = sin(w) / 2
            let c = cos(w)
            let b0, b1, b2: Double
            switch filter {
            case .lowpass: (b0, b1, b2) = ((1 - c) / 2, 1 - c, (1 - c) / 2)
            case .highpass: (b0, b1, b2) = ((1 + c) / 2, -(1 + c), (1 + c) / 2)
            case .bandpass: (b0, b1, b2) = (alpha, 0, -alpha)
            }
            let y = (b0 * x + b1 * x1 + b2 * x2 + 2 * c * y1 - (1 - alpha) * y2) / (1 + alpha)
            (x2, x1, y2, y1) = (x1, x, y1, y)
            samples[i] += Float(y * gain)
            f *= glide
            gain *= i < rise ? up : down
        }
    }

    /// A run of scale notes, `gap` seconds apart.
    private mutating func notes(_ steps: [Int], _ dur: Double, _ wave: Wave = .triangle, vol: Double, gap: Double, delay: Double = 0, octave: Double = 1) {
        for (j, step) in steps.enumerated() {
            tone(Self.scale[step] * octave, dur, wave, vol: vol, delay: delay + Double(j) * gap)
        }
    }

    static func render(_ sfx: SFX) -> [Float] {
        var s = Synth()
        switch sfx {
        case .move:
            s.tone(950, 0.025, .square, vol: 0.018)
        case .rotate:
            s.tone(600, 0.05, .triangle, vol: 0.06, to: 900)
        case .land:
            s.tone(200, 0.05, vol: 0.05)
        case .bump:
            s.tone(150, 0.045, .triangle, vol: 0.035)
        case .lock:
            s.tone(160, 0.09, vol: 0.12, to: 90)
            s.noise(0.05, vol: 0.04, freq: 1600)
        case .hardDrop:
            s.tone(130, 0.18, vol: 0.22, to: 48)
            s.noise(0.14, vol: 0.1, freq: 900, to: 160)
        case .hold:
            s.noise(0.2, vol: 0.07, .bandpass, freq: 500, to: 2600)
        case .special:
            s.notes([2, 4, 6, 9], 0.16, .sine, vol: 0.06, gap: 0.035, delay: 0.12)
        case .line:
            s.tone(1500, 0.3, .saw, vol: 0.045, to: 160)
            s.noise(0.26, vol: 0.05, .highpass, freq: 3200, to: 500)
        case .bomb:
            s.tone(95, 0.5, vol: 0.28, to: 32)
            s.noise(0.45, vol: 0.18, freq: 1400, to: 90)
        case .prism:
            s.notes(Array(4...10), 0.4, .sine, vol: 0.04, gap: 0.028)
            s.noise(0.35, vol: 0.035, .highpass, freq: 5200)
        case .swap:
            s.tone(520, 0.07, .triangle, vol: 0.07, to: 780)
            s.tone(780, 0.07, .triangle, vol: 0.05, to: 520, delay: 0.06)
        case .fail:
            s.tone(150, 0.1, .square, vol: 0.045)
            s.tone(115, 0.13, .square, vol: 0.045, delay: 0.09)
        case .token:
            s.tone(1318.5, 0.25, vol: 0.08)
            s.tone(1975.5, 0.35, vol: 0.06, delay: 0.08)
        case .level:
            s.notes([0, 2, 4, 5, 7], 0.22, vol: 0.09, gap: 0.07)
        case .over:
            s.notes([7, 5, 4, 2, 0], 0.4, vol: 0.1, gap: 0.15, octave: 0.5)
        case .swapOpen:
            s.tone(1046.5, 0.09, vol: 0.035)
        case .select:
            s.tone(1250, 0.03, .triangle, vol: 0.04)
        case .ui:
            s.tone(720, 0.04, .triangle, vol: 0.04)
        case .start:
            s.notes([0, 2, 4, 7], 0.2, vol: 0.07, gap: 0.06)
            s.noise(0.3, vol: 0.02, .bandpass, freq: 800, to: 4000)
        case .best:
            s.notes([2, 4, 5, 7, 9], 0.32, vol: 0.085, gap: 0.085)
            s.notes([7, 9, 12], 0.6, .sine, vol: 0.04, gap: 0, delay: 0.43)
            s.noise(0.5, vol: 0.02, .highpass, freq: 6000)
        case .combo:
            s.tone(180, 0.32, .saw, vol: 0.04, to: 1400)
            s.notes([4, 7, 9], 0.36, vol: 0.07, gap: 0, delay: 0.28)
            s.noise(0.3, vol: 0.05, .bandpass, freq: 400, to: 5000)
        case .pause:
            s.tone(660, 0.08, .triangle, vol: 0.05, to: 440)
        case .resume:
            s.tone(440, 0.08, .triangle, vol: 0.05, to: 660)
        case .hurry:
            s.tone(1568, 0.045, .triangle, vol: 0.045)
            s.tone(1568, 0.045, .triangle, vol: 0.045, delay: 0.11)
        case .danger:
            s.tone(196, 0.16, .triangle, vol: 0.09, to: 185)
            s.tone(185, 0.22, .triangle, vol: 0.09, to: 165, delay: 0.19)
        case .clear1, .clear2, .clear3, .clear4, .clear5, .clear6, .clear7, .clear8:
            let base = sfx.rawValue - SFX.clear1.rawValue
            s.notes([base, base + 2, base + 4], 0.24, vol: 0.1, gap: 0.045)
            s.tone(scale[base] * 2, 0.32, vol: 0.035, delay: 0.1)
        }
        // master gain with a soft ceiling
        return s.samples.map { tanh($0 * 1.8) }
    }
}

/// Plays the effects. All of it, including waking the audio hardware, happens on one
/// background queue, so sound never costs the main thread a frame or delays launch.
/// The hardware is put back to sleep after a few seconds of silence.
nonisolated final class Audio: @unchecked Sendable {
    static let shared = Audio()

    private let queue = DispatchQueue(label: "com.aaronseaman.prismfall.audio", qos: .userInitiated)
    // everything below is touched only on `queue`
    private var enabled = true
    private var engine: AVAudioEngine?
    private var voices: [AVAudioPlayerNode] = []
    private var buffers: [AVAudioPCMBuffer] = []
    private var next = 0
    private var sleep: DispatchWorkItem?

    private init() {
        queue.async { self.setUp() }
    }

    private func setUp() {
        // ambient: obeys the silent switch and mixes with the player's own music
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: Synth.rate, channels: 1)!
        for _ in 0..<6 {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
            voices.append(voice)
        }
        self.engine = engine
        buffers = SFX.allCases.map { sfx in
            let samples = Synth.render(sfx)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
            buffer.frameLength = buffer.frameCapacity
            samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
            return buffer
        }
    }

    func setEnabled(_ on: Bool) {
        queue.async { self.enabled = on }
    }
    func setVolume(_ volume: Float) {
        queue.async { self.engine?.mainMixerNode.outputVolume = volume }
    }
    func play(_ sfx: SFX) {
        let asked = CACurrentMediaTime()
        queue.async {
            // a sound that had to wait is dropped rather than played late
            guard self.enabled, let engine = self.engine, self.buffers.indices.contains(sfx.rawValue),
                  CACurrentMediaTime() - asked < 0.15 else { return }
            if !engine.isRunning {
                guard (try? engine.start()) != nil else { return }
            }
            let voice = self.voices[self.next]
            self.next = (self.next + 1) % self.voices.count
            voice.scheduleBuffer(self.buffers[sfx.rawValue], at: nil, options: .interrupts, completionHandler: nil)
            if !voice.isPlaying { voice.play() }
            // the longest effect lasts a second; after that the hardware has nothing to do
            self.sleep?.cancel()
            let sleep = DispatchWorkItem { engine.pause() }
            self.sleep = sleep
            self.queue.asyncAfter(deadline: .now() + 2.5, execute: sleep)
        }
    }
}

enum Haptics {
    static var enabled = true

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notice = UINotificationFeedbackGenerator()

    /// Rotations, selections and other small confirmations.
    static func tap() {
        if enabled { light.impactOccurred() }
    }
    /// Swaps and clears; stronger for longer chains.
    static func snap(_ intensity: CGFloat = 0.8) {
        if enabled { rigid.impactOccurred(intensity: intensity) }
    }
    /// A hard drop hitting the stack.
    static func thump() {
        if enabled { heavy.impactOccurred() }
    }
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        if enabled { notice.notificationOccurred(type) }
    }
}
