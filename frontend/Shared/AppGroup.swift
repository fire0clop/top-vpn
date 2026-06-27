import Foundation

/// Общие константы для App и Network Extension.
/// Через App Group приложение и расширение делят один контейнер:
/// приложение пишет базу доменов и конфиг прокси, расширение их читает.
enum AppGroup {
    static let identifier = "group.com.splitvpn.app"

    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            fatalError("App Group container is not available: \(identifier)")
        }
        return url
    }

    /// Путь к SQLite-базе заблокированных доменов (GRDB).
    static var domainsDatabaseURL: URL {
        containerURL.appendingPathComponent("domains.sqlite")
    }

    /// Rule-set sing-box (бинарный .srs-формат) со списком заблокированных доменов.
    /// Приложение качает его с бекенда при синхронизации, расширение читает при старте.
    /// Бинарь вместо source-JSON: в расширении жёсткий лимит памяти ~50 МБ, а разбор
    /// 127k доменов из JSON даёт мгновенный пик и фатальный jetsam-kill.
    static var blockedRuleSetURL: URL {
        containerURL.appendingPathComponent("blocked-domains.srs")
    }

    /// Rule-set sing-box (бинарный .srs) с IP-подсетями сервисов без домена/SNI
    /// (Telegram MTProto ходит прямо на IP — доменный split его не ловит).
    /// Приложение качает его с бекенда, расширение маршрутизирует эти IP в прокси.
    static var blockedIPRuleSetURL: URL {
        containerURL.appendingPathComponent("blocked-ip.srs")
    }

    /// Ключ в shared UserDefaults с метаданными синхронизации доменов.
    static let defaultsSuiteName = identifier

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: defaultsSuiteName) ?? .standard
    }
}
