import CoreMedia
import Foundation
import XADisplayProtocol

/// Returns block-buffer memory to a small pool when the sample buffer is released.
final class FrameLease {
    let pool: FrameMemoryPool
    let capacity: Int
    init(pool: FrameMemoryPool, capacity: Int) {
        self.pool = pool
        self.capacity = capacity
    }

    func recycle(_ memory: UnsafeMutableRawPointer) {
        pool.recycle(memory, capacity: capacity)
    }
}

/// A few frame buffers, reused after AVSampleBufferDisplayLayer releases the sample.
final class FrameMemoryPool {
    private let lock = NSLock()
    private var spare: [(UnsafeMutableRawPointer, Int)] = []

    func block(nalus: [Data]) -> CMBlockBuffer? {
        let byteCount = nalus.reduce(0) { $0 + 4 + $1.count }
        guard byteCount > 0 else { return nil }
        return adopt(byteCount: byteCount) { raw in
            var offset = 0
            for nalu in nalus {
                guard offset + 4 + nalu.count <= raw.count else { return false }
                var length = UInt32(nalu.count).bigEndian
                withUnsafeBytes(of: &length) { bytes in
                    raw.baseAddress?.advanced(by: offset).copyMemory(from: bytes.baseAddress!, byteCount: 4)
                }
                offset += 4
                nalu.withUnsafeBytes { bytes in
                    guard let base = bytes.baseAddress else { return }
                    raw.baseAddress?.advanced(by: offset).copyMemory(from: base, byteCount: nalu.count)
                }
                offset += nalu.count
            }
            return offset == byteCount
        }
    }

    func block(source: UnsafeRawBufferPointer, spans: [NALSpan]) -> CMBlockBuffer? {
        let byteCount = AnnexBSpan.avccByteCount(spans)
        guard byteCount > 0 else { return nil }
        return adopt(byteCount: byteCount) { raw in
            AnnexBSpan.writeAVCC(source: source, spans: spans, into: raw) == byteCount
        }
    }

    func recycle(_ memory: UnsafeMutableRawPointer, capacity: Int) {
        lock.lock()
        if spare.count < 4 {
            spare.append((memory, capacity))
        } else {
            memory.deallocate()
        }
        lock.unlock()
    }

    private func adopt(byteCount: Int, fill: (UnsafeMutableRawBufferPointer) -> Bool) -> CMBlockBuffer? {
        let (memory, capacity) = take(byteCount: byteCount)
        let filled = fill(UnsafeMutableRawBufferPointer(start: memory, count: byteCount))
        guard filled else {
            recycle(memory, capacity: capacity)
            return nil
        }
        let lease = FrameLease(pool: self, capacity: capacity)
        var source = CMBlockBufferCustomBlockSource()
        source.version = UInt32(kCMBlockBufferCustomBlockSourceVersion)
        source.refCon = Unmanaged.passRetained(lease).toOpaque()
        source.FreeBlock = { refCon, doomed, _ in
            guard let refCon = refCon else { return }
            let held = Unmanaged<FrameLease>.fromOpaque(refCon).takeRetainedValue()
            held.recycle(doomed)
        }
        var block: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: memory,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorNull,
            customBlockSource: &source,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &block
        )
        guard status == noErr, block != nil else {
            lease.recycle(memory)
            Unmanaged.passUnretained(lease).release()
            return nil
        }
        return block
    }

    private func take(byteCount: Int) -> (UnsafeMutableRawPointer, Int) {
        lock.lock()
        defer { lock.unlock() }
        if let index = spare.firstIndex(where: { $0.1 >= byteCount }) {
            return spare.remove(at: index)
        }
        let capacity = max(byteCount, 64 * 1024)
        return (UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16), capacity)
    }
}
