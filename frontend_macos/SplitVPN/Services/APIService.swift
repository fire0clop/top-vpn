import Foundation

enum APIError: Error, LocalizedError {
    case server(Int, String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case let .server(code, msg): return "Ошибка сервера (\(code)): \(msg)"
        case let .decoding(err): return "Ошибка данных: \(err.localizedDescription)"
        case let .transport(err): return "Сеть недоступна: \(err.localizedDescription)"
        }
    }
}

/// Клиент бекенда. Авторизация вырезана (тестовый проект без пользователей) —
/// эндпоинты публичные. Используется только когда useHardcodedProxy == false.
actor APIService {
    static let shared = APIService()

    private let session = URLSession(configuration: .default)
    private let base = AppConfig.backendBaseURL

    // MARK: - Публичные методы

    func bestProxy() async throws -> ProxyServer {
        let data = try await request("/proxy/best", method: "GET")
        return try decode(ProxyServer.self, from: data)
    }

    func proxies() async throws -> [ProxyServer] {
        let data = try await request("/proxy/list", method: "GET")
        return try decode([ProxyServer].self, from: data)
    }

    func domainsMeta() async throws -> DomainsMeta {
        let data = try await request("/domains/updated_at", method: "GET")
        return try decode(DomainsMeta.self, from: data)
    }

    /// Скачать полный gzip-снимок доменов. URLSession сам распаковывает gzip
    /// по Content-Encoding, поэтому возвращаем уже текст со списком доменов.
    func downloadDomainsExport() async throws -> String {
        let data = try await request("/domains/export", method: "GET")
        return String(decoding: data, as: UTF8.self)
    }

    /// Скачать предкомпилированный бинарный rule-set sing-box (.srs). Расширение
    /// читает его напрямую (format: binary) — компилировать на устройстве нельзя
    /// (libbox не экспортирует компилятор rule-set), поэтому бинарь готовит бекенд.
    func downloadDomainsRuleSet() async throws -> Data {
        try await request("/domains/export.srs", method: "GET")
    }

    /// Скачать бинарный IP rule-set (.srs) — подсети сервисов без домена/SNI
    /// (Telegram MTProto и пр.). Расширение маршрутизирует эти IP в прокси.
    func downloadDomainsIPRuleSet() async throws -> Data {
        try await request("/domains/export-ip.srs", method: "GET")
    }

    // MARK: - Внутреннее

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder.backend.decode(type, from: data) }
        catch { throw APIError.decoding(error) }
    }

    private func request(_ path: String, method: String) async throws -> Data {
        var urlRequest = URLRequest(url: base.appendingPathComponent(path))
        urlRequest.httpMethod = method

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw APIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(-1, "No HTTP response")
        }
        switch http.statusCode {
        case 200..<300:
            return data
        default:
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw APIError.server(http.statusCode, message ?? "Unknown error")
        }
    }
}
