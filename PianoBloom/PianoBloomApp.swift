import SwiftUI

@main
struct PianoBloomApp: App {
    @StateObject private var model = PracticeModel()
    var body: some Scene {
        WindowGroup { PracticeView(model: model).preferredColorScheme(.light) }
    }
}

private enum Palette {
    static let ink = Color(red: 0.12, green: 0.20, blue: 0.24)
    static let green = Color(red: 0.12, green: 0.47, blue: 0.38)
    static let cream = Color(red: 0.97, green: 0.97, blue: 0.94)
}

struct PracticeView: View {
    @ObservedObject var model: PracticeModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showHelp = false
    var body: some View {
        NavigationStack {
            practiceContent
            .background(Palette.cream)
            .navigationTitle("琴芽").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }.accessibilityLabel("使用帮助")
                    Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }.accessibilityLabel("练习记录")
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("设置")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ControlsView(model: model, microphone: model.microphone)
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                    .frame(maxWidth: 960).frame(maxWidth: .infinity)
                    .background(Palette.cream)
            }
            .sheet(isPresented: $showSettings) { SettingsView(model: model) }
            .sheet(isPresented: $showHistory) { HistoryView(model: model) }
            .sheet(isPresented: $showHelp) { HelpView() }
            .sheet(isPresented: $model.showResult) { ResultView(model: model) }
            .onChange(of: scenePhase) { phase in
                // Permission prompts make a scene inactive. Do not cancel their callbacks.
                if phase == .background { model.pause() }
            }
            .onChange(of: showSettings) { if $0 { model.pause() } }
            .onChange(of: showHistory) { if $0 { model.pause() } }
            .onChange(of: showHelp) { if $0 { model.pause() } }
        }.tint(Palette.green)
    }
    private var practiceContent: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if horizontalSizeClass == .regular { heading }
                    Picker("练习方式", selection: Binding(get: { model.mode }, set: { model.changeMode($0) })) {
                        ForEach(PracticeModel.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    MicrophoneCard(model: model, microphone: model.microphone)
                    if model.mode == .practice {
                        exercisePicker
                        ScoreCard(model: model)
                        feedback
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("让每一个声音，都有名字").font(.title3.bold())
                            Text("一次弹一个琴键，音名和键盘会跟随琴声亮起。这里可以自由探索，不计对错。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 24))
                    }
                    keyboardSection
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                        Text("音频只在设备处理，不录音、不上传")
                    }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    Text("单音练习版 · 请关闭踏板，保持环境安静").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }.padding(.horizontal, 20).padding(.vertical, 16).frame(maxWidth: 960).frame(maxWidth: .infinity)
            }
    }
    @ViewBuilder private var keyboardSection: some View {
        if model.mode == .practice {
            DisclosureGroup("键盘示意") {
                KeyboardView(detected: model.detected, expected: model.expected)
            }.font(.subheadline)
        } else {
            KeyboardView(detected: model.detected, expected: nil)
        }
    }
    private var heading: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PIANO BLOOM").font(.caption.weight(.bold)).tracking(3).foregroundStyle(Palette.green)
                Text("听见你的每一点进步").font(.system(.title2, design: .rounded).bold()).foregroundStyle(Palette.ink)
                Text("慢慢弹，琴芽陪你练。").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "leaf.fill").font(.system(size: 32)).foregroundStyle(Palette.green)
                .frame(width: 56, height: 56).background(Palette.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
        }
    }
    private var exercisePicker: some View {
        HStack {
            Text("今天练什么").font(.headline)
            Spacer()
            Menu {
                ForEach(["入门旋律", "哈农 · 右手单音"], id: \.self) { group in
                    Section(group) {
                        ForEach(Exercise.all.filter { $0.group == group }) { exercise in
                            Button(exercise.title) { model.select(exercise) }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) { Text(model.exercise.title); Image(systemName: "chevron.down").font(.caption.bold()) }
                    .font(.subheadline.weight(.semibold))
            }.accessibilityLabel("选择练习曲，当前\(model.exercise.title)")
        }
    }
    private var feedback: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.wrongNote == nil ? "sparkles" : "arrow.uturn.backward.circle")
            Text(model.feedback).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(model.wrongNote == nil ? Palette.green : Color.orange)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background((model.wrongNote == nil ? Palette.green : Color.orange).opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
    }
}

