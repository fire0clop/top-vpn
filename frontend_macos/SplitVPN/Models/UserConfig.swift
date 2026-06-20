import Foundation

/// Ответ /domains/updated_at.
struct DomainsMeta: Codable {
    let updatedAt: Date?
    let count: Int

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case count
    }
}
