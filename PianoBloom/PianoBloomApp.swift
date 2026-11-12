import SwiftUI
import UIKit

@main
struct PianoBloomApp: App {
    @StateObject private var model = PracticeModel()
    var body: some Scene {
        WindowGroup { GardenHome(model: model).preferredColorScheme(.light) }
    }
}

enum Bloom {
    static let pink = Color(red: 0.87, green: 0.28, blue: 0.51)
    static let blush = Color(red: 1, green: 0.94, blue: 0.96)
    static let ink = Color(red: 0.34, green: 0.24, blue: 0.35)
    static let lilac = Color(red: 0.62, green: 0.48, blue: 0.78)
    static let mint = Color(red: 0.24, green: 0.65, blue: 0.53)
}

struct GardenHome: View {
    @ObservedObject var model: PracticeModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var performing = false
    @State private var settings = false
    @State private var history = false
    @State private var hanon = false
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        welcome
                        if geometry.size.width > 750 {
                            HStack(alignment: .top, spacing: 24) {
                                setup.frame(width: 310)
                                library
                            }
                        } else {
                            setup
                            library
                        }
                    }.padding(geometry.size.width > 700 ? 32 : 20).frame(maxWidth: 1250).frame(maxWidth: .infinity)
                }.background(Bloom.blush)
            }
            .navigationTitle("琴芽 · 小兔钢琴花园").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { history = true } label: { Image(systemName: "clock.arrow.circlepath") }.accessibilityLabel("练习记录")
                    Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("家长设置")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { launchButton }
            .sheet(isPresented: $settings) { ParentSettings(model: model) }
            .sheet(isPresented: $history) { HistoryView(model: model) }
            .fullScreenCover(isPresented: $performing) { PerformanceScreen(model: model) }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--preview-performance") {
                    model.prepareScreenshot(); performing = true
                }
                #endif
            }
            .onChange(of: scenePhase) { if $0 == .background { model.pause() } }
        }.tint(Bloom.pink)
    }
    private var welcome: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("BUNNY’S PIANO GARDEN").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2).foregroundStyle(Bloom.pink)
                Text("今天，弹一点快乐吧").font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(Bloom.ink)
                Text("让每一个音符，开成一朵小花。") .font(.subheadline).foregroundStyle(Bloom.ink.opacity(0.6))
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("小兔陪练  ·  双手一起成长")
                }.font(.caption.bold()).foregroundStyle(Bloom.lilac).padding(.top, 4)
            }
            Spacer(minLength: 0)
            BunnyMascot().frame(width: 100, height: 118).accessibilityHidden(true)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.white, Color(red: 1, green: 0.88, blue: 0.93)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 30))
    }
    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("布置我的小舞台", systemImage: "wand.and.stars").font(.headline).foregroundStyle(Bloom.ink)
            VStack(alignment: .leading, spacing: 8) {
                Text("今天用哪只手？").font(.caption.bold()).foregroundStyle(.secondary)
                Picker("演奏手", selection: Binding(get: { model.hands }, set: { model.configure(hands: $0) })) {
                    ForEach(PracticeHands.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("练习方式").font(.caption.bold()).foregroundStyle(.secondary)
                Picker("练习方式", selection: Binding(get: { model.style }, set: { model.configure(style: $0) })) {
                    ForEach(PlayStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Text(model.style == .follow ? "弹对再向前，小兔会等你。" : "按固定节拍演奏，结束后看看节奏星星。")
                    .font(.caption).foregroundStyle(Bloom.lilac)
            }
            HStack {
                Label("速度", systemImage: "metronome")
                Spacer()
                Stepper("\(Int(model.bpm)) BPM", value: Binding(get: { model.bpm }, set: { model.configure(bpm: $0) }), in: 30...120, step: 5)
                    .font(.subheadline.monospacedDigit())
            }.font(.subheadline)
            InputSelector(model: model)
            if model.score.isHanon {
                Menu {
                    Button("整首曲谱（含反复）") { model.selectSection(nil) }
                    ForEach(Array(stride(from: 0, to: Int(ceil(model.score.length / Double(model.score.beatsPerBar))), by: 2)), id: \.self) { bar in
                        Button("第 \(bar + 1)–\(bar + 2) 小节") { model.selectSection(bar) }
                    }
                } label: {
                    Label(model.sectionBar.map { "第 \($0 + 1)–\($0 + 2) 小节" } ?? "整首练习 · 可选两小节", systemImage: "music.note.list")
                        .font(.subheadline)
                }
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 26))
    }
    private var library: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("挑一首喜欢的曲子").font(.title3.bold()).foregroundStyle(Bloom.ink)
                Spacer()
                Text(hanon ? "20 首" : "3 首").font(.caption.bold()).foregroundStyle(Bloom.pink)
            }
            Picker("曲库", selection: $hanon) { Text("星星启蒙").tag(false); Text("哈农花园").tag(true) }.pickerStyle(.segmented)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                ForEach(PianoScore.all.filter { $0.isHanon == hanon }) { score in
                    ScoreTile(score: score, selected: score.id == model.score.id) { model.select(score) }
                }
            }
        }
    }
    private var launchButton: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.score.title).font(.headline).foregroundStyle(Bloom.ink)
                Text("\(model.hands.rawValue) · \(model.style.rawValue)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { model.pause(); performing = true } label: {
                Label("进入小小音乐会", systemImage: "play.fill").font(.headline).padding(.horizontal, 12).padding(.vertical, 9)
            }.buttonStyle(.borderedProminent).clipShape(Capsule())
        }.padding(.horizontal, 24).padding(.vertical, 14).frame(maxWidth: 1186).frame(maxWidth: .infinity).background(.white)
    }
}