private struct MicrophoneCard: View {
    @ObservedObject var model: PracticeModel
    @ObservedObject var microphone: Microphone
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(status, systemImage: microphone.listening ? "waveform" : "mic")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(model.calibrated ? "中央 C 已校准" : "标准 C4 基准").font(.caption2)
            }.foregroundStyle(.white.opacity(0.8))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(model.detected.map(Music.name) ?? "—")
                    .font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(model.detected.map(Music.solfege) ?? "等待琴声").font(.title3).foregroundStyle(.white.opacity(0.7))
            }.foregroundStyle(.white).frame(minHeight: 58)
            if let frequency = model.frequency {
                Text(String(format: "%.1f Hz   ·   %@%.0f 音分", frequency, model.cents >= 0 ? "+" : "", model.cents))
                    .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.75))
            } else {
                Text(model.calibrating ? "请弹中央 C，保持约 1 秒" : "按下开始，再弹一个琴键")
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            GeometryReader { geometry in
                Capsule().fill(.white.opacity(0.15)).overlay(alignment: .leading) {
                    Capsule().fill(Color(red: 0.68, green: 0.90, blue: 0.63))
                        .frame(width: geometry.size.width * min(1, max(0, microphone.level * 16)))
                }
            }.frame(height: 4).accessibilityLabel("麦克风音量")
            if model.calibrating { ProgressView().tint(.white) }
        }.padding(22)
            .background(LinearGradient(colors: [Palette.ink, Palette.green], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
    }
    private var status: String {
        switch microphone.state {
        case .listening: return model.calibrating ? "正在校准" : "正在聆听"
        case .requesting: return "正在请求麦克风权限"
        case .denied: return "麦克风权限未开启"
        case .failed: return "麦克风暂不可用"
        case .stopped: return "准备聆听"
        }
    }
}

private struct ScoreCard: View {
    @ObservedObject var model: PracticeModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.exercise.title).font(.title3.bold())
                    Text(model.exercise.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.progress.position) / \(model.progress.notes.count)")
                    .font(.subheadline.monospacedDigit().bold()).foregroundStyle(Palette.green)
            }
            if model.exercise.id.hasPrefix("hanon-") {
                Menu {
                    Button("整首（含反复）") { model.selectSection(nil) }
                    ForEach(Array(stride(from: 0, to: model.exercise.notes.count, by: 8)), id: \.self) { start in
                        Button("第\(start + 1)–\(min(start + 8, model.exercise.notes.count))音") { model.selectSection(start) }
                    }
                } label: {
                    Label(model.sectionStart.map { "分段：第\($0 + 1)–\(min($0 + 8, model.exercise.notes.count))音" } ?? "整首练习 · 点击选择分段", systemImage: "music.note.list")
                        .font(.subheadline)
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        Text("𝄞").font(.system(size: 65)).frame(width: 42, height: 132)
                        ForEach(Array(model.progress.notes.enumerated()), id: \.offset) { index, note in
                            ScoreNote(midi: note, state: index < model.progress.position ? .done : (index == model.progress.position ? (model.wrongNote == nil ? .current : .wrong) : .future))
                                .id(index)
                                .accessibilityLabel("第\(index + 1)个音，\(Music.name(note))")
                        }
                        Color.clear.frame(width: 100, height: 1)
                    }.padding(.vertical, 4)
                }.onChange(of: model.progress.position) { index in
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(index, anchor: .center) }
                }.onChange(of: model.exercise.id) { _ in proxy.scrollTo(0, anchor: .leading) }
            }
            ProgressView(value: Double(model.progress.position), total: Double(model.progress.notes.count)).tint(Palette.green)
            Text("仅判断音符顺序；哈农按原谱反复展开，请单独弹右手。暂不评节奏、指法。").font(.caption2).foregroundStyle(.secondary)
        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct ScoreNote: View {
    enum State { case done, current, wrong, future }
    let midi: Int
    let state: State
    private var color: Color {
        switch state { case .done: return Palette.green; case .current: return Palette.ink; case .wrong: return .orange; case .future: return .gray }
    }
    var body: some View {
        VStack(spacing: 0) {
            Canvas { context, size in
                let x: CGFloat = size.width / 2
                let bottom: CGFloat = 100
                let y = bottom + 8 - CGFloat(Music.staffStep(midi)) * 4
                var staff = Path()
                for row in 0..<5 {
                    let lineY = bottom - CGFloat(row) * 8
                    staff.move(to: CGPoint(x: 0, y: lineY)); staff.addLine(to: CGPoint(x: size.width, y: lineY))
                }
                context.stroke(staff, with: .color(.gray.opacity(0.3)), lineWidth: 1)
                if y >= bottom + 8 || y <= bottom - 40 {
                    var ledger = Path()
                    let start = y >= bottom + 8 ? bottom + 8 : bottom - 40
                    let step: CGFloat = y >= bottom + 8 ? 8 : -8
                    for lineY in stride(from: start, through: y, by: step) {
                        ledger.move(to: CGPoint(x: x - 14, y: lineY)); ledger.addLine(to: CGPoint(x: x + 14, y: lineY))
                    }
                    context.stroke(ledger, with: .color(color), lineWidth: 1)
                }
                if state == .current || state == .wrong {
                    let circle = Path(ellipseIn: CGRect(x: x - 20, y: y - 20, width: 40, height: 40))
                    context.fill(circle, with: .color(color.opacity(0.09)))
                }
                context.fill(Path(ellipseIn: CGRect(x: x - 9, y: y - 6, width: 18, height: 12)), with: .color(color))
                var stem = Path()
                if y >= 52 { stem.move(to: CGPoint(x: x + 8, y: y)); stem.addLine(to: CGPoint(x: x + 8, y: y - 31)) }
                else { stem.move(to: CGPoint(x: x - 8, y: y)); stem.addLine(to: CGPoint(x: x - 8, y: y + 31)) }
                context.stroke(stem, with: .color(color), lineWidth: 1.6)
            }.frame(width: 58, height: 164)
            Text(Music.name(midi)).font(.caption.weight(state == .current ? .bold : .regular)).foregroundStyle(color)
        }.padding(.bottom, 8)
    }
}

