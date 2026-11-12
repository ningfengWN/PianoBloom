import SwiftUI

struct PracticeResult: Codable, Identifiable {
    var id = UUID()
    let title: String
    let date: Date
    let count: Int
    let mistakes: Int
    let accuracy: Int
    let seconds: Int
    var rhythm: Int?
    var missed: Int?
    var hands: String?
    var source: String?
}

enum PianoInput: String, CaseIterable { case microphone = "麦克风", midi = "USB MIDI" }
final class PracticeModel: ObservableObject {
    @Published private(set) var score = PianoScore.all[0]
    @Published private(set) var hands: PracticeHands = .both
    @Published private(set) var style: PlayStyle = .follow
    @Published private(set) var input: PianoInput = .microphone
    @Published private(set) var bpm = 60.0
    @Published private(set) var sectionBar: Int?
    @Published private(set) var performance = Performance(score: PianoScore.all[0], hands: .both, style: .follow, bpm: 60)
    @Published private(set) var heard = Set<Int>()
    @Published private(set) var feedback = "小兔准备好啦，一起弹琴吧！"
    @Published private(set) var reference: Double
    @Published private(set) var calibrated: Bool
    @Published private(set) var calibrating = false
    @Published private(set) var running = false
    @Published private(set) var exploring = false
    @Published private(set) var now = ProcessInfo.processInfo.systemUptime
    @Published private(set) var lastGrade: NoteGrade?
    @Published private(set) var results: [PracticeResult] = []
    @Published private(set) var latestResult: PracticeResult?
    @Published var showResult = false
    @Published private(set) var guided = false
    @Published private(set) var journey = GuidedJourney()
    @Published private(set) var completedJourney: GuidedJourney?
    @Published private(set) var demonstrating = false
    @Published private(set) var demoPosition = 0
    @Published private(set) var demoBeat = 0.0
    @Published var notationScale: Double { didSet { defaults.set(notationScale, forKey: "notationScale") } }
    @Published var voiceHints: Bool { didSet { defaults.set(voiceHints, forKey: "voiceHints") } }
    private let demonstrator = PianoDemonstrator()
    private var demoTimer: Timer?
    private var demoScore: PianoScore?
    private var lastVoiceTime = -Double.infinity
    var visualPosition: Int { demonstrating ? demoPosition : performance.position }
    var visualBeat: Double { demonstrating ? demoBeat : beat }
    var phraseCount: Int { max(1, Int(ceil(score.length / Double(score.beatsPerBar * 2)))) }
    var guidedTitle: String { journey.wholeSong ? "整曲演奏" : journey.stage.title }
    var guidedRange: String { journey.wholeSong ? "完整曲谱" : "第 \(journey.phrase * 2 + 1)–\(min(journey.phrase * 2 + 2, Int(ceil(score.length / Double(score.beatsPerBar))))) 小节" }
    var weakBars: [Int] {
        let positions = performance.mistakePositions.union(performance.judgments.filter { $0.value.grade != .perfect }.map(\.key))
        return Array(Set(positions.filter { $0 < performance.score.events.count }.map { Int(performance.score.events[$0].beat) / score.beatsPerBar })).sorted()
    }

