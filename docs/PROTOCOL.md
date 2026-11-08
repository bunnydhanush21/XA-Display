# Protocol

XA Display has two TCP contracts. Both are big-endian and length-prefixed. The iPad listens. The Mac connects.

| Contract | Port | Version | Who speaks |
|---|---|---|---|
| Video | 9000 | OpenDisplay-style, plus `xa.*` JSON | Mac sends pictures. iPad sends control JSON |
| Input | 9001 | **1** (`XADisplayProtocolInfo.inputVersion`) | iPad sends control. Mac sends ack, audio, clipboard |

Bonjour service type: `_opensidecar._tcp`.

## Video frames (port 9000)

```
0                   16                  32
+-------------------+-------------------+
| length (u32 BE)   | payload           |
+-------------------+-------------------+
```

`length` is the payload size. Length 0 is a fatal parse error. A declared length above the cap is rejected **before** the body is buffered.

Every TCP payload and every reassembled UDP frame is an AES-256-GCM seal (`ChannelSeal`). The key is HKDF-SHA256 of the pairing token, with a separate result for each direction. The 12-byte nonce is an 8-byte connection id plus a counter, and a reconnect draws a new connection id. The receiver rejects a nonce it has already accepted. Video, input, and UDP each use their channel name as associated data. A frame that fails the tag is dropped. HMAC and AES-GCM are CommonCrypto, not code in this repository.

| Limit | Value |
|---|---|
| Max video payload | 2,000,000 bytes plus the 29-byte AES-GCM seal |
| Max video reassembly buffer | 3,000,000 bytes |
| Partial frame timeout | 2 seconds |
| Max frames per append | 64 |

Classification of a payload, after the seal opens:

- Control JSON when the payload is at most 32,768 bytes, starts with `{`, and contains no NUL.
- Otherwise an H.264 Annex-B access unit. A timing JSON object may sit in front of the first `00 00 00 01` start code and is kept.

### Control JSON the iPad sends

`hello` omits a protocol-version field named `pv`, so an OpenDisplay sender still treats the client as its protocol 1. Fields: `pixelsWide`, `pixelsHigh`, `scale`, `device`, `id`, `orientation`.

Also: `touch`, `scroll`, `ping`, `pong`, `frameAck`, `health`, `decodeFailed`.

The XA host **does not** turn `touch` or `scroll` on this port into CGEvents. Pairing lives on port 9001. An OpenDisplay 1.30.x sender can still use those JSON messages for basic video, touch, and scroll. Do not run both senders.

### Control JSON the host sends

| `type` | Purpose |
|---|---|
| `xa.hello` | Marks the sender as XA Display Host. The iPad then sends `frameAck`, `health`, and `decodeFailed` |
| `xa.stream` | Preset name, width, height, fps, bitrate, experimental flag |
| `xa.metrics` | `captureToAckMs`, `encodeMs` |
| `xa.windows` | `body`: semicolon-separated `x,y,w,h` rectangles, normalized to the virtual display, at most 16 |
| `xa.menus` | `body`: menu titles separated by U+001E, at most 40 |
| `xa.front` | Frontmost bundle id |
| `cursor`, `cursorImg` | Optional cursor. PNG capped at 64 KiB |

## Input frames (port 9001)

```
0        8        16               48
+--------+--------+----------------+------------------+
| ver u8 | type   | flags u16      | length u32       |
+--------+--------+----------------+------------------+
| payload (length bytes)                              |
+-----------------------------------------------------+
```

`ver` must be 1. `length` must equal the remaining byte count. A truncated, oversized, or inconsistent frame throws. Callers drop the connection so the stream cannot resynchronize on a guess. An **unknown type** returns nil and is ignored, so a newer peer can be skipped without a desync.

| Limit | Value |
|---|---|
| Max input payload | 262,144 bytes |
| Max input reassembly buffer | 524,288 bytes |
| Max frames per append | 32 |
| Strings | u16 length, UTF-8, default cap 2,048 bytes |

### Types

| Type | Name | Payload |
|---|---|---|
| 1 | hello | u16 version, token, device name, device id, u8 flags. Bit 0 means the sender requires pairing |
| 2 | helloAck | u8 accepted, u32 session, reason string |
| 3 | mouse | session, seq, phase, button, space, pad, f64 x, f64 y |
| 4 | scroll | session, seq, f64 dx pixels, f64 dy pixels, u8 inertia |
| 5 | key | session, seq, phase, pad, u16 key code, u32 modifiers, text |
| 6 | modifier | session, seq, mask, down |
| 7 | ping | session, u64 client unix ms |
| 8 | pong | session, client unix ms, host unix ms |
| 9 | release | session, seq. Host releases every held button, key, and modifier |
| 10 | clipboard | session, seq, u64 revision, kind (1 text, 2 PNG). Text cap 12,000 bytes. PNG cap 200,000. The host applies text only |
| 11 | window | session, seq, action u8. Fill, snap, tile quarters, traffic-light press, edge actions |
| 12 | audio | session, sample rate, channels, codec (0 PCM, 1 AAC), f64 hostTimeMs, bytes. Cap 8,192 |
| 13 | preset | session, seq, name. Reserved. The dispatcher drops it |
| 14 | chrome | session, seq, op (1 resize, 2 menu), u16 index, u16 window index, f64 dx, f64 dy |
| 15 | media | session, seq, action u8, f64 scrub. Actions: play/pause 1, next 2, previous 3, volume up 4, volume down 5, seek forward 6, seek backward 7. Scrub is a signed fraction; zero means the action stands alone |
| 16 | nowPlaying | Host to iPad. session, app name, title, artist, f64 position, f64 duration, artwork byte count and bytes. Position and duration are -1 when unknown. Artwork may be empty |

`xa.battery` on port 9000 carries `text` (the telemetry lines) and `heat` (whether the pack is warm enough to lower bitrate). It is display data. Charge-limit commands are not on this socket. They go to the local helper in `jailbreak/battery-care/`.

Session id is chosen by the host in `helloAck`. Sequence numbers are monotonic per session. Replays are dropped. Moves and scrolls are rate-limited. Button-up and `release` are not.

Mouse coordinates are either absolute normalized (0...1 of the video) or relative. The host maps absolute points into the virtual display's global frame, the same top-left space as `CGDisplayBounds`. Scroll content follows the fingers: UIKit positive `dy` (fingers moved down) becomes a negative CGEvent `wheel1`.

### Pairing

`requirePairing` is the stricter of the Mac setting and hello flag bit 0. A token is compared case-insensitively with hyphens and spaces removed. The alphabet is `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no I, O, 0, or 1), shown as `XXXX-XXXX`. Empty token is rejected when pairing is required. Wrong token is rejected and produces no cursor motion.

## Compatibility

Port 9000 stays compatible with the length-prefix, JSON, and Annex-B behavior of the MIT iOS 12 client. Port 9001, `xa.hello`, pairing, clipboard, audio, presets, and window actions are XA. They need XA Display Host.