private struct ScoreTile: View {
    let score: PianoScore
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(score.isHanon ? "🌷" : (score.id == "star" ? "⭐️" : score.id == "ode" ? "🎀" : "🌈"))
                        .font(.system(size: 30)).frame(width: 58, height: 58).background(Bloom.blush, in: RoundedRectangle(cornerRadius: 18))
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Bloom.pink).font(.title3) }
                    else { Image(systemName: "music.note").foregroundStyle(Bloom.lilac.opacity(0.4)) }
                }
                Text(score.title).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Bloom.ink)
                Text(score.detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                Label("\(score.beatsPerBar)/4 拍  ·  支持双手", systemImage: "hands.sparkles").font(.caption2.bold()).foregroundStyle(Bloom.lilac)
            }.padding(20).frame(maxWidth: .infinity, minHeight: 185, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(selected ? Bloom.pink : .clear, lineWidth: 2))
        }.buttonStyle(.plain).accessibilityLabel("\(score.title)，\(selected ? "已选择" : "点击选择")")
    }
}

private struct InputSelector: View {
    @ObservedObject var model: PracticeModel
    @ObservedObject private var midi: MIDIInput
    init(model: PracticeModel) { self.model = model; self.midi = model.midi }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("钢琴连接", selection: Binding(get: { model.input }, set: { model.configure(input: $0) })) {
                ForEach(PianoInput.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if model.input == .midi {
                if midi.sources.isEmpty {
                    Text("用 USB 线或转接器连接电钢琴，即可准确判断双手与节奏。").font(.caption).foregroundStyle(.secondary)
                    Button("刷新钢琴连接") { midi.refresh() }.font(.caption.bold())
                } else {
                    Picker("已连接钢琴", selection: Binding(get: { midi.selected }, set: { midi.select($0) })) {
                        ForEach(midi.sources) { Text($0.name).tag($0.id) }
                    }.font(.caption)
                }
            } else {
                Text(model.hands == .both ? "双手识音为测试功能，建议先慢练（30–60 BPM）；正式评分推荐 USB MIDI。" : "在安静环境练习，先松开踏板；麦克风节奏分为估算。")
                    .font(.caption).foregroundStyle(Bloom.lilac)
            }
        }
    }
}

