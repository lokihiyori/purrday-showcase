// 猫的 7 个状态。规格见 docs/cat-state-machine.md 第 1 节。

/// "陪你做事"时用户在做的事。
public enum Activity: String, Codable, Sendable, CaseIterable {
    /// 专注番茄钟（V1.1）
    case focus
    /// 读书计时（V1.2）
    case read
    /// 散步 / 运动（V1.2）
    case move
}

/// 猫的行为状态（S1–S7）。UI 把它映射到 Rive 动画状态。
public enum CatState: Hashable, Codable, Sendable {
    /// S1 夜间熟睡：蜷在床脚
    case sleepingAtNight
    /// S2 叫醒中：喵喵叫、等你摸
    case wakingUp
    /// S3 送早餐礼物：随机掉落
    case givingGift
    /// S4 捣乱：踩脸、推杯子（贪睡中，等闹钟稍后再响）
    case makingMischief
    /// S5 白天待机：在房间里闲逛
    case idleDaytime
    /// S6 陪你做事：专注 / 散步 / 读书
    case accompanying(Activity)
    /// S7 睡前呼噜：陪你入睡
    case purringAtBedtime
}

/// 捣乱动画，按本次叫醒的贪睡次数升级（见规格 4.2）。
public enum MischiefKind: String, Codable, Sendable, CaseIterable {
    /// 第 1 次贪睡：踩脸
    case stepOnFace
    /// 第 2 次贪睡：推杯子
    case pushCup
    /// 第 3 次及以后：躺在你手机上
    case lieOnPhone

    /// 第 `snoozeCount` 次贪睡对应的动画（从 1 开始计数）。
    public static func forSnooze(_ snoozeCount: Int) -> MischiefKind {
        switch snoozeCount {
        case ...1: .stepOnFace
        case 2: .pushCup
        default: .lieOnPhone
        }
    }
}
