import Foundation
import Network
import XADisplayProtocol

/// Bonjour browse for iOS 12. NWBrowser needs iOS 13.
final class MacBrowser: NSObject, NetServiceBrowserDelegate {
    var onNames: (([String]) -> Void)?
    private let browser = NetServiceBrowser()
    private var found: [String] = []
    private let queue = DispatchQueue(label: "xa.poke")

    func start() {
        browser.delegate = self
        browser.searchForServices(ofType: XADisplayProtocolInfo.hostBonjourType, inDomain: "local.")
    }

    func stop() {
        browser.stop()
        found = []
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        if !found.contains(service.name) { found.append(service.name) }
        if !moreComing { publish() }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        found.removeAll { $0 == service.name }
        if !moreComing { publish() }
    }

    /// Opening the host service is the wake poke. The connection is not the video stream.
    func poke(name: String) {
        let connection = NWConnection(
            to: .service(name: name, type: XADisplayProtocolInfo.hostBonjourType, domain: "local", interface: nil),
            using: .tcp
        )
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.queue.asyncAfter(deadline: .now() + 0.5) { connection.cancel() }
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func publish() {
        let names = found.sorted()
        DispatchQueue.main.async { self.onNames?(names) }
    }
}