struct PerformanceScreen: View {
    @ObservedObject var model: PracticeModel
    @State private var showKeyboard = false
    @ObservedObject private var microphone: Microphone
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    init(model: PracticeModel) { self.model = model; self.microphone = model.microphone }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > 700
            let short = geometry.size.height < 500
            VStack(spacing: short ? 8 : 14) {
                header(wide: wide)
                if !short { sessionStrip(wide: wide) }
                ZStack {
                    GrandStaffView(model: model, wide: wide)
                    if let count = model.countIn { countIn(count) }
                    if !model.running && !model.microphone.requesting && model.performance.epoch == nil { readyOverlay }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white, in: RoundedRectangle(cornerRadius: 26))
                    .overlay(RoundedRectangle(cornerRadius: 26).stroke(Bloom.pink.opacity(0.08), lineWidth: 1))
                if wide && !short && showKeyboard { PerformanceKeyboard(heard: model.heard, target: model.target).frame(height: 88) }
                controls(wide: wide)
            }.padding(.horizontal, wide ? 28 : 12).padding(.top, short ? 4 : 16).padding(.bottom, 8)
                .background(Bloom.blush)
                .overlay { if model.showResult { ResultGarden(model: model) { model.showResult = false; dismiss() } } }
        }
        .tint(Bloom.pink).interactiveDismissDisabled()
         .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-landscape") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                    scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeLeft))
                }
            }
            #endif
        }
        .onDisappear { model.pause(); UIApplication.shared.isIdleTimerDisabled = false }
    }
    private func header(wide: Bool) -> some View {
        HStack(spacing: 14) {
            Button { model.pause(); dismiss() } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44).background(.white, in: Circle())
            }.accessibilityLabel("暂停并返回曲库")
            VStack(alignment: .leading, spacing: 3) {
                Text(model.score.title).font(.system(size: wide ? 25 : 19, weight: .bold, design: .rounded)).foregroundStyle(Bloom.ink)
                Text("\(model.hands.rawValue) · \(model.style.rawValue) · \(Int(model.bpm)) BPM")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if wide {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in Image(systemName: "star.fill").foregroundStyle(model.performance.correctCount > index * 8 ? Color.orange : Bloom.pink.opacity(0.18)) }
                }.font(.title3)
                BunnyMascot().frame(width: 62, height: 70).accessibilityHidden(true)
            } else {
                Text("\(model.performance.position)/\(model.performance.score.events.count)").font(.caption.monospacedDigit()).foregroundStyle(Bloom.pink)
            }
        }
    }
    private func sessionStrip(wide: Bool) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<model.score.beatsPerBar, id: \.self) { index in
                    let active = model.running && (Int(floor(model.beat)) % model.score.beatsPerBar + model.score.beatsPerBar) % model.score.beatsPerBar == index
                    Circle().fill(active ? Bloom.pink : Bloom.pink.opacity(0.16)).frame(width: active ? 12 : 8, height: active ? 12 : 8)
                }
            }.frame(width: 72)
            Text(model.feedback).font(.system(size: wide ? 15 : 12, weight: .medium, design: .rounded)).foregroundStyle(Bloom.ink).lineLimit(2)
            Spacer(minLength: 0)
            if wide {
                Text(model.style == .rhythm ? "节奏 \(model.performance.rhythmScore.map { "\($0)" } ?? "—")" : "已点亮 \(model.performance.correctCount) 颗")
                    .font(.subheadline.bold()).foregroundStyle(Bloom.lilac)
            }
        }.padding(.horizontal, 16).frame(minHeight: 44).background(.white.opacity(0.7), in: Capsule())
    }
    private var readyOverlay: some View {
        VStack(spacing: 14) {
            Text("准备好，让音符开花了吗？").font(.headline).foregroundStyle(Bloom.ink)
            Text("先数 \(model.score.beatsPerBar) 拍，再开始弹奏").font(.subheadline).foregroundStyle(.secondary)
            Button { model.toggle() } label: { Label("开始演奏", systemImage: "play.fill").font(.headline).padding(8) }
                .buttonStyle(.borderedProminent).clipShape(Capsule())
        }.padding(26).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26)).padding(14)
    }
    private func countIn(_ count: Int) -> some View {
        VStack(spacing: 4) {
            Text("预备").font(.headline)
            Text("\(count)").font(.system(size: 76, weight: .bold, design: .rounded))
        }.foregroundStyle(Bloom.pink).frame(width: 160, height: 160).background(.regularMaterial, in: Circle())
    }
    private func controls(wide: Bool) -> some View {
        VStack(spacing: 6) {
            if microphone.state == .denied {
                Button("允许麦克风后继续：打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }.font(.caption)
            }
            if case let .failed(message) = microphone.state { Text(message).font(.caption).foregroundStyle(.orange) }
            HStack(spacing: 12) {
                Button { model.restart() } label: { Label("重来", systemImage: "arrow.counterclockwise").font(.subheadline.bold()).frame(minWidth: 64, minHeight: 44) }
                if wide {
                    Button { showKeyboard.toggle() } label: { Label(showKeyboard ? "收起键盘" : "键盘", systemImage: "pianokeys").font(.subheadline.bold()).frame(minHeight: 44) }
                }
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    Text(model.inputDescription).font(.caption.bold()).foregroundStyle(Bloom.ink)
                    if model.isEstimate { Text("识音与节奏结果为估算").font(.caption2).foregroundStyle(Bloom.lilac) }
                }
                Spacer(minLength: 0)
                Button { model.toggle() } label: {
                    Label(model.running || microphone.requesting ? "暂停" : "开始", systemImage: model.running ? "pause.fill" : "play.fill")
                        .font(.headline).frame(minWidth: wide ? 120 : 70, minHeight: 34)
                }.buttonStyle(.borderedProminent).clipShape(Capsule())
            }
        }
    }
}

