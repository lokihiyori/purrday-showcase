import CatEngine
import Economy
import Foundation

/// 旁白的场景：发生了一件事（叫醒、送礼物、赖床捣乱、睡前、买了家具……）时屏幕上的一句话。
/// 她不说话——每一句都是在描述她做了什么。白天在房间里和她互动没有旁白，只有动作（`Reactions.swift`）。
/// 文字在 `Resources/Localizable.xcstrings` 里，key 是 `line.<场景>.<序号>`。
public enum CatScene: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable {
    case welcome, wake, snooze1, snooze2, snooze3
    case gift, rareGift, legendaryGift, lateWake
    /// 陪你读书、散步时摸她
    case petted
    case bedtimePrompt, purring, sleepingTapped
    case messCleared, shopBought, giftSold
    case focusStart, focusDone, focusAbandoned
    case returned

    /// 这个场景有几句。和 xcstrings 对不上时 `LocalizationTests` 会失败。
    public var lineCount: Int {
        switch self {
        case .wake, .petted: 4
        case .snooze1, .snooze2, .snooze3, .gift, .lateWake, .bedtimePrompt, .purring, .sleepingTapped: 3
        case .welcome, .rareGift, .legendaryGift, .messCleared, .shopBought, .giftSold,
             .focusStart, .focusDone, .focusAbandoned, .returned: 2
        }
    }

    /// 这个场景全部台词的本地化 key。
    public var lineKeys: [String] {
        (1...lineCount).map { "line.\(rawValue).\($0)" }
    }

    static func snooze(_ kind: MischiefKind) -> CatScene {
        switch kind {
        case .stepOnFace: .snooze1
        case .pushCup: .snooze2
        case .lieOnPhone: .snooze3
        }
    }
}

extension CatWorld {
    /// 多久没打开 App 算"回来了"
    static let returnedAfter: TimeInterval = 3 * 24 * 3600

    /// 在场景里挑一句台词（本地化 key），不和这个场景上一次说的重复。
    public mutating func line(for scene: CatScene) -> String {
        let keys = scene.lineKeys
        var candidates = keys
        if keys.count > 1, let last = state.lastLines[scene] {
            candidates.removeAll { $0 == last }
        }
        var rng = state.dialogueRng
        let index = min(Int(Double(rng.next() >> 11) * 0x1p-53 * Double(candidates.count)), candidates.count - 1)
        state.dialogueRng = rng
        state.lastLines[scene] = candidates[index]
        return candidates[index]
    }

    /// 点她时的旁白，取决于她现在的状态。白天待机时没有旁白（返回 nil）：她用动作回应。
    public func tapScene() -> CatScene? {
        switch state.cat.state {
        case .idleDaytime: nil
        case .sleepingAtNight: .sleepingTapped
        case .wakingUp: .wake
        case .makingMischief: .snooze(state.cat.mischief ?? .stepOnFace)
        case .givingGift: .gift
        case .accompanying(.read), .accompanying(.move): .petted
        case .accompanying(.focus): .focusStart
        case .purringAtBedtime: .purring
        }
    }

    /// 只对这么近的事说话；补跑出来的旧转换（比如昨晚的睡前时间）不配台词
    static let sceneRecency: TimeInterval = 30 * 60

    /// 一次更新里最值得说一句的场景：在 `since` 之后的转换里，按时间顺序取最后一个能对应到场景的。
    func scene(for update: WorldUpdate, since: Date) -> CatScene? {
        var result: CatScene?
        for output in update.outputs {
            guard case let .transition(id, from, to, at) = output, at >= since else { continue }
            switch id {
            case .t1, .t5, .x3, .x4, .x13: result = .wake
            case .t4: result = .snooze(state.cat.mischief ?? .stepOnFace)
            case .t2: result = giftScene(update)
            case .x1, .x2: result = .lateWake
            case .t6 where to == .accompanying(.focus): result = .focusStart
            case .t7 where from == .accompanying(.focus): result = .focusDone
            case .x11: result = .focusAbandoned
            case .t8: result = .bedtimePrompt
            case .x5, .x6: result = .purring
            default: break
            }
        }
        return result
    }

    private func giftScene(_ update: WorldUpdate) -> CatScene {
        let rarities = update.grants.flatMap(\.items).compactMap { economy.catalog.item($0.catalogID) }
            .filter { $0.kind == .gift }.map(\.rarity)
        switch rarities.max() {
        case .legendary: return .legendaryGift
        case .rare: return .rareGift
        default: return .gift
        }
    }

    /// 给更新配上场景和台词。
    mutating func attachLine(to update: inout WorldUpdate, now: Date, fallback: CatScene? = nil) {
        guard let scene = scene(for: update, since: now.addingTimeInterval(-Self.sceneRecency)) ?? fallback else { return }
        update.scene = scene
        update.line = line(for: scene)
    }
}
