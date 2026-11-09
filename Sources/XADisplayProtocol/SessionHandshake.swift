@preconcurrency import CommonCrypto
import Foundation
import Security

/// Ephemeral P-256 handshake. The pairing token authenticates the exchange and is not the frame key.
public enum SessionHandshake {
    public static let magic = Data("XAHS".utf8)
    public static let version: UInt8 = 1
    public static let publicKeyLength = 65
    public static let nonceLength = 16
    public static let connectionLength = 8
    public static let proofLength = 32

    public static func isHandshake(_ frame: Data) -> Bool {
        frame.count >= 6 && frame.prefix(4) == magic && frame[4] == version
    }

    public static func clientOffer() -> (state: ClientHandshake, frame: Data)? {
        guard let party = ECDHParty.generate(role: .pad) else { return nil }
        let state = ClientHandshake(party: party)
        return (state, state.offerFrame())
    }

    public static func hostAnswer(token: String, offer: Data, replay: inout HandshakeReplayGuard) -> (state: HostHandshake, reply: Data)? {
        guard let parsed = ClientHandshake.parseOffer(offer), replay.accept(connectionID: parsed.connectionID, nonce: parsed.nonce) else { return nil }
        guard let host = ECDHParty.generate(role: .host) else { return nil }
        guard let secret = ECDHParty.sharedSecret(privateKey: host.privateKey, peerPublic: parsed.publicKey) else { return nil }
        let transcript = transcriptBytes(connectionID: parsed.connectionID, clientNonce: parsed.nonce, hostNonce: host.nonce, clientPublic: parsed.publicKey, hostPublic: host.publicKey)
        let proof = mac(role: "host", token: token, transcript: transcript)
        var reply = Data(magic)
        reply.append(version)
        reply.append(2)
        reply.append(host.nonce)
        reply.append(host.publicKey)
        reply.append(proof)
        let keys = sessionKeys(secret: secret, transcript: transcript)
        let state = HostHandshake(connectionID: parsed.connectionID, clientNonce: parsed.nonce, clientPublic: parsed.publicKey, hostNonce: host.nonce, hostPublic: host.publicKey, keys: keys)
        return (state, reply)
    }

    public static func clientFinish(token: String, state: ClientHandshake, reply: Data) -> (keys: SessionKeyPair, finish: Data)? {
        guard reply.count == 4 + 1 + 1 + nonceLength + publicKeyLength + proofLength,
            reply.prefix(4) == magic, reply[4] == version, reply[5] == 2
        else { return nil }
        let hostNonce = reply.subdata(in: 6..<(6 + nonceLength))
        let hostPublic = reply.subdata(in: (6 + nonceLength)..<(6 + nonceLength + publicKeyLength))
        let presented = reply.subdata(in: (6 + nonceLength + publicKeyLength)..<reply.count)
        guard let secret = ECDHParty.sharedSecret(privateKey: state.party.privateKey, peerPublic: hostPublic) else { return nil }
        let transcript = transcriptBytes(connectionID: state.party.connectionID, clientNonce: state.party.nonce, hostNonce: hostNonce, clientPublic: state.party.publicKey, hostPublic: hostPublic)
        guard constantTimeEqual(presented, mac(role: "host", token: token, transcript: transcript)) else { return nil }
        let keys = sessionKeys(secret: secret, transcript: transcript)
        let finishProof = mac(role: "pad", token: token, transcript: transcript)
        var finish = Data(magic)
        finish.append(version)
        finish.append(3)
        finish.append(finishProof)
        return (keys, finish)
    }

    public static func hostConfirm(token: String, state: HostHandshake, finish: Data) -> SessionKeyPair? {
        guard finish.count == 4 + 1 + 1 + proofLength, finish.prefix(4) == magic, finish[4] == version, finish[5] == 3 else { return nil }
        let presented = finish.suffix(proofLength)
        let transcript = transcriptBytes(connectionID: state.connectionID, clientNonce: state.clientNonce, hostNonce: state.hostNonce, clientPublic: state.clientPublic, hostPublic: state.hostPublic)
        guard constantTimeEqual(Data(presented), mac(role: "pad", token: token, transcript: transcript)) else { return nil }
        return state.keys
    }

    public static func parse(_ data: Data) -> Bool { isHandshake(data) }

    static func transcriptBytes(connectionID: Data, clientNonce: Data, hostNonce: Data, clientPublic: Data, hostPublic: Data) -> Data {
        var data = Data()
        data.append(connectionID)
        data.append(clientNonce)
        data.append(hostNonce)
        data.append(clientPublic)
        data.append(hostPublic)
        return data
    }

