import SwiftUI

struct GrandStaffView: View {
    @ObservedObject var model: PracticeModel
    let wide: Bool
    @State private var bloomVisible = false
    @State private var bloomTask: Task<Void, Never>?
    private var perLine: Int { wide ? (model.score.isHanon && model.notationScale < 1.5 ? 16 : 8) : 4 }
    private var lineCount: Int { (model.performance.score.events.count + perLine - 1) / perLine }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(0..<lineCount, id: \.self) { row in
                        StaffSystem(score: model.performance.score, start: row * perLine, count: perLine,
                                    performance: model.performance, position: model.visualPosition, notationScale: model.notationScale, hands: model.hands, beat: model.visualBeat, running: model.running || model.demonstrating)
                            .frame(height: 236 * model.notationScale)
                            .id(row)
                            .accessibilityLabel("第 \(row + 1) 行双手琴谱")
                    }
                }.padding(.horizontal, wide ? 28 : 8).padding(.vertical, 12)
            }
            .onChange(of: model.visualPosition / perLine) { row in
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(min(lineCount - 1, row), anchor: .top) }
            }
            .onChange(of: model.performance.epoch) { _ in
                if model.performance.position == 0 { proxy.scrollTo(0, anchor: .top) }
            }
        }
        .overlay(alignment: .topTrailing) {
            if bloomVisible {
                HStack(spacing: 5) {
                    Text("✿").font(.system(size: 25))
                    Text(model.lastGrade == .wrong ? "记下啦" : "小花开啦").font(.caption.bold())
                }
                .foregroundStyle(model.lastGrade == .wrong ? Color.pink : Color(red: 0.19, green: 0.64, blue: 0.50))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.white, in: Capsule()).shadow(color: .pink.opacity(0.12), radius: 6, y: 2)
                .padding(12).transition(.scale(scale: 0.5).combined(with: .opacity))
                .accessibilityHidden(true).allowsHitTesting(false)
            }
        }
        .onChange(of: model.performance.position) { position in
            guard !model.demonstrating, position > 0,
                  let judgment = model.performance.judgments[position - 1], judgment.grade != .missed else { return }
            bloomTask?.cancel()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) { bloomVisible = true }
            bloomTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 650_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) { bloomVisible = false }
            }
        }
        .onDisappear { bloomTask?.cancel(); bloomVisible = false }
    }
}

