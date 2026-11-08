# Security

XA Display injects input into a Mac and installs an unsigned app on a jailbroken iPad. The design goal is: a peer that is not paired cannot drive the pointer, and a peer that is paired cannot make the process buffer unbounded data.

## Assets

| Asset | Where it lives |
|---|---|
| Pairing token | Mac menu bar, iPad settings, UserDefaults. Diagnostics export redacts it |
| Screen contents | H.264 inside AES-256-GCM, keyed from the pairing token |
| Pointer and keyboard | CGEvent after a paired session |
| Clipboard text | Optional, 12 KB, both switches on |
| Window and menu control | Accessibility, after a paired window or chrome message |

There is no TLS handshake. Each frame is AES-256-GCM from CommonCrypto. The key is HKDF-SHA256 of the pairing token, one key for Mac-to-iPad and one for iPad-to-Mac. The nonce is a fresh connection id plus a counter, and the receiver drops a replay. Video, input, and UDP use different associated data, so a sealed video frame does not open on the input socket. On USB the socket is still a usbmux tunnel. On Wi-Fi a peer that does not know the token cannot read or forge frames. Pairing remains the control gate for pointer injection.

## Pairing model

1. The host generates the token and shows it.
2. The person types it into the iPad.
3. The iPad `hello` carries the token and flag bit 0 when the iPad also requires pairing.
4. The host accepts the session only when the protocol version is 1 and, if either side requires pairing, the token matches.
5. Later messages must carry that session id and a new sequence number.

Turning pairing off on only one side still rejects an empty token. Both sides must turn it off before an empty token is accepted. That is deliberate, so a forgotten iPad switch cannot silently open the Mac.

Video-port `touch` and `scroll` JSON have no token. `LegacyInputPolicy` rejects them on the XA host.

## Threat model

| Threat | What the code does | Residual risk |
|---|---|---|
| Unpaired peer sends mouse events | Dropped until helloAck | A person who learns the token is paired |
| Huge length prefix | Rejected before the body is read. Buffer caps: 3 MB video, 512 KB input | A paired peer can still send up to the cap, continuously |
| Malformed frame | Connection dropped. The parser does not guess a new boundary | Session must be rebuilt |
| Replay of an old seq | Dropped | Seq is per session. GCM also rejects a flipped ciphertext |
| Clipboard exfiltration | Off unless both switches are on. Text cap 12 KB. Images are not applied. The bytes are inside the sealed input frame | A paired peer can read or set the pasteboard text while the switch is on |
| Token in logs | Diagnostics redact the token | Screenshots of the menu bar still show it |
| Wi-Fi eavesdropping | AES-256-GCM on video, input, and UDP. The tag covers the channel name | A person who learns the pairing token can decrypt |
| Jailbreak install | The IPA is unsigned and fakesigned with `ldid` on device | The device trust model is the jailbreak, not App Store review |
| Private virtual display API | Isolated in one Objective-C file. Failure is reported, not papered over | The SPI can break on a macOS update |
| Accessibility | Window moves and menu presses need the permission the person granted | A paired session can press menus and move windows when those switches are on |
| Secure input | Injected keys may be ignored by secure fields | Expected |

Out of scope: kernel exploits on the jailbreak, SIP, and protecting a token that the paired iPad already holds.

## Abuse cases that are in scope

- A program on the LAN opens port 9001 and tries an empty or guessed token.
- A program advertises a multi-gigabyte frame length.
- A paired iPad disconnects mid-drag and leaves the mouse button down.
- Diagnostics or a bug report include the token.

The first two are rejected by tests in `ProtocolTests` and `BehaviorTests`. Disconnect posts mouse-up, modifier-up, and key-up. Diagnostics redaction is tested.

## Reporting

Open a private security report through GitHub for [bunnydhanush21/XA-Display](https://github.com/bunnydhanush21/XA-Display) if the issue is a bypass of pairing or the frame caps. Ordinary bugs belong in a public issue. Do not file the pairing token in either place.
