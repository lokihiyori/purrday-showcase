import CatEngine
import Economy
import Foundation
import Testing
@testable import CatWorld

private let london = Place(latitude: 51.5, longitude: -0.1)
private let shanghaiPlace = Place(latitude: 31.2, longitude: 121.5)
private let sydney = Place(latitude: -33.9, longitude: 151.2)
private let tromso = Place(latitude: 69.6, longitude: 19.0)
private let petersburg = Place(latitude: 59.9, longitude: 30.3)
private let reykjavik = Place(latitude: 64.1, longitude: -21.9)
private let singapore = Place(latitude: 1.3, longitude: 103.8)

private func zone(_ id: String) -> TimeZone { TimeZone(identifier: id)! }

/// 和已知的日出日落（NOAA 的算法、公开的日出日落表）差几分钟以内
private func near(_ date: Date, _ hour: Int, _ minute: Int, tz: TimeZone, minutes: Double = 4) -> Bool {
    let c = calendar(tz).dateComponents([.hour, .minute, .second], from: date)
    let got = Double(c.hour! * 60 + c.minute!) + Double(c.second!) / 60
    return abs(got - Double(hour * 60 + minute)) <= minutes
}

@Suite("日出日落")
struct SunTests {
    @Test("位置只留到 0.1°")
    func coarse() {
        let place = Place(latitude: 31.23042, longitude: 121.47370)
        #expect(place.latitude == 31.2 && place.longitude == 121.5)
        #expect(Place(latitude: 95, longitude: -200) == Place(latitude: 90, longitude: -180))
        #expect(sydney.isSouthern && !london.isSouthern)
        #expect(singapore.isTropical && !shanghaiPlace.isTropical)
    }

    @Test("几个城市的日出日落对得上")
    func knownCities() throws {
        let cases: [(Place, TimeZone, Int, Int, (Int, Int), (Int, Int))] = [
            (shanghaiPlace, shanghai, 11, 12, (6, 18), (16, 58)),
            (london, zone("Europe/London"), 6, 21, (4, 43), (21, 21)),
            (london, zone("Europe/London"), 12, 21, (8, 4), (15, 53)),
            (sydney, zone("Australia/Sydney"), 12, 21, (5, 41), (20, 5)),
            (reykjavik, zone("Atlantic/Reykjavik"), 12, 21, (11, 21), (15, 30)),
        ]
        for (place, tz, month, day, rise, set) in cases {
            let date = t(day, 12, month: month, tz: tz)
            guard case let .normal(sunrise, sunset) = Sun.day(containing: date, at: place, calendar: calendar(tz)) else {
                Issue.record("\(place) \(month)-\(day) 应该有日出日落")
                continue
            }
            #expect(near(sunrise, rise.0, rise.1, tz: tz), "\(place) \(month)-\(day) 日出 \(sunrise)")
            #expect(near(sunset, set.0, set.1, tz: tz), "\(place) \(month)-\(day) 日落 \(sunset)")
        }
    }

    @Test("一天里什么时候问，答案都是当天的那一次日出日落")
    func sameDay() {
        let morning = Sun.day(containing: t(12, 0, 5), at: shanghaiPlace, calendar: calendar())
        let night = Sun.day(containing: t(12, 23, 55), at: shanghaiPlace, calendar: calendar())
        #expect(morning == night)
        guard case let .normal(sunrise, sunset) = morning else { return }
        #expect(sunrise > t(12, 0) && sunset < t(13, 0))
    }

    @Test("极昼和极夜")
    func polar() {
        let tz = zone("Europe/Oslo")
        #expect(Sun.day(containing: t(21, 12, month: 12, tz: tz), at: tromso, calendar: calendar(tz)) == .polarNight)
        #expect(Sun.day(containing: t(21, 12, month: 6, tz: tz), at: tromso, calendar: calendar(tz)) == .polarDay)
        // 极点上也不会算出怪东西
        let pole = Place(latitude: 90, longitude: 0)
        #expect(Sun.day(containing: t(21, 12, month: 6), at: pole, calendar: calendar()) == .polarDay)
    }
}

