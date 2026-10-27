import AppKit
import AVFoundation

/// Every sound is synthesized at launch: no audio files, and each pack is just a recipe.
final class Sounds {
    static let shared = Sounds()

    enum Cue: CaseIterable {
        case attention, success, error, timer, pop, open
        /// File name (without extension) that replaces this cue when dropped in the sounds folder.
        var fileName: String {
            switch self {
            case .attention: "needs-you"
            case .success: "done"
            case .error: "oops"
            case .timer: "timer"
            case .pop: "drop"
            case .open: "open"
            }
        }
    }

    /// ~/Library/Application Support/Wisp/Sounds: drop done.wav, needs-you.mp3… to use your own.
    static var folder: URL {
        let dir = Paths.support.appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var custom: [Cue: NSSound] = [:]

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var started = false

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(_ cue: Cue, pack: SoundPack? = nil) {
        let c = Prefs.shared.c
        let pack = pack ?? c.soundPack
        guard pack != .off else { return }
        if let own = customSound(cue) {
            own.stop()
            own.volume = Float(c.volume)
            own.play()
            return
        }
        let key = "\(pack.rawValue).\(cue)"
        let buffer = cache[key] ?? render(cue, pack)
        cache[key] = buffer
        if !started {
            do { try engine.start(); started = true } catch { return }
        }
        engine.mainMixerNode.outputVolume = Float(c.volume)
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    private func customSound(_ cue: Cue) -> NSSound? {
        if let s = custom[cue] { return s }
        for ext in ["wav", "mp3", "aiff", "m4a", "caf"] {
            let url = Self.folder.appendingPathComponent("\(cue.fileName).\(ext)")
            if FileManager.default.fileExists(atPath: url.path), let s = NSSound(contentsOf: url, byReference: true) {
                custom[cue] = s
                return s
            }
        }
        return nil
    }

    /// Forget cached custom files, after the person changes the folder.
    func reloadCustom() { custom.removeAll() }

    // MARK: - Synthesis

    private struct Note { var freq: Double; var start: Double; var length: Double; var gain: Double = 1 }

    private enum Wave { case sine, bell, square, triangle, wood, bubble }

    private func notes(_ cue: Cue) -> [Note] {
        switch cue {
        case .attention: [Note(freq: 880, start: 0, length: 0.18), Note(freq: 1174.7, start: 0.14, length: 0.3)]
        case .success: [Note(freq: 784, start: 0, length: 0.2), Note(freq: 987.8, start: 0.09, length: 0.22), Note(freq: 1318.5, start: 0.18, length: 0.45)]
        case .error: [Note(freq: 392, start: 0, length: 0.2), Note(freq: 311.1, start: 0.13, length: 0.35)]
        case .timer: [Note(freq: 1046.5, start: 0, length: 0.25), Note(freq: 1046.5, start: 0.3, length: 0.25), Note(freq: 1568, start: 0.6, length: 0.6)]
        case .pop: [Note(freq: 660, start: 0, length: 0.12, gain: 0.8)]
        case .open: [Note(freq: 1318.5, start: 0, length: 0.08, gain: 0.35)]
        }
    }

    private func render(_ cue: Cue, _ pack: SoundPack) -> AVAudioPCMBuffer {
        let wave: Wave
        var transpose = 1.0
        switch pack {
        case .chime: wave = .bell
        case .glass: wave = .sine; transpose = 2
        case .wood: wave = .wood; transpose = 0.5
        case .retro: wave = .square
        case .bubble: wave = .bubble
        case .off: wave = .sine
        }
        let list = notes(cue)
        let total = (list.map { $0.start + $0.length }.max() ?? 0.3) + (pack == .glass ? 0.6 : 0.15)
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(total * sr)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]
        for i in 0..<Int(frames) { out[i] = 0 }

        for note in list {
            let f = note.freq * transpose
            let first = Int(note.start * sr)
            let ring = pack == .glass ? note.length + 0.6 : note.length
            let count = min(Int(ring * sr), Int(frames) - first)
            guard count > 0 else { continue }
            var phase = 0.0
            for n in 0..<count {
                let t = Double(n) / sr
                let attack = min(1, t / 0.006)
                var env: Double
                var freq = f
                switch wave {
                case .wood: env = exp(-t * 38)
                case .bubble: env = sin(min(1, t / ring) * .pi); freq = f * (0.7 + 0.6 * t / ring)
                case .square: env = t < note.length * 0.85 ? 1 : max(0, 1 - (t - note.length * 0.85) / (note.length * 0.15))
                default: env = exp(-t * (pack == .glass ? 4.5 : 7))
                }
                phase += 2 * .pi * freq / sr
                var s: Double
                switch wave {
                case .sine, .bubble: s = sin(phase)
                case .bell: s = sin(phase) + 0.35 * sin(phase * 2.01) + 0.15 * sin(phase * 3.98)
                case .square: s = sin(phase) >= 0 ? 0.35 : -0.35
                case .triangle: s = asin(sin(phase)) * 2 / .pi
                case .wood: s = sin(phase) + 0.4 * sin(phase * 2.7) + 0.2 * Double.random(in: -1...1) * exp(-t * 90)
                }
                out[first + n] += Float(s * env * attack * note.gain * 0.28)
            }
        }
        return buffer
    }
}
