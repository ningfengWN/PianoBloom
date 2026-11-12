import SwiftUI
import AVFoundation

@main struct PianoBloomApp: App {
    var body: some Scene { WindowGroup { PracticeView() } }
}

final class Listener: ObservableObject {
    @Published var frequency: Double = 0
    @Published var message = "点击开始，允许麦克风访问"
    @Published var active = false
    var onPitch: ((Double) -> Void)?
    private var engine: AVAudioEngine?
    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else { self.message = "请在系统设置中允许麦克风访问"; return }
                self.open()
            }
        }
    }
    private func open() {
        guard !active else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            let e = AVAudioEngine()
            let input = e.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { message = "未找到可用麦克风"; return }
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                guard let channel = buffer.floatChannelData?[0] else { return }
                let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                let f = Self.pitch(samples, rate: buffer.format.sampleRate)
                DispatchQueue.main.async {
                    guard let self, self.active else { return }
                    self.frequency = f ?? 0
                    if let f { self.onPitch?(f) }
                }
            }
            engine = e
            try e.start()
            active = true
            message = "正在聆听 · 请一次弹一个音"
        } catch { stop(); message = "麦克风启动失败：\(error.localizedDescription)" }
    }
    func stop() {
        active = false
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        frequency = 0
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    // Normalized difference (YIN). Return nil for quiet or ambiguous frames.
    static func pitch(_ x: [Float], rate: Double) -> Double? {
        let n = x.count / 2
        guard n > 32 else { return nil }
        let rms = sqrt(x.reduce(0.0) { $0 + Double($1 * $1) } / Double(x.count))
        guard rms > 0.004 else { return nil }
        let limit = min(n - 2, Int(rate / 100))
        let first = max(2, Int(rate / 1100))
        guard limit > first else { return nil }
        var d = [Double](repeating: 1, count: limit + 2)
        var sum = 0.0
        for lag in 1...limit {
            var value = 0.0
            for i in 0..<n { let delta = Double(x[i] - x[i + lag]); value += delta * delta }
            sum += value
            d[lag] = sum > 0 ? value * Double(lag) / sum : 1
        }
        var lag = first
        while lag < limit - 1 {
            if d[lag] < 0.15 {
                while lag + 1 < limit && d[lag + 1] < d[lag] { lag += 1 }
                let denom = d[lag - 1] - 2 * d[lag] + d[lag + 1]
                let correction = abs(denom) > 1e-9 ? 0.5 * (d[lag - 1] - d[lag + 1]) / denom : 0
                return rate / (Double(lag) + correction)
            }
            lag += 1
        }
        return nil
    }
}