@Suite("画面钟点")
struct SceneClockTests {
    private func clock(_ place: Place, _ day: Int, month: Int, tz: TimeZone) -> (SceneClock, Date, Date) {
        let date = t(day, 12, month: month, tz: tz)
        guard case let .normal(sunrise, sunset) = Sun.day(containing: date, at: place, calendar: calendar(tz)) else {
            fatalError("测试用的日子要有日出日落")
        }
        return (SceneClock.make(for: date, at: place, calendar: calendar(tz)), sunrise, sunset)
    }

    @Test("日出对到 6:30，日落对到 18:00；天亮、天黑的快慢不变")
    func anchors() {
        let (clock, sunrise, sunset) = clock(shanghaiPlace, 12, month: 11, tz: shanghai)
        #expect(abs(clock.hour(at: sunrise) - 6.5) < 0.01)
        #expect(abs(clock.hour(at: sunset.addingTimeInterval(-1)) - 18) < 0.01)
        #expect(abs(clock.hour(at: sunset.addingTimeInterval(3 * 3600)) - 21) < 0.01)
        #expect(abs(clock.hour(at: sunrise.addingTimeInterval(-1.5 * 3600)) - 5) < 0.01)
        #expect(abs(clock.hour(at: sunrise.addingTimeInterval(1.5 * 3600)) - 8) < 0.01)
        #expect(abs(clock.hour(at: sunset.addingTimeInterval(-2 * 3600)) - 16) < 0.01)
        // 日落后一个小时就是画面上的 19 点，不会因为冬天夜长就拖得很慢
        #expect(abs(clock.hour(at: sunset.addingTimeInterval(3600)) - 19) < 0.01)
    }

    @Test("冬天下午五点半天已经黑下来，夏天晚上八点还亮着")
    func seasons() {
        let (winter, _, _) = clock(shanghaiPlace, 12, month: 11, tz: shanghai)
        #expect(winter.hour(at: t(12, 17, 30)) > 18.4)
        let tz = zone("Europe/London")
        let (summer, _, _) = clock(london, 21, month: 6, tz: tz)
        #expect(summer.hour(at: t(21, 20, 0, month: 6, tz: tz)) < 17)
        #expect((8...16).contains(summer.hour(at: t(21, 13, 0, month: 6, tz: tz))))
    }

    @Test("一整天里画面钟点一直往前走，值都在 0–24")
    func monotonic() {
        for (place, tz, month) in [(shanghaiPlace, shanghai, 11), (london, zone("Europe/London"), 6), (sydney, zone("Australia/Sydney"), 12)] {
            let (clock, _, _) = clock(place, 12, month: month, tz: tz)
            let start = t(12, 0, month: month, tz: tz)
            var last = -1.0
            var wraps = 0
            for minute in stride(from: 0, to: 24 * 60, by: 5) {
                let hour = clock.hour(at: start.addingTimeInterval(Double(minute) * 60))
                #expect((0..<24).contains(hour))
                if hour < last { wraps += 1 }
                last = hour
            }
            #expect(wraps <= 1, "\(place)：除了过午夜，不该往回走")
        }
    }

