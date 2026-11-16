import CatEngine
@testable import Economy
import Foundation
import Testing
@testable import CatWorld

@Suite("你不在的时候")
struct AwayTests {
    private func world(points: Int = 300, toys: Bool = false) throws -> CatWorld {
        var world = try makeWorld(at: t(1, 20))
        world.state.bond.points = points
        if toys {
            world.state.economy.items.append(OwnedItem(id: 9001, catalogID: "gift.yarn_ball", obtainedAt: t(1, 20), source: .gift))
        }
        return world
    }

    @Test("离开不到一小时：不算")
    func tooShort() throws {
        let world = try world()
        #expect(world.awayReport(from: t(2, 10), to: t(2, 10, 59)) == nil)
        #expect(world.awayReport(from: t(2, 10), to: t(2, 11, 30)) != nil)
    }

    @Test("白天离开几小时：挑最多三件事，时间加起来不超过离开的时间，同一段时间问几次都一样")
    func daytime() throws {
        let world = try world()
        let report = try #require(world.awayReport(from: t(2, 9), to: t(2, 17)))
        #expect((1...3).contains(report.highlights.count))
        #expect(report.highlights.allSatisfy { $0.minutes >= 15 })
        #expect(report.highlights.reduce(0) { $0 + $1.minutes } <= report.minutes)
        #expect(Set(report.highlights.map(\.kind)).count == report.highlights.count)
        #expect(report == world.awayReport(from: t(2, 9), to: t(2, 17)))
        // 有意思的事排在前面
        let scores = report.highlights.map { CatWorld.interest($0.kind) }
        #expect(scores == scores.sorted(by: >))
    }

    @Test("过了一夜：会说她睡了一整晚")
    func overnight() throws {
        let world = try world()
        let report = try #require(world.awayReport(from: t(2, 22), to: t(3, 9)))
        let night = try #require(report.highlights.first { $0.kind == .night })
        #expect(night.minutes >= 300)
    }

    @Test("离开很久：只往回看一天")
    func capped() throws {
        let world = try world()
        let report = try #require(world.awayReport(from: t(2, 9), to: t(9, 9)))
        #expect(report.minutes == 24 * 60)
    }

    @Test("她玩过玩具：玩具还丢在地板上（是你有的那件）；没有玩具就没有痕迹")
    func trace() throws {
        let plain = try world()
        #expect((2...12).allSatisfy { plain.awayReport(from: t($0, 9), to: t($0, 20))?.trace == nil })

        let playful = try world(toys: true)
        let traces = (2...20).compactMap { playful.awayReport(from: t($0, 9), to: t($0, 20))?.trace }
        #expect(!traces.isEmpty)
        #expect(traces.allSatisfy { $0.toy == "gift.yarn_ball" && (0.1...0.9).contains($0.spot.x) && $0.spot.y >= 0.7 })
    }

    @Test("打开 App：离开一小时以上才带上这段时间的报告")
    func foreground() throws {
        var world = try world()
        #expect(world.foreground(at: t(2, 9), isPlus: false).away == nil) // 第一次打开
        #expect(world.foreground(at: t(2, 9, 30), isPlus: false).away == nil)
        let update = world.foreground(at: t(2, 15), isPlus: false)
        #expect(update.away?.from == t(2, 9, 30))
        #expect(update.away?.to == t(2, 15))
    }

    @Test("小组件：白天待机时每条都带着她在做的事和姿势，换了事就换一条；是现在陪着你的那只猫")
    func widget() throws {
        var world = try world()
        world.foreground(at: t(2, 9), isPlus: false)
        let entries = world.widgetTimeline(now: t(2, 9), horizon: 8 * 3600)
        let idle = entries.filter { $0.state == .idleDaytime }
        #expect(idle.count >= 3)
        #expect(idle.allSatisfy { $0.activity != nil && $0.kind == .pudding })
        #expect(Set(idle.compactMap(\.activity)).count >= 2)
        for (a, b) in zip(entries, entries.dropFirst()) {
            #expect(a.state != b.state || a.activity != b.activity || a.nextAlarmAt != b.nextAlarmAt)
        }
    }
}
