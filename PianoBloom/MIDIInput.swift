import CoreMIDI
import AVFoundation
import Combine
import Foundation

struct PianoMIDISource: Identifiable { let id: MIDIEndpointRef; let name: String }
final class MIDIInput: ObservableObject {
    @Published private(set) var sources: [PianoMIDISource] = []
    @Published private(set) var selected: MIDIEndpointRef = 0
    @Published private(set) var active = Set<Int>()
    @Published private(set) var message = "请用 USB 连接电钢琴"
    @Published private(set) var listening = false
    var onNote: ((Int, Bool, Double) -> Void)?
    var onDisconnect: (() -> Void)?
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var parser = MIDIByteParser()
    private var generation = UUID()
    init() {
        let result = MIDIClientCreateWithBlock("PianoBloom" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        guard result == noErr else { message = "MIDI 初始化失败，请重新打开 App"; return }
        let resultPort = MIDIInputPortCreateWithBlock(client, "Piano keyboard" as CFString, &port) { [weak self] list, _ in
            let offset = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
            var packet = UnsafeRawPointer(list).advanced(by: offset).assumingMemoryBound(to: MIDIPacket.self)
            for _ in 0..<list.pointee.numPackets {
                let count = Int(packet.pointee.length)
                let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \.data)!
                let bytes = Array(UnsafeBufferPointer(start: UnsafeRawPointer(packet).advanced(by: dataOffset).assumingMemoryBound(to: UInt8.self), count: count))
                let time = packet.pointee.timeStamp == 0 ? ProcessInfo.processInfo.systemUptime : AVAudioTime.seconds(forHostTime: packet.pointee.timeStamp)
                DispatchQueue.main.async { [weak self] in self?.receive(bytes, at: time) }
                packet = UnsafePointer(MIDIPacketNext(packet))
            }
        }
        guard resultPort == noErr else { message = "无法打开 MIDI 输入端口"; return }
        refresh()
    }
    deinit { if port != 0 { MIDIPortDispose(port) }; if client != 0 { MIDIClientDispose(client) } }
    func refresh() {
        sources = (0..<MIDIGetNumberOfSources()).map { index in
            let endpoint = MIDIGetSource(index)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
            return PianoMIDISource(id: endpoint, name: name?.takeRetainedValue() as String? ?? "MIDI 钢琴")
        }
        if selected != 0, !sources.contains(where: { $0.id == selected }) {
            let wasListening = listening
            stop(); selected = 0
            if wasListening { onDisconnect?() }
        }
        if selected == 0 { selected = sources.first?.id ?? 0 }
        message = sources.first(where: { $0.id == selected })?.name ?? "请用 USB 连接电钢琴"
    }
    func select(_ source: MIDIEndpointRef) { stop(); selected = source; refresh() }
    func start() {
        refresh()
        guard selected != 0, port != 0 else { return }
        parser = MIDIByteParser(); active = []
        let status = MIDIPortConnectSource(port, selected, nil)
        listening = status == noErr
        if !listening { message = "连接 MIDI 失败，请拔插后重试" }
    }
    func stop() {
        if listening { MIDIPortDisconnectSource(port, selected) }
        listening = false; active = []; parser = MIDIByteParser(); generation = UUID()
    }
    private func receive(_ bytes: [UInt8], at time: Double) {
        guard listening else { return }
        for event in parser.feed(bytes) {
            if event.on { active.insert(event.note) } else { active.remove(event.note) }
            onNote?(event.note, event.on, time)
        }
    }
}
