import CatWorld
import CoreLocation
import Foundation
import Observation
import WeatherKit

// 窗外跟着你那里（docs/cat-life.md 4.5）。默认关着，用户在"窗外"卡片里自己打开。
// 打开后：问一次位置（系统给的是大概位置，我们再四舍五入到 0.1°），用它查 Apple 天气的逐小时天气，
// 存进存档（小组件也读得到）。日出日落是 Core 按经纬度自己算的，不用联网。
// 拿不到天气（没网、没开通 WeatherKit）时窗外的天气退回按种子算的，天亮天黑照样跟着走。

/// 问位置失败的原因
enum PlaceError: Error, Equatable {
    /// 用户没给位置权限（或者设备上关了定位）
    case denied
    /// 一时找不到位置
    case unavailable
}

/// 给一个大概的位置。
protocol PlaceProviding: Sendable {
    func place() async throws -> Place
}

/// Apple 天气的署名（用了它的数据就要显示）
struct SkyAttribution: Equatable, Sendable {
    var markLight: URL
    var markDark: URL
    var legalPage: URL
}

/// 给逐小时的天气。
protocol SkyForecasting: Sendable {
    /// 从一天前到四天后的逐小时天气（过去的是实况，"你不在的时候"会用到）
    func hourly(at place: Place, now: Date) async throws -> [HourlyWeather]
    func attribution() async -> SkyAttribution?
}

/// 用系统定位。Info.plist 里设了 `NSLocationDefaultAccuracyReduced`：系统给的就是大概位置（几公里）。
struct DevicePlace: PlaceProviding {
    /// 等多久算找不到（用户看权限弹窗的时间也算在里面）
    var timeout: Duration = .seconds(90)

    func place() async throws -> Place {
        try await withThrowingTaskGroup(of: Place.self) { group in
            group.addTask {
                // 这个对象活着的时候系统才会问权限、给位置
                let session = CLServiceSession(authorization: .whenInUse)
                defer { session.invalidate() }
                for try await update in CLLocationUpdate.liveUpdates() {
                    if let location = update.location {
                        return Place(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                    }
                    if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                        throw PlaceError.denied
                    }
                }
                throw PlaceError.unavailable
            }
            group.addTask { [timeout] in
                try await Task.sleep(for: timeout)
                throw PlaceError.unavailable
            }
            defer { group.cancelAll() }
            guard let place = try await group.next() else { throw PlaceError.unavailable }
            return place
        }
    }
}

/// 用 Apple 天气（WeatherKit）。需要开发者账号给 App 开通 WeatherKit，见 docs/mac-setup.md。
struct AppleWeather: SkyForecasting {
    func hourly(at place: Place, now: Date) async throws -> [HourlyWeather] {
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let (current, hours) = try await WeatherService.shared.weather(
            for: location,
            including: .current,
            .hourly(startDate: now.addingTimeInterval(-24 * 3600), endDate: now.addingTimeInterval(96 * 3600))
        )
        var result = hours.forecast.map { HourlyWeather(start: $0.date, weather: Self.weather($0.condition)) }
        // 这个小时用实况（放在最后，盖掉预报）
        result.append(HourlyWeather(start: now, weather: Self.weather(current.condition)))
        return result
    }

    func attribution() async -> SkyAttribution? {
        guard let attribution = try? await WeatherService.shared.attribution else { return nil }
        return SkyAttribution(markLight: attribution.combinedMarkLightURL, markDark: attribution.combinedMarkDarkURL,
                              legalPage: attribution.legalPageURL)
    }

    /// Apple 的三十多种天气 → 窗外画得出来的四种
    static func weather(_ condition: WeatherCondition) -> WindowWeather {
        switch condition {
        case .clear, .mostlyClear, .partlyCloudy, .breezy, .windy, .hot, .frigid:
            .clear
        case .cloudy, .mostlyCloudy, .foggy, .haze, .smoky, .blowingDust:
            .cloudy
        case .drizzle, .freezingDrizzle, .freezingRain, .hail, .heavyRain, .hurricane, .isolatedThunderstorms, .rain,
             .scatteredThunderstorms, .sleet, .strongStorms, .sunShowers, .thunderstorms, .tropicalStorm:
            .rain
        case .blizzard, .blowingSnow, .flurries, .heavySnow, .snow, .sunFlurries, .wintryMix:
            .snow
        @unknown default:
            .cloudy
        }
    }
}

