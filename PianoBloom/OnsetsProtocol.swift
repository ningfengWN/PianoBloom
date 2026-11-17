import Foundation

enum RecognitionEngine: String, CaseIterable {
    case basic = "基础识音（实验）"
    case onsetsVelocities = "Onsets & Velocities（Mac）"
}

struct ModelOnset: Decodable {
    var time: Double
    let notes: [Int]
}

struct OnsetsServerMessage: Decodable {
    let type: String
    let model: String?
    let version: Int?
    let sourceCommit: String?
    let checkpointSHA256: String?
    let minimumDelay: Double?
    let events: [ModelOnset]?
    let processedThrough: Double?
    let capturedThrough: Double?
    let inferenceMS: Double?
    let message: String?
    enum CodingKeys: String, CodingKey {
        case type, model, events, message
        case version = "protocol", sourceCommit = "source_commit"
        case checkpointSHA256 = "checkpoint_sha256", minimumDelay = "minimum_delay"
        case processedThrough = "processed_through", capturedThrough = "captured_through"
        case inferenceMS = "inference_ms"
    }
    static let source = "629ff11aceadf01ecc456b1c7f26a104f7e1e571"
    static let checkpoint = "90901ff8c7cb15c76a4da2f4aca643a10295c834ac9e549ee16097d4bbce642d"
    func validReady() -> Bool {
        type == "ready" && version == 1 && model == "Onsets & Velocities" &&
        sourceCommit == Self.source && checkpointSHA256 == Self.checkpoint &&
        (minimumDelay.map { $0.isFinite && $0 >= 0 && $0 <= 10 } ?? false)
    }
    func validEvents(after watermark: Double) -> Bool {
        guard type == "events", let events, events.count <= 512,
              let through = processedThrough, through.isFinite, through >= watermark,
              let captured = capturedThrough, captured.isFinite, captured >= through,
              let inferenceMS, inferenceMS.isFinite, inferenceMS >= 0 else { return false }
        var previous = watermark
        for event in events {
            guard event.time.isFinite, event.time >= previous, event.time <= through,
                  !event.notes.isEmpty, event.notes.count <= 88,
                  Set(event.notes).count == event.notes.count,
                  event.notes.allSatisfy({ (21...108).contains($0) }) else { return false }
            previous = event.time
        }
        return true
    }
}
