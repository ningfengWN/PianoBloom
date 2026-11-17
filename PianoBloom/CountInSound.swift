import AVFoundation

/// One pre-rendered bar keeps countdown clicks on the audio clock, not a UI timer.
final class CountInSound {
    private var sessionToken: UUID?
    private var player: AVAudioPlayer?
    func play(beats: Int, secondsPerBeat: Double, remaining: Double, looping: Bool = false) {
        stop()
        guard remaining > 0, secondsPerBeat > 0 else { return }
        let rate = 22050.0
        let duration = Double(beats) * secondsPerBeat
        var samples = [Float](repeating: 0, count: Int(duration * rate))
        for beat in 0..<beats {
            let start = Int(Double(beat) * secondsPerBeat * rate)
            let frequency = beat == beats - 1 ? 1320.0 : 880.0
            for i in 0..<Int(min(looping ? 0.080 : 0.045, secondsPerBeat * 0.2) * rate) where start + i < samples.count {
                let t = Double(i) / rate
                if looping {
                    // An unpitched click with a longer body remains audible over piano practice.
                    let noise = Double.random(in: -1...1)
                    samples[start + i] = Float(noise * exp(-t * 80) * min(1, t / 0.0007) * (beat == 0 ? 0.90 : 0.62))
                } else {
                    samples[start + i] = Float(sin(2 * .pi * frequency * t) * exp(-t * 90) * min(1, t / 0.002) * 0.22)
                }
            }
        }
        var data = Data()
        func word(_ value: UInt32, _ count: Int) { for i in 0..<count { data.append(UInt8((value >> (8 * i)) & 255)) } }
        let bytes = UInt32(samples.count * 2)
        data.append(Data("RIFF".utf8)); word(36 + bytes, 4)
        data.append(Data("WAVEfmt ".utf8)); word(16, 4); word(1, 2); word(1, 2)
        word(UInt32(rate), 4); word(UInt32(rate * 2), 4); word(2, 2); word(16, 2)
        data.append(Data("data".utf8)); word(bytes, 4)
        for value in samples { word(UInt32(UInt16(bitPattern: Int16(value * 32767))), 2) }
        do {
            let session = AVAudioSession.sharedInstance()
            // Microphone sessions already use playAndRecord; never reconfigure a live input engine.
            let usesCapture = session.category == .playAndRecord && AudioSessionOwnership.shared.hasCapture
            if !usesCapture { try session.setCategory(.playback, mode: .default) }
            try session.setActive(true)
            if !usesCapture { sessionToken = AudioSessionOwnership.shared.claim() }
            player = try AVAudioPlayer(data: data)
            player?.volume = 1
            player?.numberOfLoops = looping ? -1 : 0
            player?.currentTime = min(duration - 1 / rate, max(0, duration - remaining))
            player?.prepareToPlay(); player?.play()
        } catch { stop() } // Visual countdown is retained if output is unavailable.
    }
    func stop() {
        player?.stop(); player = nil
        if let token = sessionToken {
            sessionToken = nil
            if AudioSessionOwnership.shared.release(token) { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        }
    }
}