private struct StaffSystem: View {
    let score: PianoScore
    let start: Int
    let count: Int
    let performance: Performance
    let position: Int
    let notationScale: Double
    let hands: PracticeHands
    let beat: Double
    let running: Bool
    private let ink = Color(red: 0.15, green: 0.11, blue: 0.17)
    private let pink = Color(red: 0.88, green: 0.31, blue: 0.53)
    private var end: Int { min(start + count, score.events.count) }
    var body: some View {
        Canvas { context, canvasSize in
            let scale = CGFloat(notationScale)
            context.scaleBy(x: scale, y: scale)
            let size = CGSize(width: canvasSize.width / scale, height: canvasSize.height / scale)
            let left: CGFloat = 78, right: CGFloat = size.width - 16
            let topBottom: CGFloat = 88, lowBottom: CGFloat = 188, gap: CGFloat = 10
            let firstBeat = score.events[start].beat
            let last = score.events[end - 1]
            let endBeat = last.beat + last.duration
            let beatWidth = (right - left) / CGFloat(max(1, endBeat - firstBeat))
            func x(_ value: Double) -> CGFloat { left + CGFloat(value - firstBeat) * beatWidth + min(12, beatWidth * 0.08) }
            let leftPitches = score.events[start..<end].flatMap(\.left).sorted()
            let lowTreble = !leftPitches.isEmpty && leftPitches[leftPitches.count / 2] >= 60
            func y(_ note: Int, lower: Bool) -> CGFloat {
                if lower && !lowTreble { return lowBottom - CGFloat(Music.staffStep(note) + 10) * 5 }
                return (lower ? lowBottom : topBottom) + 10 - CGFloat(Music.staffStep(note)) * 5
            }
            func stemGeometry(_ index: Int, lower: Bool) -> (x: CGFloat, head: CGFloat, end: CGFloat, up: Bool) {
                let event = score.events[index]
                let pitches = lower ? event.left : event.right
                let group = (start..<end).filter { event.duration <= 0.5 && score.events[$0].duration <= 0.5 && floor(score.events[$0].beat) == floor(event.beat) }
                let groupYs = (group.isEmpty ? [index] : group).flatMap { lower ? score.events[$0].left : score.events[$0].right }.map { y($0, lower: lower) }
                let bottom = lower ? lowBottom : topBottom
                let average = groupYs.reduce(0, +) / CGFloat(max(1, groupYs.count))
                let up = average >= bottom - 20
                let ownYs = pitches.map { y($0, lower: lower) }
                return (x(event.beat) + (up ? 5 : -5),
                        up ? (ownYs.max() ?? bottom) : (ownYs.min() ?? bottom),
                        up ? (groupYs.min() ?? bottom) - 25 : (groupYs.max() ?? bottom) + 25, up)
            }
            func text(_ string: String, _ point: CGPoint, _ font: Font, _ color: Color, anchor: UnitPoint = .center) {
                context.draw(Text(string).font(font).foregroundColor(color), at: point, anchor: anchor)
            }
            let weakIndices = performance.mistakePositions.union(performance.judgments.filter { $0.value.grade != .perfect }.map(\.key))
            let weakBars = Set(weakIndices.filter { $0 < score.events.count }.map { Int(score.events[$0].beat) / score.beatsPerBar })
            for bar in weakBars {
                let from = max(firstBeat, Double(bar * score.beatsPerBar))
                let to = min(endBeat, Double((bar + 1) * score.beatsPerBar))
                if to > from {
                    context.stroke(Path(roundedRect: CGRect(x: x(from) - 12, y: 30, width: max(20, x(to) - x(from)), height: 194), cornerRadius: 8), with: .color(pink.opacity(0.6)), lineWidth: 1.3)
                }
            }
            // The cursor covers both staves so children can locate both hands at once.
            if position >= start && position < end {
                let currentX = x(score.events[position].beat)
                context.fill(Path(roundedRect: CGRect(x: currentX - 13, y: 8, width: 26, height: 216), cornerRadius: 12), with: .color(pink.opacity(0.10)))
            }
            for (lower, bottom) in [(false, topBottom), (true, lowBottom)] {
                let enabled = lower ? hands != .right : hands != .left
                let opacity = enabled ? 1.0 : 0.35
                if enabled {
                    context.fill(Path(CGRect(x: 28, y: bottom - 45, width: max(0, right - 28), height: 55)), with: .color(pink.opacity(0.035)))
                }
                var staff = Path()
                for line in 0..<5 {
                    staff.move(to: CGPoint(x: 28, y: bottom - CGFloat(line) * gap))
                    staff.addLine(to: CGPoint(x: right, y: bottom - CGFloat(line) * gap))
                }
                context.stroke(staff, with: .color(ink.opacity(0.70 * opacity)), lineWidth: 1.15)
                text(lower && !lowTreble ? "𝄢" : "𝄞", CGPoint(x: 40, y: bottom - 20), .system(size: lower && !lowTreble ? 32 : 46), ink.opacity(opacity))
                text(lower ? "左手" : "右手", CGPoint(x: 4, y: bottom - 20), .system(size: 9, weight: .medium), pink.opacity(opacity), anchor: .leading)
                if start == 0 {
                    text("\(score.beatsPerBar)", CGPoint(x: 61, y: bottom - 29), .system(size: 17, weight: .bold, design: .serif), ink.opacity(opacity))
                    text("4", CGPoint(x: 61, y: bottom - 12), .system(size: 17, weight: .bold, design: .serif), ink.opacity(opacity))
                }
                // A brace joins the grand staff. Original cross-staff notes retain their hand identity.
                if !lower {
                    var join = Path(); join.move(to: CGPoint(x: 24, y: topBottom - 40)); join.addLine(to: CGPoint(x: 24, y: lowBottom))
                    context.stroke(join, with: .color(ink.opacity(0.5)), lineWidth: 2)
                }
                for index in start..<end {
                    let event = score.events[index]
                    let notes = lower ? event.left : event.right
                    let centerX = x(event.beat)
                    let judgment = enabled ? performance.judgments[index] : nil
                    let current = index == position
                    let color: Color
                    switch judgment?.grade {
                    case .perfect?: color = Color(red: 0.19, green: 0.64, blue: 0.50)
                    case .early?, .late?: color = Color(red: 0.19, green: 0.64, blue: 0.50)
                    case .missed?: color = .gray
                    case .wrong?: color = pink
                    case nil: color = current && enabled ? pink : ink
                    }
                    let paint = color.opacity(opacity)
                    if Int((event.beat * 100).rounded()) % (score.beatsPerBar * 100) == 0 {
                        var bar = Path(); bar.move(to: CGPoint(x: centerX - 12, y: bottom - 40)); bar.addLine(to: CGPoint(x: centerX - 12, y: bottom))
                        context.stroke(bar, with: .color(ink.opacity(0.25)), lineWidth: 1.1)
                        if !lower {
                            text("\(Int(event.beat) / score.beatsPerBar + 1)", CGPoint(x: centerX - 12, y: 5), .system(size: 9), .secondary)
                        }
                    }
                    if notes.isEmpty {
                        text("𝄽", CGPoint(x: centerX, y: bottom - 20), .system(size: 24), paint)
                        continue
                    }
                    for note in notes {
                        let centerY = y(note, lower: lower)
                        let staffTop = bottom - 40
                        if centerY >= bottom + gap || centerY <= staffTop - gap {
                            let first = centerY >= bottom + gap ? bottom + gap : staffTop - gap
                            let step: CGFloat = centerY >= bottom + gap ? gap : -gap
                            var ledger = Path()
                            for line in stride(from: first, through: centerY, by: step) {
                                ledger.move(to: CGPoint(x: centerX - 9, y: line)); ledger.addLine(to: CGPoint(x: centerX + 9, y: line))
                            }
                            context.stroke(ledger, with: .color(paint), lineWidth: 1.1)
                        }
                        let head = Path(ellipseIn: CGRect(x: centerX - 5.5, y: centerY - 3.6, width: 11, height: 7.2))
                        if event.duration >= 2 { context.stroke(head, with: .color(paint), lineWidth: 1.8) }
                        else { context.fill(head, with: .color(paint)) }
                        if judgment?.grade == .early || judgment?.grade == .late {
                            let offset: CGFloat = judgment?.grade == .early ? -8 : 8
                            let shadow = Path(ellipseIn: CGRect(x: centerX - 5.5 + offset, y: centerY - 3.6, width: 11, height: 7.2))
                            context.stroke(shadow, with: .color(.red.opacity(0.7)), lineWidth: 1.3)
                        }
                    }
                    if let judgment, judgment.grade != .missed {
                        let noteYs = event.right.map { y($0, lower: false) } + event.left.map { y($0, lower: true) }
                        let flowerY = min(CGFloat(28), (noteYs.min() ?? 48) - 14)
                        // One blossom per onset column, shared by both staves.
                        if !lower || hands == .left || event.right.isEmpty {
                            let blossom = judgment.grade == .wrong ? pink : Color(red: 0.19, green: 0.64, blue: 0.50)
                            for petal in 0..<5 {
                                let angle = Double(petal) * 2 * Double.pi / 5
                                let petalX = centerX + CGFloat(cos(angle)) * 3.2
                                let petalY = flowerY + CGFloat(sin(angle)) * 3.2
                                context.fill(Path(ellipseIn: CGRect(x: petalX - 2.4, y: petalY - 2.4, width: 4.8, height: 4.8)), with: .color(blossom))
                            }
                            context.fill(Path(ellipseIn: CGRect(x: centerX - 1.8, y: flowerY - 1.8, width: 3.6, height: 3.6)), with: .color(.yellow))
                        }
                    }
                    // Beams are grouped by beat (never across barlines); half and quarter notes retain their stems.
                    let stem = stemGeometry(index, lower: lower)
                    let stemY = stem.head, up = stem.up, stemX = stem.x, stemEnd = stem.end
                    if event.duration < 4 {
                        var stem = Path(); stem.move(to: CGPoint(x: stemX, y: stemY)); stem.addLine(to: CGPoint(x: stemX, y: stemEnd))
                        context.stroke(stem, with: .color(paint), lineWidth: 1.6)
                    }
                    if event.duration <= 0.5 {
                        let nextIndex = index + 1
                        let link = nextIndex < end && score.events[nextIndex].duration <= 0.5 && floor(event.beat) == floor(score.events[nextIndex].beat)
                        let previousLink = index > start && score.events[index - 1].duration <= 0.5 && floor(event.beat) == floor(score.events[index - 1].beat)
                        if link {
                            let next = score.events[nextIndex]
                            let nextNotes = lower ? next.left : next.right
                            if let nextNote = nextNotes.first {
                                _ = nextNote
                                let nextStem = stemGeometry(nextIndex, lower: lower)
                                let nextX = nextStem.x, nextEnd = nextStem.end
                                for beam in 0..<(event.duration <= 0.25 ? 2 : 1) {
                                    let shift = CGFloat(beam) * (up ? 5 : -5)
                                    var path = Path(); path.move(to: CGPoint(x: stemX, y: stemEnd + shift)); path.addLine(to: CGPoint(x: nextX, y: nextEnd + shift))
                                    context.stroke(path, with: .color(paint), lineWidth: 2.5)
                                }
                            }
                        } else if !previousLink {
                            text(event.duration <= 0.25 ? "𝅘𝅥𝅯" : "♪", CGPoint(x: stemX + 5, y: stemEnd + 8), .system(size: 14), paint)
                        }
                    }
                }
                var final = Path(); final.move(to: CGPoint(x: right, y: bottom - 40)); final.addLine(to: CGPoint(x: right, y: bottom))
                context.stroke(final, with: .color(ink.opacity(0.4)), lineWidth: end == score.events.count ? 2 : 1)
            }
            // The current note's fixed-do label sits between the staves, away from noteheads.
            if position >= start && position < end {
                let current = score.events[position]
                let notes = current.pitches(hands).sorted()
                let names = notes.map(Music.solfege).reduce(into: [String]()) { result, name in
                    if !result.contains(name) { result.append(name) }
                }
                let label = names.prefix(3).joined(separator: " · ")
                if !label.isEmpty {
                    let width = max(CGFloat(30), CGFloat(label.count) * 5.5 + 12)
                    let labelX = min(right - width / 2, max(left, x(current.beat)))
                    context.fill(Path(roundedRect: CGRect(x: labelX - width / 2, y: 120, width: width, height: 18), cornerRadius: 5), with: .color(pink))
                    text(label, CGPoint(x: labelX, y: 129), .system(size: 10, weight: .bold, design: .rounded), .white)
                }
            }
            if running && performance.style == .rhythm && beat >= firstBeat && beat < endBeat {
                let cursor = x(beat)
                var line = Path(); line.move(to: CGPoint(x: cursor, y: 12)); line.addLine(to: CGPoint(x: cursor, y: 218))
                context.stroke(line, with: .color(pink.opacity(0.65)), lineWidth: 1.5)
                text("✦", CGPoint(x: cursor, y: 14), .system(size: 18), pink)
            }
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }
}
