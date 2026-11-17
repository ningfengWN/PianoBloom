import AVFoundation
import Combine
import Foundation

/// Owns one engine and one tap; UI updates and lifecycle changes are main-thread only.
final class Microphone: ObservableObject {
    enum State: Equatable { case stopped, requesting, listening, denied, failed(String) }
    @Published private(set) var state: State = .stopped
    @Published private(set) var level = 0.0
    var onReady: (() -> Void)?
    var onFrame: ((PitchFrame) -> Void)?
    var onModelEvents: (([ModelOnset]) -> Void)?
    var recognitionEngine: RecognitionEngine = .basic
    var modelAddress = ""
    var modelToken = ""
    @Published private(set) var processedThrough: Double?
    @Published private(set) var recognitionDelay = 0.0
    private var modelClient: OnsetsVelocitiesClient?
    var polyphonic = false
    var reference = Music.standardC
    var onStop: (() -> Void)?
    private var sessionToken: UUID?
    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var generation = UUID()
    private let queue = DispatchQueue(label: "com.pianobloom.analysis", qos: .userInitiated)
    private var observers: [NSObjectProtocol] = []
    var listening: Bool { state == .listening }
    var requesting: Bool { state == .requesting }

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            self?.stop()
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let value = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: value),
                  reason == .oldDeviceUnavailable || reason == .newDeviceAvailable else { return }
            if self?.listening == true { self?.stop() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in self?.stop() })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func start() {
        guard !listening, !requesting else { return }
        generation = UUID()
        let token = generation
        state = .requesting
        processedThrough = nil; recognitionDelay = 0
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.generation == token, self.state == .requesting else { return }
                if granted { self.open(token: token) } else { self.state = .denied; self.onStop?() }
            }
        }
    }
    private func open(token: UUID) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)
            sessionToken = AudioSessionOwnership.shared.claim(capturing: true)
            let e = AVAudioEngine()
            engine = e
            let input = e.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate >= 8000, format.channelCount > 0 else {
                throw NSError(domain: "PianoBloom", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有找到可用的麦克风"])
            }
            let usesModel = recognitionEngine == .onsetsVelocities
            let client = usesModel ? OnsetsVelocitiesClient() : nil
            modelClient = client
            let analyzer = StreamAnalyzer(rate: format.sampleRate, polyphonic: polyphonic, reference: reference)
            let capacity = DispatchSemaphore(value: 2)
            input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, audioTime in
                guard let self, let channel = buffer.floatChannelData?[0] else { return }
                guard capacity.wait(timeout: .now()) == .success else {
                    if usesModel { DispatchQueue.main.async { self.failModel("音频处理跟不上，已暂停。", token: token) } }
                    return
                }
                // Copy before leaving the callback: AVAudioEngine owns the buffer memory.
                let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                let endTime = (audioTime.isHostTimeValid ? AVAudioTime.seconds(forHostTime: audioTime.hostTime) : ProcessInfo.processInfo.systemUptime) + Double(buffer.frameLength) / format.sampleRate
                self.queue.async {
                    defer { capacity.signal() }
                    if let client {
                        client.append(samples, endTime: endTime)
                        let rms = sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, samples.count)))
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.generation == token, self.listening else { return }
                            self.level = rms
                        }
                        return
                    }
                    guard let frame = analyzer.append(samples, endTime: endTime) else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == token, self.listening else { return }
                        self.level = frame.rms
                        self.onFrame?(frame)
                    }
                }
            }
            tapInstalled = true
            if let client {
                client.onReady = { [weak self, weak e] delay in
                    guard let self, let e, self.generation == token, self.requesting else { return }
                    do {
                        e.prepare(); try e.start()
                        self.recognitionDelay = delay
                        self.state = .listening; self.onReady?()
                    } catch { self.failModel(error.localizedDescription, token: token) }
                }
                client.onEvents = { [weak self] events, through, delay in
                    guard let self, self.generation == token, self.listening else { return }
                    self.onModelEvents?(events)
                    guard self.generation == token, self.listening else { return }
                    self.processedThrough = through; self.recognitionDelay = delay
                }
                client.onFailure = { [weak self] message in self?.failModel(message, token: token) }
                client.start(address: modelAddress, token: modelToken, sampleRate: format.sampleRate)
            } else {
                e.prepare(); try e.start()
                state = .listening; onReady?()
            }
        } catch {
            stop()
            state = .failed(error.localizedDescription)
        }
    }
    private func failModel(_ message: String, token: UUID) {
        guard generation == token else { return }
        stop(); state = .failed(message)
    }
    func stop() {
        modelClient?.stop(); modelClient = nil
        generation = UUID() // Discard queued frames and cancelled permission callbacks.
        engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0) }
        tapInstalled = false
        engine = nil
        state = .stopped
        level = 0
        if let token = sessionToken {
            sessionToken = nil
            if AudioSessionOwnership.shared.release(token) {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
        onStop?()
    }
}

