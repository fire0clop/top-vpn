import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let domainsCount: Int
    let lastSync: Date?

    var body: some View {
        NavigationStack {
            List {
                Section("Список доменов") {
                    LabeledContent("Доменов", value: "\(domainsCount)")
                    LabeledContent("Обновлён",
                        value: lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                }

                Section {
                    LabeledContent("Версия", value: appVersion)
                } footer: {
                    Text("Раздельное туннелирование направляет заблокированные домены через прокси, остальной трафик идёт напрямую.")
                }
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
