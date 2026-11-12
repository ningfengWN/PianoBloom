import Foundation

enum PracticeHands: String, CaseIterable, Codable { case right = "右手", left = "左手", both = "双手" }
enum PlayStyle: String, CaseIterable { case follow = "跟谱练习", rhythm = "节奏挑战" }
enum PracticeMode: String, CaseIterable {
    case reading = "识谱", rhythm = "节奏", performance = "演奏", flow = "心流"
    var style: PlayStyle { self == .reading || self == .performance ? .follow : .rhythm }
    var waitsForCorrect: Bool { self == .performance }
    var instruction: String {
        switch self {
        case .reading: return "跟着音符练习，错音记下后继续。"
        case .rhythm: return "跟着固定节拍弹，留意起音时间。"
        case .performance: return "弹错时停在当前音符，弹对后自动继续。"
        case .flow: return "跟着节拍连续弹，错音、漏音和节奏问题结束后一起看。"
        }
    }
}

struct ScoreEvent: Equatable {
    let beat: Double
    let duration: Double
    let right: [Int]
    let left: [Int]
    func pitches(_ hands: PracticeHands) -> Set<Int> {
        Set(hands == .right ? right : hands == .left ? left : right + left)
    }
}

struct PianoScore: Identifiable {
    let id: String
    let title: String
    let detail: String
    let beatsPerBar: Int
    let events: [ScoreEvent]
    var isHanon: Bool { id.hasPrefix("hanon-") }
    var length: Double { (events.last.map { $0.beat + $0.duration }) ?? 0 }
    func excerpt(_ bar: Int?) -> PianoScore {
        guard let bar else { return self }
        let start = Double(bar * beatsPerBar)
        let selected = events.filter { $0.beat >= start && $0.beat < start + Double(beatsPerBar * 2) }
        return PianoScore(id: id, title: title, detail: "第 \(bar + 1)–\(bar + 2) 小节", beatsPerBar: beatsPerBar,
                          events: selected.map { ScoreEvent(beat: $0.beat - start, duration: $0.duration, right: $0.right, left: $0.left) })
    }
    static let all: [PianoScore] = starters + HanonScores.all
    static let starters: [PianoScore] = [
        PianoScore(id: "star", title: "小星星", detail: "双手启蒙改编 · 一起摘星星", beatsPerBar: 4, events: melody(
            [60,60,67,67,69,69,67,65,65,64,64,62,62,60,67,67,65,65,64,64,62,67,67,65,65,64,64,62,60,60,67,67,69,69,67,65,65,64,64,62,62,60],
            longAt: [6,13,20,27,34,41], bass: [48,53,48,55,48,55,48,55,48,53,48,55])),
        PianoScore(id: "ode", title: "欢乐颂", detail: "双手启蒙改编 · 小小音乐会", beatsPerBar: 4, events: melody(
            [64,64,65,67,67,65,64,62,60,60,62,64,64,62,62], longAt: [14], bass: [48,55,48,55])),
        PianoScore(id: "scale", title: "彩虹音阶", detail: "C 大调 · 双手相隔一个八度", beatsPerBar: 4,
                   events: [60,62,64,65,67,69,71,72,71,69,67,65,64,62,60].enumerated().map {
                       ScoreEvent(beat: Double($0.offset), duration: $0.offset == 14 ? 2 : 1, right: [$0.element], left: [$0.element - 12])
                   })
    ]
    private static func melody(_ notes: [Int], longAt: Set<Int>, bass: [Int]) -> [ScoreEvent] {
        var beat = 0.0
        return notes.enumerated().map { index, note in
            let duration = longAt.contains(index) ? 2.0 : 1.0
            defer { beat += duration }
            // One lower note per melody onset keeps both hands visible and individually testable.
            return ScoreEvent(beat: beat, duration: duration, right: [note], left: [bass[min(bass.count - 1, Int(beat) / 4)]])
        }
    }
}

/// Maps a practiced two-bar excerpt onto the complete, scrollable score.
/// Judgments remain local to the attempt; rendering never changes scoring scope.
struct ScoreDisplayMap {
    let indices: [Int]
    let beatOffset: Double
    init(score: PianoScore, sectionBar: Int?) {
        let offset = Double(sectionBar ?? 0) * Double(score.beatsPerBar)
        beatOffset = offset
        indices = score.events.indices.filter { index in
            sectionBar == nil || (score.events[index].beat >= offset && score.events[index].beat < offset + Double(score.beatsPerBar * 2))
        }
    }
    func globalIndex(_ localIndex: Int) -> Int? {
        indices.indices.contains(localIndex) ? indices[localIndex] : nil
    }
    func judgments(_ local: [Int: EventJudgment]) -> [Int: EventJudgment] {
        Dictionary(uniqueKeysWithValues: local.compactMap { index, value in globalIndex(index).map { ($0, value) } })
    }
    func positions(_ local: Set<Int>) -> Set<Int> { Set(local.compactMap(globalIndex)) }
}

