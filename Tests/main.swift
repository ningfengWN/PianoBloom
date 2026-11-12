import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError("FAILED: \(message)") }
}
func frame(_ midi: Int?, _ t: Double, rms: Double = 0.06) -> PitchFrame {
    PitchFrame(frequency: midi.map { Music.frequency($0) }, rms: midi == nil ? 0 : rms, time: t)
}
// Actual PCM is fed to the production detector, including overtones and detuning.
for rate in [14700.0,16000.0,12000.0] {
    for midi in [48,55,60,61,64,69,72,83] {
        for detune in [0.0, 17.0] {
            let f = Music.frequency(midi) * pow(2, detune / 1200)
            var pcm: [Float] = []
            let step: Double = 2.0 * Double.pi * f / rate
            for i in 0..<2048 {
                let phase: Double = step * Double(i)
                let fundamental: Double = 0.18 * sin(phase)
                let harmonic2: Double = 0.10 * sin(2.0 * phase)
                let harmonic3: Double = 0.05 * sin(3.0 * phase)
                pcm.append(Float(fundamental + harmonic2 + harmonic3 + 0.03))
            }
            let result = PitchDetector.analyze(pcm, sampleRate: rate, time: 0)
            check(result.frequency != nil, "detect \(midi) at \(rate)")
            if let found = result.frequency { check(abs(1200 * log2(found/f)) < 12, "pitch error \(midi) at \(rate): \(found)") }
        }
    }
}
check(PitchDetector.analyze([Float](repeating: 0, count: 2048), sampleRate: 16000, time: 0).frequency == nil, "silence rejected")
check(PitchDetector.analyze([Float](repeating: 0.2, count: 2048), sampleRate: 16000, time: 0).frequency == nil, "DC rejected")
check(PitchDetector.analyze([], sampleRate: 16000, time: 0).frequency == nil, "short buffer rejected")
var seed: UInt64 = 42
let noise = (0..<2048).map { _ -> Float in
    seed = seed &* 6364136223846793005 &+ 1
    return Float(Double(seed >> 32) / Double(UInt32.max) - 0.5) * 0.15
}
check(PitchDetector.analyze(noise, sampleRate: 16000, time: 0).frequency == nil, "noise rejected")
var gate = NoteGate()
var events: [Int] = []
for i in 0..<50 { if let event = gate.process(frame(64, Double(i) * 0.04), reference: Music.standardC, threshold: 0.004) { events.append(event) } }
check(events == [64], "sustained note emitted once")
_ = gate.process(frame(nil, 2.1), reference: Music.standardC, threshold: 0.004)
_ = gate.process(frame(nil, 2.2), reference: Music.standardC, threshold: 0.004)
for t in [2.3,2.34,2.38] { if let event = gate.process(frame(64,t), reference: Music.standardC, threshold: 0.004) { events.append(event) } }
check(events == [64,64], "same note after silence")
for t in [2.7,2.74,2.78] { if let event = gate.process(frame(65,t), reference: Music.standardC, threshold: 0.004) { events.append(event) } }
check(events == [64,64,65], "legato pitch change")
// New attack while old note is still ringing: volume rises after decay.
_ = gate.process(frame(65,3.1,rms:0.01), reference: Music.standardC, threshold: 0.004)
for t in [3.2,3.24,3.28] { if let event = gate.process(frame(65,t,rms:0.07), reference: Music.standardC, threshold: 0.004) { events.append(event) } }
check(events == [64,64,65,65], "repeat from new attack")
var calibrator = CentralCCalibrator()
var reference: Double?
for i in 0..<10 { reference = calibrator.process(PitchFrame(frequency: 263, rms: 0.1, time: Double(i) * 0.08), threshold: 0.004) ?? reference }
check(reference == 263, "stable central C calibration")
calibrator.reset()
for i in 0..<10 { check(calibrator.process(frame(72,Double(i)*0.08), threshold:0.004) == nil, "wrong octave cannot calibrate") }
var progress = PracticeProgress(notes: [60,60,62])
check(!progress.accept(64), "wrong note rejected")
check(progress.position == 0 && progress.mistakes == 1, "wrong note doesn't advance")
check(progress.accept(60) && progress.accept(60) && progress.accept(62), "correct sequence")
check(progress.complete && progress.accuracy == 75, "accuracy and completion")
check(!progress.accept(62) && progress.position == 3, "completion cannot overflow")
check(Music.staffStep(60) == 0 && Music.staffStep(72) == 7, "staff mapping")
check(abs(Music.pitch(263, reference:263) - 60) < 0.001, "calibrated note mapping")
print("PASS: \(checks) production core checks")
