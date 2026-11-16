import CatEngine
import Economy
import Foundation
import Testing
@testable import CatWorld

@Suite("窗外的季节和天气")
struct WeatherTests {
    /// 某个月里每一段（6 小时）的天气
    private func month(_ world: CatWorld, _ month: Int) -> [(Date, Weather)] {
        (1...28).flatMap { day in [3, 9, 15, 21].map { hour in
            let date = t(day, hour, month: month)
            return (date, world.weather(at: date))
        } }
    }

    @Test("季节按月份")
    func seasons() throws {
        #expect(Season.of(month: 4) == .spring && Season.of(month: 7) == .summer)
        #expect(Season.of(month: 10) == .autumn && Season.of(month: 1) == .winter && Season.of(month: 12) == .winter)
        let world = try makeWorld()
        #expect(world.season(at: t(2, 10)) == .autumn) // 测试用的是 11 月
    }

    @Test("同一段时间里天气不变，问几次都一样；一天里不会每段都乱变")
    func stable() throws {
        let world = try makeWorld()
        #expect(world.weather(at: t(5, 13)) == world.weather(at: t(5, 17, 59)))
        #expect(world.weather(at: t(5, 13)) == world.weather(at: t(5, 13)))
        let changes = (1...28).map { day in
            Set([3, 9, 15, 21].map { world.weather(at: t(day, $0)) }).count
        }
        #expect(changes.allSatisfy { $0 <= 2 })
    }

    @Test("夏天不下雪，冬天常下雪；大多数时候是晴天或者阴天；每个季节都有晴天")
    func bySeason() throws {
        let world = try makeWorld()
        let summer = month(world, 7).map(\.1)
        let winter = month(world, 1).map(\.1)
        #expect(!summer.contains(.snow))
        #expect(winter.filter { $0 == .snow }.count > 5)
        #expect(summer.filter { $0 == .clear }.count > summer.count / 2)
        for m in [1, 4, 7, 10] {
            let all = month(world, m).map(\.1)
            #expect(all.contains(.clear), "\(m) 月")
            #expect(Double(all.filter(\.isFalling).count) / Double(all.count) < 0.4, "\(m) 月")
        }
    }

    @Test("不同的存档天气不一样（不是所有人同一天下雨）")
    func perSave() throws {
        let a = try makeWorld(seed: 1), b = try makeWorld(seed: 2)
        let same = (1...28).filter { a.weather(at: t($0, 9)) == b.weather(at: t($0, 9)) }.count
        #expect(same < 28)
    }

    @Test("下雨下雪、阴天都没有阳光可晒；晴天的白天有")
    func sunbeam() throws {
        let world = try makeWorld()
        var sunny = 0
        for (date, weather) in month(world, 11) + month(world, 1) {
            let hour = world.catConfig.calendar.component(.hour, from: date)
            if weather != .clear { #expect(world.sunbeam(at: date) == nil) }
            if weather == .clear, (9...15).contains(hour) {
                #expect(world.sunbeam(at: date) != nil)
                sunny += 1
            }
            #expect(world.presence(at: date).activity != .sunbathe || weather == .clear)
        }
        #expect(sunny > 10)
    }

    @Test("下雨下雪的白天，她比晴天更常蹲在窗边看")
    func watchesTheRain() throws {
        var world = try makeWorld()
        world.state.bond.points = 300
        var falling = (watch: 0, total: 0), clear = (watch: 0, total: 0)
        for m in [1, 4, 10, 11] {
            for day in 1...28 {
                var date = t(day, 9, month: m)
                while date < t(day, 20, month: m) {
                    let watching = world.presence(at: date).activity == .watch ? 1 : 0
                    switch world.weather(at: date) {
                    case .rain, .snow: falling = (falling.watch + watching, falling.total + 1)
                    case .clear: clear = (clear.watch + watching, clear.total + 1)
                    case .cloudy: break
                    }
                    date = date.addingTimeInterval(LifeSchedule.block)
                }
            }
        }
        #expect(falling.total > 100 && clear.total > 100)
        #expect(Double(falling.watch) / Double(falling.total) > Double(clear.watch) / Double(clear.total) * 1.2)
    }
}
