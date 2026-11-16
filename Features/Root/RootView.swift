import AlarmKit
import CatEngine
import CatWorld
import StoreKit
import SwiftUI

struct RootView: View {
    @Environment(WorldStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(RealSky.self) private var sky
    @Environment(\.requestReview) private var requestReview
    @AppStorage("onboarded") private var onboarded = false
    @State private var showPaywall = false
    @State private var audio = BedtimeAudio()
    // 睡前声音的设置（在睡前页里改，边放边生效）
    @AppStorage(BedtimeMix.ambientKey) private var bedtimeAmbient = BedtimeMix.Ambient.none.rawValue
    @AppStorage(BedtimeMix.purrVolumeKey) private var bedtimePurrVolume = 0.7
    @AppStorage(BedtimeMix.ambientVolumeKey) private var bedtimeAmbientVolume = 0.5

    var body: some View {
        TabView {
            Tab("tab.room", systemImage: "house.fill") { RoomView() }
            Tab("tab.alarms", systemImage: "alarm.fill") { AlarmListView() }
            Tab("tab.shop", systemImage: "bag.fill") { ShopView() }
            Tab("tab.backpack", systemImage: "backpack.fill") { BackpackView() }
        }
        .tint(Color("AccentColor"))
        .fontDesign(.rounded)
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { _ in })) {
            OnboardingView { onboarded = true }
        }
        .fullScreenCover(isPresented: Binding(get: { onboarded && isWaking }, set: { _ in })) {
            WakeView()
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                store.foreground(now: RoomClock.now())
                // 打开了"窗外跟着你那里"：隔一阵子更新一次天气
                Task { await sky.refresh(store: store) }
            }
        }
        .onChange(of: store.pendingPrompts) { _, prompts in
            guard let prompt = prompts.first else { return }
            store.pendingPrompts.removeFirst()
            switch prompt {
            case .paywall: showPaywall = true
            case .requestReview: requestReview()
            }
        }
        .onChange(of: store.paywallRequested) { _, requested in
            if requested {
                showPaywall = true
                store.paywallRequested = false
            }
        }
        .onChange(of: store.effectsVersion) {
            audio.apply(store.lastEffects, kind: store.activeCat) { store.send(.bedtimeTimerEnded(at: RoomClock.now())) }
        }
        .onChange(of: bedtimeAmbient) { audio.refresh() }
        .onChange(of: bedtimePurrVolume) { audio.refresh() }
        .onChange(of: bedtimeAmbientVolume) { audio.refresh() }
        .task {
            // 闹钟响起 / 被锁屏操作停止或贪睡时，AlarmKit 会推送最新的闹钟列表
            for await alarms in AlarmManager.shared.alarmUpdates {
                let alerting = alarms.filter { $0.state == .alerting }.map(\.id.uuidString)
                store.alarmsUpdated(alertingIDs: alerting, now: RoomClock.now())
            }
        }
    }

    private var isWaking: Bool {
        store.cat.state == .wakingUp || store.cat.state == .makingMischief
    }
}
