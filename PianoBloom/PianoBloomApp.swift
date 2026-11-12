import SwiftUI
import UIKit

@main
struct PianoBloomApp: App {
    @UIApplicationDelegateAdaptor(PianoAppDelegate.self) private var appDelegate
    @StateObject private var model = PracticeModel()
    var body: some Scene {
        WindowGroup { GardenHome(model: model).preferredColorScheme(.light) }
    }
}

final class PianoAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-landscape") { return .landscapeLeft }
        #endif
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
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
    @State private var freeListening = false
    @State private var settings = false
    @State private var history = false
    @State private var hanon = false
    @State private var searchText = ""
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
                    Button { model.pause(); freeListening = true } label: { Image(systemName: "tuningfork") }.accessibilityLabel("自由识音")
                    Button { history = true } label: { Image(systemName: "clock.arrow.circlepath") }.accessibilityLabel("练习记录")
                    Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("家长设置")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { launchButton }
            .sheet(isPresented: $freeListening) { FreeListeningView(model: model) }
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
                Text(model.style == .follow ? "跟着音符慢慢弹，错音会记下并继续。" : "按固定节拍演奏，结束后看看节奏星星。")
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
    private var filteredScores: [PianoScore] {
        PianoScore.all.filter { searchText.isEmpty ? $0.isHanon == hanon : $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    private var library: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("挑一首喜欢的曲子").font(.title3.bold()).foregroundStyle(Bloom.ink)
                Spacer()
                Text("\(filteredScores.count) 首").font(.caption.bold()).foregroundStyle(Bloom.pink)
            }
            TextField("搜索曲名，如：小星星、哈农", text: $searchText)
                .textFieldStyle(.roundedBorder).accessibilityLabel("搜索曲谱")
            Picker("曲库", selection: $hanon) { Text("星星启蒙").tag(false); Text("哈农花园").tag(true) }.pickerStyle(.segmented)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                ForEach(filteredScores) { score in
                    ScoreTile(score: score, selected: score.id == model.score.id) { model.select(score) }
                }
            }
        }
    }
    private var launchButton: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.score.title).font(.headline).foregroundStyle(Bloom.ink)
                Button("自由练习") { model.beginFree(); performing = true }.font(.caption.bold())
            }
            Spacer(minLength: 4)
            Button { model.beginGuided(); performing = true } label: {
                Label("小兔带你练", systemImage: "sparkles").font(.headline).padding(.horizontal, 12).padding(.vertical, 9)
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
                Text(score.detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
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
    @State private var showKeyboard = true
    @State private var showReview = false
    @State private var showScoreSettings = false
    @ObservedObject private var microphone: Microphone
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    init(model: PracticeModel) { self.model = model; self.microphone = model.microphone }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > 700
            let short = geometry.size.height < 600
            VStack(spacing: 0) {
                header(wide: wide)
                practiceNavigation(wide: wide)
                Rectangle().fill(Bloom.pink.opacity(0.16)).frame(height: 2)
                VStack(spacing: 0) {
                    scoreTitle(wide: wide)
                    ZStack {
                        GrandStaffView(model: model, wide: wide)
                        if let count = model.countIn { countIn(count) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.background(.white)
                if showKeyboard || model.demonstrating {
                    PerformanceKeyboard(heard: model.heard, target: model.target)
                        .frame(height: short ? 48 : (geometry.size.width > geometry.size.height ? 64 : 76))
                        .padding(.horizontal, wide ? 16 : 8).padding(.top, 6)
                }
                controls(wide: wide)
            }.padding(.bottom, 4)
                .background(Bloom.blush)
                .overlay { if model.showResult { ResultGarden(model: model) { model.showResult = false; dismiss() } } }
        }
        .tint(Bloom.pink).interactiveDismissDisabled()
        .sheet(isPresented: $showReview) { PracticeLegend() }
        .popover(isPresented: $showScoreSettings) { scoreSettings.padding(24).frame(minWidth: 280) }
         .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-landscape") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                    var controller = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
                    controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
                    while let presented = controller?.presentedViewController { controller = presented; controller?.setNeedsUpdateOfSupportedInterfaceOrientations() }
                    scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeLeft)) { error in
                        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        try? error.localizedDescription.write(to: folder.appendingPathComponent("orientation-error.txt"), atomically: true, encoding: .utf8)
                    }
                }
            }
            #endif
        }
        .onDisappear { model.pause(); UIApplication.shared.isIdleTimerDisabled = false }
    }
    private var handSelector: some View {
        Picker("选择演奏手", selection: Binding(get: { model.hands }, set: { model.selectHandsDuringPractice($0) })) {
            ForEach([PracticeHands.left, .right, .both], id: \.self) { hand in Text(hand.rawValue).tag(hand) }
        }.pickerStyle(.segmented)
            .accessibilityHint("切换后从当前小段开头继续，正在收音时会自动恢复")
    }
    private func practiceNavigation(wide: Bool) -> some View {
        HStack(spacing: 12) {
            handSelector.frame(maxWidth: wide ? 280 : .infinity)
            if wide {
                Text(model.guided ? model.guidedTitle : model.style.rawValue)
                    .font(.caption.bold()).foregroundStyle(Bloom.lilac)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    ForEach(0..<model.score.beatsPerBar, id: \.self) { index in
                        let active = model.running && (Int(floor(model.beat)) % model.score.beatsPerBar + model.score.beatsPerBar) % model.score.beatsPerBar == index
                        Circle().fill(active ? Bloom.pink : Bloom.pink.opacity(0.18)).frame(width: 7, height: 7)
                    }
                }.accessibilityLabel("节拍指示")
                Text("\(Int(model.bpm)) BPM").font(.caption.monospacedDigit()).foregroundStyle(Bloom.ink)
            }
        }.padding(.horizontal, wide ? 20 : 12).padding(.bottom, 8)
    }
    private func scoreTitle(wide: Bool) -> some View {
        HStack(spacing: 10) {
            Text(model.guided ? "整曲 · " + model.guidedRange : "完整曲谱")
                .font(.caption.bold()).foregroundStyle(Bloom.lilac)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Bloom.blush, in: Capsule())
            Spacer(minLength: 0)
            Text(model.score.title).font(.system(size: wide ? 20 : 16, weight: .bold, design: .rounded))
                .foregroundStyle(Bloom.ink).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if wide { BunnyMascot().frame(width: 30, height: 34).accessibilityHidden(true) }
            Text("\(model.performance.position)/\(model.performance.score.events.count)")
                .font(.caption.monospacedDigit()).foregroundStyle(Bloom.lilac)
        }.padding(.horizontal, wide ? 24 : 12).frame(height: wide ? 42 : 36)
    }
    private var scoreSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("看得更清楚").font(.headline)
            Text("琴谱大小 \(Int(model.notationScale * 100))% ").font(.subheadline)
            Slider(value: $model.notationScale, in: 1...1.7, step: 0.05).accessibilityLabel("五线谱大小")
            Toggle("显示琴键", isOn: $showKeyboard)
            Toggle("小兔语音提示", isOn: $model.voiceHints)
            Button("听听怎么练") { model.speakInstruction() }
            Button("音符颜色说明") { showScoreSettings = false; showReview = true }
            Text("小花标记表示已弹过：绿色为正确，粉红色为错音；灰色表示漏弹。错音自动记下并继续，不会暂停收音。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func header(wide: Bool) -> some View {
        HStack(spacing: wide ? 16 : 8) {
            Button { model.pause(); dismiss() } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
                    .background(.white, in: Circle())
            }.accessibilityLabel("暂停并返回曲库")
            if wide {
                VStack(spacing: 4) {
                    Image(systemName: model.guided ? "leaf.fill" : "music.note.list").font(.title3)
                    Text(model.guided ? "乐句练习" : "全曲练习").font(.caption.bold())
                }.foregroundStyle(Bloom.ink).frame(width: 86, height: 58)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                VStack(spacing: 4) {
                    Image(systemName: model.style == .follow ? "music.note" : "metronome.fill")
                        .font(.title3).foregroundStyle(.white).frame(width: 34, height: 34)
                        .background(Bloom.pink, in: Circle())
                    Text(model.style == .follow ? "识谱" : "节奏").font(.caption.bold()).foregroundStyle(Bloom.pink)
                }.frame(width: 50)
                Spacer(minLength: 0)
            }
            toolButton("重来", icon: "arrow.counterclockwise", active: false) { model.restart() }
            toolButton(model.demonstrating ? "停止" : "试听", icon: model.demonstrating ? "stop.fill" : "headphones", active: model.demonstrating) {
                model.demonstrating ? model.pause() : model.demonstrate()
            }
            toolButton("琴键", icon: "pianokeys", active: showKeyboard) { showKeyboard.toggle() }
            toolButton("设置", icon: "gearshape.fill", active: false) { model.pause(); showScoreSettings = true }
            if !wide { Spacer(minLength: 0) }
        }.padding(.horizontal, wide ? 20 : 12).padding(.vertical, wide ? 8 : 6)
    }
    private func toolButton(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(active ? .white : Bloom.pink)
                    .frame(width: 40, height: 40)
                    .background(active ? Bloom.pink : .white, in: Circle())
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Bloom.ink)
            }.frame(minWidth: 46, minHeight: 58)
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
    private func countIn(_ count: Int) -> some View {
        VStack(spacing: 4) {
            Text("预备").font(.headline)
            Text("\(count)").font(.system(size: 76, weight: .bold, design: .rounded))
        }.foregroundStyle(Bloom.pink).frame(width: 160, height: 160).background(.regularMaterial, in: Circle())
    }
    private func controls(wide: Bool) -> some View {
        VStack(spacing: 2) {
            if microphone.state == .denied {
                Button("允许麦克风后继续：打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }.font(.caption)
            }
            if case let .failed(message) = microphone.state { Text(message).font(.caption).foregroundStyle(.orange) }
            HStack(spacing: 12) {
                Button { model.pause(); showReview = true } label: {
                    Image(systemName: "questionmark.circle").font(.title3).frame(width: 44, height: 44)
                }.accessibilityLabel("练习说明")
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.feedback).font(.system(size: wide ? 13 : 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Bloom.ink).lineLimit(1)
                    Text(model.inputDescription + (model.isEstimate ? " · 结果为估算" : ""))
                        .font(.system(size: 10)).foregroundStyle(Bloom.lilac).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if wide {
                    Text(model.style == .rhythm ? "节奏 \(model.performance.rhythmScore.map { "\($0)" } ?? "—")" : "✿ \(model.performance.correctCount)")
                        .font(.subheadline.bold()).foregroundStyle(Bloom.mint)
                }
                Button { model.toggle() } label: {
                    Label(model.demonstrating ? "停止" : (model.running || microphone.requesting ? "暂停" : "开始"), systemImage: model.demonstrating ? "stop.fill" : (model.running ? "pause.fill" : "play.fill"))
                        .font(.subheadline.bold()).frame(minWidth: wide ? 92 : 68, minHeight: 32)
                }.buttonStyle(.borderedProminent).clipShape(Capsule())
            }
        }.padding(.horizontal, wide ? 16 : 8).padding(.top, 4)
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
                    if model.guided {
                        Text(model.journey.complete ? "整曲练习完成啦！" : "下一步：\(model.guidedTitle) · \(model.guidedRange)").font(.headline).foregroundStyle(Bloom.lilac)
                        if !model.journey.complete {
                            Button(model.completedJourney?.stage == model.journey.stage && model.completedJourney?.phrase == model.journey.phrase && model.completedJourney?.wholeSong == model.journey.wholeSong ? "再练一次（已练 \(model.journey.attempts)/3 遍）" : "进入下一步") { model.continueGuided() }
                                .buttonStyle(.borderedProminent).controlSize(.large).clipShape(Capsule())
                        }
                        Button("重练刚才这一段") { model.repeatGuided() }
                    } else {
                        Button("再开一朵小花") { model.restart() }.buttonStyle(.borderedProminent).controlSize(.large).clipShape(Capsule())
                    }
                    if !model.weakBars.isEmpty {
                        VStack(spacing: 10) {
                            Text("这些小节，再开一朵花").font(.headline)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(model.weakBars, id: \.self) { bar in
                                        Button("第 \((model.sectionBar ?? 0) + bar + 1) 小节") { model.replayWeakBar(bar) }.buttonStyle(.bordered)
                                    }
                                }
                            }
                        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    }
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
                    Text("跟谱练习按弹奏的顺序前进，弹错也会记下并自动继续。节奏挑战按固定速度前进，漏弹不会暂停谱面。切换手型会从当前小段重新计分，并在原先正在收音时自动恢复。")
                    Text("哈农速度以四分音符为一拍；例如 60 BPM 下十六分音符间隔 250 毫秒。")
                    Text("曲谱与所有音频分析均在设备运行，不保存录音、不上传声音。")
                }
                Section("琴谱与署名") {
                    Text("PianoBloom 2.4 · 整曲花朵琴谱")
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

private struct FreeListeningView: View {
    @ObservedObject var model: PracticeModel
    @ObservedObject private var microphone: Microphone
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    init(model: PracticeModel) { self.model = model; self.microphone = model.microphone }
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                BunnyMascot().frame(width: 110, height: 130)
                Text("每个声音，都有名字").font(.title2.bold()).foregroundStyle(Bloom.ink)
                Text(model.heard.sorted().map(Music.name).joined(separator: " ").isEmpty ? "—" : model.heard.sorted().map(Music.name).joined(separator: " "))
                    .font(.system(size: 64, weight: .bold, design: .rounded)).foregroundStyle(Bloom.pink)
                Text(model.heard.sorted().map(Music.solfege).joined(separator: " ")).font(.title3).foregroundStyle(Bloom.lilac)
                Text("一次弹一个音，自由探索，不计对错。").font(.subheadline).foregroundStyle(.secondary)
                ProgressView(value: min(1, microphone.level * 16)).tint(Bloom.pink).frame(maxWidth: 280)
                if microphone.state == .denied {
                    Button("打开系统设置，允许麦克风") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                }
                if case let .failed(message) = microphone.state { Text(message).font(.caption).foregroundStyle(.orange) }
                Button { if model.exploring || microphone.requesting { model.pause() } else { model.explore() } } label: {
                    Label(model.exploring || microphone.requesting ? "暂停聆听" : "开始聆听", systemImage: model.exploring ? "pause.fill" : "mic.fill").font(.headline).padding(8)
                }.buttonStyle(.borderedProminent).clipShape(Capsule())
                Spacer(minLength: 0)
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(Bloom.blush)
                .navigationTitle("自由识音").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { model.pause(); dismiss() } } }
        }.onDisappear { model.pause() }
    }
}

