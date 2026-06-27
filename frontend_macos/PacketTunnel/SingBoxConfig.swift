import Foundation

/// Собирает JSON-конфиг sing-box для раздельного туннелирования по ГЕОГРАФИИ:
/// российские домены (.ru/.рф/.su) идут напрямую, ВСЁ остальное — через прокси.
///
/// Почему так, а не по блок-листу: список antizapret покрывает только «заблокировано
/// Россией». Сервисы, которые душатся (YouTube) или геоблокируются самим провайдером
/// для РФ-IP (ChatGPT/OpenAI), в нём отсутствуют — приходилось латать вручную. Гео-модель
/// проксирует любой зарубежный ресурс автоматически; для РФ-сервисов — прямой маршрут
/// (быстро, и часть из них сама блокирует иностранные IP).
enum SingBoxConfig {
    /// Российские зоны → прямой маршрут. `.рф` в SNI/резолве приходит в punycode,
    /// поэтому добавляем и xn--p1ai.
    private static let ruDomainSuffixes = [".ru", ".рф", "xn--p1ai", ".su"]

    static func build(
        proxy: ProxyConfig,
        blockedRuleSetPath _: String,
        blockedIPRuleSetPath _: String
    ) throws -> String {
        let proxyOutbounds = makeProxyOutbounds(proxy)

        let config: [String: Any] = [
            // ДИАГНОСТИКА: уровень повышен до debug, чтобы LogCollector выловил
            // причину, по которой Reality-аутбаунд не уходит на WiFi. Вернуть на warn.
            "log": ["level": "debug", "timestamp": true],
            "dns": [
                "servers": [
                    // Заблокированное/зарубежное резолвим через прокси (обход подмены DPI
                    // и корректный гео-резолв для сервисов вроде OpenAI).
                    // Формат sing-box 1.11: DNS-сервер задаётся через "address" (URL),
                    // а не "type"/"server" (то — формат 1.12+).
                    ["tag": "dns-proxy", "address": "https://1.1.1.1/dns-query", "detour": "proxy"],
                    // Российские домены — системным резолвером (local).
                    ["tag": "dns-direct", "address": "local"],
                ],
                "rules": [
                    // РФ-зоны резолвим напрямую, остальное (final) — через прокси.
                    ["domain_suffix": ruDomainSuffixes, "server": "dns-direct"],
                ],
                "final": "dns-proxy",
                "strategy": "ipv4_only",
            ],
            "inbounds": [
                [
                    "type": "tun",
                    "tag": "tun-in",
                    "address": ["172.19.0.1/30"],
                    "auto_route": true,
                    "strict_route": false,
                    // system-стек вместо gvisor: на iOS-расширении жёсткий лимит
                    // памяти ~50 МБ, userspace-стек gvisor его пробивает на старте.
                    "stack": "system",
                ],
            ],
            "outbounds": proxyOutbounds + [["type": "direct", "tag": "direct"]],
            "route": [
                "rules": [
                    ["action": "sniff"],
                    ["protocol": "dns", "action": "hijack-dns"],
                    // Глушим QUIC (HTTP/3 поверх UDP): Reality-флоу xtls-rprx-vision
                    // не пропускает UDP, а YouTube/Google по умолчанию идут через QUIC
                    // и зависают. reject заставляет их откатиться на TCP/443 (работает).
                    ["protocol": "quic", "action": "reject"],
                    // Приватные/LAN-диапазоны (роутер, принтеры, локальный бэкенд) —
                    // всегда напрямую. Иначе соединения на «голый» приватный IP без
                    // домена уходят в final:proxy и не достучатся до домашней сети.
                    ["ip_is_private": true, "outbound": "direct"],
                    // Российские домены (из sniff/DNS) — напрямую. Всё прочее ловит final.
                    ["domain_suffix": ruDomainSuffixes, "outbound": "direct"],
                ],
                // Всё, что не распознано как российское, — через прокси (автоматически
                // покрывает любой зарубежный/ограниченный ресурс без хардкода).
                "final": "proxy",
                // ОБЯЗАТЕЛЬНО true (как в эталоне sing-box-for-apple): именно через это
                // sing-box при смене дефолтного интерфейса (updateDefaultInterface из
                // платформенного монитора) сам перебиндивает соединения на новую сеть.
                // Без него смена WiFi↔сотовая ломает туннель.
                "auto_detect_interface": true,
                // default_domain_resolver — поле из sing-box 1.12, в 1.11 его нет.
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// Один или несколько прокси-аутбаундов. Если задан пул эндпоинтов (>1), строим по
    /// Reality-аутбаунду на каждый + группу `urltest` с тегом "proxy" — клиент сам
    /// выбирает живой/быстрый и переключается при блокировке (авторотация без бэкенда).
    private static func makeProxyOutbounds(_ proxy: ProxyConfig) -> [[String: Any]] {
        let isReality = proxy.protocolType == "vless" && proxy.network != "ws" && (proxy.uuid?.isEmpty == false)
        let endpoints = proxy.endpoints ?? []

        guard isReality, endpoints.count > 1 else {
            // Один сервер / ws / socks — прежний одиночный аутбаунд "proxy".
            return [makeProxyOutbound(proxy)]
        }

        var outs: [[String: Any]] = []
        var tags: [String] = []
        for (i, ep) in endpoints.enumerated() {
            let tag = "proxy-\(i)"
            // Маскировка на эндпоинт: своя на каждый порт (apple/icloud/mozilla/…),
            // фолбэк — общий serverName. Разнообразие фронтов = поломка одного
            // не валит весь пул (urltest уйдёт на живые).
            let sni = ep.serverName ?? proxy.serverName ?? ""
            outs.append(realityOutbound(proxy, host: ep.host, port: ep.port, serverName: sni, tag: tag))
            tags.append(tag)
        }
        // Группа авто-выбора: пингует членов раз в минуту и держит трафик на живом.
        outs.append([
            "type": "urltest",
            "tag": "proxy",
            "outbounds": tags,
            "url": "https://www.gstatic.com/generate_204",
            "interval": "1m0s",
            "tolerance": 200,
            "idle_timeout": "30m0s",
            "interrupt_exist_connections": true,
        ])
        return outs
    }

    /// Reality-аутбаунд для конкретного host:port (ключи берутся из proxy — они общие).
    /// `serverName` — маскировка именно для этого эндпоинта (может отличаться по портам).
    private static func realityOutbound(_ proxy: ProxyConfig, host: String, port: Int, serverName: String, tag: String) -> [String: Any] {
        var out: [String: Any] = [
            "type": "vless",
            "tag": tag,
            "server": host,
            "server_port": port,
            "uuid": proxy.uuid ?? "",
            "tls": [
                "enabled": true,
                "server_name": serverName,
                "utls": ["enabled": true, "fingerprint": "chrome"],
                "reality": [
                    "enabled": true,
                    "public_key": proxy.publicKey ?? "",
                    "short_id": proxy.shortId ?? "",
                ],
            ],
        ]
        if let flow = proxy.flow, !flow.isEmpty { out["flow"] = flow }
        return out
    }

    /// Исходящий прокси-outbound: VLESS+Reality (обход DPI) либо SOCKS5 (легаси/тест).
    private static func makeProxyOutbound(_ proxy: ProxyConfig) -> [String: Any] {
        // VLESS поверх WebSocket+TLS через Cloudflare. Reality/vision тут несовместимы
        // (CDN терминирует TLS), поэтому обычный TLS + ws-транспорт. Маскировка — под
        // обычный заход на домен за Cloudflare, который провайдер резать не станет.
        if proxy.protocolType == "vless", proxy.network == "ws", let uuid = proxy.uuid, !uuid.isEmpty {
            let sni = proxy.serverName ?? proxy.host
            var tls: [String: Any] = [
                "enabled": true,
                "server_name": sni,
                // http/1.1 обязателен: WebSocket поверх HTTP/2 у Cloudflare не
                // проходит (Extended CONNECT), даём явный ALPN.
                "alpn": ["http/1.1"],
                "utls": ["enabled": true, "fingerprint": "chrome"],
            ]
            // ECH: прячем реальный SNI (внешне — cloudflare-ech.com), иначе ТСПУ режет
            // поток по имени домена. Конфиг зашит статически; при ротации ключа CF
            // вернёт retry_configs и sing-box переподключится сам (SNI всегда скрыт).
            if let ech = proxy.echConfig, !ech.isEmpty {
                tls["ech"] = [
                    "enabled": true,
                    "config": ["-----BEGIN ECH CONFIGS-----", ech, "-----END ECH CONFIGS-----"],
                ]
            }
            return [
                "type": "vless",
                "tag": "proxy",
                "server": proxy.host,
                "server_port": proxy.port,
                "uuid": uuid,
                "tls": tls,
                "transport": [
                    "type": "ws",
                    "path": proxy.wsPath ?? "/",
                    "headers": ["Host": sni],
                ],
            ]
        }

        if proxy.protocolType == "vless", let uuid = proxy.uuid, !uuid.isEmpty {
            var out: [String: Any] = [
                "type": "vless",
                "tag": "proxy",
                "server": proxy.host,
                "server_port": proxy.port,
                "uuid": uuid,
                "tls": [
                    "enabled": true,
                    "server_name": proxy.serverName ?? "",
                    // utls маскирует TLS-отпечаток под Chrome (требование Reality).
                    "utls": ["enabled": true, "fingerprint": "chrome"],
                    "reality": [
                        "enabled": true,
                        "public_key": proxy.publicKey ?? "",
                        "short_id": proxy.shortId ?? "",
                    ],
                ],
            ]
            if let flow = proxy.flow, !flow.isEmpty {
                out["flow"] = flow
            }
            return out
        }

        var socksOut: [String: Any] = [
            "type": "socks",
            "tag": "proxy",
            "server": proxy.host,
            "server_port": proxy.port,
            "version": "5",
        ]
        if let user = proxy.username, !user.isEmpty {
            socksOut["username"] = user
            socksOut["password"] = proxy.password ?? ""
        }
        return socksOut
    }
}
