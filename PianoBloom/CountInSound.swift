import AVFoundation

/// One pre-rendered bar keeps countdown clicks on the audio clock, not a UI timer.
final class CountInSound {
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
            for i in 0..<Int(min(0.045, secondsPerBeat * 0.2) * rate) where start + i < samples.count {
                let t = Double(i) / rate
                if looping {
                    // A short unpitched click is less likely to resemble a piano note.
                    let noise = Double.random(in: -1...1)
                    samples[start + i] = Float(noise * exp(-t * 240) * min(1, t / 0.001) * (beat == 0 ? 0.35 : 0.20))
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
            if session.category != .playAndRecord { try session.setCategory(.playback, mode: .default) }
            try session.setActive(true)
            player = try AVAudioPlayer(data: data)
            player?.numberOfLoops = looping ? -1 : 0
            player?.currentTime = min(duration - 1 / rate, max(0, duration - remaining))
            player?.prepareToPlay(); player?.play()
        } catch { player = nil } // Visual countdown is retained if output is unavailable.
    }
    func stop() { player?.stop(); player = nil }
}
