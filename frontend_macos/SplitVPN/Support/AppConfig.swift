import Foundation

enum AppConfig {
    /// Базовый URL бекенда.
    /// LAN-IP Mac — чтобы реальный iPhone в той же Wi-Fi достучался до бэка.
    /// (Для симулятора подошёл бы и localhost; этот IP работает в обоих случаях,
    /// пока телефон и Mac в одной сети.)
    static let backendBaseURL = URL(string: "http://YOUR_BACKEND_HOST:8080")!

    /// Как часто приложение проверяет обновление списка доменов.
    static let domainSyncInterval: TimeInterval = 60 * 60 * 24  // раз в сутки

    /// ТЕСТОВЫЙ РЕЖИМ: один захардкоженный прокси, бэкенд можно выключить совсем.
    /// Гео-модель маршрутизации (.ru→direct, остальное→proxy) список доменов не
    /// использует, поэтому при true приложение не ходит на бэк ни за прокси, ни за
    /// доменами. Вернуть false, когда поднимем пул серверов с авторотацией через бэк.
    static let useHardcodedProxy = true

    /// Пул VLESS+Reality серверов с авторотацией (клиентский urltest, без бэкенда).
    /// Все эндпоинты с ОДНИМИ ключами Reality — клиент сам выбирает живой и переключается
    /// при блокировке DPI. host/port — фолбэк-дефолт (первый эндпоинт).
    /// Серверы: YOUR_SERVER_A_HOST (NL) и YOUR_SERVER_B_HOST (DE), каждый на 443/8443/2053/41820.
    static let hardcodedProxy = ProxyConfig(
        host: "YOUR_SERVER_A_HOST",
        port: 8443,
        protocolType: "vless",
        username: nil,
        password: nil,
        region: "Европа",
        uuid: "00000000-0000-0000-0000-000000000000",
        flow: "xtls-rprx-vision",
        publicKey: "YOUR_REALITY_PUBLIC_KEY",
        shortId: "YOUR_REALITY_SHORT_ID",
        serverName: "www.apple.com",
        // Разнообразие маскировки: каждый порт прячется за своим доменом
        // (apple/icloud/mozilla/lovelive). Поломка одного фронта валит лишь ~четверть
        // пула — urltest сам уходит на живые, полного простоя нет. На серверах
        // serverNames = суперсет всех 4 доменов, поэтому сторож может менять dest
        // без рассинхрона с этими SNI. См. [[project-splitvpn-proxy]].
        // Порядок важен: urltest на «прогреве» (до первого замера) держит ПЕРВЫЙ
        // эндпоинт, поэтому :443 (его РФ-ТСПУ режет чаще всего) идёт ПОСЛЕДНИМ, а
        // первыми — надёжные нестандартные порты. Иначе на старте подключения юзер
        // упирается в заблокированный :443, пока urltest не переключится.
        endpoints: [
            .init(host: "YOUR_SERVER_A_HOST", port: 8443, serverName: "gateway.icloud.com"),
            .init(host: "YOUR_SERVER_A_HOST", port: 2053, serverName: "addons.mozilla.org"),
            .init(host: "YOUR_SERVER_A_HOST", port: 41820, serverName: "www.lovelive-anime.jp"),
            .init(host: "YOUR_SERVER_B_HOST", port: 8443, serverName: "gateway.icloud.com"),
            .init(host: "YOUR_SERVER_B_HOST", port: 2053, serverName: "addons.mozilla.org"),
            .init(host: "YOUR_SERVER_B_HOST", port: 41820, serverName: "www.lovelive-anime.jp"),
            .init(host: "YOUR_SERVER_A_HOST", port: 443, serverName: "www.apple.com"),
            .init(host: "YOUR_SERVER_B_HOST", port: 443, serverName: "www.apple.com"),
        ]
    )
}

/// JSON-декодер, понимающий ISO8601 с дробными секундами (формат бекенда).
extension JSONDecoder {
    static let backend: JSONDecoder = {
        let decoder = JSONDecoder()
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = withFractional.date(from: string) ?? plain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid date: \(string)"
            )
        }
        return decoder
    }()
}
