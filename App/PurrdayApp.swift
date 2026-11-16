import CatEngine
import CatWorld
import Economy
import SwiftUI
import WidgetKit

@main
struct PurrdayApp: App {
    @State private var store: WorldStore
    @State private var sky: RealSky

    init() {
        let store = AppEnvironment.makeStore()
        _store = State(initialValue: store)
        _sky = State(initialValue: RealSky(hasPlace: store.world.place != nil))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(sky)
        }
    }
}

/// 组装 App 的依赖。
@MainActor
enum AppEnvironment {
    static func makeStore() -> WorldStore {
        let catalog: Catalog
        do {
            catalog = try Catalog.bundled()
        } catch {
            fatalError("内置目录 catalog.json 读取失败：\(error)") // 打包错误，开发阶段就会发现
        }
        let store = WorldStore(
            storage: WorldStorage(fileURL: AppGroup.file("world.json")),
            log: EventLog(fileURL: AppGroup.file("events.jsonl")),
            plus: PlusStatus(),
            scheduler: AlarmKitScheduler(),
            catConfig: CatEngineConfig(calendar: .autoupdatingCurrent),
            economy: EconomyEngine(catalog: catalog),
            now: RoomClock.now()
        )
        store.onPersist = { WidgetCenter.shared.reloadAllTimelines() }
        #if DEBUG
        let debugFish = UserDefaults.standard.integer(forKey: "debugFish") // 启动参数 -debugFish 200
        if debugFish > 0 { store.debugGrantFish(debugFish) }
        let debugBond = UserDefaults.standard.integer(forKey: "debugBond") // 启动参数 -debugBond 600（看某个好感阶段）
        if debugBond > 0 { store.debugSetBond(debugBond) }
        if UserDefaults.standard.bool(forKey: "debugMornings") { store.debugFillMornings(now: .now) } // -debugMornings 1
        // -debugPlace 64.1,-21.9：当作用户在这个经纬度（看日出日落、南半球季节的效果；不问权限、不联网）
        if let raw = UserDefaults.standard.string(forKey: "debugPlace") {
            let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 { store.observeSky(place: Place(latitude: parts[0], longitude: parts[1]), hourly: [], now: .now) }
        }
        #endif
        return store
    }
}
