import Foundation
import NetworkExtension
import Combine

/// Управляет системным VPN-профилем (NETunnelProviderManager): создаёт/обновляет
/// конфигурацию, запускает и останавливает туннель, публикует статус для UI.
/// Сам трафик гоняет PacketTunnelProvider в расширении — здесь только control plane.
@MainActor
final class VPNManager: ObservableObject {
    static let shared = VPNManager()

    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var lastError: String?

    private let tunnelBundleId = "com.splitvpn.app.PacketTunnel"
    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    private init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let conn = note.object as? NEVPNConnection else { return }
            Task { @MainActor in self?.status = conn.status }
        }
    }

    deinit {
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
    }

    /// Подгружает существующий профиль (если есть) и текущий статус.
    func loadCurrentState() async {
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        manager = managers.first
        status = manager?.connection.status ?? .disconnected
    }

    /// Запускает туннель. Сохраняет прокси в App Group, создаёт/обновляет профиль,
    /// затем стартует. Решение «через прокси или напрямую» принимает расширение.
    func start(proxy: ProxyConfig) async {
        lastError = nil
        proxy.saveToAppGroup()
        do {
            let mgr = try await loadOrCreateManager()
            try await configure(mgr, proxy: proxy)
            try mgr.connection.startVPNTunnel()
            manager = mgr
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
    }

    // MARK: - Внутреннее

    private func loadOrCreateManager() async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let mgr = managers.first ?? NETunnelProviderManager()
        // Подтягиваем состояние профиля в этот объект. Без этого первый
        // saveToPreferences у свежесозданного менеджера падает с
        // configurationStale (NEVPNError code 4).
        try? await mgr.loadFromPreferences()
        return mgr
    }

    private func configure(_ mgr: NETunnelProviderManager, proxy: ProxyConfig) async throws {
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleId
        // serverAddress отображается в Настройках iOS — кладём регион прокси.
        proto.serverAddress = proxy.region
        proto.providerConfiguration = [
            "host": proxy.host,
            "port": proxy.port,
            "protocol": proxy.protocolType,
            "username": proxy.username as Any,
            "password": proxy.password as Any,
        ]

        // loadFromPreferences перетирает in-memory правки, поэтому применяем
        // настройки заново перед каждым сохранением.
        func apply() {
            mgr.protocolConfiguration = proto
            mgr.localizedDescription = "SplitVPN"
            mgr.isEnabled = true
        }

        apply()
        do {
            try await mgr.saveToPreferences()
        } catch let error as NSError where error.domain == NEVPNErrorDomain
            && error.code == NEVPNError.configurationStale.rawValue {
            // Конфиг на диске изменился между load и save — перечитываем и пробуем ещё раз.
            try await mgr.loadFromPreferences()
            apply()
            try await mgr.saveToPreferences()
        }
        // Перечитываем — иначе startVPNTunnel может кинуть configurationInvalid.
        try await mgr.loadFromPreferences()
    }
}
