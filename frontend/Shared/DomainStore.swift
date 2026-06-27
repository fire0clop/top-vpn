import Foundation
import GRDB

/// SQLite-хранилище заблокированных доменов (GRDB), лежит в App Group.
/// Приложение наполняет его при синхронизации, Network Extension читает
/// при перехвате DNS, чтобы решить — домен заблокирован или нет.
final class DomainStore {
    private let dbQueue: DatabaseQueue

    init(readonly: Bool = false) throws {
        var config = Configuration()
        config.readonly = readonly
        config.busyMode = .timeout(5)
        // WAL позволяет расширению читать, пока приложение пишет.
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        dbQueue = try DatabaseQueue(path: AppGroup.domainsDatabaseURL.path, configuration: config)
        if !readonly {
            try migrate()
        }
    }

    private func migrate() throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS blocked_domains (
                    domain TEXT PRIMARY KEY
                ) WITHOUT ROWID
            """)
        }
    }

    /// Атомарно заменить весь список. Расширение в любой момент видит либо
    /// старый, либо новый список целиком — благодаря транзакции SQLite,
    /// никогда наполовину обновлённый (важно: пользователь может быть в VPN).
    func replaceAll(_ domains: [String]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM blocked_domains")
            for domain in domains {
                let normalized = domain.lowercased()
                guard !normalized.isEmpty else { continue }
                try db.execute(
                    sql: "INSERT OR IGNORE INTO blocked_domains (domain) VALUES (?)",
                    arguments: [normalized]
                )
            }
        }
    }

    func count() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM blocked_domains") ?? 0
        }
    }

    /// Заблокирован ли хост. Проверяем сам хост и все его родительские
    /// суффиксы: для "rr1.sn.googlevideo.com" сматчит "googlevideo.com".
    func isBlocked(host: String) -> Bool {
        let lower = host.lowercased()
        let labels = lower.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return false }
        // Кандидаты: youtube.com, m.youtube.com, ... — от полного к самому короткому.
        var candidates: [String] = []
        for i in 0..<(labels.count - 1) {
            candidates.append(labels[i...].joined(separator: "."))
        }
        return (try? dbQueue.read { db -> Bool in
            for candidate in candidates {
                if try Bool.fetchOne(
                    db,
                    sql: "SELECT 1 FROM blocked_domains WHERE domain = ? LIMIT 1",
                    arguments: [candidate]
                ) ?? false {
                    return true
                }
            }
            return false
        }) ?? false
    }
}
