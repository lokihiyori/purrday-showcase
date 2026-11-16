import CatEngine
import Economy
import Foundation

// 窗外的季节和天气（docs/cat-on-chair.md 第 4 条）：不只是换个背景——下雨下雪的日子没有太阳可晒，
// 她更爱蹲在窗边看、睡得也更多。平时天气由种子和日期算出来（不联网、不存档），同一时刻问几次都一样；
// 用户打开"跟着你那里"以后，有真实天气的钟点用真实的（`Sky.swift`）。

/// 季节（按月份；南半球反过来）。
public enum Season: String, Sendable, CaseIterable {
    case spring, summer, autumn, winter

    public static func of(month: Int, southern: Bool = false) -> Season {
        let northern: Season = switch month {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
        guard southern else { return northern }
        return switch northern {
        case .spring: .autumn
        case .summer: .winter
        case .autumn: .spring
        case .winter: .summer
        }
    }
}

/// 窗外的天气。
public enum Weather: String, Codable, Sendable, CaseIterable {
    case clear, cloudy, rain, snow

    /// 有没有太阳照进来
    public var isSunny: Bool { self == .clear }
    /// 在下雨或者下雪
    public var isFalling: Bool { self == .rain || self == .snow }
}

/// 同一个类型的另一个名字：App 里同时用 WeatherKit 时，`Weather` 会和它的类型重名。
public typealias WindowWeather = Weather

public enum WeatherRules {
    /// 每 6 小时一段（凌晨、上午、下午、晚上），一段里天气不变
    public static let block: TimeInterval = 6 * 3600

    /// 每个季节一天的天气：下雨 / 下雪 / 阴天的可能（剩下的是晴天）
    static func odds(_ season: Season) -> (rain: Double, snow: Double, cloudy: Double) {
        switch season {
        case .spring: (0.24, 0, 0.18)
        case .summer: (0.14, 0, 0.12)
        case .autumn: (0.24, 0.02, 0.22)
        case .winter: (0.05, 0.26, 0.24)
        }
    }

    /// 下雨、下雪时她更爱做什么（倍数）
    static let fallingActivities: [CatActivity: Double] = [.watch: 1.9, .nap: 1.35, .loaf: 1.2, .hide: 1.2, .play: 0.8]
}

extension CatWorld {
    /// 季节。知道用户在南半球时反过来。
    public func season(at date: Date) -> Season {
        Season.of(month: catConfig.calendar.component(.month, from: date), southern: state.sky.place?.isSouthern ?? false)
    }

    /// 此刻窗外的天气：有真实天气就用真实的，没有就用按种子算的。
    public func weather(at date: Date) -> Weather {
        observedWeather(at: date) ?? seededWeather(at: date)
    }

    /// 按种子算的天气。先定这一天的"主天气"，一天四段里大多数是它，偶尔放晴或者转阴。
    /// 和哪只猫陪着你无关（用存档的种子，不用每只猫自己的）。
    public func seededWeather(at date: Date) -> Weather {
        let c = catConfig.calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let day = UInt64((c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0))
        var rng = SeededRandom(seed: Self.mix(state.lifeSeed, day, 0x5745_4154))
        var odds = WeatherRules.odds(season(at: date))
        if state.sky.place?.isTropical ?? false {
            // 热带不下雪：算成下雨
            odds = (odds.rain + odds.snow, 0, odds.cloudy)
        }
        let roll = Self.unit(&rng)
        let main: Weather = roll < odds.rain ? .rain : roll < odds.rain + odds.snow ? .snow
            : roll < odds.rain + odds.snow + odds.cloudy ? .cloudy : .clear
        // 这一段：70% 是主天气；下雨下雪的日子其余时候是阴天，别的日子其余时候在晴和阴之间换
        var blockRng = SeededRandom(seed: Self.mix(state.lifeSeed, day * 4 + UInt64((c.hour ?? 0) / 6), 0x424C_4F43))
        if Self.unit(&blockRng) < 0.7 { return main }
        if main.isFalling { return .cloudy }
        return main == .clear ? (Self.unit(&blockRng) < 0.4 ? .cloudy : .clear) : .clear
    }

    /// 地板上的阳光：晴天、有太阳的钟点才有（知道日出日落时跟着真实的太阳）。
    public func sunbeam(at date: Date) -> RoomPoint? {
        guard weather(at: date).isSunny else { return nil }
        return RoomGeometry.sunbeam(sceneHour: sceneHour(at: date))
    }
}