private final class StreamAnalyzer {
    private let stride: Int
    private let rate: Double
    private var partial = 0.0
    private var partialCount = 0
    private var samples: [Float] = []
    private var newCount = 0
    private let polyphonic: Bool
    private let reference: Double
    private var envelope = 0.0
    private var onsetTime: Double?
    init(rate: Double, polyphonic: Bool, reference: Double) {
        self.polyphonic = polyphonic; self.reference = reference
        stride = max(1, Int(ceil(rate / 16000)))
        self.rate = rate / Double(stride)
        samples.reserveCapacity(8192)
    }
    func append(_ input: [Float], endTime: Double) -> PitchFrame? {
        for x in input {
            partial += Double(x); partialCount += 1
            if partialCount == stride {
                samples.append(Float(partial / Double(stride)))
                newCount += 1; partial = 0; partialCount = 0
            }
        }
        let count = polyphonic ? 4096 : 2048
        guard samples.count >= count, newCount >= 256 else { return nil }
        let window = Array(samples.suffix(count))
        samples = window
        newCount = 0
        let short = window.suffix(256)
        let level = sqrt(short.reduce(0.0) { $0 + Double($1 * $1) } / Double(short.count))
        if level > max(0.005, envelope * 1.7) { onsetTime = endTime - Double(short.count) / rate }
        envelope = max(level, envelope * 0.87)
        var frame = PitchDetector.analyze(Array(window.suffix(2048)), sampleRate: rate, time: endTime)
        if let onsetTime, endTime - onsetTime < 0.22 { frame.onsetTime = onsetTime }
        if polyphonic {
            var poly = PolyphonicDetector.analyze(window, sampleRate: rate, reference: reference, time: endTime)
            if let onsetTime, endTime - onsetTime < 0.22 { poly.onsetTime = onsetTime }
            frame.polyphony = poly
        }
        return frame
    }
}

/// Local note demonstration, not a prerecorded teacher video. Input is stopped before playback.
final class PianoDemonstrator {
    private var sessionToken: UUID?
    private var player: AVAudioPlayer?
    private let speaker = AVSpeechSynthesizer()
    func speak(_ text: String) {
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            sessionToken = AudioSessionOwnership.shared.claim()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = 0.44
            speaker.speak(utterance)
        } catch { /* The same instruction remains visible when audio is unavailable. */ }
    }
    var isPlaying: Bool { player?.isPlaying == true }
    var playbackTime: Double { player?.currentTime ?? 0 }
    var outputDescription: String {
        let session = AVAudioSession.sharedInstance()
        if session.outputVolume < 0.01 { return "设备媒体音量为 0，请调高音量。" }
        return "正在试听 · " + session.currentRoute.outputs.map(\.portName).joined(separator: "、")
    }
    func play(score: PianoScore, hands: PracticeHands, bpm: Double) throws {
        stop()
        let data = try PianoPreviewAudio.wav(score: score, hands: hands, bpm: bpm)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        sessionToken = AudioSessionOwnership.shared.claim()
        let audio = try AVAudioPlayer(data: data)
        audio.volume = 1
        guard audio.prepareToPlay(), audio.play() else { throw PianoPreviewError.playback }
        player = audio
    }
    func stop() {
        player?.stop(); player = nil
        if speaker.isSpeaking || speaker.isPaused { speaker.stopSpeaking(at: .immediate) }
        if let token = sessionToken {
            sessionToken = nil
            if AudioSessionOwnership.shared.release(token) { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        }
    }
}