enum NoteGrade: String { case perfect, early, late, wrong, missed }
struct EventJudgment {
    let grade: NoteGrade
    let error: Double?
    let heard: Set<Int>
}

/// Uses an absolute beat grid: late notes never move the grid or improve future scores.
/// Pause shifts its epoch; count-in and the final note's duration are part of the session.
struct Performance {
    let score: PianoScore
    let hands: PracticeHands
    let style: PlayStyle
    let bpm: Double
    let waitForCorrect: Bool
    private(set) var judgments: [Int: EventJudgment] = [:]
    private(set) var position = 0
    private(set) var epoch: Double?
    private(set) var pauseTime: Double?
    private(set) var mistakes = 0
    private(set) var mistakePositions = Set<Int>()
    private(set) var finished = false
    private var pending: Set<Int> = []
    private var pendingTime: Double?
    private var suppressUntil = -Double.infinity
    var secondsPerBeat: Double { 60 / bpm }
    // At slow tempos a sixteenth note still has its own nonoverlapping window.
    var window: Double {
        let spacing = score.events.dropFirst().enumerated().map { $0.element.beat - score.events[$0.offset].beat }.filter { $0 > 0 }.min() ?? 1
        return min(0.23, spacing * secondsPerBeat * 0.48)
    }
    var correctCount: Int { judgments.values.filter { $0.grade != .wrong && $0.grade != .missed }.count }
    var missedCount: Int { judgments.values.filter { $0.grade == .missed }.count }
    var earlyCount: Int { judgments.values.filter { $0.grade == .early }.count }
    var lateCount: Int { judgments.values.filter { $0.grade == .late }.count }
    var pitchScore: Int {
        let pendingMistakes = waitForCorrect ? mistakePositions.filter { judgments[$0] == nil }.count : 0
        let denominator = finished ? score.events.count : judgments.count + pendingMistakes
        let correctedMistakes = mistakePositions.filter { judgments[$0] != nil }.count
        let firstTryCorrect = waitForCorrect ? max(0, correctCount - correctedMistakes) : correctCount
        return Int((100 * Double(firstTryCorrect) / Double(max(1, denominator))).rounded())
    }
    var rhythmScore: Int? {
        guard style == .rhythm, !judgments.isEmpty else { return nil }
        let sum = judgments.values.reduce(0.0) { value, judgment in
            guard let error = judgment.error, judgment.grade != .wrong && judgment.grade != .missed else { return value }
            return value + max(0, 1 - abs(error) / window)
        }
        let denominator = finished ? score.events.count : judgments.count
        return Int((100 * sum / Double(max(1, denominator))).rounded())
    }
    init(score: PianoScore, hands: PracticeHands, style: PlayStyle, bpm: Double, waitForCorrect: Bool = false) {
        self.score = score; self.hands = hands; self.style = style; self.bpm = min(160, max(20, bpm))
        self.waitForCorrect = waitForCorrect && style == .follow
    }
    mutating func start(at time: Double) {
        if let pauseTime, let epoch { self.epoch = epoch + time - pauseTime; self.pauseTime = nil }
        else if epoch == nil { epoch = time + Double(score.beatsPerBar) * secondsPerBeat }
        pending = []; pendingTime = nil; suppressUntil = -Double.infinity
    }
    mutating func pause(at time: Double) {
        guard epoch != nil, pauseTime == nil else { return }
        pauseTime = time; pending = []; pendingTime = nil
    }
    func beat(at time: Double) -> Double { ((pauseTime ?? time) - (epoch ?? time)) / secondsPerBeat }
    func expectedTime(_ index: Int) -> Double { (epoch ?? 0) + score.events[index].beat * secondsPerBeat }
    mutating func tick(at time: Double) {
        guard style == .rhythm, epoch != nil, pauseTime == nil, !finished else { return }
        while position < score.events.count, time > expectedTime(position) + window {
            if judgments[position] == nil { judgments[position] = EventJudgment(grade: .missed, error: nil, heard: []) }
            position += 1; pending = []; pendingTime = nil
        }
        if position == score.events.count, time >= (epoch ?? time) + score.length * secondsPerBeat { finished = true }
    }
    @discardableResult mutating func play(_ notes: Set<Int>, at time: Double, groupingWindow: Double = 0.09) -> NoteGrade? {
        guard !finished, pauseTime == nil, let epoch, !notes.isEmpty else { return nil }
        if style == .rhythm { tick(at: time); if time < epoch - window { return nil } }
        else if time < epoch { return nil }
        guard position < score.events.count, time >= suppressUntil else { return nil }
        let target = score.events[position].pitches(hands)
        guard !target.isEmpty else { return nil }
        let error = time - expectedTime(position)
        if style == .rhythm && error < -window { return nil }
        if let pendingTime, time - pendingTime > groupingWindow { pending = []; self.pendingTime = nil }
        if pendingTime == nil { pendingTime = time }
        pending.formUnion(notes)
        if !pending.isSubset(of: target) {
            mistakePositions.insert(position)
            mistakes += 1
            let heard = pending
            pending = []; pendingTime = nil
            // Other packets from the same chord are ignored in both modes.
            suppressUntil = time + max(0, min(groupingWindow, window))
            if waitForCorrect { return .wrong }
            judgments[position] = EventJudgment(grade: .wrong, error: style == .rhythm ? error : nil, heard: heard)
            position += 1
            if style == .follow { finished = position == score.events.count }
            return .wrong
        }
        guard pending == target else { return nil } // One hand alone never passes a two-hand event.
        let onsetError = (pendingTime ?? time) - expectedTime(position)
        let grade: NoteGrade = style == .follow || abs(onsetError) <= window * 0.3 ? .perfect : (onsetError < 0 ? .early : .late)
        judgments[position] = EventJudgment(grade: grade, error: style == .rhythm ? onsetError : nil, heard: pending)
        pending = []; pendingTime = nil
        position += 1
        if style == .follow { finished = position == score.events.count }
        return grade
    }
}

