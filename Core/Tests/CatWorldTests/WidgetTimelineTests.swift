import CatEngine
import Economy
import Foundation
import Testing
@testable import CatWorld

@Suite("小组件时间线")
struct WidgetTimelineTests {
    @Test("晚上 8 点生成：睡前呼噜 → 入睡 → 早上闹钟来叫你")
    func eveningTimeline() throws {
        var world = try makeWorld(at: t(1, 20)) // 11-01 周日
        try world.setAlarm(weekdayAlarm(), isPlus: false)
        // 白天待机时她换一件事做也会多一条；这里只看状态什么时候变
        let entries = stateChanges(world.widgetTimeline(now: t(1, 20)))
        #expect(entries.map(\.state) == [.idleDaytime, .purringAtBedtime, .sleepingAtNight, .wakingUp, .idleDaytime])
        #expect(entries.map(\.date) == [t(1, 20), t(1, 23), t(2, 2), t(2, 7), t(2, 7, 30)])
        #expect(entries[0].nextAlarmAt == t(2, 7))
        #expect(entries[3].nextAlarmAt == t(3, 7)) // 响过之后显示下一次
    }

    /// 只留下状态变了的那几条
    private func stateChanges(_ entries: [WidgetEntry]) -> [WidgetEntry] {
        var result: [WidgetEntry] = []
        for entry in entries where result.last?.state != entry.state { result.append(entry) }
        return result
    }

    @Test("不会改动真实的世界")
    func doesNotMutate() throws {
        var world = try makeWorld(at: t(1, 20))
        try world.setAlarm(weekdayAlarm(), isPlus: false)
        let before = world.state
        _ = world.widgetTimeline(now: t(1, 20))
        #expect(world.state == before)
    }

    @Test("没有闹钟：夜里睡觉，早上自己醒来")
    func noAlarm() throws {
        let world = try makeWorld(at: t(1, 20))
        let all = world.widgetTimeline(now: t(1, 20))
        #expect(stateChanges(all).map(\.state) == [.idleDaytime, .purringAtBedtime, .sleepingAtNight, .idleDaytime])
        #expect(all.allSatisfy { $0.nextAlarmAt == nil })
    }

    @Test("钱包和乱子数量带到小组件")
    func walletAndMess() throws {
        var world = try makeWorld()
        world.ingest(onTimeMorning(2), isPlus: false)
        let entry = try #require(world.widgetTimeline(now: t(2, 7, 5)).first)
        #expect(entry.fish == 10)
        #expect(entry.state == .givingGift)
    }

    @Test("每个状态都有本地化名字")
    func nameKeys() {
        let states: [CatState] = [.sleepingAtNight, .wakingUp, .givingGift, .makingMischief, .idleDaytime, .accompanying(.focus), .purringAtBedtime]
        #expect(Set(states.map(\.nameKey)).count == 7)
    }
}
