import Foundation

struct PitchFrame {
    var frequency: Double?
    var rms: Double
    var time: Double
}

enum PitchDetector {
    /// YIN with DC removal. Work at <= 16 kHz, off the audio callback.
    static func analyze(_ samples: [Float], sampleRate: Double, time: Double) -> PitchFrame {
        guard samples.count >= 1024, sampleRate >= 8000 else {
            return PitchFrame(frequency: nil, rms: 0, time: time)
        }
        let mean = samples.reduce(0.0) { $0 + Double($1) } / Double(samples.count)
        let x = samples.map { Double($0) - mean }
        let rms = sqrt(x.reduce(0) { $0 + $1 * $1 } / Double(x.count))
        guard rms > 0.001 else { return PitchFrame(frequency: nil, rms: rms, time: time) }
        let count = x.count / 2
        let maxLag = min(count - 2, Int(sampleRate / 115))
        let minLag = max(2, Int(sampleRate / 1200))
        guard maxLag > minLag + 2 else { return PitchFrame(frequency: nil, rms: rms, time: time) }
        var difference = [Double](repeating: 1, count: maxLag + 1)
        var total = 0.0
        for lag in 1...maxLag {
            var sum = 0.0
            for i in 0..<count { let d = x[i] - x[i + lag]; sum += d * d }
            total += sum
            difference[lag] = total > 0 ? sum * Double(lag) / total : 1
        }
        var lag = minLag
        while lag < maxLag - 1 {
            if difference[lag] < 0.16 {
                while lag + 1 < maxLag && difference[lag + 1] < difference[lag] { lag += 1 }
                let a = difference[lag - 1], b = difference[lag], c = difference[lag + 1]
                let denominator = a - 2 * b + c
                let offset = abs(denominator) > 1e-12 ? 0.5 * (a - c) / denominator : 0
                let f = sampleRate / (Double(lag) + max(-1, min(1, offset)))
                return PitchFrame(frequency: (120...1100).contains(f) ? f : nil, rms: rms, time: time)
            }
            lag += 1
        }
        return PitchFrame(frequency: nil, rms: rms, time: time)
    }
}

enum Music {
    static let standardC = 261.6255653
    static func frequency(_ midi: Int, reference: Double = standardC) -> Double {
        reference * pow(2, Double(midi - 60) / 12)
    }
    static func pitch(_ frequency: Double, reference: Double) -> Double {
        60 + 12 * log2(frequency / reference)
    }
    static func name(_ midi: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return names[(midi % 12 + 12) % 12] + String(midi / 12 - 1)
    }
    static func solfege(_ midi: Int) -> String {
        let names = ["Do", "Di", "Re", "Ri", "Mi", "Fa", "Fi", "Sol", "Si", "La", "Li", "Ti"]
        return names[(midi % 12 + 12) % 12]
    }
    static func staffStep(_ midi: Int) -> Int {
        let natural = [0,0,1,1,2,3,3,4,4,5,5,6]
        return (midi / 12 - 5) * 7 + natural[(midi % 12 + 12) % 12]
    }
}

struct Exercise: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let notes: [Int]
    static let all = [
        Exercise(id: "scale", title: "中央 C 音阶", subtitle: "8 个音 · 认识键盘", notes: [60,62,64,65,67,69,71,72]),
        Exercise(id: "ode", title: "欢乐颂", subtitle: "15 个音 · 练习重复音", notes: [64,64,65,67,67,65,64,62,60,60,62,64,64,62,62]),
        Exercise(id: "star", title: "小星星", subtitle: "14 个音 · 旋律初体验", notes: [60,60,67,67,69,69,67,65,65,64,64,62,62,60])
    ]
}

/// A note event requires a stable pitch. Sustained tones never advance twice.
/// Rearm after real silence or a new attack (volume increase), including repeated notes.
struct NoteGate {
    private var candidate: Int?
    private var candidateSince = 0.0
    private var emitted: Int?
    private var lastEvent = -100.0
    private var quietSince: Double?
    private var previousRMS = 0.0
    private var armed = true
    mutating func reset() { self = NoteGate() }
    mutating func process(_ frame: PitchFrame, reference: Double, threshold: Double) -> Int? {
        defer { previousRMS = frame.rms }
        guard let f = frame.frequency, f.isFinite, f > 0, frame.rms >= threshold else {
            candidate = nil
            if frame.rms < threshold {
                if quietSince == nil { quietSince = frame.time }
                if frame.time - (quietSince ?? frame.time) >= 0.08 { armed = true; emitted = nil }
            }
            return nil
        }
        quietSince = nil
        if previousRMS > 0, frame.rms > max(threshold * 2, previousRMS * 1.65), frame.time - lastEvent > 0.22 {
            armed = true; candidate = nil
        }
        let pitch = Music.pitch(f, reference: reference)
        let midi = Int(pitch.rounded())
        guard abs(pitch - Double(midi)) <= 0.40 else { candidate = nil; return nil }
        if candidate != midi { candidate = midi; candidateSince = frame.time; return nil }
        guard frame.time - candidateSince >= 0.055, frame.time - lastEvent >= 0.16 else { return nil }
        guard armed || emitted != midi else { return nil }
        armed = false; emitted = midi; lastEvent = frame.time
        return midi
    }
}

struct CentralCCalibrator {
    private var frequencies: [Double] = []
    private var since: Double?
    mutating func reset() { self = CentralCCalibrator() }
    mutating func process(_ frame: PitchFrame, threshold: Double) -> Double? {
        guard let f = frame.frequency, (250...274).contains(f), frame.rms >= threshold else {
            reset(); return nil
        }
        if let first = frequencies.first, abs(1200 * log2(f / first)) > 18 { reset() }
        if since == nil { since = frame.time }
        frequencies.append(f)
        guard frequencies.count >= 6, frame.time - (since ?? frame.time) >= 0.5 else { return nil }
        let sorted = frequencies.sorted()
        return sorted[sorted.count / 2]
    }
}

struct PracticeProgress {
    var notes: [Int]
    private(set) var position = 0
    private(set) var mistakes = 0
    private(set) var attempted = Set<Int>()
    var complete: Bool { position >= notes.count }
    var accuracy: Int { Int((100 * Double(position) / Double(max(1, position + mistakes))).rounded()) }
    mutating func accept(_ midi: Int) -> Bool {
        guard !complete else { return false }
        if midi == notes[position] { position += 1; return true }
        mistakes += 1; attempted.insert(position); return false
    }
}
