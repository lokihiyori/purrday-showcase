import CatEngine
import Foundation

/// 小组件某一时刻要显示的内容。
public struct WidgetEntry: Hashable, Sendable {
    public var date: Date
    public var state: CatState
    public var mischief: MischiefKind?
    public var nextAlarmAt: Date?
    public var fish: Int
    public var messCount: Int
    /// 现在陪着你的是哪只猫
    public var kind: CatKind = .pudding
    /// 白天待机时她在做什么（其他状态为 nil）
    public var activity: CatActivity?
    /// 她的姿势（小组件用它挑图）
    public var pose: CatPose = .sit
}

extension CatWorld {
    /// 小组件时间线：从 `now` 开始，猫的状态每变一次就是一条。
    ///
    /// 在世界的一份拷贝上模拟时间推进（睡前时间、入睡截止、早晨），并假设闹钟会按时响，
    /// 所以 App 没打开时锁屏上的猫也会按时睡觉、按时来叫你。真实状态不受影响。
    /// App 每次保存后应让小组件重新加载时间线。
    public func widgetTimeline(now: Date, horizon: TimeInterval = 24 * 3600, step: TimeInterval = 15 * 60) -> [WidgetEntry] {
        var sim = self
        var entries: [WidgetEntry] = []

        func record(_ date: Date) {
            let cat = sim.state.cat
            let now = sim.presence(at: date)
            let entry = WidgetEntry(
                date: date, state: cat.state, mischief: cat.mischief,
                nextAlarmAt: sim.nextAlarmAt(after: date),
                fish: sim.state.economy.wallet.fish, messCount: cat.messCount,
                kind: sim.state.activeCat, activity: now.activity, pose: now.pose
            )
            // 状态、闹钟、她在做的事都没变就不用新的一条
            if let last = entries.last, last.state == entry.state, last.nextAlarmAt == entry.nextAlarmAt,
               last.activity == entry.activity {
                return
            }
            entries.append(entry)
        }

        sim.tick(at: now, isPlus: false)
        record(now)
        var t = now
        let end = now.addingTimeInterval(horizon)
        while t < end {
            let next = min(t.addingTimeInterval(step), end)
            if let alarm = sim.nextAlarmAt(after: t), alarm <= next {
                // 预测：闹钟按时响
                let update = sim.ingest([LoggedEvent(id: "widget-prediction-\(alarm.timeIntervalSince1970)",
                                                     event: .alarmFired(alarmID: "widget", at: alarm))], isPlus: false)
                _ = update
                record(alarm)
            }
            let update = sim.tick(at: next, isPlus: false)
            let changedAt = update.outputs.compactMap { output -> Date? in
                if case let .transition(_, _, _, at) = output { at } else { nil }
            }.last
            record(changedAt ?? next)
            t = next
        }
        return entries
    }
}

extension CatState {
    /// 状态名的本地化 key（Localizable.xcstrings 里的 `state.*`）。
    public var nameKey: String {
        switch self {
        case .sleepingAtNight: "state.sleepingAtNight"
        case .wakingUp: "state.wakingUp"
        case .givingGift: "state.givingGift"
        case .makingMischief: "state.makingMischief"
        case .idleDaytime: "state.idleDaytime"
        case .accompanying: "state.accompanying"
        case .purringAtBedtime: "state.purringAtBedtime"
        }
    }
}
