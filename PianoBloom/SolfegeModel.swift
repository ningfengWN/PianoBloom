import AVFoundation
import SwiftUI

enum SolfegeActivity: String, CaseIterable { case listen = "听唱谱", sing = "我来唱" }

/// Collects system Chinese speech in memory. Rendering, not pitchMultiplier,
/// tunes the voiced syllables to exact score periods and lengths.
private final class SolfegeVoiceBank: NSObject, AVSpeechSynthesizerDelegate {
    private var speech: AVSpeechSynthesizer?
    private var utterance: AVSpeechUtterance?
    private var samples: [String: SolfegeVoiceSample] = [:]
    private var generation = UUID()
    private var collected: [Float] = []
    private var rate = 22050.0
    private var finishWord: ((Result<SolfegeVoiceSample, Error>) -> Void)?
    func stop() {
        generation = UUID(); finishWord = nil; utterance = nil
        speech?.delegate = nil
        if speech?.isSpeaking == true { speech?.stopSpeaking(at: .immediate) }
        speech = nil; collected = []
    }
    func prepare(words: [String], progress: @escaping (Int, Int) -> Void,
                 completion: @escaping (Result<[String: SolfegeVoiceSample], Error>) -> Void) {
        stop()
        let id = generation
        func next(_ index: Int) {
            guard self.generation == id else { return }
            if index == words.count { completion(.success(self.samples)); return }
            progress(index, words.count)
            let word = words[index]
            if self.samples[word] != nil { next(index + 1); return }
            guard let voice = AVSpeechSynthesisVoice(language: "zh-CN") else {
                completion(.failure(VoiceError.unavailable)); return
            }
            // A fresh writer avoids cancel/requeue races with an earlier utterance.
            let writer = AVSpeechSynthesizer()
            writer.delegate = self
            self.speech = writer
            self.collected = []; self.rate = 22050
            let utterance = AVSpeechUtterance(string: word)
            utterance.voice = voice; utterance.rate = 0.42
            self.utterance = utterance
            self.finishWord = { result in
                guard self.generation == id else { return }
                switch result {
                case .failure(let error): self.stop(); completion(.failure(error))
                case .success(let sample):
                    self.samples[word] = sample
                    // Leave the writer's terminal callback before preparing the next syllable.
                    DispatchQueue.main.async { next(index + 1) }
                }
            }
            writer.write(utterance) { [weak self, weak writer] buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                let count = Int(pcm.frameLength), channels = Int(pcm.format.channelCount)
                let sampleRate = pcm.format.sampleRate
                var values = [Float](repeating: 0, count: count)
                if channels > 0, let data = pcm.floatChannelData {
                    for frame in 0..<count {
                        for channel in 0..<channels {
                            values[frame] += pcm.format.isInterleaved ? data[0][frame * channels + channel] / Float(channels) : data[channel][frame] / Float(channels)
                        }
                    }
                } else if channels > 0, let data = pcm.int16ChannelData {
                    for frame in 0..<count {
                        for channel in 0..<channels {
                            let value = pcm.format.isInterleaved ? data[0][frame * channels + channel] : data[channel][frame]
                            values[frame] += Float(value) / (32768 * Float(channels))
                        }
                    }
                }
                DispatchQueue.main.async {
                    guard let self, let writer, self.generation == id,
                          self.speech === writer, self.finishWord != nil else { return }
                    if count <= 1 { self.completeWord() }
                    else {
                        self.collected += values; self.rate = sampleRate
                        if self.collected.count > Int(sampleRate * 5) { self.failWord(VoiceError.unavailable) }
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak writer] in
                guard let self, let writer, self.generation == id, self.speech === writer,
                      self.finishWord != nil else { return }
                self.failWord(VoiceError.timeout)
            }
        }
        next(0)
    }
    private func completeWord() {
        guard let finish = finishWord else { return }
        finishWord = nil
        guard !collected.isEmpty else { finish(.failure(VoiceError.unavailable)); return }
        finish(.success(SolfegeVoiceSample(samples: collected, sampleRate: rate)))
    }
    private func failWord(_ error: Error) {
        let finish = finishWord; finishWord = nil; finish?(.failure(error))
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.speech === synthesizer, self.utterance === utterance else { return }
            self.completeWord()
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.speech === synthesizer, self.utterance === utterance else { return }
            self.failWord(VoiceError.unavailable)
        }
    }
    enum VoiceError: LocalizedError {
        case unavailable, render, timeout, playback
        var errorDescription: String? {
            switch self {
            case .unavailable: return "系统中文语音暂不可用。请在系统设置的朗读内容中下载中文语音，再返回重试。"
            case .render: return "当前中文语音无法合成唱谱，请更换中文语音后重试。"
            case .timeout: return "唱谱准备超时，已停止。可以点击重试；若仍失败，请确认系统中文语音已下载。"
            case .playback: return "唱谱声音未能开始播放，请重试。"
            }
        }
    }
}