struct PerformanceKeyboard: View {
    let heard: Set<Int>
    let target: Set<Int>
    var body: some View {
        Canvas { context, size in
            let whites = (33...88).filter { [0,2,4,5,7,9,11].contains($0 % 12) }
            let width = size.width / CGFloat(whites.count)
            for (index, note) in whites.enumerated() {
                let rect = CGRect(x: CGFloat(index) * width + 0.5, y: 0, width: width - 1, height: size.height)
                let path = Path(roundedRect: rect, cornerRadius: 4)
                context.fill(path, with: .color(heard.contains(note) ? Bloom.pink.opacity(0.45) : .white))
                context.stroke(path, with: .color(Bloom.pink.opacity(0.12)), lineWidth: 1)
                if target.contains(note) {
                    context.draw(Text("●").font(.system(size: 9)).foregroundColor(Bloom.pink), at: CGPoint(x: rect.midX, y: size.height - 14))
                }
                if note % 12 == 0 { context.draw(Text(Music.name(note)).font(.system(size: 8)).foregroundColor(.gray), at: CGPoint(x: rect.midX, y: size.height - 5)) }
            }
            for note in 33...88 where !whites.contains(note) {
                guard let before = whites.lastIndex(where: { $0 < note }) else { continue }
                let rect = CGRect(x: CGFloat(before + 1) * width - width * 0.3, y: 0, width: width * 0.6, height: size.height * 0.62)
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(heard.contains(note) ? Bloom.pink : Bloom.ink))
            }
        }.accessibilityLabel("钢琴键盘，目标音\(target.sorted().map(Music.name).joined(separator: "、"))")
    }
}

struct BunnyMascot: View {
    var body: some View {
        Canvas { context, size in
            func ellipse(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: Color) {
                context.fill(Path(ellipseIn: CGRect(x: size.width * x, y: size.height * y, width: size.width * w, height: size.height * h)), with: .color(color))
            }
            ellipse(0.05,0.14,0.9,0.8,Color.white.opacity(0.6))
            ellipse(0.23,0.02,0.20,0.51,.white); ellipse(0.56,0,0.20,0.52,.white)
            ellipse(0.29,0.07,0.08,0.34,Color(red: 1, green: 0.72, blue: 0.82)); ellipse(0.62,0.06,0.08,0.35,Color(red: 1, green: 0.72, blue: 0.82))
            ellipse(0.12,0.34,0.76,0.61,.white)
            ellipse(0.20,0.65,0.17,0.10,Bloom.pink.opacity(0.22)); ellipse(0.64,0.65,0.17,0.10,Bloom.pink.opacity(0.22))
            ellipse(0.33,0.57,0.045,0.065,Bloom.ink); ellipse(0.64,0.57,0.045,0.065,Bloom.ink)
            context.draw(Text("ω").font(.system(size: size.width * 0.18, weight: .medium)).foregroundColor(Bloom.pink), at: CGPoint(x: size.width * 0.51, y: size.height * 0.72))
            context.draw(Text("✿").font(.system(size: size.width * 0.32)).foregroundColor(Bloom.pink), at: CGPoint(x: size.width * 0.79, y: size.height * 0.43))
        }
    }
}

