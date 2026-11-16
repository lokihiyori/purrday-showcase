import Foundation

/// 转换编号，与 docs/cat-state-machine.md 第 3 节一一对应。
/// T1–T9 是计划书原图的箭头，X1–X13 是补充转换。
public enum TransitionID: String, Codable, Sendable, CaseIterable {
    case t1 = "T1", t2 = "T2", t3 = "T3", t4 = "T4", t5 = "T5", t6 = "T6", t7 = "T7", t8 = "T8", t9 = "T9"
    case x1 = "X1", x2 = "X2", x3 = "X3", x4 = "X4", x5 = "X5", x6 = "X6", x7 = "X7"
    case x8 = "X8", x9 = "X9", x10 = "X10", x11 = "X11", x12 = "X12", x13 = "X13"
}

/// 奖励类型。具体数值（小鱼干数量、掉落表）由 Economy 决定，CatEngine 只说"发什么"。
public enum CatReward: Hashable, Codable, Sendable {
    /// 准时起床的早餐礼物：礼物 1 件 + 10 小鱼干；`luckyBoost` 为 true 时稀有掉落率提升
    case wakeGift(luckyBoost: Bool)
    /// 完成一个番茄钟：5 小鱼干
    case focusCompleted
    /// 读完一本书：30 小鱼干 + 书架多一本书脊
    case bookFinished
    /// 步数达标：纪念品 1 件
    case stepGoalSouvenir
}

/// 房间里的乱子。
public enum MessKind: Hashable, Codable, Sendable {
    /// 贪睡留下的乱子
    case snooze(MischiefKind)
    /// 番茄钟中途放弃，猫去抓沙发
    case sofaScratched
}

/// 需要 App 执行或记录的副作用。
public enum CatEffect: Hashable, Sendable {
    /// 房间里加一个乱子（已经考虑了上限）
    case messAdded(MessKind)
    /// 开始播放呼噜声和环境音
    case startBedtimeAudio(endsAt: Date)
    /// 停止呼噜声
    case stopBedtimeAudio
    /// 到了睡前时间，提示用户开启睡前模式
    case promptBedtime
    /// 写入 `DayLog.wokeOnTime` / `snoozeCount`（只有能拿奖励的那次叫醒才记录）
    case wakeRecorded(onTime: Bool, snoozeCount: Int, day: LogicalDay)
    /// 写入 `DayLog.sleptAt`
    case sleepRecorded(at: Date, day: LogicalDay)
    /// 写入一条 `Session`
    case sessionRecorded(Activity, start: Date, end: Date, completed: Bool)
}

/// 引擎的输出。
public enum CatOutput: Hashable, Sendable {
    case transition(TransitionID, from: CatState, to: CatState, at: Date)
    case reward(CatReward)
    case effect(CatEffect)
}
