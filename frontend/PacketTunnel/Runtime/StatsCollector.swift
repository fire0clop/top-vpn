import Foundation
import Libbox

/// Подписывается на статус sing-box через command-client (тот же канал, что и логи)
/// и раз в секунду пишет трафик (скорость + суммарно) в App Group. Приложение читает
/// это по таймеру и показывает в интерфейсе.
final class StatsCollector: NSObject, LibboxCommandClientHandlerProtocol {
    private var client: LibboxCommandClient?
    private let queue = DispatchQueue(label: "com.splitvpn.app.PacketTunnel.stats")

    func start() {
        let options = LibboxCommandClientOptions()
        options.addCommand(LibboxCommandStatus)
        options.statusInterval = Int64(NSEC_PER_SEC) // обновление раз в секунду
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
    func setDefaultLogLevel(_: Int32) {}
    func updateClashMode(_: String?) {}
    func writeLogs(_: LibboxLogIteratorProtocol?) {}
    func write(_: LibboxConnectionEvents?) {}
    func writeGroups(_: LibboxOutboundGroupIteratorProtocol?) {}
    func writeOutbounds(_: LibboxOutboundGroupItemIteratorProtocol?) {}
}
