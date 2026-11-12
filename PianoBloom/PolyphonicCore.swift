import Foundation

struct PolyphonicFrame {
    let notes: Set<Int>
    let rms: Double
    let confidence: Double
    let time: Double
    var onsetTime: Double?
}

/// Experimental piano transcription. Fits nonnegative harmonic templates to a Hann-windowed FFT.
/// It is deliberately independent of the expected score: target notes cannot manufacture detections.
/// Octave unisons and an unfamiliar piano's harmonic envelope remain ambiguous; use MIDI for grading.
enum PolyphonicDetector {
    static func analyze(_ samples: [Float], sampleRate: Double, reference: Double, time: Double) -> PolyphonicFrame {
        let size = 4096
        guard samples.count >= size, sampleRate >= 8000 else {
            return PolyphonicFrame(notes: [], rms: 0, confidence: 0, time: time)
        }
        let input = Array(samples.suffix(size))
        let mean = input.reduce(0.0) { $0 + Double($1) } / Double(size)
        let rms = sqrt(input.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(size))
        guard rms > 0.001 else { return PolyphonicFrame(notes: [], rms: rms, confidence: 0, time: time) }
        var real = (0..<size).map { (Double(input[$0]) - mean) * (0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(size))) }
        var imaginary = [Double](repeating: 0, count: size)
        fft(&real, &imaginary)
        let spectrum = (0...size / 2).map { hypot(real[$0], imaginary[$0]) * 4 / Double(size) }
        let peak = spectrum.max() ?? 0
        guard peak > 0.003 else { return PolyphonicFrame(notes: [], rms: rms, confidence: 0, time: time) }
        // Sparse templates preserve the amplitude relationship between fundamentals and overtones.
        var templates: [[(Int, Double)]] = []
        for note in 33...88 {
            var weights: [Int: Double] = [:]
            let fundamental = Music.frequency(note, reference: reference)
            for harmonic in 1...8 {
                let center = fundamental * Double(harmonic) * Double(size) / sampleRate
                guard center < Double(size / 2 - 3) else { break }
                for bin in max(1, Int(center) - 2)...min(size / 2 - 1, Int(center) + 3) {
                    let d = Double(bin) - center
                    func sinc(_ x: Double) -> Double { abs(x) < 1e-8 ? 1 : sin(.pi * x) / (.pi * x) }
                    let hann = abs(sinc(d) + 0.5 * sinc(d - 1) + 0.5 * sinc(d + 1))
                    weights[bin, default: 0] += hann / pow(Double(harmonic), 1.25)
                }
            }
            templates.append(weights.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
        }
        let norms = templates.map { $0.reduce(0.0) { $0 + $1.1 * $1.1 } }
        var amplitudes = [Double](repeating: 0, count: templates.count)
        var residual = spectrum
        for _ in 0..<24 {
            for index in templates.indices {
                let projection = templates[index].reduce(0.0) { $0 + residual[$1.0] * $1.1 }
                let next = max(0, amplitudes[index] + (projection - peak * 0.018) / max(1e-9, norms[index]))
                let change = next - amplitudes[index]
                if abs(change) > 1e-8 {
                    for (bin, weight) in templates[index] { residual[bin] -= change * weight }
                    amplitudes[index] = next
                }
            }
        }
        let largest = amplitudes.max() ?? 0
        let candidates = amplitudes.enumerated().filter { $0.element > max(0.008, largest * 0.23) }.sorted { $0.element > $1.element }.prefix(4)
        let energy = spectrum.reduce(0.0) { $0 + $1 * $1 }
        let remaining = residual.reduce(0.0) { $0 + $1 * $1 }
        let confidence = max(0, min(1, 1 - remaining / max(1e-9, energy)))
        let notes = confidence >= 0.64 ? Set(candidates.map { $0.offset + 33 }) : []
        return PolyphonicFrame(notes: notes, rms: rms, confidence: confidence, time: time)
    }
    private static func fft(_ real: inout [Double], _ imaginary: inout [Double]) {
        let n = real.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j ^= bit
            if i < j { real.swapAt(i, j); imaginary.swapAt(i, j) }
        }
        var length = 2
        while length <= n {
            let angle = -2 * Double.pi / Double(length)
            for start in stride(from: 0, to: n, by: length) {
                for k in 0..<length / 2 {
                    let cosine = cos(angle * Double(k)), sine = sin(angle * Double(k))
                    let first = start + k, second = first + length / 2
                    let r = real[second] * cosine - imaginary[second] * sine
                    let im = real[second] * sine + imaginary[second] * cosine
                    real[second] = real[first] - r; imaginary[second] = imaginary[first] - im
                    real[first] += r; imaginary[first] += im
                }
            }
            length <<= 1
        }
    }
}

struct PolyphonicGate {
    private var candidate: Set<Int> = []
    private var since = 0.0
    private var emitted: Set<Int> = []
    private var lastEvent = -Double.infinity
    private var quietSince: Double?
    private var attack: Double?
    mutating func reset() { self = PolyphonicGate() }
    mutating func process(_ frame: PolyphonicFrame, threshold: Double) -> (Set<Int>, Double)? {
        if frame.rms < threshold {
            if quietSince == nil { quietSince = frame.time }
            if frame.time - (quietSince ?? frame.time) > 0.07 { emitted = []; candidate = [] }
            return nil
        }
        quietSince = nil
        if let onset = frame.onsetTime, onset > lastEvent + 0.1 { attack = onset }
        guard frame.confidence >= 0.64, !frame.notes.isEmpty else { candidate = []; return nil }
        if candidate != frame.notes { candidate = frame.notes; since = frame.time; return nil }
        guard frame.time - since >= 0.03, frame.time - lastEvent > 0.10 else { return nil }
        guard emitted != candidate || attack != nil else { return nil }
        let time = attack ?? max(frame.time - 0.07, since - 0.03)
        emitted = candidate; attack = nil; lastEvent = frame.time
        return (candidate, time)
    }
}
