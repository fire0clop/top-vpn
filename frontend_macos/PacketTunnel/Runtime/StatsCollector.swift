import Foundation
import Libbox

/// Подписывается на статус sing-box (command-client) и раз в секунду пишет трафик
/// в App Group. Версия под API libbox 1.11 (options.command, лог строками и т.д.).
final class StatsCollector: NSObject, LibboxCommandClientHandlerProtocol {
    private var client: LibboxCommandClient?
    private let queue = DispatchQueue(label: "com.splitvpn.app.PacketTunnel.stats")

    func start() {
        let options = LibboxCommandClientOptions()
        options.command = LibboxCommandStatus
        options.statusInterval = Int64(NSEC_PER_SEC)
        let client = LibboxNewCommandClient(self, options)
        self.client = client
        queue.async { [weak self] in
            guard let client = self?.client else { return }
            for _ in 0 ..< 50 {
                do { try client.connect(); break } catch { Thread.sleep(forTimeInterval: 0.2) }
            }
        }
    }

    func stop() {
        try? client?.disconnect()
        client = nil
        VPNStats.clear()
    }

    // MARK: - LibboxCommandClientHandlerProtocol

    func writeStatus(_ message: LibboxStatusMessage?) {
        guard let m = message else { return }
        var stats = VPNStats()
        stats.uplink = m.uplink
        stats.downlink = m.downlink
        stats.uplinkTotal = m.uplinkTotal
        stats.downlinkTotal = m.downlinkTotal
        stats.connectionsOut = m.connectionsOut
        stats.updatedAt = Date()
        stats.saveToAppGroup()
    }

    func connected() {}
    func disconnected(_: String?) {}
    func clearLogs() {}
    func initializeClashMode(_: LibboxStringIteratorProtocol?, currentMode _: String?) {}
    func updateClashMode(_: String?) {}
    func writeLogs(_: LibboxStringIteratorProtocol?) {}
    func write(_: LibboxConnections?) {}
    func writeGroups(_: LibboxOutboundGroupIteratorProtocol?) {}
}