private struct KeyboardView: View {
    let detected: Int?
    let expected: Int?
    private let whiteNotes = [60,62,64,65,67,69,71,72]
    private let blackNotes = [(61, 1), (63, 2), (66, 4), (68, 5), (70, 6)]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Label("目标音", systemImage: "circle").foregroundStyle(Palette.green)
                Label("听到的音", systemImage: "circle.fill").foregroundStyle(Color.orange)
            }.font(.caption2)
            GeometryReader { geometry in
                let width = geometry.size.width / 8
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 2) {
                        ForEach(whiteNotes, id: \.self) { note in
                            VStack {
                                Spacer()
                                if expected == note { Circle().stroke(Palette.green, lineWidth: 2).frame(width: 12, height: 12) }
                                Text(Music.name(note)).font(.caption2).foregroundStyle(.secondary)
                            }.padding(.bottom, 8).frame(maxWidth: .infinity).frame(height: 104)
                                .background(detected == note ? Color.orange.opacity(0.25) : .white, in: UnevenKey())
                        }
                    }
                    ForEach(blackNotes, id: \.0) { item in
                        RoundedRectangle(cornerRadius: 4).fill(detected == item.0 ? Color.orange : Palette.ink)
                            .frame(width: width * 0.56, height: 64).offset(x: width * CGFloat(item.1) - width * 0.28)
                    }
                }
            }.frame(height: 104)
        }.padding(14).background(Palette.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("键盘示意，目标\(expected.map(Music.name) ?? "无")，听到\(detected.map(Music.name) ?? "无")")
    }
}
private struct UnevenKey: Shape {
    func path(in rect: CGRect) -> Path { Path(roundedRect: rect, cornerRadius: 5) }
}

