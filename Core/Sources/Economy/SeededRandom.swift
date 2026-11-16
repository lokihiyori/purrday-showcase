/// 可复现的随机数生成器（SplitMix64）。种子相同，掉落结果就相同，便于测试和事件回放。
/// 状态是 Codable 的，可以和存档一起保存。
public struct SeededRandom: RandomNumberGenerator, Codable, Hashable, Sendable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension RandomNumberGenerator {
    /// [0, 1) 之间的 Double。自己实现，不依赖标准库 `random(in:)` 的内部算法，保证跨版本可复现。
    mutating func unitDouble() -> Double {
        Double(next() >> 11) * 0x1p-53
    }
}
