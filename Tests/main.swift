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
check(follow.play([50,62,65], at: 3) == .wrong && follow.position == 2, "wrong note recorded and automatically advances")
check(follow.play([52,64], at: 12) == .perfect && follow.finished, "follow continues after error without restarting input")
check(follow.play([52,64], at: 13) == nil && follow.position == 3, "completion ignores further notes")
check(follow.rhythmScore == nil && follow.pitchScore == 67, "free practice never invents rhythm score")
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


// Guided learning: unlocking is driven by completed attempts, pitch AND rhythm.
var journey = GuidedJourney()
check(journey.stage == .right && journey.phrase == 0, "guided starts with right hand")
journey.record(pitch: 100, rhythm: nil, phraseCount: 2)
check(journey.stage == .left, "right hand precedes left")
journey.record(pitch: 100, rhythm: nil, phraseCount: 2)
check(journey.stage == .both, "left hand precedes two hands")
journey.record(pitch: 69, rhythm: nil, phraseCount: 2)
check(journey.stage == .both && journey.attempts == 1, "69 does not unlock flow")
journey.record(pitch: 70, rhythm: nil, phraseCount: 2)
check(journey.stage == .flow && journey.attempts == 0, "70 unlocks flow")
journey.record(pitch: 100, rhythm: 89, phraseCount: 2)
check(journey.stage == .flow, "rhythm threshold enforced")
journey.record(pitch: 89, rhythm: 100, phraseCount: 2)
check(journey.stage == .flow, "pitch threshold enforced")
journey.record(pitch: 0, rhythm: 0, phraseCount: 2)
check(journey.stage == .concert, "three completed attempts unlock next practice stage")
journey.record(pitch: 90, rhythm: 90, phraseCount: 2)
check(journey.stage == .right && journey.phrase == 1, "next phrase restarts separate hands")
journey.record(pitch: 100, rhythm: nil, phraseCount: 2)
journey.record(pitch: 100, rhythm: nil, phraseCount: 2)
journey.record(pitch: 100, rhythm: nil, phraseCount: 2)
journey.record(pitch: 100, rhythm: 100, phraseCount: 2)
journey.record(pitch: 100, rhythm: 100, phraseCount: 2)
check(journey.wholeSong && journey.stage == .concert && !journey.complete, "whole song follows last phrase")
let savedJourney = try! JSONEncoder().encode(journey)
check(try! JSONDecoder().decode(GuidedJourney.self, from: savedJourney) == journey, "journey round-trip persistence")
journey.record(pitch: 100, rhythm: 100, phraseCount: 2)
check(journey.complete, "whole-song performance completes learning path")
let completed = journey
journey.record(pitch: 100, rhythm: 100, phraseCount: 2)
check(journey == completed, "completion idempotent")
var weak = Performance(score: pair, hands: .both, style: .follow, bpm: 60)
weak.start(at: 0)
_ = weak.play([61], at: 2)
check(weak.mistakePositions == [0], "wrong event retained for targeted review")


