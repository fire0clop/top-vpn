import Foundation

/// Прокси-сервер, как его отдаёт бекенд (/proxy/list, /proxy/best).
struct ProxyServer: Codable, Identifiable, Equatable {
    let id: Int
    let host: String
    let port: Int
    let `protocol`: String
    let region: String
    let username: String?
    let password: String?
    let uuid: String?
    let flow: String?
    let publicKey: String?
    let shortId: String?
    let serverName: String?
    let isActive: Bool
    let latencyMs: Int?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, host, port, region, username, password, uuid, flow
        case `protocol`
        case publicKey = "public_key"
        case shortId = "short_id"
        case serverName = "server_name"
        case isActive = "is_active"
        case latencyMs = "latency_ms"
        case expiresAt = "expires_at"
    }

    var asProxyConfig: ProxyConfig {
        ProxyConfig(
            host: host,
            port: port,
            protocolType: `protocol`,
            username: username,
            password: password,
            region: region,
            uuid: uuid,
            flow: flow,
            publicKey: publicKey,
            shortId: shortId,
            serverName: serverName
        )
    }
}
