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
    for midi in [35,36,47,48,55,60,61,64,69,72,83,88] {
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
for midi in [59,61] {
    calibrator.reset()
    for i in 0..<10 { check(calibrator.process(frame(midi,Double(i)*0.08), threshold:0.004) == nil, "adjacent key cannot calibrate") }
}
var progress = PracticeProgress(notes: [60,60,62])
check(!progress.accept(64), "wrong note rejected")
check(progress.position == 0 && progress.mistakes == 1, "wrong note doesn't advance")
check(progress.accept(60) && progress.accept(60) && progress.accept(62), "correct sequence")
check(progress.complete && progress.accuracy == 75, "accuracy and completion")
check(!progress.accept(62) && progress.position == 3, "completion cannot overflow")
check(Music.staffStep(60) == 0 && Music.staffStep(72) == 7, "staff mapping")
check(abs(Music.pitch(263, reference:263) - 60) < 0.001, "calibrated note mapping")


check(Exercise.hanon.count == 20, "20 Hanon exercises")
check(Array(Exercise.hanon[0].notes.prefix(8)) == [48,52,53,55,57,55,53,52], "Hanon 1 original opening")
for exercise in Exercise.hanon {
    check(!exercise.notes.isEmpty, "nonempty Hanon score")
    check(exercise.notes.allSatisfy { (47...88).contains($0) }, "Hanon detector range")
    var run = PracticeProgress(notes: exercise.notes)
    for note in exercise.notes { _ = run.accept(note) }
    check(run.complete && run.accuracy == 100, "full Hanon follow-through")
}



// Full-score integrity and genuine two-hand attribution.
check(PianoScore.all.count == 23, "all scores available")
check(HanonScores.all[0].events.count == 465, "Hanon 1 original repeat expanded")
check(HanonScores.all[0].events[0].right == [48] && HanonScores.all[0].events[0].left == [36], "original registers, not fabricated C4 left hand")
check(HanonScores.all[19].events.last!.pitches(.both) == [36,48,52,60], "Hanon 20 closing four-note chord")
for score in PianoScore.all {
    check(!score.events.isEmpty, "nonempty score")
    check(score.events.allSatisfy { !$0.pitches(.both).isEmpty && $0.duration > 0 }, "score events have pitch and duration")
    for index in score.events.indices.dropFirst() {
        check(abs(score.events[index].beat - score.events[index - 1].beat - score.events[index - 1].duration) < 0.001, "source rhythm continuity")
    }
    let excerpt = score.excerpt(0)
    check(excerpt.events.first?.beat == 0 && excerpt.length > 0, "excerpt normalized")
}
let pair = PianoScore(id: "test", title: "Test", detail: "", beatsPerBar: 2, events: [
    ScoreEvent(beat: 0, duration: 1, right: [60], left: [48]),
    ScoreEvent(beat: 1, duration: 1, right: [62], left: [50]),
    ScoreEvent(beat: 2, duration: 2, right: [64], left: [52])])
var follow = Performance(score: pair, hands: .both, style: .follow, bpm: 60)
follow.start(at: 0)
check(follow.play([48,60], at: 1) == nil, "ignore count-in playing")
check(follow.play([60], at: 2) == nil && follow.position == 0, "right alone cannot pass both hands")
check(follow.play([48], at: 2.04) == .perfect && follow.position == 1, "two MIDI packets grouped")
check(follow.play([50,62,65], at: 3) == .wrong && follow.position == 1, "extra note is a mistake")
check(follow.play([50,62], at: 4) == .perfect, "follow allows free timing")
check(follow.play([52,64], at: 12) == .perfect && follow.finished, "free practice completes")
check(follow.rhythmScore == nil && follow.pitchScore == 75, "free practice never invents rhythm score")
var challenge = Performance(score: pair, hands: .both, style: .rhythm, bpm: 60)
challenge.start(at: 0)
check(challenge.play([48,60], at: 2) == .perfect, "on-grid chord perfect")
check(challenge.play([50,62], at: 3.1) == .late, "late chord recognized")
check(challenge.play([52,64], at: 3.9) == .early, "early chord recognized")
check(!challenge.finished, "final hold duration not skipped")
challenge.tick(at: 6)
check(challenge.finished && challenge.rhythmScore! < 100 && challenge.pitchScore == 100, "separate pitch and rhythm scores")
var missed = Performance(score: pair, hands: .both, style: .rhythm, bpm: 60)
missed.start(at: 0); missed.tick(at: 3.4)
check(missed.position == 2 && missed.missedCount == 2, "missed notes advance without freezing")
_ = missed.play([52,64], at: 4)
missed.tick(at: 6)
check(missed.finished && missed.rhythmScore == 33, "misses included in rhythm denominator")
var paused = Performance(score: pair, hands: .both, style: .rhythm, bpm: 60)
paused.start(at: 0); paused.pause(at: 1); paused.tick(at: 100)
check(paused.position == 0, "pause freezes count-in")
paused.start(at: 11)
check(paused.epoch == 12 && paused.play([48,60], at: 12) == .perfect, "resume preserves beat grid")
var delayedHands = Performance(score: pair, hands: .both, style: .follow, bpm: 60)
delayedHands.start(at: 0)
_ = delayedHands.play([60], at: 2)
_ = delayedHands.play([48], at: 2.3)
check(delayedHands.position == 0, "unrelated separate hand notes never fake a chord")
// MIDI transport: packet splitting, running status, real-time bytes and velocity zero.
var parser = MIDIByteParser()
check(parser.feed([0x90,60]).isEmpty, "split MIDI note")
let transport = parser.feed([0xF8,100,48,90,60,0,0x80,48,64])
check(transport.count == 4 && transport[0].on && transport[1].note == 48 && !transport[2].on && !transport[3].on, "MIDI running status and note-off")
check(parser.feed([0xF0,1,2,0x90,60,100,0xF7]).isEmpty, "ignore sysex payload")
// Feed real PCM mixtures to the polyphonic production analyzer, not expected-score mocks.
func pianoMixture(_ notes: [Int], rate: Double = 16000) -> [Float] {
    (0..<4096).map { i in
        var value = 0.0
        for note in notes {
            let f = Music.frequency(note)
            for harmonic in 1...8 where f * Double(harmonic) < rate / 2 {
                value += 0.12 / pow(Double(harmonic), 1.25) * sin(2 * .pi * f * Double(harmonic) * Double(i) / rate + Double(harmonic) * 0.17)
            }
        }
        return Float(value)
    }
}
for pitches in [[36,48], [48,60], [48,64,67], [35,47], [60], [36], [52,64]] {
    let detection = PolyphonicDetector.analyze(pianoMixture(pitches), sampleRate: 16000, reference: Music.standardC, time: 1)
    check(detection.notes == Set(pitches), "polyphonic PCM \(pitches): \(detection.notes)")
}
check(PolyphonicDetector.analyze([Float](repeating: 0, count: 4096), sampleRate: 16000, reference: Music.standardC, time: 0).notes.isEmpty, "polyphonic silence")
var polyGate = PolyphonicGate()
var chordEvents = 0
for i in 0..<20 {
    if polyGate.process(PolyphonicFrame(notes: [48,60], rms: 0.1, confidence: 0.9, time: Double(i) * 0.04), threshold: 0.004) != nil { chordEvents += 1 }
}
check(chordEvents == 1, "sustained chord cannot repeatedly advance")
print("PASS: \(checks) production core checks")
