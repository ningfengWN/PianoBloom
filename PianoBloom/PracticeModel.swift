import SwiftUI

struct PracticeResult: Codable, Identifiable {
    var id = UUID()
    let title: String
    let date: Date
    let count: Int
    let mistakes: Int
    let accuracy: Int
    let seconds: Int
}

final class PracticeModel: ObservableObject {
    enum Mode: String, CaseIterable { case practice = "跟谱练习", tuner = "自由识音" }
    @Published var mode: Mode = .practice
    @Published private(set) var exercise = Exercise.all[0]
    @Published private(set) var progress = PracticeProgress(notes: Exercise.all[0].notes)
    @Published private(set) var frequency: Double?
    @Published private(set) var detected: Int?
    @Published private(set) var cents = 0.0
    @Published private(set) var reference: Double
    @Published private(set) var calibrated: Bool
    @Published private(set) var calibrating = false
    @Published private(set) var feedback = "准备好了吗？从中央 C 开始。"
    @Published private(set) var wrongNote: Int?
    @Published private(set) var results: [PracticeResult] = []
    @Published var showResult = false
    @Published private(set) var latestResult: PracticeResult?
    @Published var sensitivity: Double { didSet { defaults.set(sensitivity, forKey: "sensitivity") } }
    let microphone = Microphone()
    private let defaults: UserDefaults
    private var gate = NoteGate()
    private var calibrator = CentralCCalibrator()
    private var calibrationDeadline: Double?
    private var calibrationTimer: Timer?
    private var startTime: Date?
    private var lastFrameTime: Double?
    private var elapsed: TimeInterval = 0
    private var waitingAfterCalibration = false
    var threshold: Double { 0.012 * pow(0.10, sensitivity) }
    var expected: Int? { progress.complete ? nil : progress.notes[progress.position] }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.double(forKey: "centralC")
        reference = (245...280).contains(stored) ? stored : Music.standardC
        calibrated = (245...280).contains(stored)
        sensitivity = defaults.object(forKey: "sensitivity") == nil ? 0.5 : min(1, max(0, defaults.double(forKey: "sensitivity")))
        if let data = defaults.data(forKey: "results"), let history = try? JSONDecoder().decode([PracticeResult].self, from: data) { results = history }
        microphone.onFrame = { [weak self] in self?.receive($0) }
        microphone.onStop = { [weak self] in self?.didStop() }
    }
    func select(_ exercise: Exercise) {
        self.exercise = exercise
        restart()
    }
    func changeMode(_ mode: Mode) {
        self.mode = mode
        pause()
        feedback = mode == .tuner ? "弹一个音，看看它的名字。" : "点击开始，逐个弹出高亮音符。"
    }
    func restart() {
        pause()
        progress = PracticeProgress(notes: exercise.notes)
        elapsed = 0; wrongNote = nil; latestResult = nil
        feedback = "准备练习 \(exercise.title)，请弹 \(Music.name(exercise.notes[0]))。"
    }
    func toggle() {
        if microphone.listening || microphone.requesting { pause(); return }
        if progress.complete && mode == .practice { restart() }
        gate.reset(); lastFrameTime = nil
        microphone.start()
        feedback = mode == .tuner ? "正在聆听，请弹单音。" : "请弹高亮音符，弹对后自动前进。"
    }
    func pause() { microphone.stop() }
    private func didStop() {
        if let startTime { elapsed += Date().timeIntervalSince(startTime) }
        startTime = nil
        frequency = nil; detected = nil; lastFrameTime = nil; waitingAfterCalibration = false
        gate.reset()
        if calibrating { feedback = "校准已取消，原基准音已保留。" }
        calibrating = false; calibrationTimer?.invalidate(); calibrationTimer = nil
    }
    func calibrate() {
        pause()
        calibrator.reset(); calibrating = true; waitingAfterCalibration = false
        feedback = "请弹中央 C（C4），保持约 1 秒；不要踩踏板。"
        calibrationDeadline = ProcessInfo.processInfo.systemUptime + 15
        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.calibrating else { return }
            if ProcessInfo.processInfo.systemUptime > (self.calibrationDeadline ?? 0) {
                self.pause(); self.feedback = "没有听到稳定的中央 C。请靠近钢琴后重试。"
            }
        }
        microphone.start()
    }
    func resetCalibration() {
        pause(); reference = Music.standardC; calibrated = false
        defaults.removeObject(forKey: "centralC")
        feedback = "已恢复标准音高：中央 C = 261.63 Hz。"
    }
    private func receive(_ frame: PitchFrame) {
        if let lastFrameTime, frame.time - lastFrameTime > 0.35 { gate.reset() }
        lastFrameTime = frame.time
        if let f = frame.frequency, frame.rms >= threshold {
            frequency = f
            let value = Music.pitch(f, reference: reference)
            detected = Int(value.rounded()); cents = (value - value.rounded()) * 100
        } else { frequency = nil; detected = nil; cents = 0 }
        if calibrating {
            if let c = calibrator.process(frame, threshold: threshold) {
                reference = c; calibrated = true; defaults.set(c, forKey: "centralC")
                calibrating = false; calibrationTimer?.invalidate(); calibrationTimer = nil
                waitingAfterCalibration = true
                gate.reset()
                feedback = "校准完成！请先松开琴键，再开始弹奏。"
            }
            return
        }
        if waitingAfterCalibration {
            guard frame.rms < threshold else { return }
            waitingAfterCalibration = false; gate.reset(); return
        }
        guard mode == .practice, !progress.complete else { return }
        if startTime == nil { startTime = Date() }
        guard let note = gate.process(frame, reference: reference, threshold: threshold) else { return }
        if progress.accept(note) {
            wrongNote = nil
            if progress.complete { finish() }
            else { feedback = "弹对了！接下来是 \(Music.name(progress.notes[progress.position]))。" }
        } else {
            wrongNote = note
            feedback = "听到 \(Music.name(note))，请试试 \(Music.name(progress.notes[progress.position]))。"
        }
    }
    private func finish() {
        let seconds = Int(elapsed + (startTime.map { Date().timeIntervalSince($0) } ?? 0))
        let result = PracticeResult(title: exercise.title, date: Date(), count: progress.position, mistakes: progress.mistakes, accuracy: progress.accuracy, seconds: seconds)
        latestResult = result
        results.insert(result, at: 0); results = Array(results.prefix(30))
        if let data = try? JSONEncoder().encode(results) { defaults.set(data, forKey: "results") }
        feedback = "完成了！每一次练习都在进步。"
        pause(); showResult = true
    }
}