// Continuous wrong-note handling: one chord must never eat multiple score events.
var moving = Performance(score: pair, hands: .both, style: .follow, bpm: 60)
moving.start(at: 0)
check(moving.play([61], at: 2) == .wrong && moving.position == 1, "wrong first hand advances one event")
check(moving.play([48], at: 2.03) == nil && moving.position == 1, "other packet of same wrong chord is suppressed")
check(moving.judgments[0]?.grade == .wrong && moving.mistakes == 1, "wrong event has permanent review feedback")
check(moving.play([50,62], at: 3) == .perfect && moving.position == 2, "next correct chord works without start or resume")
check(moving.play([65], at: 4) == .wrong && moving.finished, "last wrong note completes free follow")
check(moving.pitchScore == 33 && moving.mistakePositions == [0,2], "wrong notes count once in accuracy denominator")
var wrongGrid = Performance(score: pair, hands: .both, style: .rhythm, bpm: 60)
wrongGrid.start(at: 0)
_ = wrongGrid.play([61], at: 2)
check(wrongGrid.position == 1 && wrongGrid.epoch == 2, "wrong rhythm note leaves fixed beat grid unchanged")
check(wrongGrid.play([50,62], at: 2.2) == nil && wrongGrid.position == 1, "new position cannot be played before its rhythm window")
_ = wrongGrid.play([50,62], at: 3)
_ = wrongGrid.play([65], at: 4)
check(!wrongGrid.finished, "final wrong rhythm note still honors final duration")
wrongGrid.tick(at: 6)
check(wrongGrid.finished && wrongGrid.pitchScore == 33 && wrongGrid.rhythmScore == 33, "wrong rhythm events included once and graded zero")
var selectableJourney = GuidedJourney(phrase: 3, stage: .flow, attempts: 2, wholeSong: false)
selectableJourney.chooseHand(.left)
check(selectableJourney.phrase == 3 && selectableJourney.stage == .left && selectableJourney.attempts == 0, "left hand freely selectable without losing phrase")
selectableJourney.chooseHand(.both)
check(selectableJourney.stage == .both, "both hands selectable without completing left")
selectableJourney.chooseHand(.right)
check(selectableJourney.stage == .right, "can go backwards to right hand")
selectableJourney.wholeSong = true
selectableJourney.chooseHand(.left)
check(selectableJourney.wholeSong, "hand change preserves full-song scope")
// A complete score stays visible while local excerpt judgments map to their original notes.
let displayScore = PianoScore.starters[0]
let entireMap = ScoreDisplayMap(score: displayScore, sectionBar: nil)
check(entireMap.indices.count == displayScore.events.count && entireMap.globalIndex(0) == 0, "whole score mapping preserves every event")
let excerptMap = ScoreDisplayMap(score: displayScore, sectionBar: 2)
let excerptScore = displayScore.excerpt(2)
check(excerptMap.indices.count == excerptScore.events.count && excerptMap.beatOffset == 8, "excerpt mapping matches scored range")
check(excerptMap.globalIndex(0).map { displayScore.events[$0].beat } == 8, "later phrase starts on original score beat")
check(excerptMap.globalIndex(excerptScore.events.count) == nil, "finished excerpt never highlights next unplayed phrase")
let mappedJudgments = excerptMap.judgments([0: EventJudgment(grade: .perfect, error: nil, heard: [60])])
check(mappedJudgments[excerptMap.indices[0]]?.grade == .perfect && mappedJudgments[0] == nil, "played flower appears on global note, not first row")
check(excerptMap.positions([0]) == [excerptMap.indices[0]], "mistake review aligns with the complete score")
check(ScoreDisplayMap(score: displayScore, sectionBar: 999).indices.isEmpty, "out of range excerpt safely maps no notes")
check(PracticeMode.allCases.count == 4 && PracticeMode.performance.style == .follow && PracticeMode.performance.waitsForCorrect, "performance mode directly selectable with correction waiting")
check(PracticeMode.reading.style == .follow && PracticeMode.rhythm.style == .rhythm, "independent practice modes map to existing scoring engines")
// Performance waits for correction without stopping input; flow keeps its fixed grid.
var waitingPerformance = Performance(score: pair, hands: .both, style: PracticeMode.performance.style, bpm: 60, waitForCorrect: PracticeMode.performance.waitsForCorrect)
waitingPerformance.start(at: 0)
check(waitingPerformance.play([61], at: 2) == .wrong && waitingPerformance.position == 0, "performance wrong note stays on current target")
waitingPerformance.tick(at: 30)
check(waitingPerformance.position == 0 && !waitingPerformance.finished, "performance never times out while waiting for correction")
check(waitingPerformance.play([48], at: 30) == nil && waitingPerformance.position == 0, "one correct hand alone cannot pass performance chord")
check(waitingPerformance.play([60], at: 30.03) == .perfect && waitingPerformance.position == 1, "correct chord resumes without another start")
_ = waitingPerformance.play([50,62], at: 31)
_ = waitingPerformance.play([52,64], at: 32)
check(waitingPerformance.finished && waitingPerformance.pitchScore == 67 && waitingPerformance.mistakes == 1, "performance retains original mistake after correction")
check(PracticeMode.flow.style == .rhythm && !PracticeMode.flow.waitsForCorrect, "flow uses uninterrupted timing grid")
check(challenge.earlyCount + challenge.lateCount > 0, "timing deviations available for final summary")
// Flow annotations distinguish isolated omissions from hesitation runs without changing grades.
let omission = EventJudgment(grade: .missed, error: nil, heard: [])
let badNote = EventJudgment(grade: .wrong, error: 0, heard: [61])
let goodNote = EventJudgment(grade: .perfect, error: 0, heard: [60])
let singleOmission = FlowReview(score: pair, judgments: [0: omission, 1: goodNote])
check(singleOmission.stalledPositions.isEmpty && singleOmission.stallSections == 0, "single missed note remains a red omission, not hesitation")
let silentRun = FlowReview(score: pair, judgments: [0: omission, 1: omission, 2: goodNote])
check(silentRun.stalledPositions == [0,1] && silentRun.stallSections == 1, "consecutive silent attacks form one hesitation section")
let denseErrors = FlowReview(score: pair, judgments: [0: badNote, 1: badNote, 2: badNote])
check(denseErrors.denseErrorPositions == [0,1,2] && denseErrors.denseErrorSections == 1, "three consecutive wrong onsets are gray excessive errors")
check(FlowReview(score: pair, judgments: [0: badNote, 1: goodNote, 2: badNote]).grayPositions.isEmpty, "correct onset separates error runs")
check(FlowReview(score: pair, judgments: [2: omission]).stalledPositions.isEmpty, "one long note omission is not a multi-attack hesitation")
let quickRun = PianoScore(id: "fast", title: "Fast", detail: "", beatsPerBar: 4, events: (0..<4).map { ScoreEvent(beat: Double($0) / 4, duration: 0.25, right: [60], left: []) })
check(FlowReview(score: quickRun, judgments: [0: omission, 1: omission]).grayPositions.isEmpty, "brief pair of sixteenth misses stays red")
check(FlowReview(score: quickRun, judgments: [0: omission, 1: omission, 2: omission, 3: omission]).stalledPositions.count == 4, "full beat of consecutive misses forms hesitation")
check(missed.judgments[0]?.grade == .missed && missed.rhythmScore == 33, "annotation review preserves original timing and pitch grades")
print("PASS: \(checks) production core checks")
