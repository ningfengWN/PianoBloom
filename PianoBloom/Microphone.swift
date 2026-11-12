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
    var polyphonic = false
    var reference = Music.standardC
    var onStop: (() -> Void)?
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
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)
            let e = AVAudioEngine()
            engine = e
            let input = e.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate >= 8000, format.channelCount > 0 else {
                throw NSError(domain: "PianoBloom", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有找到可用的麦克风"])
            }
            let analyzer = StreamAnalyzer(rate: format.sampleRate, polyphonic: polyphonic, reference: reference)
            let capacity = DispatchSemaphore(value: 2)
            input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, audioTime in
                guard let self, let channel = buffer.floatChannelData?[0],
                      capacity.wait(timeout: .now()) == .success else { return }
                // Copy before leaving the callback: AVAudioEngine owns the buffer memory.
                let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                let endTime = (audioTime.isHostTimeValid ? AVAudioTime.seconds(forHostTime: audioTime.hostTime) : ProcessInfo.processInfo.systemUptime) + Double(buffer.frameLength) / format.sampleRate
                self.queue.async {
                    defer { capacity.signal() }
                    guard let frame = analyzer.append(samples, endTime: endTime) else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == token, self.listening else { return }
                        self.level = frame.rms
                        self.onFrame?(frame)
                    }
                }
            }
            tapInstalled = true
            e.prepare()
            try e.start()
            state = .listening
            onReady?()
        } catch {
            stop()
            state = .failed(error.localizedDescription)
        }
    }
    func stop() {
        generation = UUID() // Discard queued frames and cancelled permission callbacks.
        engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0) }
        tapInstalled = false
        engine = nil
        state = .stopped
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
        if polyphonic {
            var poly = PolyphonicDetector.analyze(window, sampleRate: rate, reference: reference, time: endTime)
            if let onsetTime, endTime - onsetTime < 0.22 { poly.onsetTime = onsetTime }
            frame.polyphony = poly
        }
        return frame
    }
}
