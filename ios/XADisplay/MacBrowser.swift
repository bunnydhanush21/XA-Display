import Foundation
import Network
import XADisplayProtocol

final class MacBrowser {
    var onNames: (([String]) -> Void)?
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "xa.macbrowse")

    func start() {
        let browser = NWBrowser(for: .bonjour(type: XADisplayProtocolInfo.hostBonjourType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let names = results.compactMap { result -> String? in
                if case .service(let name, _, _, _) = result.endpoint { return name }
                return nil
            }.sorted()
            DispatchQueue.main.async { self?.onNames?(names) }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Opening the host service is the wake poke. The connection is not the video stream.
    func poke(name: String) {
        let connection = NWConnection(to: .service(name: name, type: XADisplayProtocolInfo.hostBonjourType, domain: "local", interface: nil), using: .tcp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.queue.asyncAfter(deadline: .now() + 0.5) { connection.cancel() }
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }
}