struct PracticeView: View {
    @StateObject private var listener = Listener()
    @Environment(\.scenePhase) private var phase
    @State private var reference = 261.625565
    @State private var calibrating = false
    @State private var calibration: [Double] = []
    @State private var position = 0
    @State private var feedback = "先校准中央 C，再开始练习"
    @State private var lastAccepted = Date.distantPast
    @State private var candidate = -1
    @State private var stable = 0
    @State private var exercise = 0
    @State private var lastNote = -1
    @State private var released = true
    private let titles = ["中央 C 音阶", "欢乐颂 · 单音"]
    private let scores = [[60,62,64,65,67,69,71,72], [64,64,65,67,67,65,64,62,60,60,62,64,64,62,62]]
    private var notes: [Int] { scores[exercise] }
    private func name(_ midi: Int) -> String {
        let names = ["C","C♯","D","D♯","E","F","F♯","G","G♯","A","A♯","B"]
        return names[(midi % 12 + 12) % 12] + String(midi / 12 - 1)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("琴芽 · PianoBloom").font(.largeTitle.bold())
                Text("麦克风单音陪练").foregroundStyle(.secondary)
                Picker("练习曲", selection: $exercise) {
                    ForEach(0..<titles.count, id: \.self) { Text(titles[$0]).tag($0) }
                }.pickerStyle(.segmented).onChange(of: exercise) { _ in reset() }
                VStack(spacing: 8) {
                    Text(listener.frequency > 0 ? name(Int((60 + 12 * log2(listener.frequency / reference)).rounded())) : "—")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                    Text(listener.frequency > 0 ? String(format: "%.1f Hz", listener.frequency) : "等待琴声").monospacedDigit()
                    Text(listener.message).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding().background(.white, in: RoundedRectangle(cornerRadius: 24))
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(Array(notes.enumerated()), id: \.offset) { i, note in
                            VStack {
                                ZStack {
                                    Path { p in
                                        for y in stride(from: 24, through: 72, by: 12) {
                                            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: 58, y: y))
                                        }
                                        if note == 60 { p.move(to: CGPoint(x: 13, y: 84)); p.addLine(to: CGPoint(x: 43, y: 84)) }
                                    }.stroke(.gray.opacity(0.5), lineWidth: 1)
                                    let steps = [60:0,62:1,64:2,65:3,67:4,69:5,71:6,72:7]
                                    let y = CGFloat(84 - (steps[note] ?? 0) * 6)
                                    Ellipse().fill(i < position ? Color.green : (i == position ? Color.indigo : Color.primary)).frame(width: 17, height: 12).position(x: 29, y: y)
                                    Path { p in p.move(to: CGPoint(x: 37, y: y)); p.addLine(to: CGPoint(x: 37, y: y - 30)) }.stroke(i < position ? Color.green : Color.primary, lineWidth: 2)
                                }.frame(width: 58, height: 110)
                                Text(name(note)).font(.caption).foregroundStyle(i == position ? .indigo : .secondary)
                            }.background(i == position ? Color.indigo.opacity(0.1) : .clear)
                        }
                    }
                }.padding().background(.white, in: RoundedRectangle(cornerRadius: 20))
                Text(feedback).font(.headline).accessibilityLabel(feedback)
                ProgressView(value: Double(position), total: Double(notes.count)).tint(.green)
                HStack {
                    Button(listener.active ? "停止聆听" : "开始聆听") {
                        if listener.active { listener.stop() } else { listener.onPitch = receive; listener.start() }
                    }.buttonStyle(.borderedProminent)
                    Button("校准中央 C") {
                        calibration = []; calibrating = true; feedback = "请弹中央 C，并保持片刻"
                        listener.onPitch = receive
                        if !listener.active { listener.start() }
                    }.buttonStyle(.bordered)
                    Button("重练") { reset() }.buttonStyle(.bordered)
                }.controlSize(.large)
                Text("校准基准：\(reference, specifier: "%.2f") Hz\n适用 C3–C6 附近的单音。请关闭踏板，避免说话及伴奏；双手和弦暂不支持。重复音请重新按键，保持适当间隔。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.background(Color(red: 0.95, green: 0.96, blue: 0.99))
        .onChange(of: listener.frequency) { f in if f == 0 { released = true } }
        .onChange(of: phase) { value in if value != .active { listener.stop() } }
    }
    private func reset() { position = 0; lastNote = -1; released = true; stable = 0; candidate = -1; feedback = "请弹 \(name(notes[0]))" }
    private func receive(_ f: Double) {
        if calibrating {
            guard f > 240, f < 285 else { calibration = []; return }
            calibration.append(f)
            if calibration.count >= 8 {
                let average = calibration.reduce(0,+) / Double(calibration.count)
                guard calibration.allSatisfy({ abs(1200 * log2($0 / average)) < 15 }) else { calibration = []; return }
                reference = average; calibrating = false; feedback = "校准完成，请弹 \(name(notes[min(position, notes.count - 1)]))"
            }
            return
        }
        guard position < notes.count else { return }
        let pitch = 60 + 12 * log2(f / reference)
        let midi = Int(pitch.rounded())
        guard abs(pitch - Double(midi)) < 0.35 else { return }
        if candidate == midi { stable += 1 } else { candidate = midi; stable = 1 }
        guard stable >= 2, Date().timeIntervalSince(lastAccepted) > 0.45 else { return }
        if midi == notes[position] {
            guard midi != lastNote || released else { return }
            lastNote = midi; released = false
            position += 1; lastAccepted = Date(); stable = 0
            feedback = position == notes.count ? "完成！所有音符都弹对了 🎉" : "弹对了！下一个：\(name(notes[position]))"
        } else { feedback = "听到 \(name(midi))，请弹 \(name(notes[position]))" }
    }
}
