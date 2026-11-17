import SwiftUI
import UIKit

struct SolfegeScreen: View {
    @StateObject private var model: SolfegeModel
    @ObservedObject private var microphone: Microphone
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    init(score: PianoScore, bpm: Double, countdownSound: Bool) {
        let model = SolfegeModel(score: score, bpm: bpm, countdownSound: countdownSound)
        _model = StateObject(wrappedValue: model)
        microphone = model.microphone
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 12) {
                    Text(model.score.title).font(.title2.bold()).foregroundStyle(Bloom.ink)
                    Picker("唱谱模式", selection: $model.mode) {
                        ForEach(SingingMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    HStack(spacing: 12) {
                        Picker("声部", selection: $model.hand) {
                            Text("右手旋律").tag(PracticeHands.right)
                            Text("左手旋律").tag(PracticeHands.left)
                        }.pickerStyle(.segmented).frame(maxWidth: 260)
                        Picker("唱谱音区", selection: $model.octave) {
                            Text("低八度").tag(-1)
                            Text("原谱音区").tag(0)
                            Text("高八度").tag(1)
                            Text("高两八度").tag(2)
                        }.pickerStyle(.menu)
                        Spacer(minLength: 0)
                        Text("\(Int(model.bpm)) BPM").font(.caption.monospacedDigit())
                    }
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.feedback).font(.subheadline).foregroundStyle(Bloom.ink)
                            Text(model.activity == .listen ? "本机合成唱谱 · 非真人录音" : "仅评音高与起音 · 不评唱名发音，不要同时弹琴")
                                .font(.caption).foregroundStyle(Bloom.lilac)
                        }
                        Spacer(minLength: 0)
                        if model.preparing {
                            VStack(spacing: 4) {
                                ProgressView(value: model.preparationProgress).frame(width: 70)
                                Text("\(Int(model.preparationProgress * 100))%").font(.caption.monospacedDigit())
                            }
                        }
                        if let count = model.countIn { Text("\(count)").font(.largeTitle.bold()).foregroundStyle(Bloom.pink) }
                    }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    SolfegeScore(model: model, wide: geometry.size.width > 700)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                    if model.activity == .sing, !model.singingResults.isEmpty {
                        VStack(spacing: 4) {
                            Text(model.mode == .follow ? "音高 \(model.singingPitchScore) 分" : "音高 \(model.singingPitchScore) 分 · 节奏 \(model.assessment.rhythmScore.map { "\($0) 分" } ?? "待确认")")
                                .font(.headline).foregroundStyle(Bloom.ink)
                            Text(model.mode == .follow ? "识谱模式不评价节奏；唱对后继续。" : "已评 \(model.singingResults.count)/\(model.notes.count) 个音 · 检测到 \(model.assessment.timingCount) 个清晰起音")
                                .font(.caption).foregroundStyle(Bloom.lilac)
                        }
                    }
                    if microphone.state == .denied {
                        Button("打开系统设置，允许麦克风") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                    }
                    if case let .failed(message) = microphone.state { Text(message).font(.caption).foregroundStyle(.orange) }
                    HStack {
                        Button("听示范") { model.listen() }.buttonStyle(.bordered)
                        Button { if model.preparing || model.running || microphone.requesting { model.stop() } else { model.startPractice() } } label: {
                            Label(model.preparing || model.running || microphone.requesting ? "停止" : "开始唱谱", systemImage: model.running ? "stop.fill" : "mic.fill")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 38)
                        }.buttonStyle(.borderedProminent).clipShape(Capsule())
                    }
                    Text("和弦取所选声部最高音，唱单旋律；升降音按谱面音高示范。")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(geometry.size.width > 700 ? 22 : 12).background(Bloom.blush)
            }
            .navigationTitle("唱谱小舞台").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { model.stop(); dismiss() } } }
        }
        .tint(Bloom.pink).interactiveDismissDisabled()
        .onChange(of: model.mode) { _ in model.configure() }
        .onChange(of: model.hand) { _ in model.configure() }
        .onChange(of: model.octave) { _ in model.configure() }
        .onChange(of: scenePhase) { phase in if phase != .active { model.stop() } }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { model.stop(); UIApplication.shared.isIdleTimerDisabled = false }
    }
}

private struct SolfegeScore: View {
    @ObservedObject var model: SolfegeModel
    let wide: Bool
    private var displayScale: Double { (wide ? 1.35 : 1.05) * 1.16 }
    private var layout: ScoreRowLayout { ScoreRowLayout(score: model.score) }
    private var focusRow: Int { layout.row(forEvent: model.scorePosition) }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(layout.rows.indices, id: \.self) { row in
                        let line = layout.rows[row]
                        StaffSystem(score: model.score, start: line.events.lowerBound, count: line.events.count, measureRange: line.bars,
                            judgments: model.judgments, mistakePositions: [], style: .follow,
                            flowMode: false, grayPositions: [], position: model.scorePosition,
                            notationScale: displayScale, hands: model.hand,
                            beat: model.elapsed * model.bpm / 60, running: model.running,
                            pops: [], popCompleted: { _ in }, showsNoteNames: false)
                            .frame(height: 236 * displayScale).id(row)
                    }
                }.padding(.horizontal, 8).padding(.vertical, 10)
            }
            .onChange(of: focusRow) { row in
                if model.running { withAnimation { proxy.scrollTo(row, anchor: .top) } }
            }
            .onChange(of: model.activity) { _ in proxy.scrollTo(0, anchor: .top) }
        }
    }
}
