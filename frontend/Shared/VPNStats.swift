import Foundation

/// Снимок трафика туннеля. Расширение (StatsCollector) пишет его в App Group по
/// подписке на статус sing-box, приложение читает по таймеру и показывает в UI.
struct VPNStats: Codable, Equatable {
    /// Текущая скорость, байт/с.
    var uplink: Int64 = 0
    var downlink: Int64 = 0
    /// Суммарно за сессию, байт.
    var uplinkTotal: Int64 = 0
    var downlinkTotal: Int64 = 0
    /// Соединений сейчас.
    var connectionsOut: Int32 = 0
    var updatedAt: Date = .init()

    static let zero = VPNStats()
}

extension VPNStats {
    private static let defaultsKey = "vpn.stats"

    func saveToAppGroup() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        AppGroup.sharedDefaults.set(data, forKey: Self.defaultsKey)
    }

    static func loadFromAppGroup() -> VPNStats {
        guard let data = AppGroup.sharedDefaults.data(forKey: defaultsKey),
              let stats = try? JSONDecoder().decode(VPNStats.self, from: data)
        else { return .zero }
        return stats
    }

    static func clear() {
        AppGroup.sharedDefaults.removeObject(forKey: defaultsKey)
    }
}
