import CatWorld
import Foundation
import Testing
import WeatherKit
@testable import Purrday

/// 假的定位：给一个固定的位置，或者失败
private struct FakePlace: PlaceProviding {
    var result: Result<Place, PlaceError>
    func place() async throws -> Place { try result.get() }
}

/// 假的天气：给接下来几个小时固定的天气，或者失败
private struct FakeWeather: SkyForecasting {
    var weather: WindowWeather?
    func hourly(at place: Place, now: Date) async throws -> [HourlyWeather] {
        guard let weather else { throw URLError(.notConnectedToInternet) }
        return (-2..<12).map { HourlyWeather(start: now.addingTimeInterval(Double($0) * 3600), weather: weather) }
    }

    func attribution() async -> SkyAttribution? {
        SkyAttribution(markLight: URL(string: "https://example.com/light.png")!, markDark: URL(string: "https://example.com/dark.png")!,
                       legalPage: URL(string: "https://example.com/legal")!)
    }
}

@MainActor
@Suite("窗外跟着你那里")
struct RealSkyTests {
    let base = WorldStoreTests()
    let shanghai = Place(latitude: 31.2, longitude: 121.5)

    /// 每个测试一份干净的设置
    private func defaults() -> UserDefaults {
        let name = "RealSkyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func sky(_ place: Result<Place, PlaceError>, weather: WindowWeather?, defaults: UserDefaults, hasPlace: Bool = false) -> RealSky {
        RealSky(places: FakePlace(result: place), forecasts: FakeWeather(weather: weather), defaults: defaults, hasPlace: hasPlace)
    }

    @Test("默认关着：不问位置、不改存档；第一次打开 App 不显示提示，第二次起才显示，点开过就不再显示")
    func offByDefault() async throws {
        let store = try base.makeStore(now: base.date(12, 10))
        let defaults = defaults()
        let first = sky(.success(shanghai), weather: .rain, defaults: defaults)
        #expect(first.status == .off && !first.isEnabled && !first.showsHint)
        await first.refresh(store: store, now: base.date(12, 10))
        #expect(store.world.place == nil)
        let second = sky(.success(shanghai), weather: .rain, defaults: defaults)
        #expect(second.showsHint)
        second.markHintSeen()
        #expect(!second.showsHint)
        #expect(!sky(.success(shanghai), weather: .rain, defaults: defaults).showsHint)
    }

    @Test("打开：记下大概的位置和真实天气，窗外马上变成真实的；设置记住了，下次打开 App 还是开着")
    func turnOn() async throws {
        let now = base.date(12, 10)
        let store = try base.makeStore(now: now)
        let defaults = defaults()
        let real: WindowWeather = store.world.seededWeather(at: now) == .snow ? .rain : .snow
        let sky = sky(.success(shanghai), weather: real, defaults: defaults)
        await sky.turnOn(store: store, now: now)
        #expect(sky.status == .on && !sky.weatherUnavailable && sky.attribution != nil)
        #expect(store.world.place == shanghai)
        #expect(store.weather(at: now) == real)
        // 上海 11 月 12 日 16:58 日落：17:30 画面上已经是黄昏
        #expect(store.sceneHour(at: base.date(12, 17, 30)) > 18.4)
        // 存进了存档
        let reopened = try base.makeStore(now: now)
        #expect(reopened.world.place == shanghai && reopened.weather(at: now) == real)
        #expect(self.sky(.success(shanghai), weather: real, defaults: defaults, hasPlace: true).status == .on)
    }

    @Test("半小时内不重复拿天气；过了半小时再拿")
    func throttle() async throws {
        let now = base.date(12, 10)
        let store = try base.makeStore(now: now)
        let sky = sky(.success(shanghai), weather: .rain, defaults: defaults())
        await sky.turnOn(store: store, now: now)
        let first = store.world.state.sky.weatherUpdatedAt
        await sky.refresh(store: store, now: now.addingTimeInterval(10 * 60))
        #expect(store.world.state.sky.weatherUpdatedAt == first)
        await sky.refresh(store: store, now: now.addingTimeInterval(31 * 60))
        #expect(store.world.state.sky.weatherUpdatedAt == now.addingTimeInterval(31 * 60))
    }

    @Test("拿不到天气：天气退回按种子算的，天亮天黑照样跟着位置")
    func noWeather() async throws {
        let now = base.date(12, 10)
        let store = try base.makeStore(now: now)
        let sky = sky(.success(shanghai), weather: nil, defaults: defaults())
        await sky.turnOn(store: store, now: now)
        #expect(sky.status == .on && sky.weatherUnavailable && sky.attribution == nil)
        #expect(store.world.place == shanghai)
        #expect(store.weather(at: now) == store.world.seededWeather(at: now))
        #expect(store.sceneHour(at: base.date(12, 17, 30)) > 18.4)
    }

