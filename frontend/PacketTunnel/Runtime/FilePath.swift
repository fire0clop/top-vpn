import Foundation

/// Рабочие каталоги для sing-box внутри App Group (логи, кэш, рабочие файлы).
/// libbox требует base/working/temp пути при инициализации.
enum FilePath {
    static var sharedDirectory: URL { AppGroup.containerURL }

    static var workingDirectory: URL {
        let url = sharedDirectory.appendingPathComponent("Working", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var cacheDirectory: URL {
        let url = sharedDirectory.appendingPathComponent("Cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Файл rule-set с заблокированными доменами (sing-box читает его при старте).
    static var blockedRuleSetURL: URL { AppGroup.blockedRuleSetURL }

    /// Путь к бинарному .srs rule-set для конфига sing-box. Берём свежий из App Group
    /// (его кладёт приложение после синхронизации с бекендом), а до первой синхронизации
    /// — вшитый в расширение seed, чтобы VPN работал сразу после установки.
    static var resolvedRuleSetPath: String {
        resolved(downloaded: AppGroup.blockedRuleSetURL, seed: "blocked")
    }

    /// Путь к бинарному .srs с IP-подсетями (Telegram и пр.). Логика та же, что и
    /// у доменного rule-set: свежий из App Group, до синхронизации — вшитый seed.
    static var resolvedIPRuleSetPath: String {
        resolved(downloaded: AppGroup.blockedIPRuleSetURL, seed: "blocked-ip")
    }

    private static func resolved(downloaded: URL, seed: String) -> String {
        if FileManager.default.fileExists(atPath: downloaded.path) {
            return downloaded.path
        }
        if let url = Bundle.main.url(forResource: seed, withExtension: "srs") {
            return url.path
        }
        return downloaded.path
    }
}
