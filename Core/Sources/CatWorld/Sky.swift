import CatEngine
import Economy
import Foundation

// 窗外跟着你那里走（docs/cat-life.md 4.5）：用户同意后，App 把大概的位置和逐小时的真实天气交给这里。
// 这里只做纯计算：按经纬度算日出日落，把真实的钟点换算成"画面钟点"（天空、光线、地板上的阳光都按它画），
// 有真实天气就用真实的，没有就退回按种子算的（`Weather.swift`）。不联网、不读时钟。

/// 大概的位置：四舍五入到 0.1°（约 10 公里）。够算日出日落和查天气，认不出是哪条街。
public struct Place: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = (min(max(latitude, -90), 90) * 10).rounded() / 10
        self.longitude = (min(max(longitude, -180), 180) * 10).rounded() / 10
    }

    /// 南半球：季节反过来
    public var isSouthern: Bool { latitude < 0 }
    /// 热带：不下雪
    public var isTropical: Bool { abs(latitude) < 23.5 }
}

/// 某一天的太阳。
public enum SunDay: Hashable, Sendable {
    case normal(sunrise: Date, sunset: Date)
    /// 极昼：太阳一整天不落
    case polarDay
    /// 极夜：太阳一整天不升
    case polarNight
}

public enum Sun {
    /// `date` 所在的那一天（当地日历）的日出日落。标准的日出方程，误差一两分钟。
    public static func day(containing date: Date, at place: Place, calendar: Calendar) -> SunDay {
        let rad = Double.pi / 180
        let noon = calendar.startOfDay(for: date).addingTimeInterval(12 * 3600)
        let julian = noon.timeIntervalSince1970 / 86400 + 2_440_587.5
        // 离当地中午最近的那次"太阳过头顶"是 2000 年起的第几天
        let n = (julian - 2_451_545.0 + place.longitude / 360).rounded()
        let meanNoon = n - place.longitude / 360
        let anomaly = (357.5291 + 0.985_600_28 * meanNoon).truncatingRemainder(dividingBy: 360) * rad
        let center = 1.9148 * sin(anomaly) + 0.02 * sin(2 * anomaly) + 0.0003 * sin(3 * anomaly)
        let longitude = (anomaly / rad + center + 180 + 102.9372).truncatingRemainder(dividingBy: 360) * rad
        let transit = 2_451_545.0 + meanNoon + 0.0053 * sin(anomaly) - 0.0069 * sin(2 * longitude)
        let sinDeclination = sin(longitude) * sin(23.4397 * rad)
        let cosDeclination = (1 - sinDeclination * sinDeclination).squareRoot()
        let latitude = min(max(place.latitude, -89), 89) * rad
        // 太阳上沿碰到地平线（算上大气折射）：-0.833°
        let cosHour = (sin(-0.833 * rad) - sin(latitude) * sinDeclination) / (cos(latitude) * cosDeclination)
        if cosHour > 1 { return .polarNight }
        if cosHour < -1 { return .polarDay }
        let half = acos(cosHour) / rad / 360
        func moment(_ julian: Double) -> Date { Date(timeIntervalSince1970: (julian - 2_440_587.5) * 86400) }
        return .normal(sunrise: moment(transit - half), sunset: moment(transit + half))
    }
}

/// 把真实的时刻换算成"画面钟点"。房间的天空、光线是按一个标准的日子画的（6:30 日出、18:00 日落，
/// `RoomAtmosphere` 的关键帧），知道了真实的日出日落，就把真实时刻对到那条曲线上：
/// 冬天下午五点天就黑了，夏天晚上八点还亮着。晨昏的长度不跟着白天拉长（天黑下来总是那么快）。
public struct SceneClock: Hashable, Sendable {
    struct Anchor: Hashable, Sendable {
        var time: Date
        /// 画面钟点；跨到第二天的会超过 24，前一天的是负数
        var hour: Double
    }

    /// 标准日子的日出、日落（画面钟点）
    public static let sunrise = 6.5
    public static let sunset = 18.0
    /// 日出前多久天开始亮、日出后多久天全亮；日落前多久光线开始变暖、日落后多久天全黑（小时）
    static let dawn = 1.5, morning = 1.5, afternoon = 2.0, dusk = 3.0

    let anchors: [Anchor]

