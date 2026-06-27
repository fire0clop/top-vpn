import Foundation
import Libbox

/// ДИАГНОСТИКА. Достаёт runtime-логи sing-box с устройства без джейлбрейка.
///
/// Логи самого движка (выбор маршрута, dial аутбаунда, ошибки Reality-хендшейка)
/// НЕ попадают в os_log — libbox отдаёт их только через command-client канал
/// (writeLogs:), тот же, что использует GUI. Поэтому поднимаем внутри расширения
/// собственный command-client, подписываемся на лог-поток и пишем строки в файл
/// box.log в контейнере App Group, откуда его можно вытащить через devicectl.
final class LogCollector: NSObject, LibboxCommandClientHandlerProtocol {
    /// Файл в корне App Group-контейнера: легко вытащить с устройства.
    static var logFileURL: URL { AppGroup.containerURL.appendingPathComponent("box.log") }

    private var client: LibboxCommandClient?
    private let queue = DispatchQueue(label: "com.splitvpn.app.PacketTunnel.logcollector")
    private var handle: FileHandle?

    func start() {
        // Свежий файл на каждый запуск туннеля.
        try? FileManager.default.removeItem(at: Self.logFileURL)
        FileManager.default.createFile(atPath: Self.logFileURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: Self.logFileURL)
        append("=== log collector started \(Date()) ===")

        let options = LibboxCommandClientOptions()
        options.command = LibboxCommandLog
        let client = LibboxNewCommandClient(self, options)
        self.client = client

        // connect() блокируется, пока соединение живо, и пушит логи в writeLogs:.
        // Серверный сокет поднимается сразу после server.start(); даём ему мгновение
        // и ретраим на случай гонки старта.
        queue.async { [weak self] in
            guard let client = self?.client else { return }
            for _ in 0 ..< 50 {
                do {
                    try client.connect()
                    // Вернулись штатно — значит отключились. Выходим.
                    break
                } catch {
                    Thread.sleep(forTimeInterval: 0.2)
                }
            }
        }
    }

    func stop() {
        try? client?.disconnect()
        client = nil
        append("=== log collector stopped \(Date()) ===")
        queue.async { [weak self] in
            try? self?.handle?.close()
            self?.handle = nil
        }
    }

    private func append(_ line: String) {
        queue.async { [weak self] in
            guard let handle = self?.handle, let data = (line + "\n").data(using: .utf8) else { return }
            handle.write(data)
        }
    }

    // MARK: - LibboxCommandClientHandlerProtocol

    // В этой версии лог приходит строками (LibboxStringIterator), не LibboxLogEntry.
    func writeLogs(_ messageList: LibboxStringIteratorProtocol?) {
        guard let it = messageList else { return }
        while it.hasNext() {
            append(it.next())
        }
    }

    func connected() { append("=== connected ===") }
    func disconnected(_ message: String?) { append("=== disconnected: \(message ?? "") ===") }
    func clearLogs() {}
    func initializeClashMode(_: LibboxStringIteratorProtocol?, currentMode _: String?) {}
    func updateClashMode(_: String?) {}
    func write(_: LibboxConnections?) {}
    func writeGroups(_: LibboxOutboundGroupIteratorProtocol?) {}
    func writeStatus(_: LibboxStatusMessage?) {}
}
