import Foundation
import Combine

/// Синхронизация списка заблокированных доменов с беком.
/// Скачивает полный снимок только когда серверный updated_at новее локального,
/// и кладёт его в общий с расширением SQLite атомарно (без обрывов VPN).
@MainActor
final class DomainService: ObservableObject {
    static let shared = DomainService()

    @Published private(set) var localCount: Int = 0
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var isSyncing = false

    private enum Key {
        static let serverUpdatedAt = "domains.server_updated_at"
        static let lastSyncedAt = "domains.last_synced_at"
    }

    private let defaults = AppGroup.sharedDefaults

    private init() {
        lastSyncedAt = defaults.object(forKey: Key.lastSyncedAt) as? Date
        localCount = (try? DomainStore().count()) ?? 0
    }

    /// Серверное время последнего обновления, которое мы уже применили локально.
    private var appliedServerUpdatedAt: Date? {
        defaults.object(forKey: Key.serverUpdatedAt) as? Date
    }

    /// Нужна ли синхронизация: либо база пуста, либо сервер обновился.
    func needsSync(serverUpdatedAt: Date?) -> Bool {
        if localCount == 0 { return true }
        guard let serverUpdatedAt else { return false }
        guard let applied = appliedServerUpdatedAt else { return true }
        return serverUpdatedAt > applied
    }

    /// Проверить мету на беке и при необходимости скачать новый снимок.
    @discardableResult
    func syncIfNeeded() async throws -> Bool {
        let meta = try await APIService.shared.domainsMeta()
        guard needsSync(serverUpdatedAt: meta.updatedAt) else {
            markSynced()
            return false
        }
        try await downloadAndApply(serverUpdatedAt: meta.updatedAt)
        return true
    }

    private func downloadAndApply(serverUpdatedAt: Date?) async throws {
        isSyncing = true
        defer { isSyncing = false }

        let raw = try await APIService.shared.downloadDomainsExport()
        // Бинарные rule-set'ы (.srs) бекенд компилирует сам — расширение читает их
        // напрямую, без пика памяти от разбора source-JSON со 127k доменов.
        let ruleSet = try await APIService.shared.downloadDomainsRuleSet()
        // IP rule-set (Telegram и пр.) — отдельный файл, может отсутствовать на старом
        // беке; в этом случае оставляем вшитый seed и не валим всю синхронизацию.
        let ipRuleSet = try? await APIService.shared.downloadDomainsIPRuleSet()

        // Разбор и запись в фоне — список большой (>100k строк).
        let count = try await Task.detached(priority: .utility) {
            let domains = raw
                .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                .map(String.init)
            let store = try DomainStore()
            try store.replaceAll(domains)
            // Атомарная подмена .srs: расширение всегда читает целостный rule-set,
            // даже если пользователь сидит в VPN во время обновления — без обрывов.
            try ruleSet.write(to: AppGroup.blockedRuleSetURL, options: .atomic)
            if let ipRuleSet {
                try ipRuleSet.write(to: AppGroup.blockedIPRuleSetURL, options: .atomic)
            }
            return try store.count()
        }.value

        localCount = count
        if let serverUpdatedAt {
            defaults.set(serverUpdatedAt, forKey: Key.serverUpdatedAt)
        }
        markSynced()
    }

    private func markSynced() {
        let now = Date()
        defaults.set(now, forKey: Key.lastSyncedAt)
        lastSyncedAt = now
    }
}
