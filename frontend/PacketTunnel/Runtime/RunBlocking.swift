import Foundation

/// libbox вызывает наши методы синхронно (из Go-потока), а часть iOS-API
/// асинхронная (setTunnelNetworkSettings). Этот мостик блокирующе ждёт async.
func runBlocking<T>(_ block: @escaping () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<T>()
    Task.detached(priority: .userInitiated) {
        box.value = await block()
        semaphore.signal()
    }
    semaphore.wait()
    return box.value
}

func runBlocking<T>(_ block: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<T>()
    Task.detached(priority: .userInitiated) {
        do { box.result = .success(try await block()) }
        catch { box.result = .failure(error) }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.result.get()
}

private final class ResultBox<T> {
    var result: Result<T, Error>!
    var value: T!
}
