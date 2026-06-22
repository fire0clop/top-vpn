import Foundation
import NetworkExtension
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var selectedProxy: ProxyConfig?
    @Published var proxyRegion: String = "—"
    @Published var domainsCount: Int = 0
    @Published var lastSync: Date?
    @Published var statusText: String = "Отключено"
    @Published var isBusy = false
    @Published var error: String?

    // Трафик (читается из App Group раз в секунду, пока туннель активен).
    @Published var downloadSpeed: Int64 = 0
    @Published var uploadSpeed: Int64 = 0
    @Published var downloadTotal: Int64 = 0
    @Published var uploadTotal: Int64 = 0
    @Published var connectedSince: Date?

    private let vpn = VPNManager.shared
    private let domains = DomainService.shared
    private var cancellables = Set<AnyCancellable>()
    private var statsTimer: Timer?

    var vpnStatus: NEVPNStatus { vpn.status }
    var isConnected: Bool { vpn.status == .connected }
    var isTransitioning: Bool {
        vpn.status == .connecting || vpn.status == .disconnecting || vpn.status == .reasserting
    }

    init() {
        vpn.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.statusText = Self.label(for: $0)
                self?.handleStatusChange($0)
            }
            .store(in: &cancellables)
        vpn.$lastError
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .assign(to: &$error)
        domains.$localCount.receive(on: RunLoop.main).assign(to: &$domainsCount)
        domains.$lastSyncedAt.receive(on: RunLoop.main).assign(to: &$lastSync)
    }

    /// Стартовая загрузка: статус туннеля, лучший прокси, синк доменов.
    func onAppear() async {
        await vpn.loadCurrentState()
        domainsCount = (try? DomainStore().count()) ?? 0
        await refreshProxy()
        // В тестовом режиме домены не нужны (гео-модель) и бэк выключен — не синкаем.
        if !AppConfig.useHardcodedProxy {
            await syncDomains()
        }
    }

    func refreshProxy() async {
        // Тестовый режим: берём захардкоженный прокси, на бэкенд не ходим.
        if AppConfig.useHardcodedProxy {
            selectedProxy = AppConfig.hardcodedProxy
            proxyRegion = AppConfig.hardcodedProxy.region
            return
        }
        do {
            let best = try await APIService.shared.bestProxy()
            let config = best.asProxyConfig
            selectedProxy = config
            proxyRegion = config.region
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func syncDomains() async {
        do {
            try await domains.syncIfNeeded()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func toggleConnection() async {
        error = nil
        if isConnected || isTransitioning {
            vpn.stop()
            return
        }
        guard let proxy = selectedProxy else {
            await refreshProxy()
            guard let proxy = selectedProxy else {
                error = "Нет доступного прокси"
                return
            }
            await vpn.start(proxy: proxy)
            return
        }
        isBusy = true
        defer { isBusy = false }
        // Перед стартом убеждаемся, что список доменов на устройстве свежий.
        // В тестовом режиме (гео-модель, бэк выключен) синк пропускаем — иначе
        // вне домашней сети вызов висит весь таймаут до недоступного бэкенда.
        if !AppConfig.useHardcodedProxy {
            await syncDomains()
        }
        await vpn.start(proxy: proxy)
    }

    // MARK: - Трафик

    private func handleStatusChange(_ status: NEVPNStatus) {
        if status == .connected {
            if connectedSince == nil { connectedSince = Date() }
            startStatsPolling()
        } else {
            stopStatsPolling()
            connectedSince = nil
            downloadSpeed = 0; uploadSpeed = 0; downloadTotal = 0; uploadTotal = 0
        }
    }

    private func startStatsPolling() {
        guard statsTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStats() }
        }
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer
        refreshStats()
    }

    private func stopStatsPolling() {
        statsTimer?.invalidate()
        statsTimer = nil
    }

    private func refreshStats() {
        let s = VPNStats.loadFromAppGroup()
        downloadSpeed = s.downlink
        uploadSpeed = s.uplink
        downloadTotal = s.downlinkTotal
        uploadTotal = s.uplinkTotal
    }

    private static func label(for status: NEVPNStatus) -> String {
        switch status {
        case .invalid, .disconnected: return "Отключено"
        case .connecting: return "Подключение…"
        case .connected: return "Защищено"
        case .disconnecting: return "Отключение…"
        case .reasserting: return "Переподключение…"
        @unknown default: return "—"
        }
    }
}
