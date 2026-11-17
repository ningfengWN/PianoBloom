import Foundation

struct PhotoScoreEvent: Codable {
    var beat: Double
    var duration: Double
    var right: [Int]
    var left: [Int]
}
struct PhotoScoreDraft: Codable {
    var title: String
    var beatsPerBar: Int
    var beatUnit: Int
    var warnings: [String]
    var events: [PhotoScoreEvent]
    func score(id: String) throws -> PianoScore {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, events.count > 0, events.count <= 1200,
              [2,3,4].contains(beatsPerBar), beatUnit == 4 else { throw PhotoScoreError.invalid("目前支持 2/4、3/4、4/4 拍，需包含曲名和音符。") }
        var previous = -Double.infinity
        for event in events {
            guard event.beat.isFinite, event.duration.isFinite, event.beat >= 0, event.beat <= 3600,
                  event.duration > 0, event.duration <= 16, event.beat > previous,
                  !event.right.isEmpty || !event.left.isEmpty,
                  (event.right + event.left).allSatisfy({ (21...108).contains($0) }),
                  Set(event.right).count == event.right.count, Set(event.left).count == event.left.count else {
                throw PhotoScoreError.invalid("请检查拍点顺序、时值和音高；同一拍的音应合并为一组，不能保存空音组。")
            }
            previous = event.beat
        }
        return PianoScore(id: id, title: title, detail: "照片录入 · 人工核对 · 起音练习谱", beatsPerBar: beatsPerBar,
            events: events.map { ScoreEvent(beat: $0.beat, duration: $0.duration, right: $0.right, left: $0.left) })
    }
}
struct PhotoScoreRecord: Codable, Identifiable {
    let id: String
    let bookID: String?
    let entryID: String?
    let draft: PhotoScoreDraft
    let photoCount: Int
}
enum PhotoScoreError: LocalizedError {
    case invalid(String)
    case quota
    var errorDescription: String? { switch self { case .invalid(let message): return message; case .quota: return "OpenAI API 额度不足或已达账单上限，已停止并暂停后续识谱请求。" } }
}
enum ScorePitchInput {
    static func read(_ text: String) throws -> [Int] {
        try text.split(whereSeparator: { $0 == "," || $0 == "，" || $0.isWhitespace }).map { raw in
            let token = String(raw).uppercased().replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "B")
            if let midi = Int(token), (21...108).contains(midi) { return midi }
            let chars = Array(token)
            let bases: [Character: Int] = ["C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11]
            guard let first = chars.first, let base = bases[first] else { throw PhotoScoreError.invalid("音高请写 C4、F#4、Bb3，多个音用空格分隔。") }
            let accidental = chars.count > 1 && (chars[1] == "#" || chars[1] == "B") ? (chars[1] == "#" ? 1 : -1) : 0
            let offset = accidental == 0 ? 1 : 2
            guard let octave = Int(String(chars.dropFirst(offset))) else { throw PhotoScoreError.invalid("音名需带音区，例如中央 C 写 C4。") }
            let midi = (octave + 1) * 12 + base + accidental
            guard (21...108).contains(midi) else { throw PhotoScoreError.invalid("音高超出钢琴音域。") }
            return midi
        }
    }
}

enum PhotoScoreResponse {
    static func decode(_ data: Data, status: Int) throws -> PhotoScoreDraft {
        guard (200...299).contains(status) else {
            let failure = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = failure?["error"] as? [String: Any]
            let code = error?["code"] as? String ?? error?["type"] as? String ?? ""
            if ["insufficient_quota", "billing_hard_limit_reached", "billing_not_active", "usage_limit_reached"].contains(code) { throw PhotoScoreError.quota }
            let message = status == 401 ? "API Key 无效，请检查识谱设置。" : status == 429 ? "请求过多，本次识谱已停止，不会自动重试。" : "识谱请求失败（\(status)），请检查模型是否支持图像与结构化输出。"
            throw PhotoScoreError.invalid(message)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["status"] as? String == "completed",
              let output = object["output"] as? [[String: Any]] else { throw PhotoScoreError.invalid("识谱结果未完成，照片可能过多。请减少页数后重试。") }
        let texts = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }.filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }
        guard let text = texts.first else { throw PhotoScoreError.invalid("未取得可用的识谱结果，请换一张清晰谱页。") }
        return try JSONDecoder().decode(PhotoScoreDraft.self, from: Data(text.utf8))
    }
}