final class SolfegeModel: ObservableObject {
    let score: PianoScore
    let bpm: Double
    let countdownSound: Bool
    let microphone = Microphone()
    @Published var activity: SolfegeActivity = .listen
    @Published var hand: PracticeHands = .right
    @Published var octave = 0
    @Published private(set) var preparing = false
    @Published private(set) var preparationProgress = 0.0
    @Published private(set) var preparationFailed = false
    @Published private(set) var running = false
    @Published private(set) var completed = false
    @Published private(set) var elapsed = 0.0
    @Published private(set) var assessment: SingingAssessment
    @Published private(set) var feedback = "先听 App 唱一遍，再试着自己唱。"
    private let bank = SolfegeVoiceBank()
    private let countSound = CountInSound()
    private let renderQueue = DispatchQueue(label: "com.pianobloom.solfege.render", qos: .userInitiated)
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var epoch: Double?
    private var generation = UUID()
    private var preparationJob: SolfegePreparationJob?
    var notes: [SingingNote] { assessment.notes }
    var position: Int {
        if activity == .sing { return assessment.position }
        return notes.lastIndex(where: { $0.start <= elapsed }) ?? 0
    }
    var scorePosition: Int { completed && activity == .listen ? score.events.count : (position < notes.count ? notes[position].sourceIndex : score.events.count) }
    var countIn: Int? { running && activity == .sing && elapsed < 0 ? Int(ceil(-elapsed / (60 / bpm))) : nil }
    var judgments: [Int: EventJudgment] {
        Dictionary(uniqueKeysWithValues: assessment.results.map { index, result in
            let note = notes[index]
            let heard: Set<Int> = result.cents.map { Set([Int((Double(note.midi) + $0 / 100).rounded())]) } ?? []
            return (note.sourceIndex, EventJudgment(grade: result.grade, error: result.timingError, heard: heard))
        })
    }
    init(score: PianoScore, bpm: Double, countdownSound: Bool) {
        self.score = score; self.bpm = bpm; self.countdownSound = countdownSound
        assessment = SingingAssessment(score: score, hand: .right, bpm: bpm, octave: 0)
        microphone.recognitionEngine = .basic // Human voice uses single-pitch YIN, never the piano model.
        microphone.polyphonic = false
        microphone.onReady = { [weak self] in self?.startSingingClock() }
        microphone.onFrame = { [weak self] frame in self?.receive(frame) }
        microphone.onStop = { [weak self] in
            guard let self, self.running, self.activity == .sing else { return }
            self.stop(); self.feedback = "聆听已暂停。"
        }
    }
    deinit { timer?.invalidate(); preparationJob?.cancel() }
    func configure() {
        stop()
        assessment = SingingAssessment(score: score, hand: hand, bpm: bpm, octave: octave)
        completed = false; elapsed = 0
    }
    func toggle() {
        if running || preparing || microphone.requesting { stop(); return }
        configure()
        guard !notes.isEmpty else { feedback = "这个声部没有可唱的音符。"; return }
        if activity == .listen { prepareSong() }
        else { microphone.start() }
    }
    func stop() {
        preparationJob?.cancel(); preparationJob = nil
        generation = UUID(); running = false; preparing = false
        timer?.invalidate(); timer = nil
        player?.stop(); player = nil; bank.stop(); countSound.stop()
        microphone.stop()
    }
    private func prepareSong() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { feedback = error.localizedDescription; return }
        preparing = true; preparationFailed = false; preparationProgress = 0
        feedback = "正在准备中文唱名…"
        let id = generation, sequence = notes, length = assessment.length
        guard length <= 600 else { preparing = false; feedback = "曲子较长，请先选一个小段唱谱。"; return }
        let job = SolfegePreparationJob(timeout: 30)
        preparationJob = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.generation == id, self.preparing else { return }
            self.failPreparation(SolfegeVoiceBank.VoiceError.timeout, id: id)
        }
        bank.prepare(words: Array(Set(notes.map { Solfege.word($0.midi) })).sorted(), progress: { [weak self] index, total in
            guard let self, self.generation == id else { return }
            self.preparationProgress = Double(index) / Double(max(1, total)) * 0.4
            self.feedback = "正在准备唱名 \(index + 1)/\(total)…"
        }) { [weak self] result in
            guard let self, self.generation == id else { return }
            switch result {
            case .failure(let error): self.failPreparation(error, id: id)
            case .success(let voices):
                self.renderQueue.async {
                    let rate = 16000.0
                    // Analyze each syllable once; reuse its voiced grain across pitches and lengths.
                    var grains: [String: SolfegeVoiceGrain] = [:]
                    for (word, voice) in voices {
                        guard let grain = SolfegeVoiceRenderer.prepare(voice, shouldCancel: { job.isCancelled }) else {
                            DispatchQueue.main.async {
                                self.failPreparation(job.isCancelled ? SolfegeVoiceBank.VoiceError.timeout : .render, id: id)
                            }; return
                        }
                        grains[word] = grain
                    }
                    var waveform = [Float](repeating: 0, count: Int((length + 0.15) * rate))
                    var cache: [String: [Float]] = [:]
                    for (index, note) in sequence.enumerated() {
                        guard !job.isCancelled else { return }
                        DispatchQueue.main.async {
                            guard self.generation == id, self.preparing else { return }
                            self.preparationProgress = 0.4 + 0.55 * Double(index) / Double(max(1, sequence.count))
                            self.feedback = "正在合成旋律 \(index + 1)/\(sequence.count)…"
                        }
                        let key = "\(note.midi)-\(note.duration)"
                        if cache[key] == nil {
                            guard let grain = grains[Solfege.word(note.midi)],
                                  let rendered = SolfegeVoiceRenderer.render(grain, midi: note.midi, duration: note.duration * 0.95, shouldCancel: { job.isCancelled }) else {
                                DispatchQueue.main.async {
                                    guard self.generation == id else { return }
                                    self.failPreparation(job.isCancelled ? SolfegeVoiceBank.VoiceError.timeout : .render, id: id)
                                }; return
                            }
                            cache[key] = rendered
                        }
                        let start = Int(note.start * rate)
                        for (offset, value) in cache[key]!.enumerated() where start + offset < waveform.count { waveform[start + offset] += value }
                    }
                    guard !job.isCancelled else { return }
                    let data = Self.wav(waveform, rate: UInt32(rate))
                    DispatchQueue.main.async {
                        guard self.generation == id else { return }
                        do {
                            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                            try AVAudioSession.sharedInstance().setActive(true)
                            self.player = try AVAudioPlayer(data: data)
                            guard let player = self.player, player.prepareToPlay(), player.play() else {
                                self.failPreparation(SolfegeVoiceBank.VoiceError.playback, id: id); return
                            }
                            self.preparationJob = nil; self.preparationProgress = 1
                            self.preparing = false; self.running = true
                            self.feedback = "合成唱谱示范 · 跟着亮起的音符一起唱。"
                            self.startTimer()
                        } catch { self.failPreparation(error, id: id) }
                    }
                }
            }
        }
    }
    private func failPreparation(_ error: Error, id: UUID) {
        guard generation == id else { return }
        stop() // Invalidates all late speech/render callbacks before a retry.
        preparationFailed = true; feedback = error.localizedDescription
    }
    private func startSingingClock() {
        guard activity == .sing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let countDuration = Double(score.beatsPerBar) * 60 / bpm
        epoch = now + countDuration; elapsed = -countDuration; running = true
        feedback = "预备，跟着倒计时，再唱亮起来的唱名。"
        if countdownSound { countSound.play(beats: score.beatsPerBar, secondsPerBeat: 60 / bpm, remaining: countDuration) }
        startTimer()
    }
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self, self.running else { return }
            if self.activity == .listen {
                self.elapsed = self.player?.currentTime ?? self.elapsed
                if self.elapsed >= self.assessment.length || self.player?.isPlaying == false {
                    self.stop(); self.completed = true; self.feedback = "听完啦，切换到“我来唱”试一试。"
                }
            } else if let epoch = self.epoch {
                self.elapsed = ProcessInfo.processInfo.systemUptime - epoch
                self.assessment.tick(self.elapsed)
                if self.assessment.position == self.notes.count {
                    self.stop(); self.completed = true; self.feedback = "唱完啦！看看音高和节奏，再练一次。"
                }
            }
        }
    }
    private func receive(_ frame: PitchFrame) {
        guard running, activity == .sing, let epoch else { return }
        // Pitch describes the middle of the YIN window; onset describes the attack.
        assessment.accept(frequency: frame.frequency, rms: frame.rms,
                          time: frame.time - epoch - 0.064,
                          onset: frame.onsetTime.map { $0 - epoch })
        if elapsed >= 0 { feedback = "用自己的声音唱，不要同时弹琴或播放伴奏。" }
    }
    private static func wav(_ values: [Float], rate: UInt32) -> Data {
        var data = Data()
        func word(_ value: UInt32, _ count: Int) { for i in 0..<count { data.append(UInt8((value >> (8 * i)) & 255)) } }
        let size = UInt32(values.count * 2)
        data.append(Data("RIFF".utf8)); word(36 + size, 4)
        data.append(Data("WAVEfmt ".utf8)); word(16, 4); word(1, 2); word(1, 2)
        word(rate, 4); word(rate * 2, 4); word(2, 2); word(16, 2)
        data.append(Data("data".utf8)); word(size, 4)
        let peak = max(0.5, values.map { abs($0) }.max() ?? 1)
        for value in values { word(UInt32(UInt16(bitPattern: Int16(max(-1, min(1, value / peak)) * 26000))), 2) }
        return data
    }
}
