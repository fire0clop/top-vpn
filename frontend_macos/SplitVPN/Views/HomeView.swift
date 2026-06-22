import SwiftUI

struct HomeView: View {
    @StateObject private var model = HomeViewModel()
    @State private var showSettings = false
    @State private var pulse = false

    private var accent: Color { model.isConnected ? Color(red: 0.20, green: 0.80, blue: 0.55) : .gray }

    var body: some View {
        NavigationStack {
            ZStack {
                background
                VStack(spacing: 26) {
                    Spacer(minLength: 8)
                    connectButton
                    statusBlock
                    Spacer(minLength: 8)
                    if model.isConnected {
                        trafficPanel
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    serverCard
                }
                .padding(20)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.isConnected)
            }
            .navigationTitle("SplitVPN")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").font(.body.weight(.semibold))
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(domainsCount: model.domainsCount, lastSync: model.lastSync)
            }
            .task { await model.onAppear() }
            .refreshable { await model.syncDomains(); await model.refreshProxy() }
            .onAppear { pulse = true }
        }
    }

    // MARK: - Фон

    private var background: some View {
        LinearGradient(
            colors: model.isConnected
                ? [Color(red: 0.04, green: 0.16, blue: 0.13), Color(red: 0.02, green: 0.06, blue: 0.08)]
                : [Color(red: 0.10, green: 0.11, blue: 0.13), Color(red: 0.03, green: 0.03, blue: 0.05)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: model.isConnected)
    }

    // MARK: - Кнопка подключения

    private var connectButton: some View {
        Button {
            Task { await model.toggleConnection() }
        } label: {
            ZStack {
                // мягкое свечение при включении
                Circle()
                    .fill(accent)
                    .frame(width: 210, height: 210)
                    .blur(radius: 50)
                    .opacity(model.isConnected ? 0.55 : 0.0)
                // пульсирующее кольцо
                Circle()
                    .stroke(accent.opacity(0.35), lineWidth: 2)
                    .frame(width: 230, height: 230)
                    .scaleEffect(pulse && model.isConnected ? 1.08 : 0.96)
                    .opacity(model.isConnected ? (pulse ? 0.0 : 0.6) : 0)
                    .animation(model.isConnected ? .easeOut(duration: 1.8).repeatForever(autoreverses: false) : .default, value: pulse)
                // основной круг
                Circle()
                    .fill(LinearGradient(colors: [accent.opacity(0.9), accent.opacity(0.55)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 190, height: 190)
                    .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: accent.opacity(model.isConnected ? 0.6 : 0.2), radius: 24, y: 8)

                VStack(spacing: 10) {
                    if model.isTransitioning {
                        ProgressView().controlSize(.large).tint(.white)
                    } else {
                        Image(systemName: "power")
                            .font(.system(size: 58, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    Text(model.isConnected ? "ВКЛ" : "ВЫКЛ")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .tracking(2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
    }

    // MARK: - Статус + длительность

    private var statusBlock: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 9, height: 9)
                    .shadow(color: accent, radius: model.isConnected ? 4 : 0)
                Text(model.statusText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            if model.isConnected, let since = model.connectedSince {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Self.duration(since))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            if let error = model.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Панель трафика

    private var trafficPanel: some View {
        HStack(spacing: 12) {
            trafficTile(
                title: "Загрузка", icon: "arrow.down",
                color: Color(red: 0.30, green: 0.70, blue: 1.0),
                speed: model.downloadSpeed, total: model.downloadTotal
            )
            trafficTile(
                title: "Отдача", icon: "arrow.up",
                color: Color(red: 0.55, green: 0.80, blue: 0.40),
                speed: model.uploadSpeed, total: model.uploadTotal
            )
        }
    }

    private func trafficTile(title: String, icon: String, color: Color, speed: Int64, total: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(color.gradient, in: Circle())
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.6))
            }
            Text(Self.speed(speed))
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text("за сессию " + Self.bytes(total))
                .font(.caption2).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Карточка сервера

    private var serverCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe.europe.africa.fill")
                .font(.title2).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Сервер").font(.caption).foregroundStyle(.white.opacity(0.5))
                Text(model.proxyRegion).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            }
            Spacer()
            if model.isConnected {
                Image(systemName: "lock.shield.fill").foregroundStyle(accent)
            }
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Форматирование

    private static func speed(_ b: Int64) -> String { bytes(b) + "/с" }

    private static func bytes(_ b: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.zeroPadsFractionDigits = false
        f.allowsNonnumericFormatting = false // 0 → "0 КБ", а не "Zero KB"
        return f.string(fromByteCount: max(0, b))
    }

    private static func duration(_ since: Date) -> String {
        let s = Int(Date().timeIntervalSince(since))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
