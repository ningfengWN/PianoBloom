import Foundation

enum Solfege {
    static let spoken = ["多", "多", "来", "来", "咪", "发", "发", "嗦", "嗦", "拉", "拉", "西"]
    static let names = ["Do", "♯Do", "Re", "♯Re", "Mi", "Fa", "♯Fa", "Sol", "♯Sol", "La", "♯La", "Si"]
    static func name(_ note: Int) -> String { names[(note % 12 + 12) % 12] }
    static func word(_ note: Int) -> String { spoken[(note % 12 + 12) % 12] }
}

struct SingingNote {
    let sourceIndex: Int
    let midi: Int
    let start: Double
    let duration: Double
}

struct SingingResult {
    let cents: Double?
    let timingError: Double?
    var pitchScore: Int { cents.map { Int(max(0, 100 * (1 - abs($0) / 120)).rounded()) } ?? 0 }
    var grade: NoteGrade {
        guard let cents else { return .missed }
        if abs(cents) > 70 { return .wrong }
        if let timingError, abs(timingError) > 0.10 { return timingError < 0 ? .early : .late }
        return .perfect
    }
}

struct SingingAssessment {
    let notes: [SingingNote]
    private(set) var results: [Int: SingingResult] = [:]
    private var pitches: [Int: [Double]] = [:]
    private var onsets: [Int: Double] = [:]
    private var lastOnset = -Double.infinity
    private(set) var position = 0
    var length: Double { notes.last.map { $0.start + $0.duration } ?? 0 }
    var pitchScore: Int { results.isEmpty ? 0 : results.values.reduce(0) { $0 + $1.pitchScore } / results.count }
    var timingCount: Int { results.values.filter { $0.timingError != nil }.count }
    var rhythmScore: Int? {
        let errors = results.values.compactMap(\.timingError)
        // Do not award a convincing rhythm score from a single isolated syllable.
        guard errors.count >= max(1, (results.count + 1) / 2) else { return nil }
        return Int((errors.reduce(0.0) { $0 + max(0, 100 * (1 - abs($1) / 0.35)) } / Double(errors.count)).rounded())
    }
    init(score: PianoScore, hand: PracticeHands, bpm: Double, octave: Int) {
        let seconds = 60 / min(120, max(30, bpm))
        notes = score.events.enumerated().compactMap { index, event in
            let voice = hand == .left ? event.left : event.right
            guard let note = voice.max() else { return nil } // Sing one melodic line, never a chord.
            return SingingNote(sourceIndex: index, midi: note + octave * 12,
                start: event.beat * seconds, duration: event.duration * seconds)
        }
    }
    mutating func accept(frequency: Double?, rms: Double, time: Double, onset: Double?) {
        guard time >= 0, rms >= 0.003 else { return }
        if let frequency, frequency.isFinite, (70...1400).contains(frequency),
           let index = notes.indices.first(where: { time >= notes[$0].start && time < notes[$0].start + notes[$0].duration }) {
            let note = notes[index]
            let phase = (time - note.start) / note.duration
            if (0.20...0.85).contains(phase), results[index] == nil {
                pitches[index, default: []].append(Music.pitch(frequency, reference: Music.standardC))
            }
        }
        if let onset, onset >= 0, onset - lastOnset > 0.09,
           let index = notes.indices.min(by: { abs(notes[$0].start - onset) < abs(notes[$1].start - onset) }),
           abs(notes[index].start - onset) <= min(0.35, notes[index].duration * 0.45) {
            lastOnset = onset
            let error = onset - notes[index].start
            if onsets[index] == nil || abs(error) < abs(onsets[index]!) { onsets[index] = error }
        }
    }
    mutating func tick(_ elapsed: Double) {
        while position < notes.count, elapsed >= notes[position].start + notes[position].duration + 0.10 {
            let values = (pitches[position] ?? []).sorted()
            let cents = values.count >= 3 ? (values[values.count / 2] - Double(notes[position].midi)) * 100 : nil
            results[position] = SingingResult(cents: cents, timingError: onsets[position])
            position += 1
        }
    }
}

