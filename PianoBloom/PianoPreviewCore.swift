import Foundation

/// A stale recorder must never deactivate a newer playback session.
final class AudioSessionOwnership {
    static let shared = AudioSessionOwnership()
    private let lock = NSLock()
    private var owner: UUID?
    private var capturing = false
    var hasCapture: Bool { lock.lock(); defer { lock.unlock() }; return owner != nil && capturing }
    func claim(capturing: Bool = false) -> UUID {
        lock.lock(); defer { lock.unlock() }
        let token = UUID(); owner = token; self.capturing = capturing; return token
    }
    func release(_ token: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard owner == token else { return false }
        owner = nil; capturing = false; return true
    }
}

enum PianoPreviewError: LocalizedError {
    case noNotes, invalidTempo, playback
    var errorDescription: String? {
        switch self {
        case .noNotes: return "当前范围所选声部没有可试听的音符，请切换左手、右手或双手。"
        case .invalidTempo: return "试听速度无效，请重新设置速度。"
        case .playback: return "试听未能开始播放，请重新点击试听并检查音频输出。"
        }
    }
}

enum PianoPreviewAudio {
    static func wav(score: PianoScore, hands: PracticeHands, bpm: Double) throws -> Data {
        guard bpm.isFinite, (20...160).contains(bpm) else { throw PianoPreviewError.invalidTempo }
        guard score.events.contains(where: { !$0.pitches(hands).isEmpty }) else { throw PianoPreviewError.noNotes }
        let rate = 22050.0, beatSeconds = 60 / bpm
        let seconds = min(40, score.length * beatSeconds + 0.4)
        guard seconds.isFinite, seconds > 0 else { throw PianoPreviewError.noNotes }
        var samples = [Double](repeating: 0, count: Int(seconds * rate))
        for event in score.events {
            let start = Int(event.beat * beatSeconds * rate)
            guard start >= 0, start < samples.count else { continue }
            let duration = min(event.duration * beatSeconds * 0.9 + 0.1, seconds - Double(start) / rate)
            guard duration > 0 else { continue }
            for note in event.pitches(hands) {
                let frequency = Music.frequency(note)
                for i in 0..<Int(duration * rate) where start + i < samples.count {
                    let t = Double(i) / rate
                    let envelope = min(1, t / 0.008) * exp(-t * 3.5) * min(1, max(0, duration - t) / 0.04)
                    let tone = sin(2 * .pi * frequency * t) + 0.25 * sin(4 * .pi * frequency * t) + 0.10 * sin(6 * .pi * frequency * t)
                    samples[start + i] += tone * envelope * 0.28
                }
            }
        }
        let peak = samples.map { abs($0) }.max() ?? 0
        guard peak > 0.00001 else { throw PianoPreviewError.noNotes }
        let gain = peak > 0.9 ? 0.9 / peak : 1
        var data = Data()
        func word(_ value: UInt32, _ count: Int) { for i in 0..<count { data.append(UInt8((value >> (8 * i)) & 255)) } }
        let bytes = UInt32(samples.count * 2)
        data.append(Data("RIFF".utf8)); word(36 + bytes, 4)
        data.append(Data("WAVEfmt ".utf8)); word(16, 4); word(1, 2); word(1, 2)
        word(UInt32(rate), 4); word(UInt32(rate * 2), 4); word(2, 2); word(16, 2)
        data.append(Data("data".utf8)); word(bytes, 4)
        for value in samples { word(UInt32(UInt16(bitPattern: Int16(max(-1, min(1, value * gain)) * 30000))), 2) }
        return data
    }
}