    @Test("白夜（高纬度的夏天）：没有全黑的时候；高纬度的冬天白天很短也不出错")
    func extremes() {
        // 雷克雅未克的夏至：太阳半夜才落、凌晨三点又升起来，黄昏直接接上黎明
        let summer = zone("Atlantic/Reykjavik")
        let white = SceneClock.make(for: t(21, 12, month: 6, tz: summer), at: reykjavik, calendar: calendar(summer))
        let start = t(21, 0, month: 6, tz: summer)
        for minute in stride(from: 0, to: 24 * 60, by: 10) {
            let hour = white.hour(at: start.addingTimeInterval(Double(minute) * 60))
            #expect((5...20.5).contains(hour), "白夜里不该有深夜：\(hour)")
        }
        // 圣彼得堡的夏至：夜只有五个小时，全黑的时候不到一个小时
        let tz = zone("Europe/Moscow")
        let (short5, _, _) = clock(petersburg, 21, month: 6, tz: tz)
        let dark = stride(from: 0, to: 24 * 60, by: 5).filter { minute in
            let hour = short5.hour(at: t(21, 0, month: 6, tz: tz).addingTimeInterval(Double(minute) * 60))
            return hour >= 21 || hour < 5
        }
        #expect(dark.count * 5 < 60)
        let iceland = zone("Atlantic/Reykjavik")
        let (short, sunrise, sunset) = clock(reykjavik, 21, month: 12, tz: iceland)
        #expect(abs(short.hour(at: sunrise) - 6.5) < 0.01)
        #expect(short.hour(at: sunset.addingTimeInterval(-60)) > 17.9)
        #expect(short.hour(at: t(21, 2, month: 12, tz: iceland)) < 5 || short.hour(at: t(21, 2, month: 12, tz: iceland)) >= 21)
    }

    @Test("极夜一整天是夜里，极昼一整天是白天")
    func polar() {
        let tz = zone("Europe/Oslo")
        let night = SceneClock.make(for: t(21, 12, month: 12, tz: tz), at: tromso, calendar: calendar(tz))
        let day = SceneClock.make(for: t(21, 12, month: 6, tz: tz), at: tromso, calendar: calendar(tz))
        for hour in [0, 6, 12, 18, 23] {
            #expect(night.hour(at: t(21, hour, month: 12, tz: tz)) <= 5)
            #expect((8...16).contains(day.hour(at: t(21, hour, month: 6, tz: tz))))
        }
    }
}

@Suite("窗外跟着你那里")
struct RealSkyTests {
    private func hours(from start: Date, count: Int, _ weather: Weather) -> [HourlyWeather] {
        (0..<count).map { HourlyWeather(start: start.addingTimeInterval(Double($0) * 3600), weather: weather) }
    }

    @Test("没打开时：画面钟点就是墙上的钟点，没有位置，天气按种子算")
    func off() throws {
        let world = try makeWorld()
        #expect(world.place == nil && world.sunDay(at: t(12, 10)) == nil && world.sceneClock(for: t(12, 10)) == nil)
        #expect(abs(world.sceneHour(at: t(12, 17, 30)) - 17.5) < 0.001)
        #expect(world.observedWeather(at: t(12, 10)) == nil)
        #expect(world.weather(at: t(12, 10)) == world.seededWeather(at: t(12, 10)))
    }

    @Test("有真实天气的钟点用真实的，没有的钟点还是按种子算")
    func observed() throws {
        var world = try makeWorld()
        let seeded = world.seededWeather(at: t(12, 10))
        let real: Weather = seeded == .snow ? .rain : .snow
        world.observeSky(place: shanghaiPlace, hourly: hours(from: t(12, 9), count: 3, real), at: t(12, 9, 20))
        #expect(world.place == shanghaiPlace)
        #expect(world.weather(at: t(12, 9, 0)) == real && world.weather(at: t(12, 11, 59)) == real)
        #expect(world.observedWeather(at: t(12, 12, 0)) == nil)
        #expect(world.weather(at: t(12, 8, 59)) == world.seededWeather(at: t(12, 8, 59)))
        #expect(world.state.sky.weatherUpdatedAt == t(12, 9, 20))
    }

    @Test("下雨的真实天气：地板上没有阳光，她更爱看窗外")
    func rainChangesHerDay() throws {
        var world = try makeWorld()
        world.observeSky(place: shanghaiPlace, hourly: hours(from: t(12, 0), count: 24, .rain), at: t(12, 0, 5))
        #expect(world.sunbeam(at: t(12, 11)) == nil)
        world.observeSky(place: shanghaiPlace, hourly: hours(from: t(12, 0), count: 24, .clear), at: t(12, 0, 6))
        #expect(world.sunbeam(at: t(12, 11)) != nil)
        // 上海 11 月 12 日 16:58 日落：16:45 太阳已经照不进来了（墙上的钟点 16:45 本来还有）
        #expect(world.sunbeam(at: t(12, 16, 45)) == nil)
        #expect(RoomGeometry.sunbeam(at: t(12, 16, 45), calendar: calendar()) != nil)
    }

