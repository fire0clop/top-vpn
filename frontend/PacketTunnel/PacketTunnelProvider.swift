import Libbox
import NetworkExtension
import os.log

/// Главный класс расширения. Поднимает sing-box (libbox) как движок туннеля:
/// весь трафик заходит в tun, sing-box по rule-set заблокированных доменов
/// решает — гнать соединение через SOCKS5-прокси или напрямую (split tunneling).
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let log = Logger(subsystem: "com.splitvpn.app.PacketTunnel", category: "tunnel")
    private var commandServer: LibboxCommandServer?
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
        // iOS убивает Network Extension при превышении ~50 МБ (jetsam ActiveHard).
        // Включаем watchdog sing-box: у лимита он форсит агрессивный Go GC, чтобы
        // удержать процесс под потолком. Ставим 45 МБ — запас до фатальных 50.
        setup.oomKillerEnabled = true
        setup.oomMemoryLimit = 45 * 1024 * 1024
        var setupError: NSError?
        LibboxSetup(setup, &setupError)
        if let setupError { throw setupError }

        let config = try SingBoxConfig.build(
            proxy: proxy,
            blockedRuleSetPath: FilePath.resolvedRuleSetPath,
            blockedIPRuleSetPath: FilePath.resolvedIPRuleSetPath
        )

        let platform = BoxPlatformInterface(self)
        var serverError: NSError?
        guard let server = LibboxNewCommandServer(platform, platform, &serverError) else {
            throw serverError ?? TunnelError.startFailed
        }
        platformInterface = platform
        commandServer = server

        try server.start()

        // ДИАГНОСТИКА: подписываемся на лог-поток движка ДО старта сервиса, чтобы
        // не пропустить ранние сообщения о dial аутбаунда / Reality-хендшейке.
        let collector = LogCollector()
        collector.start()
        logCollector = collector

        // Сбор трафика (скорость/объём) для отображения в приложении.
        let stats = StatsCollector()
        stats.start()
        statsCollector = stats

        try server.startOrReloadService(config, options: LibboxOverrideOptions())
        log.info("sing-box запущен")

        // Смену сети (WiFi↔сотовая) обрабатывает сам sing-box: платформенный монитор
        // (BoxPlatformInterface.startDefaultInterfaceMonitor) сообщает движку новый
        // дефолтный интерфейс, а тот при auto_detect_interface перебиндивает соединения.
        // Никакого ручного resetNetwork — как в эталоне sing-box-for-apple.
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
        try? commandServer?.closeService()
        commandServer?.close()
        commandServer = nil
        platformInterface?.reset()
        platformInterface = nil
    }

    // sleep()/wake() — как в эталоне sing-box-for-apple. iOS зовёт их при усыплении/
    // пробуждении расширения (в т.ч. блокировка экрана, простой WiFi-радио). pause()
    // корректно замораживает движок, wake() — будит и освежает соединения. Без этого
    // после простоя на WiFi туннель «вис» (поработал и перестал пропускать данные).
    override func sleep(completionHandler: @escaping () -> Void) {
        commandServer?.pause()
        completionHandler()
    }

    override func wake() {
        commandServer?.wake()
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