    static func sessionKeys(secret: Data, transcript: Data) -> SessionKeyPair {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        transcript.withUnsafeBytes { raw in
            _ = CC_SHA256(raw.baseAddress, CC_LONG(transcript.count), &hash)
        }
        let salt = Data(hash)
        let hostToPad = HKDF.derive(ikm: secret, salt: salt, info: Data("xa-display-aead-v2\nhost-to-pad".utf8), outputLength: 32)
        let padToHost = HKDF.derive(ikm: secret, salt: salt, info: Data("xa-display-aead-v2\npad-to-host".utf8), outputLength: 32)
        return SessionKeyPair(hostToPad: hostToPad, padToHost: padToHost)
    }

    static func mac(role: String, token: String, transcript: Data) -> Data {
        let key = HKDF.hmac(key: Data("xa-display-handshake-v1".utf8), message: Data(PairingGate.normalize(token).utf8))
        var message = Data(role.utf8)
        message.append(0)
        message.append(transcript)
        return HKDF.hmac(key: key, message: message)
    }

    static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        var diff = lhs.count ^ rhs.count
        let count = max(lhs.count, rhs.count)
        if count == 0 { return false }
        for index in 0..<count {
            let left = index < lhs.count ? lhs[lhs.index(lhs.startIndex, offsetBy: index)] : 0
            let right = index < rhs.count ? rhs[rhs.index(rhs.startIndex, offsetBy: index)] : 0
            diff |= Int(left ^ right)
        }
        return diff == 0
    }
}

/// SessionKeyPair.
public struct SessionKeyPair: Equatable {
    public var hostToPad: Data
    public var padToHost: Data
    public init(hostToPad: Data, padToHost: Data) {
        self.hostToPad = hostToPad
        self.padToHost = padToHost
    }
}

/// HandshakeReplayGuard.
public struct HandshakeReplayGuard {
    private var seen: [Data] = []

    public init() {}

    public mutating func accept(connectionID: Data, nonce: Data) -> Bool {
        var key = connectionID
        key.append(nonce)
        if seen.contains(key) { return false }
        if seen.count >= 64 { return false }
        seen.append(key)
        return true
    }
}

/// ECDHParty.
public struct ECDHParty {
    public enum Role: String { case pad, host }
    public let role: Role
    public let privateKey: SecKey
    public let publicKey: Data
    public let nonce: Data
    public let connectionID: Data

    public static func generate(role: Role) -> ECDHParty? {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
            let publicKey = SecKeyCopyPublicKey(privateKey),
            let exported = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?,
            exported.count == SessionHandshake.publicKeyLength
        else { return nil }
        var nonce = Data(count: SessionHandshake.nonceLength)
        var connection = Data(count: SessionHandshake.connectionLength)
        let nonceStatus = nonce.withUnsafeMutableBytes { CCRandomGenerateBytes($0.baseAddress, SessionHandshake.nonceLength) }
        let connectionStatus = connection.withUnsafeMutableBytes { CCRandomGenerateBytes($0.baseAddress, SessionHandshake.connectionLength) }
        guard nonceStatus == 0, connectionStatus == 0 else { return nil }
        return ECDHParty(role: role, privateKey: privateKey, publicKey: exported, nonce: nonce, connectionID: connection)
    }

    public static func sharedSecret(privateKey: SecKey, peerPublic: Data) -> Data? {
        guard peerPublic.count == SessionHandshake.publicKeyLength else { return nil }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 256
        ]
        var error: Unmanaged<CFError>?
        guard let peer = SecKeyCreateWithData(peerPublic as CFData, attributes as CFDictionary, &error) else { return nil }
        let parameters = [SecKeyKeyExchangeParameter.requestedSize.rawValue: 32] as CFDictionary
        guard let secret = SecKeyCopyKeyExchangeResult(privateKey, .ecdhKeyExchangeStandard, peer, parameters, &error) as Data?, secret.count == 32 else { return nil }
        return secret
    }
}

/// ClientHandshake.
public struct ClientHandshake {
    public let party: ECDHParty

    public func offerFrame() -> Data {
        var frame = Data(SessionHandshake.magic)
        frame.append(SessionHandshake.version)
        frame.append(1)
        frame.append(party.connectionID)
        frame.append(party.nonce)
        frame.append(party.publicKey)
        return frame
    }

    static func parseOffer(_ frame: Data) -> (connectionID: Data, nonce: Data, publicKey: Data)? {
        let expected = 4 + 1 + 1 + SessionHandshake.connectionLength + SessionHandshake.nonceLength + SessionHandshake.publicKeyLength
        guard frame.count == expected, frame.prefix(4) == SessionHandshake.magic, frame[4] == SessionHandshake.version, frame[5] == 1 else { return nil }
        let idEnd = 6 + SessionHandshake.connectionLength
        let nonceEnd = idEnd + SessionHandshake.nonceLength
        return (frame.subdata(in: 6..<idEnd), frame.subdata(in: idEnd..<nonceEnd), frame.subdata(in: nonceEnd..<frame.count))
    }
}

/// HostHandshake.
public struct HostHandshake {
    public let connectionID: Data
    public let clientNonce: Data
    public let clientPublic: Data
    public let hostNonce: Data
    public let hostPublic: Data
    public let keys: SessionKeyPair
}
