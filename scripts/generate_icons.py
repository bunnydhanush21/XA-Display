#!/usr/bin/env python3
"""Draw the XA Display icon. No third-party code."""
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def png(path, w, h, rgba):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + rgba[y * w * 4 : (y + 1) * w * 4] for y in range(h))
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def pixel(w, h, x, y):
    nx = (x + 0.5) / w
    ny = (y + 0.5) / h
    # rounded square
    dx = abs(nx - 0.5) * 2
    dy = abs(ny - 0.5) * 2
    r = max(dx, dy)
    if r > 0.92:
        return (0, 0, 0, 0)
    bg = (14, 42, 54, 255)
    # screen
    if 0.16 < nx < 0.84 and 0.18 < ny < 0.72:
        if nx < 0.20 or nx > 0.80 or ny < 0.22 or ny > 0.68:
            return (232, 168, 56, 255)
        return (244, 236, 214, 255)
    # stand
    if 0.42 < nx < 0.58 and 0.72 <= ny < 0.80:
        return (232, 168, 56, 255)
    if 0.34 < nx < 0.66 and 0.80 <= ny < 0.86:
        return (232, 168, 56, 255)
    return bg


def draw(size):
    buf = bytearray(size * size * 4)
    for y in range(size):
        for x in range(size):
            c = pixel(size, size, x, y)
            i = (y * size + x) * 4
            buf[i : i + 4] = bytes(c)
    return bytes(buf)


IOS = [
    20, 29, 40, 50, 57, 58, 60, 72, 76, 80, 87, 100, 114, 120, 144, 152, 167, 180, 1024,
]
MAC = [16, 32, 64, 128, 256, 512, 1024]


def main():
    ios = ROOT / "ios/XADisplay/Assets.xcassets/AppIcon.appiconset"
    mac = ROOT / "macos/XADisplayHost/Assets.xcassets/AppIcon.appiconset"
    ios.mkdir(parents=True, exist_ok=True)
    mac.mkdir(parents=True, exist_ok=True)
    cache = {}
    for size in sorted(set(IOS + MAC)):
        cache[size] = draw(size)
    for size in IOS:
        png(ios / f"{size}.png", size, size, cache[size])
    for size in MAC:
        png(mac / f"{size}.png", size, size, cache[size])
    print("icons", len(IOS), len(MAC))


if __name__ == "__main__":
    main()