    /// 这个时刻的画面钟点（0..<24）
    public func hour(at date: Date) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return 12 }
        var hour = date < first.time ? first.hour : last.hour
        for (a, b) in zip(anchors, anchors.dropFirst()) where date >= a.time && date < b.time {
            hour = a.hour + (b.hour - a.hour) * date.timeIntervalSince(a.time) / b.time.timeIntervalSince(a.time)
            break
        }
        let wrapped = hour.truncatingRemainder(dividingBy: 24)
        return wrapped < 0 ? wrapped + 24 : wrapped
    }

    /// `date` 那一天用的钟。
    public static func make(for date: Date, at place: Place, calendar: Calendar) -> SceneClock {
        let start = calendar.startOfDay(for: date)
        let end = start.addingTimeInterval(86400)
        switch Sun.day(containing: date, at: place, calendar: calendar) {
        case .polarDay:
            // 太阳不落：一整天都是白天，地板上的阳光慢慢移
            return SceneClock(anchors: [Anchor(time: start, hour: 8), Anchor(time: end, hour: 16)])
        case .polarNight:
            return SceneClock(anchors: [Anchor(time: start, hour: 0), Anchor(time: end, hour: 5)])
        case let .normal(sunrise, sunset):
            let day: TimeInterval = 86400
            var lastSet = sunset.addingTimeInterval(-day)
            if case let .normal(_, set) = Sun.day(containing: date.addingTimeInterval(-day), at: place, calendar: calendar) { lastSet = set }
            var nextRise = sunrise.addingTimeInterval(day)
            if case let .normal(rise, _) = Sun.day(containing: date.addingTimeInterval(day), at: place, calendar: calendar) { nextRise = rise }
            return SceneClock(anchors:
                night(from: lastSet, to: sunrise, offset: -24)
                    + daytime(from: sunrise, to: sunset)
                    + night(from: sunset, to: nextRise, offset: 0))
        }
    }

    /// 白天：日出 → 全亮 → 光线变暖 → 日落。白天太短（高纬度的冬天）时，上午和下午在中间碰头。
    private static func daytime(from sunrise: Date, to sunset: Date) -> [Anchor] {
        let length = sunset.timeIntervalSince(sunrise) / 3600
        let lead = min(morning, length * morning / (morning + afternoon))
        let tail = min(afternoon, length - lead)
        return [
            Anchor(time: sunrise, hour: Self.sunrise),
            Anchor(time: sunrise.addingTimeInterval(lead * 3600), hour: Self.sunrise + lead),
            Anchor(time: sunset.addingTimeInterval(-tail * 3600), hour: Self.sunset - tail),
        ]
    }

    /// 夜里：日落 → 天全黑 → 天开始亮 → 日出。夜太短（高纬度的夏天）时，黄昏直接接上黎明。
    private static func night(from sunset: Date, to sunrise: Date, offset: Double) -> [Anchor] {
        let length = sunrise.timeIntervalSince(sunset) / 3600
        let lead = min(dusk, length * dusk / (dusk + dawn))
        let tail = min(dawn, length - lead)
        return [
            Anchor(time: sunset, hour: Self.sunset + offset),
            Anchor(time: sunset.addingTimeInterval(lead * 3600), hour: Self.sunset + lead + offset),
            Anchor(time: sunrise.addingTimeInterval(-tail * 3600), hour: Self.sunrise - tail + 24 + offset),
        ]
    }
}

/// 一个整点开始的一小时里，真实的天气。
public struct HourlyWeather: Hashable, Sendable {
    public var start: Date
    public var weather: Weather

    public init(start: Date, weather: Weather) {
        self.start = start
        self.weather = weather
    }
}

/// 存档里关于"窗外跟着你那里"的部分。用户没打开这个功能时是空的。
public struct SkyState: Codable, Hashable, Sendable {
    public internal(set) var place: Place?
    /// 真实天气：从 1970 年起的第几个小时 → 天气。只留前后几天。
    var hours: [Int: Weather] = [:]
    /// 最近一次拿到真实天气的时间
    public internal(set) var weatherUpdatedAt: Date?

    public init() {}

    static func hourIndex(_ date: Date) -> Int { Int((date.timeIntervalSince1970 / 3600).rounded(.down)) }
}

public enum SkyRules {
    /// 过去的真实天气留多久（"你不在的时候"要用）、未来的预报留多久
    static let keepPast = 48, keepFuture = 96
    /// 位置变了这么多（度）就算换了地方：旧的天气不再适用
    static let moved = 1.0
}

extension CatWorld {
    /// 用户同意用的大概位置（没打开"跟着你那里"时是 nil）
    public var place: Place? { state.sky.place }

    /// 记下位置和逐小时的真实天气（过去几小时的实况 + 未来的预报）。`hourly` 为空表示这次只拿到了位置
    /// （没网、天气服务不可用）：日出日落和季节照样跟着走，天气先用按种子算的。
    public mutating func observeSky(place: Place, hourly: [HourlyWeather], at now: Date) {
        if let old = state.sky.place,
           abs(old.latitude - place.latitude) > SkyRules.moved || abs(old.longitude - place.longitude) > SkyRules.moved {
            state.sky.hours = [:]
            state.sky.weatherUpdatedAt = nil
        }
        state.sky.place = place
        guard !hourly.isEmpty else { return }
        for hour in hourly { state.sky.hours[SkyState.hourIndex(hour.start)] = hour.weather }
        let current = SkyState.hourIndex(now)
        state.sky.hours = state.sky.hours.filter { (current - SkyRules.keepPast...current + SkyRules.keepFuture).contains($0.key) }
        state.sky.weatherUpdatedAt = now
    }

    /// 用户关掉了"跟着你那里"：位置和真实天气都忘掉。
    public mutating func forgetSky() {
        state.sky = SkyState()
    }

    /// 这个时刻有没有真实的天气
    public func observedWeather(at date: Date) -> Weather? {
        state.sky.hours[SkyState.hourIndex(date)]
    }

    /// 这一天的日出日落（不知道位置时是 nil）
    public func sunDay(at date: Date) -> SunDay? {
        state.sky.place.map { Sun.day(containing: date, at: $0, calendar: catConfig.calendar) }
    }

    /// 这一天的画面钟（不知道位置时是 nil：画面钟点就是墙上的钟点）
    public func sceneClock(for date: Date) -> SceneClock? {
        state.sky.place.map { SceneClock.make(for: date, at: $0, calendar: catConfig.calendar) }
    }

    /// 画面钟点：天空、光线、地板上的阳光按它画。
    public func sceneHour(at date: Date) -> Double {
        sceneClock(for: date)?.hour(at: date) ?? Self.clockHour(date, calendar: catConfig.calendar)
    }

    public static func clockHour(_ date: Date, calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }
}