private struct ResultGarden: View {
    @ObservedObject var model: PracticeModel
    let close: () -> Void
    var body: some View {
        ZStack {
            Bloom.blush.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    BunnyMascot().frame(width: 140, height: 160)
                    Text("今天的音乐，开花啦！").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(Bloom.ink)
                    if let result = model.latestResult {
                        Text("\(result.title) · \(result.hands ?? "")").font(.headline).foregroundStyle(Bloom.lilac)
                        HStack(spacing: 36) {
                            score("音符", value: result.accuracy)
                            if let rhythm = result.rhythm { score("节奏", value: rhythm) }
                        }.padding(24).background(.white, in: RoundedRectangle(cornerRadius: 28))
                        Text("点亮 \(result.count) 组音符 · 漏弹 \(result.missed ?? 0) 组 · \(result.seconds) 秒").font(.subheadline).foregroundStyle(.secondary)
                        if result.source == "麦克风估算" { Text("麦克风估算结果；双手八度与踏板可能影响准确性。") .font(.caption).foregroundStyle(Bloom.lilac) }
                        Text(result.rhythm == nil ? "这次是自由跟谱练习，没有节奏评分。" : "节奏分按固定速度下的起音时间计算；漏弹记 0 分。")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    Button("再开一朵小花") { model.restart() }.buttonStyle(.borderedProminent).controlSize(.large).clipShape(Capsule())
                    Button("回到钢琴花园", action: close).font(.headline)
                }.padding(32).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
        }
    }
    private func score(_ label: String, value: Int) -> some View {
        VStack { Text("\(value)").font(.system(size: 52, weight: .bold, design: .rounded)).foregroundStyle(Bloom.pink); Text("\(label)星星").font(.subheadline).foregroundStyle(Bloom.ink) }
    }
}

private struct ParentSettings: View {
    @ObservedObject var model: PracticeModel
    @ObservedObject private var microphone: Microphone
    @Environment(\.dismiss) private var dismiss
    init(model: PracticeModel) { self.model = model; self.microphone = model.microphone }
    var body: some View {
        NavigationStack {
            Form {
                Section("麦克风与音高") {
                    Slider(value: $model.sensitivity, in: 0...1) { Text("麦克风灵敏度") }
                    Text("向左忽略背景声，向右捕捉轻音。").font(.caption)
                    LabeledContent("中央 C", value: String(format: "%.2f Hz", model.reference))
                    Button(model.calibrating ? "取消校准" : "校准中央 C") { if model.calibrating { model.pause() } else { model.calibrate() } }
                    Text(model.feedback).font(.caption).foregroundStyle(.secondary)
                    if microphone.state == .denied { Text("麦克风未授权，请在系统设置 → 琴芽中打开麦克风权限。").font(.caption).foregroundStyle(.orange) }
                    Button("恢复标准音高") { model.resetCalibration() }
                }
                Section("麦克风节奏补偿") {
                    Slider(value: $model.latencyMS, in: -300...300, step: 10)
                    Text("当前 \(Int(model.latencyMS)) 毫秒：正值会把识别起音向前移动。仅补偿设备延迟，不改变固定节拍网格。")
                        .font(.caption)
                }
                Section("给家长的话") {
                    Text("USB MIDI 可以直接读到两只手按下的琴键，是双手与节奏评分的推荐方式。")
                    Text("真钢琴麦克风双手识别仍在测试中，无法保证区分八度音和泛音；请关闭踏板、保持安静，并把麦克风结果作为参考。")
                    Text("跟谱练习会等孩子弹对；节奏挑战在一小节预备后按固定速度前进，漏弹不会暂停谱面。节奏分仅评价起音时间，不评价力度、指法或松键时长。")
                    Text("哈农速度以四分音符为一拍；例如 60 BPM 下十六分音符间隔 250 毫秒。")
                    Text("曲谱与所有音频分析均在设备运行，不保存录音、不上传声音。")
                }
                Section("琴谱与署名") {
                    Text("PianoBloom 2.0 · 小兔钢琴花园")
                    Text("哈农 1–20：Steve Taylor / Javier Ruiz-Alma，Mutopia，CC BY-SA 4.0。保留双手、时值，展开原谱反复。启蒙双手曲为本 App 教学改编。")
                    Link("查看曲谱来源", destination: URL(string: "https://www.mutopiaproject.org/ftp/HanonCL/virtuoso-pianist-pt1/")!)
                }
            }.navigationTitle("家长设置").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { model.pause(); dismiss() } } }
        }.onDisappear { model.pause() }
    }
}

private struct HistoryView: View {
    @ObservedObject var model: PracticeModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if model.results.isEmpty { Text("第一朵音乐小花，等你来点亮。") }
                ForEach(model.results) { result in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(result.title).font(.headline); Spacer(); Text("\(result.accuracy) 分").foregroundStyle(Bloom.pink) }
                        Text("\(result.hands ?? "单音") · \(result.source ?? "麦克风估算") · 节奏 \(result.rhythm.map { "\($0) 分" } ?? "未评分")").font(.caption)
                        Text(result.date, style: .date).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
            }.navigationTitle("我的音乐小花").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
