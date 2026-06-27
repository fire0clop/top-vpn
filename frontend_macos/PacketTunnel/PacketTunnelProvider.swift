import Libbox
import NetworkExtension
import os.log

/// Главный класс расширения. Поднимает sing-box (libbox) как движок туннеля:
/// весь трафик заходит в tun, sing-box по rule-set заблокированных доменов
/// решает — гнать соединение через SOCKS5-прокси или напрямую (split tunneling).
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let log = Logger(subsystem: "com.splitvpn.app.PacketTunnel", category: "tunnel")
    private var commandServer: LibboxCommandServer?
    private var service: LibboxBoxService?
    private var platformInterface: BoxPlatformInterface?
    private var logCollector: LogCollector?
    private var statsCollector: StatsCollector?

    override func startTunnel(
        options _: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let proxy = ProxyConfig.loadFromAppGroup() else {
            log.error("Нет конфигурации прокси в App Group")
            completionHandler(TunnelError.missingProxy)
            return
        }
        log.info("Старт туннеля, прокси \(proxy.host, privacy: .public):\(proxy.port)")

        // libbox.startService синхронный и блокирующий (вызовет openTun) — уводим
        // его с основного потока, чтобы не держать NetworkExtension callback.
        Task.detached(priority: .userInitiated) { [self] in
            do {
                try startService(proxy: proxy)
                completionHandler(nil)
            } catch {
                log.error("Ошибка старта sing-box: \(error.localizedDescription, privacy: .public)")
                completionHandler(error)
            }
        }
    }

    private func startService(proxy: ProxyConfig) throws {
        let setup = LibboxSetupOptions()
        setup.basePath = FilePath.sharedDirectory.path
        setup.workingPath = FilePath.workingDirectory.path
        setup.tempPath = FilePath.cacheDirectory.path
        var setupError: NSError?
        LibboxSetup(setup, &setupError)
        if let setupError { throw setupError }

        let config = try SingBoxConfig.build(
            proxy: proxy,
            blockedRuleSetPath: FilePath.resolvedRuleSetPath,
            blockedIPRuleSetPath: FilePath.resolvedIPRuleSetPath
        )

        let platform = BoxPlatformInterface(self)
        platformInterface = platform

        // Новая архитектура libbox: движок — отдельный LibboxBoxService (конфиг +
        // платформенный интерфейс), а командный сервер только обслуживает лог-поток.
        var serviceError: NSError?
        guard let service = LibboxNewService(config, platform, &serviceError) else {
            throw serviceError ?? TunnelError.startFailed
        }
        self.service = service

        guard let server = LibboxNewCommandServer(platform, 3000) else {
            throw TunnelError.startFailed
        }
        commandServer = server
        server.setService(service)
        try server.start()

        // Подписываемся на лог-поток движка ДО его старта.
        let collector = LogCollector()
        collector.start()
        logCollector = collector

        let stats = StatsCollector()
        stats.start()
        statsCollector = stats

        try service.start()
        log.info("sing-box запущен")

        // Смену сети (WiFi↔сотовая) движок обрабатывает сам через auto_detect_interface:
        // платформенный монитор сообщает новый дефолтный интерфейс.
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        log.info("Стоп туннеля, причина \(reason.rawValue)")
        stopService()
        completionHandler()
    }

    /// Останавливает движок: вызывается и из stopTunnel, и из libbox handler.
    func stopService() {
        logCollector?.stop()
        logCollector = nil
        statsCollector?.stop()
        statsCollector = nil
        try? service?.close()
        service = nil
        try? commandServer?.close()
        commandServer = nil
        platformInterface?.reset()
        platformInterface = nil
    }

    // pause/wake движка при усыплении/пробуждении расширения (блокировка экрана, простой
    // радио). В новой архитектуре они на самом сервисе, а не на командном сервере.
    override func sleep(completionHandler: @escaping () -> Void) {
        service?.pause()
        completionHandler()
    }

    override func wake() {
        service?.wake()
    }

    override func handleAppMessage(_: Data, completionHandler: ((Data?) -> Void)?) {
        completionHandler?(nil)
    }
}

enum TunnelError: Error, LocalizedError {
    case missingProxy
    case startFailed

    var errorDescription: String? {
        switch self {
        case .missingProxy: return "Прокси не настроен"
        case .startFailed: return "Не удалось запустить движок"
        }
    }
}
