import Foundation

/// Один эндпоинт сервера (host:port). Ключи Reality общие для всего пула.
/// `serverName` — необязательная маскировка (SNI/Reality-фронт) именно для этого
/// эндпоинта: разные порты прячутся за разными доменами (apple/icloud/mozilla/…),
/// чтобы поломка одного фронта (как www.microsoft.com 2026-06-27) не уронила весь
/// пул — urltest сам уйдёт на живые. nil → берётся общий ProxyConfig.serverName.
struct ProxyEndpoint: Codable, Equatable {
    var host: String
    var port: Int
    var serverName: String?
}

/// Конфигурация прокси-сервера, полученная с бекенда (/proxy/best).
/// Приложение сохраняет её в App Group, расширение читает при старте туннеля.
struct ProxyConfig: Codable, Equatable {
    var host: String
    var port: Int
    var protocolType: String   // "socks5" | "vless" | ...
    var username: String?
    var password: String?
    var region: String
    // VLESS+Reality (заполнены при protocolType == "vless")
    var uuid: String?
    var flow: String?
    var publicKey: String?
    var shortId: String?
    var serverName: String?
    // Транспорт. network == "ws" → VLESS поверх WebSocket+TLS (через CDN/Cloudflare):
    // обход блокировки по IP/порту, т.к. трафик идёт на адреса Cloudflare. В этом
    // режиме Reality/flow не используются. nil или "tcp" → прежний VLESS+Reality.
    var network: String?
    var wsPath: String?
    // ECH (Encrypted Client Hello): base64 ECHConfigList. Прячет реальный SNI
    // (внешне видно только cloudflare-ech.com) — без этого ТСПУ режет наш поток по
    // имени домена. Конфиг берётся из HTTPS-DNS-записи домена в Cloudflare.
    var echConfig: String?
    // Пул эндпоинтов для авторотации (urltest). Все с одними ключами Reality —
    // отличаются только host:port. Если задан (>1), клиент сам выбирает живой и
    // переключается при блокировке. nil/пусто → используется одиночный host:port.
    var endpoints: [ProxyEndpoint]?

    enum CodingKeys: String, CodingKey {
        case host, port
        case protocolType = "protocol"
        case username, password, region
        case uuid, flow
        case publicKey = "public_key"
        case shortId = "short_id"
        case serverName = "server_name"
        case network
        case wsPath = "ws_path"
        case echConfig = "ech_config"
        case endpoints
    }
}

extension ProxyConfig {
    private static let defaultsKey = "proxy.config"

    /// Сохранить выбранный прокси в общий контейнер.
    func saveToAppGroup() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        AppGroup.sharedDefaults.set(data, forKey: Self.defaultsKey)
    }

    /// Прочитать прокси из общего контейнера (вызывается в расширении).
    static func loadFromAppGroup() -> ProxyConfig? {
        guard let data = AppGroup.sharedDefaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(ProxyConfig.self, from: data)
    }
}