@MainActor
@Observable
final class RealSky {
    enum Status: Equatable {
        /// 没打开
        case off
        /// 正在问位置（第一次打开）
        case asking
        /// 跟着你那里
        case on
        /// 没有位置权限
        case denied
        /// 一时找不到位置
        case noPlace
    }

    static let enabledKey = "sky.followsPlace"
    static let hintSeenKey = "sky.hintSeen"
    static let launchesKey = "sky.launches"
    /// 多久更新一次天气
    static let refreshEvery: TimeInterval = 30 * 60

    private(set) var status: Status
    /// 最近一次有没有拿到真实天气。没拿到时窗外的天气是按种子算的
    private(set) var weatherUnavailable = false
    private(set) var attribution: SkyAttribution?
    /// 用户有没有点开过"窗外"
    private(set) var hintSeen: Bool
    /// 第几次打开 App
    @ObservationIgnored private let launches: Int

    /// 窗台下面要不要有一行小提示：还没点开过"窗外"，而且不是第一次打开 App（第一次先让用户认识猫）
    var showsHint: Bool { !hintSeen && launches >= 2 }

    @ObservationIgnored private let places: any PlaceProviding
    @ObservationIgnored private let forecasts: any SkyForecasting
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private var refreshing = false

    init(places: any PlaceProviding = DevicePlace(), forecasts: any SkyForecasting = AppleWeather(),
         defaults: UserDefaults = .standard, hasPlace: Bool = false) {
        self.places = places
        self.forecasts = forecasts
        self.defaults = defaults
        hintSeen = defaults.bool(forKey: Self.hintSeenKey)
        launches = defaults.integer(forKey: Self.launchesKey) + 1
        defaults.set(launches, forKey: Self.launchesKey)
        status = defaults.bool(forKey: Self.enabledKey) ? (hasPlace ? .on : .asking) : .off
    }

    var isEnabled: Bool { status != .off }

    func markHintSeen() {
        guard !hintSeen else { return }
        hintSeen = true
        defaults.set(true, forKey: Self.hintSeenKey)
    }

    /// 用户打开了开关：问位置、拿天气。
    func turnOn(store: WorldStore, now: Date = .now) async {
        defaults.set(true, forKey: Self.enabledKey)
        if status == .off { status = store.world.place == nil ? .asking : .on }
        await refresh(store: store, now: now, force: true)
    }

    /// 用户关掉了开关：位置和真实天气都忘掉，窗外回到随意的天气。
    func turnOff(store: WorldStore) {
        defaults.set(false, forKey: Self.enabledKey)
        status = .off
        weatherUnavailable = false
        attribution = nil
        lastRefresh = nil
        store.forgetSky()
    }

    /// 回到前台时叫一下：打开着、离上次更新够久了，就再拿一次。
    func refresh(store: WorldStore, now: Date = .now, force: Bool = false) async {
        guard isEnabled, !refreshing else { return }
        if !force, let lastRefresh, now.timeIntervalSince(lastRefresh) < Self.refreshEvery { return }
        refreshing = true
        defer { refreshing = false }
        let place: Place
        do {
            place = try await places.place()
        } catch PlaceError.denied {
            // 权限收回了：不再用以前记下的位置
            guard isEnabled else { return }
            store.forgetSky()
            status = .denied
            attribution = nil
            return
        } catch {
            guard isEnabled else { return }
            // 找不到位置：以前记下的还能用（日出日落不会变）
            status = store.world.place == nil ? .noPlace : .on
            return
        }
        var hourly: [HourlyWeather] = []
        do {
            hourly = try await forecasts.hourly(at: place, now: now)
        } catch {
            hourly = []
        }
        // 等的时候用户可能把开关关了
        guard isEnabled else { return }
        weatherUnavailable = hourly.isEmpty
        store.observeSky(place: place, hourly: hourly, now: now)
        status = .on
        lastRefresh = now
        if !hourly.isEmpty, attribution == nil { attribution = await forecasts.attribution() }
    }
}