    @Test("没有位置权限：什么都不记，说明是没权限；找不到位置：说明是找不到")
    func noPlace() async throws {
        let now = base.date(12, 10)
        let store = try base.makeStore(now: now)
        let denied = sky(.failure(.denied), weather: .rain, defaults: defaults())
        await denied.turnOn(store: store, now: now)
        #expect(denied.status == .denied && store.world.place == nil)
        #expect(abs(store.sceneHour(at: base.date(12, 17, 30)) - 17.5) < 0.001)
        let lost = sky(.failure(.unavailable), weather: .rain, defaults: defaults())
        await lost.turnOn(store: store, now: now)
        #expect(lost.status == .noPlace && store.world.place == nil)
    }

    @Test("后来收回了权限：以前记下的位置和天气都忘掉；只是一时找不到位置：以前的还用着")
    func revoked() async throws {
        let now = base.date(12, 10)
        let store = try base.makeStore(now: now)
        let defaults = defaults()
        await sky(.success(shanghai), weather: .rain, defaults: defaults).turnOn(store: store, now: now)
        let lost = sky(.failure(.unavailable), weather: .rain, defaults: defaults, hasPlace: true)
        await lost.refresh(store: store, now: now.addingTimeInterval(3600))
        #expect(lost.status == .on && store.world.place == shanghai)
        let revoked = sky(.failure(.denied), weather: .rain, defaults: defaults, hasPlace: true)
        await revoked.refresh(store: store, now: now.addingTimeInterval(7200))
        #expect(revoked.status == .denied && store.world.place == nil && store.world.observedWeather(at: now) == nil)
    }

    @Test("关掉：位置和真实天气都忘掉，窗外回到按种子算的天气和墙上的钟点")
    func turnOff() async throws {
        let now = base.date(12, 10)
        let store = try base.makeStore(now: now)
        let defaults = defaults()
        let sky = sky(.success(shanghai), weather: .rain, defaults: defaults)
        await sky.turnOn(store: store, now: now)
        sky.turnOff(store: store)
        #expect(sky.status == .off && sky.attribution == nil)
        #expect(store.world.place == nil && store.world.state.sky == SkyState())
        #expect(abs(store.sceneHour(at: base.date(12, 17, 30)) - 17.5) < 0.001)
        #expect(!defaults.bool(forKey: RealSky.enabledKey))
        #expect(try base.makeStore(now: now).world.place == nil)
    }

    @Test("画面钟点换了一天、换了地方都会重新算")
    func sceneHourCache() throws {
        let store = try base.makeStore(now: base.date(12, 10))
        store.observeSky(place: shanghai, hourly: [], now: base.date(12, 10))
        let evening = store.sceneHour(at: base.date(12, 17, 30))
        #expect(evening == store.world.sceneHour(at: base.date(12, 17, 30)))
        #expect(store.sceneHour(at: base.date(13, 17, 30)) == store.world.sceneHour(at: base.date(13, 17, 30)))
        // 换到悉尼（11 月是那边的春末，傍晚五点半天还亮着——按上海的时区算是另一个钟点，这里只看它确实重新算了）
        store.observeSky(place: Place(latitude: -33.9, longitude: 151.2), hourly: [], now: base.date(12, 10))
        #expect(store.sceneHour(at: base.date(12, 17, 30)) == store.world.sceneHour(at: base.date(12, 17, 30)))
        #expect(store.sceneHour(at: base.date(12, 17, 30)) != evening)
    }

    @Test("Apple 的每一种天气都对到窗外画得出来的四种里")
    func conditions() {
        #expect(AppleWeather.weather(.clear) == .clear && AppleWeather.weather(.partlyCloudy) == .clear)
        #expect(AppleWeather.weather(.mostlyCloudy) == .cloudy && AppleWeather.weather(.foggy) == .cloudy)
        #expect(AppleWeather.weather(.drizzle) == .rain && AppleWeather.weather(.thunderstorms) == .rain)
        #expect(AppleWeather.weather(.heavySnow) == .snow && AppleWeather.weather(.wintryMix) == .snow)
        let all = Set(WeatherCondition.allCases.map(AppleWeather.weather))
        #expect(all == Set(WindowWeather.allCases))
    }

    @Test("窗外卡片上的图标：晴天夜里是月亮")
    func symbols() {
        #expect(WindowSheet.symbol(.clear, night: false) == "sun.max.fill")
        #expect(WindowSheet.symbol(.clear, night: true) == "moon.stars.fill")
        #expect(WindowSheet.symbol(.rain, night: true) == "cloud.rain.fill")
        // 每种天气、每个季节都有名字（不是把 key 原样显示出来）
        for weather in WindowWeather.allCases {
            for season in Season.allCases {
                let text = WindowSheet.nowText(weather, season)
                #expect(!text.contains("weather.") && !text.contains("season."), "\(text)")
            }
        }
    }
}