private struct PracticeLegend: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Label("绿色音符和小花：弹对且已经弹过", systemImage: "music.note").foregroundStyle(Bloom.mint)
                Label("红色音符和粉色小花：已记下错音，自动继续", systemImage: "music.note").foregroundStyle(.red)
                Label("灰色音符：这一拍漏弹了", systemImage: "music.note").foregroundStyle(.gray)
                Label("红色影子在前：弹早了；在后：弹晚了", systemImage: "metronome").foregroundStyle(Bloom.lilac)
                Label("粉色框：本次需要复习的小节", systemImage: "rectangle.dashed").foregroundStyle(Bloom.pink)
                Text("示范是本机生成的音符声音和同步键盘。阶段讲解和手动示范会暂停收音；弹奏中的错音只用画面提示，不再播放语音或要求点击开始。")
                Text("带练流程：两小节右手 → 左手 → 双手 → 节奏挑战 → 演奏；完成全部小段后进入整曲演奏。")
                Text("双手达到 70 分或完成 3 遍进入节奏挑战；挑战与演奏要求音符、节奏均达到 90 分，或完成 3 遍。麦克风成绩仍为估算。")
            }.navigationTitle("小兔练琴说明").toolbar { ToolbarItem(placement: .confirmationAction) { Button("明白啦") { dismiss() } } }
        }
    }
}
