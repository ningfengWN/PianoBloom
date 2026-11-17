import AVFoundation
import Foundation

/// Independent network client; model/code execute in the GPL service, not in this app.
/// All mutable transport and resampler state lives on one serial queue.
final class OnsetsVelocitiesClient {
    var onReady: ((Double) -> Void)?
    var onEvents: (([ModelOnset], Double, Double) -> Void)?
    var onFailure: ((String) -> Void)?
    private let queue = DispatchQueue(label: "com.pianobloom.onsets.transport")
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var generation = UUID()
    private var active = false, ready = false, sending = false
    private var outgoing: [Data] = []
    private var partial: [Float] = []
    private var origin: Double?
    private var watermark = 0.0

    func start(address: String, token: String, sampleRate: Double) {
        queue.async {
            self.close()
            let id = self.generation
            guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
                  ["ws", "wss"].contains(url.scheme ?? ""), url.host != nil,
                  url.user == nil, url.password == nil, !token.isEmpty else {
                self.fail("请在家长设置填写模型服务地址和连接码。", id: id); return
            }
            self.active = true; self.origin = nil; self.watermark = 0
            guard let input = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
                  let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: input, to: output) else {
                self.fail("无法准备模型音频格式。", id: id); return
            }
            converter.primeMethod = .none
            self.inputFormat = input; self.converter = converter
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            let session = URLSession(configuration: configuration)
            self.session = session
            let socket = session.webSocketTask(with: url)
            socket.maximumMessageSize = 1024 * 1024
            self.socket = socket; socket.resume()
            let start: [String: Any] = ["protocol": 1, "sample_rate": 16000, "token": token]
            guard let data = try? JSONSerialization.data(withJSONObject: start), let text = String(data: data, encoding: .utf8) else {
                self.fail("无法创建模型连接。", id: id); return
            }
            socket.send(.string(text)) { error in
                if let error { self.queue.async { self.fail(error.localizedDescription, id: id) } }
            }
            self.receive(id: id)
            self.queue.asyncAfter(deadline: .now() + 10) {
                if self.generation == id && !self.ready { self.fail("模型未响应，请检查 Mac 服务和同一 Wi-Fi 连接。", id: id) }
            }
        }
    }

    func append(_ samples: [Float], endTime: Double) {
        queue.async {
            guard self.active, self.ready, let converter = self.converter, let inputFormat = self.inputFormat else { return }
            let id = self.generation
            if self.origin == nil { self.origin = endTime - Double(samples.count) / inputFormat.sampleRate }
            guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)),
                  let inputData = input.floatChannelData?[0],
                  let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat,
                    frameCapacity: AVAudioFrameCount(ceil(Double(samples.count) * 16000 / inputFormat.sampleRate)) + 64) else {
                self.fail("模型音频缓冲创建失败。", id: id); return
            }
            input.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { if let base = $0.baseAddress { inputData.update(from: base, count: samples.count) } }
            var supplied = false
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if supplied { inputStatus.pointee = .noDataNow; return nil }
                supplied = true; inputStatus.pointee = .haveData; return input
            }
            guard status != .error, error == nil, let values = output.floatChannelData?[0] else {
                self.fail(error?.localizedDescription ?? "音频转换失败。", id: id); return
            }
            self.partial.append(contentsOf: UnsafeBufferPointer(start: values, count: Int(output.frameLength)))
            while self.partial.count >= 1536 {
                let block = Array(self.partial.prefix(1536)); self.partial.removeFirst(1536)
                let data = block.withUnsafeBytes { Data($0) } // Apple platforms use little-endian Float32.
                self.outgoing.append(data)
            }
            guard self.outgoing.count <= 8 else { self.fail("模型连接跟不上录音，已暂停，请检查网络。", id: id); return }
            self.sendNext(id: id)
        }
    }

    private func sendNext(id: UUID) {
        guard generation == id, active, !sending, !outgoing.isEmpty, let socket else { return }
        sending = true
        let block = outgoing.removeFirst()
        socket.send(.data(block)) { error in
            self.queue.async {
                guard self.generation == id else { return }
                self.sending = false
                if let error { self.fail(error.localizedDescription, id: id) }
                else { self.sendNext(id: id) }
            }
        }
    }
    private func receive(id: UUID) {
        socket?.receive { result in
            self.queue.async {
                guard self.generation == id, self.active else { return }
                do {
                    let data: Data
                    switch try result.get() {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: throw ClientError.invalidMessage
                    }
                    let reply = try JSONDecoder().decode(OnsetsServerMessage.self, from: data)
                    if reply.type == "error" { self.fail(reply.message ?? "模型服务出错。", id: id); return }
                    if !self.ready {
                        guard reply.validReady(), let delay = reply.minimumDelay else { throw ClientError.invalidModel }
                        self.ready = true
                        DispatchQueue.main.async { self.onReady?(delay) }
                    } else {
                        guard reply.validEvents(after: self.watermark), let through = reply.processedThrough,
                              let origin = self.origin else { throw ClientError.invalidMessage }
                        self.watermark = through
                        let events = (reply.events ?? []).map { event -> ModelOnset in
                            var absolute = event; absolute.time += origin; return absolute
                        }
                        let delay = max(0, ProcessInfo.processInfo.systemUptime - origin - through)
                        guard delay < 12 else { throw ClientError.tooSlow }
                        DispatchQueue.main.async { self.onEvents?(events, origin + through, delay) }
                    }
                    self.receive(id: id)
                } catch { self.fail(error.localizedDescription, id: id) }
            }
        }
    }
    func stop() { queue.async { self.close() } }
    private func close() {
        generation = UUID(); active = false; ready = false; sending = false
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        converter = nil; inputFormat = nil; outgoing = []; partial = []; origin = nil
    }
    private func fail(_ message: String, id: UUID) {
        guard generation == id else { return }
        close()
        DispatchQueue.main.async { self.onFailure?(message) }
    }
    private enum ClientError: LocalizedError {
        case invalidMessage, invalidModel, tooSlow
        var errorDescription: String? {
            switch self {
            case .invalidMessage: return "模型返回了无效音符或时间信息，已暂停。"
            case .invalidModel: return "服务端模型或协议与此版本不匹配，请更新 Mac 服务。"
            case .tooSlow: return "模型处理积压超过 12 秒，已暂停，请使用更快的推理设备。"
            }
        }
    }
}
