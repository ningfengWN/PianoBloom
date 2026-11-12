import SwiftUI

struct GrandStaffView: View {
    @ObservedObject var model: PracticeModel
    let wide: Bool
    private var perLine: Int { model.score.isHanon && wide ? 16 : 8 }
    private var lineCount: Int { (model.performance.score.events.count + perLine - 1) / perLine }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(0..<lineCount, id: \.self) { row in
                        StaffSystem(score: model.performance.score, start: row * perLine, count: perLine,
                                    performance: model.performance, hands: model.hands, beat: model.beat, running: model.running)
                            .frame(height: wide ? 256 : 236)
                            .id(row)
                            .accessibilityLabel("第 \(row + 1) 行双手琴谱")
                    }
                }.padding(.horizontal, wide ? 28 : 8).padding(.vertical, 12)
            }
            .onChange(of: model.performance.position / perLine) { row in
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(min(lineCount - 1, row), anchor: .top) }
            }
            .onChange(of: model.performance.epoch) { _ in
                if model.performance.position == 0 { proxy.scrollTo(0, anchor: .top) }
            }
        }
    }
}

private struct StaffSystem: View {
    let score: PianoScore
    let start: Int
    let count: Int
    let performance: Performance
    let hands: PracticeHands
    let beat: Double
    let running: Bool
    private let ink = Color(red: 0.30, green: 0.23, blue: 0.33)
    private let pink = Color(red: 0.88, green: 0.31, blue: 0.53)
    private var end: Int { min(start + count, score.events.count) }
    var body: some View {
        Canvas { context, size in
            let left: CGFloat = 58, right: CGFloat = size.width - 16
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
            func text(_ string: String, _ point: CGPoint, _ font: Font, _ color: Color, anchor: UnitPoint = .center) {
                context.draw(Text(string).font(font).foregroundColor(color), at: point, anchor: anchor)
            }
            // The cursor covers both staves so children can locate both hands at once.
            if performance.position >= start && performance.position < end {
                let currentX = x(score.events[performance.position].beat)
                context.fill(Path(roundedRect: CGRect(x: currentX - 13, y: 8, width: 26, height: 216), cornerRadius: 12), with: .color(pink.opacity(0.10)))
            }
            for (lower, bottom) in [(false, topBottom), (true, lowBottom)] {
                let enabled = lower ? hands != .right : hands != .left
                let opacity = enabled ? 1.0 : 0.25
                var staff = Path()
                for line in 0..<5 {
                    staff.move(to: CGPoint(x: 28, y: bottom - CGFloat(line) * gap))
                    staff.addLine(to: CGPoint(x: right, y: bottom - CGFloat(line) * gap))
                }
                context.stroke(staff, with: .color(ink.opacity(0.28 * opacity)), lineWidth: 0.8)
                text(lower && !lowTreble ? "𝄢" : "𝄞", CGPoint(x: 40, y: bottom - 20), .system(size: lower && !lowTreble ? 32 : 46), ink.opacity(opacity))
                text(lower ? "左手" : "右手", CGPoint(x: 4, y: bottom - 20), .system(size: 9, weight: .medium), pink.opacity(opacity), anchor: .leading)
                // A brace joins the grand staff. Original cross-staff notes retain their hand identity.
                if !lower {
                    var join = Path(); join.move(to: CGPoint(x: 24, y: topBottom - 40)); join.addLine(to: CGPoint(x: 24, y: lowBottom))
                    context.stroke(join, with: .color(ink.opacity(0.5)), lineWidth: 2)
                }
                for index in start..<end {
                    let event = score.events[index]
                    let notes = lower ? event.left : event.right
                    let centerX = x(event.beat)
                    let judgment = performance.judgments[index]
                    let current = index == performance.position
                    let color: Color
                    switch judgment?.grade {
                    case .perfect?: color = Color(red: 0.19, green: 0.64, blue: 0.50)
                    case .early?, .late?: color = Color(red: 0.69, green: 0.48, blue: 0.81)
                    case .missed?, .wrong?: color = .orange
                    case nil: color = current ? pink : ink
                    }
                    let paint = color.opacity(opacity)
                    if Int((event.beat * 100).rounded()) % (score.beatsPerBar * 100) == 0 {
                        var bar = Path(); bar.move(to: CGPoint(x: centerX - 12, y: bottom - 40)); bar.addLine(to: CGPoint(x: centerX - 12, y: bottom))
                        context.stroke(bar, with: .color(ink.opacity(0.25)), lineWidth: 0.8)
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
                            context.stroke(ledger, with: .color(paint), lineWidth: 0.8)
                        }
                        let head = Path(ellipseIn: CGRect(x: centerX - 5.5, y: centerY - 3.6, width: 11, height: 7.2))
                        if event.duration >= 2 { context.stroke(head, with: .color(paint), lineWidth: 1.8) }
                        else { context.fill(head, with: .color(paint)) }
                    }
                    // Beams are grouped by beat (never across barlines); half and quarter notes retain their stems.
                    let stemY = y(notes[0], lower: lower)
                    let up = stemY >= bottom - 20
                    let stemX = centerX + (up ? 5 : -5)
                    let stemEnd = stemY + (up ? -25 : 25)
                    if event.duration < 4 {
                        var stem = Path(); stem.move(to: CGPoint(x: stemX, y: stemY)); stem.addLine(to: CGPoint(x: stemX, y: stemEnd))
                        context.stroke(stem, with: .color(paint), lineWidth: 1.2)
                    }
                    if event.duration <= 0.5 {
                        let nextIndex = index + 1
                        let link = nextIndex < end && score.events[nextIndex].duration <= 0.5 && floor(event.beat) == floor(score.events[nextIndex].beat)
                        let previousLink = index > start && score.events[index - 1].duration <= 0.5 && floor(event.beat) == floor(score.events[index - 1].beat)
                        if link {
                            let next = score.events[nextIndex]
                            let nextNotes = lower ? next.left : next.right
                            if let nextNote = nextNotes.first {
                                let nextY = y(nextNote, lower: lower)
                                let nextUp = nextY >= bottom - 20
                                let nextX = x(next.beat) + (nextUp ? 5 : -5)
                                let nextEnd = nextY + (nextUp ? -25 : 25)
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
