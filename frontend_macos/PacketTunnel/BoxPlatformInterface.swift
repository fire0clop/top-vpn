import Foundation
import Libbox
import Network
import NetworkExtension
import os.log

/// Мост между sing-box (libbox) и iOS NetworkExtension.
/// libbox при старте сервиса вызывает `openTun` — мы переводим его TunOptions
/// в NEPacketTunnelNetworkSettings, применяем их и возвращаем файловый дескриптор
/// tun-интерфейса, в который sing-box пишет напрямую.
final class BoxPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol, LibboxCommandServerHandlerProtocol {
    private static let log = Logger(subsystem: "com.splitvpn.app.PacketTunnel", category: "platform")
    private unowned let tunnel: PacketTunnelProvider
    private var networkSettings: NEPacketTunnelNetworkSettings?
    private var nwMonitor: NWPathMonitor?

    init(_ tunnel: PacketTunnelProvider) {
        self.tunnel = tunnel
    }

    func reset() {
        networkSettings = nil
        nwMonitor?.cancel()
        nwMonitor = nil
    }

    // MARK: - Tun

    func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        try runBlocking { [self] in
            try await openTun0(options, ret0_)
        }
    }

    private func openTun0(_ options: LibboxTunOptionsProtocol?, _ ret0_: UnsafeMutablePointer<Int32>?) async throws {
        guard let options else { throw boxError("Nil tun options") }
        guard let ret0_ else { throw boxError("Nil return pointer") }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())

            // В этой версии libbox DNS-сервер — один StringBox.value (не итератор).
            let dnsServer = try options.getDNSServerAddress().value
            if !dnsServer.isEmpty {
                settings.dnsSettings = NEDNSSettings(servers: [dnsServer])
            }

            // IPv4
            var ipv4Address: [String] = []
            var ipv4Mask: [String] = []
            if let it = options.getInet4Address() {
                while it.hasNext() {
                    let p = it.next()!
                    ipv4Address.append(p.address())
                    ipv4Mask.append(p.mask())
                }
            }
            if !ipv4Address.isEmpty {
                let ipv4 = NEIPv4Settings(addresses: ipv4Address, subnetMasks: ipv4Mask)
                var routes: [NEIPv4Route] = []
                if let rit = options.getInet4RouteAddress(), rit.hasNext() {
                    while rit.hasNext() {
                        let p = rit.next()!
                        routes.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask()))
                    }
                } else {
                    routes.append(NEIPv4Route.default())
                }
                var excluded: [NEIPv4Route] = []
                if let eit = options.getInet4RouteExcludeAddress() {
                    while eit.hasNext() {
                        let p = eit.next()!
                        excluded.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask()))
                    }
                }
                ipv4.includedRoutes = routes
                ipv4.excludedRoutes = excluded
                settings.ipv4Settings = ipv4
            }

            // IPv6
            var ipv6Address: [String] = []
            var ipv6Prefixes: [NSNumber] = []
            if let it = options.getInet6Address() {
                while it.hasNext() {
                    let p = it.next()!
                    ipv6Address.append(p.address())
                    ipv6Prefixes.append(NSNumber(value: p.prefix()))
                }
            }
            if !ipv6Address.isEmpty {
                let ipv6 = NEIPv6Settings(addresses: ipv6Address, networkPrefixLengths: ipv6Prefixes)
                var routes: [NEIPv6Route] = []
                if let rit = options.getInet6RouteAddress(), rit.hasNext() {
                    while rit.hasNext() {
                        let p = rit.next()!
                        routes.append(NEIPv6Route(destinationAddress: p.address(), networkPrefixLength: NSNumber(value: p.prefix())))
                    }
                } else {
                    routes.append(NEIPv6Route.default())
                }
                var excluded: [NEIPv6Route] = []
                if let eit = options.getInet6RouteExcludeAddress() {
                    while eit.hasNext() {
                        let p = eit.next()!
                        excluded.append(NEIPv6Route(destinationAddress: p.address(), networkPrefixLength: NSNumber(value: p.prefix())))
                    }
                }
                ipv6.includedRoutes = routes
                ipv6.excludedRoutes = excluded
                settings.ipv6Settings = ipv6
            }
        }

        networkSettings = settings
        try await tunnel.setTunnelNetworkSettings(settings)

        if let fd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = fd
            return
        }
        let loopFd = LibboxGetTunnelFileDescriptor()
        if loopFd != -1 {
            ret0_.pointee = loopFd
        } else {
            throw boxError("Missing tun file descriptor")
        }
    }

    // MARK: - Interface monitor (для auto_detect_interface)

    func usePlatformAutoDetectControl() -> Bool { false }

    func autoDetectControl(_: Int32) throws {}

    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        guard let listener else { return }
        let monitor = NWPathMonitor()
        nwMonitor = monitor
        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { path in
            self.onUpdateDefaultInterface(listener, path)
            semaphore.signal()
            monitor.pathUpdateHandler = { path in
                self.onUpdateDefaultInterface(listener, path)
            }
        }
        monitor.start(queue: DispatchQueue.global())
        semaphore.wait()
    }

    private func onUpdateDefaultInterface(_ listener: LibboxInterfaceUpdateListenerProtocol, _ path: Network.NWPath) {
        guard path.status != .unsatisfied, let iface = path.availableInterfaces.first else {
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        // Просто сообщаем sing-box актуальный дефолтный интерфейс (как эталон
        // sing-box-for-apple). Перебиндинг соединений при смене сети движок делает сам
        // через auto_detect_interface — никакого ручного resetNetwork отсюда.
        listener.updateDefaultInterface(iface.name, interfaceIndex: Int32(iface.index), isExpensive: path.isExpensive, isConstrained: path.isConstrained)
    }

    func closeDefaultInterfaceMonitor(_: LibboxInterfaceUpdateListenerProtocol?) throws {
        nwMonitor?.cancel()
        nwMonitor = nil
    }

    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        guard let nwMonitor else { throw boxError("Interface monitor not started") }
        let path = nwMonitor.currentPath
        guard path.status != .unsatisfied else { return InterfaceIterator([]) }
        var interfaces: [LibboxNetworkInterface] = []
        for it in path.availableInterfaces {
            let iface = LibboxNetworkInterface()
            iface.name = it.name
            iface.index = Int32(it.index)
            switch it.type {
            case .wifi: iface.type = LibboxInterfaceTypeWIFI
            case .cellular: iface.type = LibboxInterfaceTypeCellular
            case .wiredEthernet: iface.type = LibboxInterfaceTypeEthernet
            default: iface.type = LibboxInterfaceTypeOther
            }
            interfaces.append(iface)
        }
        return InterfaceIterator(interfaces)
    }

    private final class InterfaceIterator: NSObject, LibboxNetworkInterfaceIteratorProtocol {
        private var iterator: IndexingIterator<[LibboxNetworkInterface]>
        private var current: LibboxNetworkInterface?
        init(_ array: [LibboxNetworkInterface]) { iterator = array.makeIterator() }
        func hasNext() -> Bool { current = iterator.next(); return current != nil }
        func next() -> LibboxNetworkInterface? { current }
    }

    // MARK: - Прочее платформенное (минимум для iOS)

    func underNetworkExtension() -> Bool { true }
    func includeAllNetworks() -> Bool { false }
    func useProcFS() -> Bool { false }
    func clearDNSCache() {}
    func readWIFIState() -> LibboxWIFIState? { nil }
    func localDNSTransport() -> LibboxLocalDNSTransportProtocol? { nil }
    func systemCertificates() -> LibboxStringIteratorProtocol? { nil }
    func send(_: LibboxNotification?) throws {}
    func writeLog(_ message: String?) {
        guard let message else { return }
        Self.log.debug("\(message, privacy: .public)")
    }

    // Привязки трафика к процессам/пакетам на iOS/macOS нет — не поддерживаем.
    func packageName(byUid _: Int32, error: NSErrorPointer) -> String {
        error?.pointee = boxError("packageNameByUid not supported")
        return ""
    }

    func uid(byPackageName _: String?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        throw boxError("uidByPackageName not supported")
    }

    func findConnectionOwner(_: Int32, sourceAddress _: String?, sourcePort _: Int32, destinationAddress _: String?, destinationPort _: Int32, ret0_: UnsafeMutablePointer<Int32>?) throws {
        throw boxError("findConnectionOwner not supported")
    }

    // MARK: - CommandServerHandler

    func postServiceClose() {}

    func serviceReload() throws {}

    func getSystemProxyStatus() -> LibboxSystemProxyStatus? {
        LibboxSystemProxyStatus()
    }

    func setSystemProxyEnabled(_: Bool) throws {}

    private func boxError(_ message: String) -> NSError {
        NSError(domain: "BoxPlatformInterface", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
