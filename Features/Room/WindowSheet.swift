import CatWorld
import SwiftUI

/// "窗外"：点一下房间里的窗户打开。能看到现在窗外的天气、今天的日出日落，
/// 还有一个开关——让窗外的天气、季节、天亮天黑跟着你所在的地方（docs/cat-life.md 4.5）。
struct WindowSheet: View {
    @Environment(WorldStore.self) private var store
    @Environment(RealSky.self) private var sky
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        outlook(at: RoomClock.shift(timeline.date))
                    }
                    followCard
                    if sky.status == .on, !sky.weatherUnavailable, let attribution = sky.attribution {
                        attributionRow(attribution)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .background(PaperBackground())
            .navigationTitle("window.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") { dismiss() }.accessibilityIdentifier("window.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { sky.markHintSeen() }
    }

    // MARK: 现在窗外的样子

    private func outlook(at date: Date) -> some View {
        let weather = store.weather(at: date)
        let season = store.world.season(at: date)
        let hour = store.sceneHour(at: date)
        let night = RoomAtmosphere.darkness(at: hour) > 0.6
        return VStack(spacing: 12) {
            WindowSky(date: date, weather: weather, season: season, sceneHour: hour)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.caramel.opacity(0.35), lineWidth: 2))
                .accessibilityHidden(true)
            HStack(spacing: 10) {
                Image(systemName: Self.symbol(weather, night: night))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.caramelDeep)
                    .font(.title2)
                    .accessibilityHidden(true)
                Text(Self.nowText(weather, season))
                    .handwritten(20, relativeTo: .headline)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("window.now")
            if let sun = store.world.sunDay(at: date) {
                HStack(spacing: 8) {
                    Image(systemName: "sunrise.fill").foregroundStyle(Theme.caramel).accessibilityHidden(true)
                    Text(Self.sunText(sun))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                    Spacer(minLength: 0)
                }
                .accessibilityIdentifier("window.sun")
            }
        }
        .gameCard(padding: 14)
    }

    /// "下雨 · 秋天"。key 先拼成字符串再查（直接在 LocalizationValue 里插值查不到）
    static func nowText(_ weather: Weather, _ season: Season) -> String {
        let weatherKey = "weather." + weather.rawValue
        let seasonKey = "season." + season.rawValue
        return localized("window.now", String(localized: String.LocalizationValue(weatherKey)),
                         String(localized: String.LocalizationValue(seasonKey)))
    }

    static func symbol(_ weather: Weather, night: Bool) -> String {
        switch weather {
        case .clear: night ? "moon.stars.fill" : "sun.max.fill"
        case .cloudy: night ? "cloud.moon.fill" : "cloud.sun.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "cloud.snow.fill"
        }
    }

    static func sunText(_ sun: SunDay) -> String {
        switch sun {
        case let .normal(sunrise, sunset):
            localized("window.sun", sunrise.formatted(date: .omitted, time: .shortened), sunset.formatted(date: .omitted, time: .shortened))
        case .polarDay: String(localized: "window.sun.polarDay")
        case .polarNight: String(localized: "window.sun.polarNight")
        }
    }

    // MARK: 跟着你那里

    private var followCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { sky.isEnabled }, set: { on in
                if on {
                    Task { await sky.turnOn(store: store) }
                } else {
                    sky.turnOff(store: store)
                }
            })) {
                Label("window.follow.title", systemImage: "location.fill")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.caramel)
            .accessibilityIdentifier("window.follow")
            Text("window.follow.detail")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if let status = statusKey {
                Divider().overlay(Theme.line)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if sky.status == .asking { ProgressView().controlSize(.small) }
                    Text(LocalizedStringKey(status))
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                        .foregroundStyle(sky.status == .denied ? Theme.caramelDeep : Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("window.status")
                if sky.status == .denied {
                    Button("window.openSettings") {
                        // 这个 App 在系统"设置"里的那一页
                        if let url = URL(string: "app-settings:") { openURL(url) }
                    }
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .tint(Theme.caramelDeep)
                }
            }
        }
        .gameCard(padding: 14)
        .animation(.snappy, value: sky.status)
    }

    /// 开关下面那一行说明现在的情况
    private var statusKey: String? {
        switch sky.status {
        case .off: nil
        case .asking: "window.status.asking"
        case .denied: "window.status.denied"
        case .noPlace: "window.status.noPlace"
        case .on: sky.weatherUnavailable ? "window.status.noWeather" : "window.status.on"
        }
    }

    // MARK: Apple 天气的署名（用了它的数据就要显示）

    private func attributionRow(_ attribution: SkyAttribution) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: colorScheme == .dark ? attribution.markDark : attribution.markLight) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.clear
            }
            .frame(height: 14)
            .accessibilityLabel(Text(verbatim: " Weather"))
            Link("window.attribution", destination: attribution.legalPage)
                .font(.system(.caption, design: .rounded))
                .tint(Theme.inkSoft)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }
}