/// Byte-stream parser shared by all CoreMIDI packets for one source.
/// Handles running status, realtime interleaving, sysex, note-off and velocity zero.
struct MIDIByteParser {
    private var status: UInt8 = 0
    private var data: [UInt8] = []
    private var sysex = false
    mutating func feed(_ bytes: [UInt8]) -> [(note: Int, on: Bool)] {
        var events: [(Int, Bool)] = []
        for byte in bytes {
            if byte >= 0xF8 { continue }
            if byte == 0xF0 { sysex = true; status = 0; data = []; continue }
            if byte == 0xF7 { sysex = false; continue }
            if sysex { continue }
            if byte & 0x80 != 0 { status = byte < 0xF0 ? byte : 0; data = []; continue }
            guard status != 0 else { continue }
            data.append(byte)
            let length = (status & 0xF0 == 0xC0 || status & 0xF0 == 0xD0) ? 1 : 2
            if data.count == length {
                let command = status & 0xF0
                if command == 0x90 || command == 0x80 { events.append((Int(data[0]), command == 0x90 && data[1] > 0)) }
                data = []
            }
        }
        return events
    }
}

// A serializable learning path. Unlocks depend on completed attempts, never elapsed app time.
enum GuidedStage: String, Codable, CaseIterable {
    case right, left, both, flow, concert, finished
    var title: String {
        switch self {
        case .right: return "右手小段"
        case .left: return "左手小段"
        case .both: return "双手合练"
        case .flow: return "节奏挑战"
        case .concert: return "小小演奏家"
        case .finished: return "整曲完成"
        }
    }
    var hands: PracticeHands { self == .right ? .right : self == .left ? .left : .both }
    var style: PlayStyle { self == .flow ? .rhythm : .follow }
    var instruction: String {
        switch self {
        case .right: return "先听一遍，再用右手弹亮起来的音符。"
        case .left: return "轮到左手啦，右手休息一下。"
        case .both: return "两只手一起试试。音符分达到 70 分，或完整练习 3 遍，进入节奏挑战。"
        case .flow: return "跟着固定拍子弹，音符和节奏都达到 90 分，或完整练习 3 遍，进入演奏。"
        case .concert: return "弹错会停在当前音符，看看提示，弹对后继续。"
        case .finished: return "每个小乐段，都开出一朵花！"
        }
    }
}
struct GuidedJourney: Codable, Equatable {
    var phrase = 0
    var stage: GuidedStage = .right
    var attempts = 0
    var wholeSong = false
    var complete: Bool { stage == .finished }
    mutating func chooseHand(_ hands: PracticeHands) {
        stage = hands == .right ? .right : hands == .left ? .left : .both
        attempts = 0
    }
    mutating func record(pitch: Int, rhythm: Int?, phraseCount: Int) {
        guard !complete else { return }
        attempts += 1
        switch stage {
        case .right: stage = .left; attempts = 0
        case .left: stage = .both; attempts = 0
        case .both:
            if pitch >= 70 || attempts >= 3 { stage = .flow; attempts = 0 }
        case .flow:
            if (pitch >= 90 && (rhythm ?? 0) >= 90) || attempts >= 3 { stage = .concert; attempts = 0 }
        case .concert:
            guard pitch >= 90 || attempts >= 3 else { return }
            attempts = 0
            if wholeSong { stage = .finished }
            else if phrase + 1 < max(1, phraseCount) { phrase += 1; stage = .right }
            else { wholeSong = true }
        case .finished: break
        }
    }
}
