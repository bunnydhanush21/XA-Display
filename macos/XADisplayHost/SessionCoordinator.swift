import Foundation
import XADisplayProtocol

actor SessionCoordinator {
    private var phase = ConnectionPhase.idle

    func send(_ event: ConnectionEvent) -> ConnectionPhase {
        phase = ConnectionMachine.reduce(phase, event)
        return phase
    }

    func current() -> ConnectionPhase { phase }
}