struct SolfegeVoiceSample {
    let samples: [Float]
    let sampleRate: Double
}

/// Pitch-synchronous overlap-add: system speech supplies syllables and formants;
/// the voiced grain is repeated at the score's target period and stretched to its duration.
enum SolfegeVoiceRenderer {
    static func render(_ source: SolfegeVoiceSample, midi: Int, duration: Double, outputRate: Double = 16000) -> [Float]? {
        guard duration > 0, duration <= 600, (0...127).contains(midi), source.sampleRate > 0, source.sampleRate.isFinite, !source.samples.isEmpty else { return nil }
        let input = source.samples
        let peak = input.map { abs($0) }.max() ?? 0
        guard peak > 0.001, let lo = input.firstIndex(where: { abs($0) > peak * 0.025 }),
              let hi = input.lastIndex(where: { abs($0) > peak * 0.025 }), hi - lo > 1024 else { return nil }
        let trimmed = Array(input[lo...hi])
        var candidates: [(Int, Double, Double)] = []
        let size = min(2048, trimmed.count - 2)
        for center in stride(from: max(size / 2, trimmed.count / 3), to: trimmed.count - size / 2, by: max(1, size / 4)) {
            let block = Array(trimmed[(center - size / 2)..<(center + size / 2)])
            let frame = PitchDetector.analyze(block, sampleRate: source.sampleRate, time: 0)
            if let f = frame.frequency, (90...650).contains(f) { candidates.append((center, f, frame.rms)) }
        }
        guard let best = candidates.max(by: { $0.2 < $1.2 }) else { return nil }
        let period = source.sampleRate / best.1
        let radius = Int(ceil(period))
        let searchLo = max(radius + 1, best.0 - radius), searchHi = min(trimmed.count - radius - 2, best.0 + radius)
        guard searchHi > searchLo else { return nil }
        let anchor = (searchLo...searchHi).max(by: { trimmed[$0] < trimmed[$1] }) ?? best.0
        var output = [Float](repeating: 0, count: max(1, Int(duration * outputRate)))
        var weights = [Float](repeating: 0, count: output.count)
        let targetPeriod = outputRate / Music.frequency(midi)
        let grainRadius = period * outputRate / source.sampleRate
        var center = 0.0
        while center < Double(output.count) + grainRadius {
            let left = max(0, Int(floor(center - grainRadius))), right = min(output.count - 1, Int(ceil(center + grainRadius)))
            if left <= right {
                for index in left...right {
                    let delta = (Double(index) - center) * source.sampleRate / outputRate
                    let sourcePosition = Double(anchor) + delta
                    let first = Int(floor(sourcePosition)), fraction = Float(sourcePosition - floor(sourcePosition))
                    guard first >= 0, first + 1 < trimmed.count, abs(delta) <= period else { continue }
                    let window = Float(0.5 + 0.5 * cos(.pi * delta / period))
                    let value = trimmed[first] * (1 - fraction) + trimmed[first + 1] * fraction
                    output[index] += value * window; weights[index] += window
                }
            }
            center += targetPeriod
        }
        // Preserve a short consonant prefix; crossfade into the sustained, tuned vowel.
        let prefix = min(Int(outputRate * 0.065), output.count / 4)
        for index in output.indices {
            if weights[index] > 0.001 { output[index] /= weights[index] }
            if index < prefix {
                let sourceIndex = min(trimmed.count - 1, Int(Double(index) * source.sampleRate / outputRate))
                let blend = Float(index) / Float(max(1, prefix))
                output[index] = trimmed[sourceIndex] * (1 - blend) + output[index] * blend
            }
            let fade = min(1, min(Double(index) / (outputRate * 0.005), Double(output.count - index) / (outputRate * 0.025)))
            output[index] *= Float(max(0, fade))
        }
        return output
    }
}