    @Published var sensitivity: Double { didSet { defaults.set(sensitivity, forKey: "sensitivity") } }
    @Published var latencyMS: Double { didSet { defaults.set(latencyMS, forKey: "latencyMS") } }
    let microphone = Microphone()
    let midi = MIDIInput()
    private let defaults: UserDefaults
    private var gate = NoteGate()
    private var polyGate = PolyphonicGate()
    private var calibrator = CentralCCalibrator()
    private var timer: Timer?
    private var calibrationTimer: Timer?
    private var lastFrameTime: Double?
    private var startedAt: Double?
    private var elapsed = 0.0
    private var recordingResult = false
    var threshold: Double { 0.012 * pow(0.10, sensitivity) }
    var isEstimate: Bool { input == .microphone }
    var currentScore: PianoScore { score.excerpt(sectionBar) }
    var beat: Double { performance.beat(at: now) }
    var countIn: Int? {
        guard running, beat < 0 else { return nil }
        return max(1, Int(ceil(-beat)))
    }
    var target: Set<Int> {
        guard performance.position < performance.score.events.count else { return [] }
        return performance.score.events[performance.position].pitches(hands)
    }
    var inputDescription: String { input == .midi ? midi.message : (hands == .both ? "麦克风双手 · 测试模式" : "麦克风识音") }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedScale = defaults.double(forKey: "notationScale")
        notationScale = savedScale == 0 ? 1.35 : min(1.7, max(1, savedScale))
        voiceHints = defaults.object(forKey: "voiceHints") == nil ? true : defaults.bool(forKey: "voiceHints")
        let stored = defaults.double(forKey: "centralC")
        reference = (245...280).contains(stored) ? stored : Music.standardC
        calibrated = (245...280).contains(stored)
        sensitivity = defaults.object(forKey: "sensitivity") == nil ? 0.5 : min(1, max(0, defaults.double(forKey: "sensitivity")))
        latencyMS = min(300, max(-300, defaults.double(forKey: "latencyMS")))
        if let data = defaults.data(forKey: "results"), let history = try? JSONDecoder().decode([PracticeResult].self, from: data) { results = history }
        microphone.onFrame = { [weak self] in self?.receive($0) }
        microphone.onReady = { [weak self] in if self?.calibrating == false && self?.exploring == false { self?.beginClock() } }
        microphone.onStop = { [weak self] in self?.didStop() }
        midi.onNote = { [weak self] note, on, time in
            guard let self, self.input == .midi, self.running else { return }
            self.heard = self.midi.active
            if on { self.accept([note], at: time) }
        }
        midi.onDisconnect = { [weak self] in self?.pause(); self?.feedback = "钢琴连接断开了，接好后可以继续。" }
    }
    #if DEBUG
    func prepareScreenshot() {
        select(HanonScores.all[0])
        if ProcessInfo.processInfo.arguments.contains("--preview-guided") { beginGuided(); return }
        performance.start(at: ProcessInfo.processInfo.systemUptime)
        performance.pause(at: ProcessInfo.processInfo.systemUptime)
    }
    #endif
    deinit { timer?.invalidate(); calibrationTimer?.invalidate(); demoTimer?.invalidate() }
    func select(_ score: PianoScore) { pause(); guided = false; self.score = score; sectionBar = nil; restart() }
    func configure(hands: PracticeHands? = nil, style: PlayStyle? = nil, input: PianoInput? = nil, bpm: Double? = nil) {
        pause()
        guided = false
        if let hands { self.hands = hands }
        if let style { self.style = style }
        if let input { self.input = input }
        if let bpm { self.bpm = min(120, max(30, bpm)) }
        restart()
    }
    func selectSection(_ bar: Int?) { sectionBar = bar; restart() }
    func restart() {
        pause()
        performance = Performance(score: currentScore, hands: hands, style: style, bpm: bpm)
        elapsed = 0; recordingResult = false; latestResult = nil; showResult = false; lastGrade = nil
        feedback = style == .follow ? "跟着发光的音符，慢慢弹就好。" : "先数一小节，再跟着星星的节拍弹。"
    }
    func beginGuided() {
        pause(); guided = true
        if let data = defaults.data(forKey: "journey-" + score.id), let saved = try? JSONDecoder().decode(GuidedJourney.self, from: data), !saved.complete, saved.phrase < phraseCount { journey = saved }
        else { journey = GuidedJourney() }
        applyJourney()
    }
    func beginFree() { pause(); guided = false }
    private func applyJourney() {
        hands = journey.stage.hands; style = journey.stage.style
        sectionBar = journey.wholeSong ? nil : journey.phrase * 2
        restart(); feedback = journey.stage.instruction
        if voiceHints { demonstrator.speak(journey.stage.instruction) }
    }
    func continueGuided() { guard guided, !journey.complete else { return }; applyJourney() }
    func repeatGuided() {
        guard let completedJourney else { restart(); return }
        journey = completedJourney; saveJourney(); applyJourney()
    }
    private func saveJourney() {
        if let data = try? JSONEncoder().encode(journey) { defaults.set(data, forKey: "journey-" + score.id) }
    }
    func replayWeakBar(_ localBar: Int) {
        let global = (sectionBar ?? 0) + localBar
        guided = false; selectSection(global)
    }
    func speakInstruction() {
        pause(); demonstrator.speak(guided ? journey.stage.instruction : "先听示范，再弹亮起来的音符。")
    }
    func demonstrate() {
        pause()
        // Always audition a bounded excerpt. Whole-score audition starts at the current two-bar group.
        let globalBar = sectionBar ?? (Int(performance.score.events[min(performance.position, performance.score.events.count - 1)].beat) / score.beatsPerBar / 2 * 2)
        let excerpt = score.excerpt(globalBar)
        guard !excerpt.events.isEmpty else { return }
        do {
            try demonstrator.play(score: excerpt, hands: hands, bpm: bpm)
            demoScore = excerpt; demonstrating = true
            let start = ProcessInfo.processInfo.systemUptime
            let offset = Double(globalBar - (sectionBar ?? 0)) * Double(score.beatsPerBar)
            demoBeat = offset; demoPosition = performance.score.events.firstIndex(where: { $0.beat >= offset }) ?? 0
            feedback = "正在听音符示范，键盘会同步亮起。"
            demoTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                guard let self else { return }
                let beat = (ProcessInfo.processInfo.systemUptime - start) * self.bpm / 60
                self.demoBeat = offset + beat
                if beat >= excerpt.length { self.pause(); self.feedback = "示范结束，轮到你来试试。"; return }
                let index = excerpt.events.lastIndex(where: { $0.beat <= beat }) ?? 0
                self.demoPosition = self.performance.score.events.firstIndex(where: { $0.beat >= offset + excerpt.events[index].beat }) ?? 0
                self.heard = excerpt.events[index].pitches(self.hands)
            }
        } catch { feedback = "示范声音暂不可用，请检查设备声音设置。" }
    }
    func toggle() {
        if demonstrating { pause(); return }
        if running || microphone.requesting { pause(); return }
        demonstrator.stop()
        if performance.finished { restart() }
        gate.reset(); polyGate.reset(); lastFrameTime = nil
        if input == .midi {
            midi.start()
            if midi.listening { beginClock() } else { feedback = midi.message }
        } else {
            microphone.polyphonic = hands == .both
            microphone.reference = reference
            microphone.start()
        }
    }
    private func beginClock() {
        guard !running else { return }
        now = ProcessInfo.processInfo.systemUptime
        performance.start(at: now); running = true; startedAt = now
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        feedback = "预备，一起数拍子。"
    }
    private func tick() {
        now = ProcessInfo.processInfo.systemUptime
        guard running else { return }
        let before = performance.missedCount
        performance.tick(at: now - (input == .microphone ? 0.25 : 0.02))
        if performance.missedCount > before { lastGrade = .missed; feedback = "这颗星星先放过，跟上下一拍吧。" }
        if performance.finished { finish() }
        else if beat >= 0, feedback == "预备，一起数拍子。" { feedback = style == .follow ? "请弹亮起来的音符。" : "跟着节拍，让星星亮起来。" }
    }
    func pause() {
        demonstrating = false; demoTimer?.invalidate(); demoTimer = nil; demoScore = nil; demonstrator.stop()
        now = ProcessInfo.processInfo.systemUptime
        performance.pause(at: now)
        if let startedAt { elapsed += max(0, now - startedAt) }
        startedAt = nil; running = false
        timer?.invalidate(); timer = nil
        midi.stop(); microphone.stop()
        heard = []; gate.reset(); polyGate.reset()
    }
    private func didStop() {
        if running {
            now = ProcessInfo.processInfo.systemUptime; performance.pause(at: now)
            if let startedAt { elapsed += max(0, now - startedAt) }
            startedAt = nil; running = false; timer?.invalidate(); timer = nil
            feedback = "聆听暂停了，准备好后可以继续。"
        }
        calibrating = false; exploring = false; calibrationTimer?.invalidate(); calibrationTimer = nil
        heard = []; gate.reset(); polyGate.reset()
    }
    func explore() {
        pause(); exploring = true
        microphone.polyphonic = false; microphone.reference = reference
        microphone.start()
    }
    func calibrate() {
        pause(); calibrator.reset(); calibrating = true
        microphone.polyphonic = false
        feedback = "请弹中央 C（C4），保持一秒，不要踩踏板。"
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            if ProcessInfo.processInfo.systemUptime > deadline { self.pause(); self.feedback = "没有听到稳定的中央 C，请靠近钢琴后再试。" }
        }
        microphone.start()
    }
    func resetCalibration() {
        pause(); reference = Music.standardC; calibrated = false
        defaults.removeObject(forKey: "centralC"); feedback = "已恢复标准音高。"
    }
    private func receive(_ frame: PitchFrame) {
        if calibrating {
            if let c = calibrator.process(frame, threshold: threshold) {
                reference = c; calibrated = true; defaults.set(c, forKey: "centralC")
                pause(); feedback = "校准好啦！松开琴键，再进入小小音乐会。"
            }
            return
        }
        if exploring {
            if let f = frame.frequency, frame.rms >= threshold { heard = [Int(Music.pitch(f, reference: reference).rounded())] } else { heard = [] }
            return
        }
        guard running, input == .microphone else { return }
        if let lastFrameTime, frame.time - lastFrameTime > 0.4 { gate.reset(); polyGate.reset() }
        lastFrameTime = frame.time
        if hands == .both, let poly = frame.polyphony {
            heard = poly.rms >= threshold ? poly.notes : []
            if let (notes, time) = polyGate.process(poly, threshold: threshold) { accept(notes, at: time) }
        } else {
            if let f = frame.frequency, frame.rms >= threshold { heard = [Int(Music.pitch(f, reference: reference).rounded())] } else { heard = [] }
            if let note = gate.process(frame, reference: reference, threshold: threshold) { accept([note], at: frame.time - 0.07) }
        }
    }
    private func accept(_ notes: Set<Int>, at time: Double) {
        guard running else { return }
        let corrected = time - (input == .microphone ? latencyMS / 1000 : 0)
        guard let grade = performance.play(notes, at: corrected, groupingWindow: min(0.09, performance.window)) else { return }
        lastGrade = grade
        switch grade {
        case .perfect: feedback = "真棒！又点亮一颗小星星。"
        case .early: feedback = "音弹对啦，再等一点点节拍。"
        case .late: feedback = "音弹对啦，下次早一点点。"
        case .wrong: feedback = hands == .both ? "看看两只手，再试试发光的音符。" : "再看看发光的音符，小兔等你。"
        case .missed: break
        }
        if grade == .wrong && style == .follow && voiceHints && time - lastVoiceTime > 3 {
            lastVoiceTime = time
            let notes = target.sorted().map(Music.name).joined(separator: "、")
            pause(); feedback = "请再试试 \(notes)，点击开始继续。"
            demonstrator.speak("再试试亮起来的音符。")
        }
        if performance.finished { finish() }
    }
    private func finish() {
        guard !recordingResult else { return }
        recordingResult = true
        let seconds = Int(elapsed + (startedAt.map { max(0, now - $0) } ?? 0))
        let result = PracticeResult(title: score.title + (sectionBar.map { " · 第 \($0 + 1) 小节起" } ?? ""), date: Date(), count: performance.correctCount,
                                    mistakes: performance.mistakes, accuracy: performance.pitchScore, seconds: seconds,
                                    rhythm: performance.rhythmScore, missed: performance.missedCount, hands: hands.rawValue,
                                    source: input == .microphone ? "麦克风估算" : "MIDI")
        if guided {
            completedJourney = journey
            journey.record(pitch: result.accuracy, rhythm: result.rhythm, phraseCount: phraseCount)
            saveJourney()
        }
        latestResult = result; results.insert(result, at: 0); results = Array(results.prefix(30))
        if let data = try? JSONEncoder().encode(results) { defaults.set(data, forKey: "results") }
        pause(); showResult = true
    }
}