private struct ControlsView: View {
    @ObservedObject var model: PracticeModel
    @ObservedObject var microphone: Microphone
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(spacing: 12) {
            if case .denied = microphone.state {
                Text("需要麦克风权限才能听见钢琴。请在系统设置中允许琴芽访问麦克风。").font(.subheadline)
                Button("打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }.buttonStyle(.bordered)
            }
            if case let .failed(message) = microphone.state {
                Text("收音失败：\(message)。请检查麦克风连接后重试。").font(.caption).foregroundStyle(.red)
            }
            Button { model.toggle() } label: {
                Label(microphone.listening || microphone.requesting ? "暂停聆听" : (model.progress.complete && model.mode == .practice ? "再练一次" : "开始聆听"), systemImage: microphone.listening ? "pause.fill" : "mic.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.borderedProminent).controlSize(.large)
            HStack(spacing: 12) {
                Button { if model.calibrating { model.pause() } else { model.calibrate() } } label: {
                    Label(model.calibrating ? "取消校准" : "校准中央 C", systemImage: "tuningfork").frame(maxWidth: .infinity)
                }
                if model.mode == .practice {
                    Button { model.restart() } label: { Label("重新练习", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
                }
            }.font(.subheadline).buttonStyle(.bordered).controlSize(.large)
            if model.calibrating { Text(model.feedback).font(.caption).foregroundStyle(Palette.green) }
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: PracticeModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("中央 C 基准") {
                    LabeledContent("当前频率", value: String(format: "%.2f Hz", model.reference))
                    Text(model.calibrated ? "已保存你的钢琴校准值。" : "使用标准音高 A4 = 440 Hz 对应的中央 C。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("恢复标准音高") { model.resetCalibration() }
                }
                Section("麦克风灵敏度") {
                    Slider(value: $model.sensitivity, in: 0...1).accessibilityLabel("麦克风灵敏度")
                    HStack { Text("忽略背景声"); Spacer(); Text("捕捉轻音") }.font(.caption)
                    Text("安静时仍频繁出现音名，请向左调；轻弹没有反应，请向右调。校准和练习使用同一个设置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("关于琴芽") {
                    Text("PianoBloom 1.0 · 单音练习版")
                    Text("本机处理音频；只保存校准值、灵敏度与最近 30 次完整练习记录。不保存录音。")
                    Text("内置哈农第 1–20 首右手曲谱，可整首或每 8 音分段练习。")
                    Text("曲谱改编自 Mutopia，Steve Taylor / Javier Ruiz-Alma，CC BY-SA 4.0。")
                    Link("曲谱来源与授权", destination: URL(string: "https://www.mutopiaproject.org/ftp/HanonCL/virtuoso-pianist-pt1/")!)
                    Text("暂不支持双手和弦、踏板混音、导入曲谱和节奏评分。")
                }
            }.navigationTitle("设置").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

private struct HistoryView: View {
    @ObservedObject var model: PracticeModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if model.results.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("第一片琴芽，等你点亮。").font(.headline)
                        Text("完整练完一首曲子后，记录就会出现在这里。").foregroundStyle(.secondary)
                    }.padding(.vertical)
                }
                ForEach(model.results) { result in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text(result.title).font(.headline); Spacer(); Text("\(result.accuracy)%").foregroundStyle(Palette.green) }
                        Text("\(result.count) 个正确音 · \(result.mistakes) 次错音 · \(result.seconds) 秒").font(.caption)
                        Text(result.date, style: .date).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }.navigationTitle("练习记录").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

private struct ResultView: View {
    @ObservedObject var model: PracticeModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "leaf.circle.fill").font(.system(size: 80)).foregroundStyle(Palette.green)
            Text("又长出一片新叶子").font(.title.bold())
            if let result = model.latestResult {
                Text(result.title).font(.title3).foregroundStyle(.secondary)
                Text("\(result.accuracy)%").font(.system(size: 64, weight: .semibold, design: .rounded)).foregroundStyle(Palette.green)
                Text("音符准确率").foregroundStyle(.secondary)
                Text("弹对 \(result.count) 个音   ·   错音 \(result.mistakes) 次   ·   用时 \(result.seconds) 秒").font(.subheadline)
                Text("准确率 = 正确音 ÷（正确音 + 错音），不评价节奏。").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("再练一次") { model.restart(); dismiss() }.buttonStyle(.borderedProminent).controlSize(.large)
            Button("回到琴谱") { dismiss() }.padding(.bottom, 20)
        }.padding(24).frame(maxWidth: .infinity).background(Palette.cream)
    }
}

private struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("第一次练习") {
                    Label("把手机或 iPad 放在钢琴旁约 30–80 厘米，关闭踏板。", systemImage: "1.circle")
                    Label("点击「校准中央 C」，允许麦克风访问。弹中央 C（C4）并保持约 1 秒。", systemImage: "2.circle")
                    Label("校准完成后松开琴键，等余音变小，再弹高亮音符。", systemImage: "3.circle")
                    Label("弹对后琴谱自动前进，弹错会停下来等待。", systemImage: "4.circle")
                }
                Section("重复音怎么弹？") {
                    Text("重新抬指、按键；App 会尝试根据新的击键音量变化判断。若余音导致卡住，请松开琴键等待片刻再弹，或者降低灵敏度。")
                }
                Section("识别不稳定？") {
                    Text("靠近钢琴，关闭背景音乐和踏板，避免边弹边说话。一次只弹一个音。支持识别约 B2–F6；和弦、强混响及噪声可能导致误判。")
                    Text("校准只能修正整台琴的整体音高偏移，不能代替钢琴调律。练习可使用默认标准音高，无需每次校准。")
                }
                Section("来电、切后台和换耳机") {
                    Text("收音会暂停，进度保留。回到 App 后点击「开始聆听」继续；不会在后台录音。建议使用设备内置麦克风。")
                }
            }.navigationTitle("使用帮助").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