    @Test("只拿到位置（没网）：日出日落跟着走，以前的天气留着")
    func placeOnly() throws {
        var world = try makeWorld()
        world.observeSky(place: shanghaiPlace, hourly: hours(from: t(12, 9), count: 2, .rain), at: t(12, 9))
        world.observeSky(place: shanghaiPlace, hourly: [], at: t(12, 9, 30))
        #expect(world.observedWeather(at: t(12, 10)) == .rain)
        #expect(world.state.sky.weatherUpdatedAt == t(12, 9))
        #expect(world.sceneHour(at: t(12, 17, 30)) > 18.4)
        guard case let .normal(sunrise, _)? = world.sunDay(at: t(12, 10)) else {
            Issue.record("应该有日出")
            return
        }
        #expect(near(sunrise, 6, 18, tz: shanghai))
    }

    @Test("太旧的和太远的天气会清掉；换了地方，旧天气不再用")
    func pruneAndMove() throws {
        var world = try makeWorld()
        world.observeSky(place: shanghaiPlace, hourly: hours(from: t(10, 0), count: 24 * 10, .cloudy), at: t(10, 0))
        #expect(world.observedWeather(at: t(10, 5)) == .cloudy)
        #expect(world.observedWeather(at: t(13, 23)) == .cloudy)
        #expect(world.observedWeather(at: t(15, 0)) == nil) // 只留 96 小时的预报
        world.observeSky(place: shanghaiPlace, hourly: hours(from: t(13, 0), count: 2, .rain), at: t(13, 0))
        #expect(world.observedWeather(at: t(10, 5)) == nil) // 两天以前的清掉
        #expect(world.observedWeather(at: t(11, 5)) == .cloudy)
        #expect(world.state.sky.hours.count <= SkyRules.keepPast + SkyRules.keepFuture + 1)
        world.observeSky(place: london, hourly: [], at: t(13, 1))
        #expect(world.observedWeather(at: t(13, 0)) == nil && world.state.sky.weatherUpdatedAt == nil)
        #expect(world.place == london)
    }

    @Test("关掉以后全部忘掉")
    func forget() throws {
        var world = try makeWorld()
        world.observeSky(place: shanghaiPlace, hourly: hours(from: t(12, 9), count: 3, .rain), at: t(12, 9))
        world.forgetSky()
        #expect(world.place == nil && world.observedWeather(at: t(12, 10)) == nil)
        #expect(world.state.sky == SkyState())
    }

    @Test("南半球季节反过来；热带不下雪")
    func hemisphere() throws {
        #expect(Season.of(month: 12, southern: true) == .summer && Season.of(month: 7, southern: true) == .winter)
        #expect(Season.of(month: 4, southern: true) == .autumn && Season.of(month: 10, southern: true) == .spring)
        var world = try makeWorld()
        #expect(world.season(at: t(12, 10)) == .autumn)
        world.observeSky(place: sydney, hourly: [], at: t(12, 10))
        #expect(world.season(at: t(12, 10)) == .spring)
        world.observeSky(place: singapore, hourly: [], at: t(12, 11))
        let january = (1...28).flatMap { day in [3, 9, 15, 21].map { world.weather(at: t(day, $0, month: 1)) } }
        #expect(!january.contains(.snow) && january.contains(.rain))
    }

    @Test("存档：位置和真实天气存得下、读得回；旧存档没有这部分也能读")
    func save() throws {
        var world = try makeWorld()
        world.observeSky(place: shanghaiPlace, hourly: hours(from: t(12, 9), count: 3, .snow), at: t(12, 9))
        let data = try JSONEncoder().encode(world.state)
        let loaded = try JSONDecoder().decode(WorldState.self, from: data)
        #expect(loaded == world.state)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["sky"] = nil
        let old = try JSONDecoder().decode(WorldState.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.sky == SkyState())
    }
}
