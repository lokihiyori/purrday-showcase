import CatEngine
import CatWorld
import Economy
import SwiftUI

/// 房间：铺满整个屏幕，布丁按自己的作息过日子（docs/cat-life.md）。
struct RoomView: View {
    @Environment(WorldStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var editing = false
    @State private var showingCats = false
    /// "窗外"卡片（点窗户打开）
    @State private var showingWindow = false
    @State private var actor = CatActor()
    /// 回到前台的次数：变了就让布丁直接出现在该在的地方（不从旧位置走过去）
    @State private var appearances = 0
    @State private var actorReady = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let layout = StageLayout(geo: geo, editing: editing)
                RoomScene(editing: editing, layout: layout, actor: actor) { showingWindow = true }
            }
            // 挂在 GeometryReader 上（按安全区域排版），按钮才会在标签栏上面；房间本身铺满全屏
            .overlay(alignment: .bottom) {
                bottomBar.padding(.horizontal).padding(.bottom, 8)
            }
            // 陪她玩的三个按钮竖着放在右边，不挡住房间中间的她
            .overlay(alignment: .bottomTrailing) {
                if !editing, store.play == nil, store.canInteract {
                    ActionDock()
                        .padding(.trailing, 12)
                        .padding(.bottom, store.cat.messCount > 0 || store.cat.state == .purringAtBedtime ? 64 : 12)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: store.play == nil)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // 点名字：看所有的猫，换一只出来、领养新的
                    Button {
                        showingCats = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "pawprint.fill").foregroundStyle(Color.accentColor)
                            Text(CatNames.name(store.activeCat)).font(.headline).foregroundStyle(Theme.ink)
                        }
                        .fixedSize() // 工具栏会把纯文字压成"…"
                        .padding(.horizontal, 6)
                    }
                    .accessibilityHint(Text("cats.title"))
                    .accessibilityIdentifier("room.cats")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy) { editing.toggle() }
                    } label: {
                        // 工具栏里的按钮默认只显示图标，"布置"要让人一眼看懂，所以把文字也拼上
                        HStack(spacing: 4) {
                            Image(systemName: editing ? "checkmark" : "paintbrush.pointed.fill")
                            Text(editing ? "common.done" : "room.edit")
                        }
                    }
                    .accessibilityIdentifier("room.edit")
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) { FishBadge(fish: store.world.state.economy.wallet.fish) }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                actorReady = false
                store.sayAmbientLine(now: RoomClock.now())
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { appearances += 1 }
            }
            .task(id: refreshKey) { await followPresence() }
            .overlay(alignment: .top) {
                // 你不在的时候她做了什么（有新回忆要弹时先让回忆弹）
                if !editing, store.memoryToasts.isEmpty, let away = store.awayReport {
                    AwayCard(report: away) { withAnimation(.snappy) { store.dismissAwayReport() } }
                        .padding(.top, 8)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: away) {
                            try? await Task.sleep(for: .seconds(9))
                            withAnimation(.snappy) { store.dismissAwayReport() }
                        }
                }
            }
            .animation(.snappy, value: store.awayReport)
            .overlay(alignment: .top) {
                if !editing, let memory = store.memoryToasts.first {
                    MemoryToast(memory: memory, kind: store.activeCat)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: memory) {
                            try? await Task.sleep(for: .seconds(3.4))
                            withAnimation(.snappy) { store.dismissMemoryToast() }
                        }
                }
            }
            .animation(.snappy, value: store.memoryToasts.first)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.55), trigger: store.purrTicks)
            .onChange(of: store.purrUntil) { _, until in
                if let until { PurrSound.shared.purr(until: until, kind: store.activeCat) }
            }
            .onChange(of: store.soundSerial) { _, _ in
                if let sound = store.soundCue { CatVoice.shared.play(sound, kind: store.activeCat) }
            }
            .sensoryFeedback(.warning, trigger: store.flinchAt)
            .sheet(isPresented: Binding(get: { !store.pendingGrants.isEmpty }, set: { _ in })) {
                GiftSheet()
            }
            .sheet(isPresented: $showingCats) {
                CatsSheet()
            }
            .sheet(isPresented: $showingWindow) {
                WindowSheet()
            }
            .onChange(of: store.activeCat) { _, _ in
                actorReady = false // 换了一只猫：直接出现，不从上一只的位置走过来
            }
        }
    }

    /// 房间、猫的状态、看新家具这些变了，就马上重新问一次布丁该在哪
    private var refreshKey: RefreshKey {
        RefreshKey(room: store.world.state.room, state: store.cat.state, focus: store.catFocusItemID,
                   focusUntil: store.catFocusUntil, greetingUntil: store.greetingUntil, appearances: appearances,
                   interaction: store.interactionVersion, kind: store.activeCat)
    }

    private struct RefreshKey: Equatable {
        var room: RoomLayout
        var state: CatState
        var focus: Int?
        var focusUntil: Date?
        var greetingUntil: Date?
        var appearances: Int
        var interaction: Int
        var kind: CatKind
    }

    /// 每一拍（`CatPresence.nextChange`）问一次 Core 布丁该在哪、在做什么，交给 `CatActor` 安排走过去。
    private func followPresence() async {
        if appearances != lastAppearances {
            lastAppearances = appearances
            actorReady = false
        }
        while !Task.isCancelled {
            let now = RoomClock.now()
            let presence = store.presence(at: now)
            let bottoms = Dictionary(uniqueKeysWithValues: store.world.state.room.placed.map { ($0.itemID, $0.position.y) })
            actor.update(to: presence, now: now, animated: actorReady, itemBottoms: bottoms, hurry: store.catHurries(at: now),
                         speed: CatStyle.of(store.activeCat).speed)
            actorReady = true
            store.interactionTick(now: now, catArrived: !actor.isMoving(at: now))
            let wait = max(0.25, presence.nextChange.timeIntervalSince(now) + 0.05)
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    @State private var lastAppearances = 0

    /// 房间下面的按钮：布置时是收起来的家具；平时是收拾乱子、进入睡前模式，和陪她玩的三个按钮；
    /// 逗猫的时候换成提示和"完成"。
    @ViewBuilder
    private var bottomBar: some View {
        if editing {
            StoredFurnitureTray()
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    if store.cat.messCount > 0 {
                        Button {
                            withAnimation { store.clearMess(now: RoomClock.now()) }
                        } label: {
                            Label("room.mess.hint", systemImage: "sparkles")
                        }
                        .buttonStyle(.glass)
                    }
                    if store.cat.state == .purringAtBedtime {
                        NavigationLink {
                            BedtimeView()
                        } label: {
                            Label("bedtime.title", systemImage: "moon.zzz.fill")
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
                if store.play != nil {
                    PlayBar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: store.play != nil)
        }
    }
}

/// 房间画布（3:4）在屏幕上的位置：铺满屏幕宽度，底边贴着标签栏；布置时往上让出放家具的一栏。
/// 坐标都是全屏的（包括状态栏和标签栏下面）。
struct StageLayout {
    var screen: CGSize
    var stage: CGRect

    static let trayHeight = 132.0

    init(geo: GeometryProxy, editing: Bool) {
        let insets = geo.safeAreaInsets
        screen = CGSize(width: geo.size.width + insets.leading + insets.trailing,
                        height: geo.size.height + insets.top + insets.bottom)
        let width = min(screen.width, (screen.height - insets.top) * 0.75)
        let height = width * 4 / 3
        let bottom = screen.height - insets.bottom - 6 - (editing ? Self.trayHeight : 0)
        let top = max(bottom - height, insets.top - 60)
        stage = CGRect(x: (screen.width - width) / 2, y: top, width: width, height: height)
    }
}

/// 整个房间：窗外的天空、背景、阳光、家具、布丁，按前后顺序叠起来（规则见 `RoomGeometry.layers`）；
/// 上面再盖一层随时间变的光线和纸张颗粒。
struct RoomScene: View {
    @Environment(WorldStore.self) private var store
    @Environment(RealSky.self) private var sky
    let editing: Bool
    let layout: StageLayout
    let actor: CatActor
    /// 点了窗户
    var onWindowTap: () -> Void = {}
    @State private var draggingID: Int?
    @State private var dragOffset: CGSize = .zero
    /// 手指正在她身上划（摸）
    @State private var stroke: Stroke?

    private struct Stroke {
        var last: CGPoint
        var travelled = 0.0
        var sincePet = 0.0
        var petted = false
        /// 最近一小段手指移动的方向（毛顺着倒）
        var delta: CGSize = .zero
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let date = RoomClock.shift(timeline.date)
            let frame = actor.frame(at: date)
            // 画面钟点：知道用户在哪儿时跟着真实的日出日落（冬天天黑得早）
            let hour = store.sceneHour(at: date)
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Color(red: RoomArt.ceilingColor.red, green: RoomArt.ceilingColor.green, blue: RoomArt.ceilingColor.blue)
                    stageContent(frame: frame, date: date)
                        .frame(width: layout.stage.width, height: layout.stage.height, alignment: .topLeading)
                        .offset(x: layout.stage.minX, y: layout.stage.minY)
                    // 一天里的光线，再乘上天气（下雨天暗一点、冷一点）
                    RoomAtmosphere.light(at: hour).color
                        .blendMode(.multiply)
                        .allowsHitTesting(false)
                    RoomAtmosphere.weatherTint(store.weather(at: date)).color
                        .blendMode(.multiply)
                        .allowsHitTesting(false)
                    nightGlows(hour: hour)
                        .frame(width: layout.stage.width, height: layout.stage.height, alignment: .topLeading)
                        .offset(x: layout.stage.minX, y: layout.stage.minY)
                        .accessibilityHidden(true)
                    Image(RoomArt.paperGrain)
                        .resizable(resizingMode: .tile)
                        .blendMode(.multiply)
                        .opacity(0.55)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .compositingGroup()
                overlays(frame: frame, date: date)
                    .frame(width: layout.stage.width, height: layout.stage.height, alignment: .topLeading)
                    .offset(x: layout.stage.minX, y: layout.stage.minY)
                if store.play != nil, !editing {
                    featherControl
                        .frame(width: layout.stage.width, height: layout.stage.height)
                        .offset(x: layout.stage.minX, y: layout.stage.minY)
                }
                if let blink = store.blink {
                    BlinkLids(elapsed: date.timeIntervalSince(blink.start))
                        .frame(width: layout.screen.width, height: layout.screen.height)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: layout.screen.width, height: layout.screen.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
    }

    // MARK: 画布里的东西（坐标以画布左上角为原点）

    private var size: CGSize { layout.stage.size }

    @ViewBuilder
    private func stageContent(frame: CatActor.Frame, date: Date) -> some View {
        let pane = RoomArt.windowPane
        let bgHeight = size.width * RoomArt.backgroundAspect
        ZStack(alignment: .topLeading) {
            WindowSky(date: date, weather: store.weather(at: date), season: store.world.season(at: date),
                      sceneHour: store.sceneHour(at: date))
                .frame(width: pane.width * size.width, height: pane.height * size.height)
                .position(x: pane.midX * size.width, y: pane.midY * size.height)
                .accessibilityHidden(true)
            Image(RoomArt.background)
                .resizable()
                .frame(width: size.width, height: bgHeight)
                .position(x: size.width / 2, y: -size.width * RoomArt.backgroundStageTop + bgHeight / 2)
                .accessibilityHidden(true)
            if !editing {
                // 点窗户：看窗外的天气，可以让它跟着你那里（家具、猫画在它上面，挡住的地方点到的是它们）
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: pane.width * size.width, height: pane.height * size.height)
                    .position(x: pane.midX * size.width, y: pane.midY * size.height)
                    .onTapGesture { onWindowTap() }
                    .accessibilityElement()
                    .accessibilityLabel(Text("room.window"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("room.window")
            }
            if let beam = store.sunbeam(at: date) {
                Sunbeam(center: beam, stage: size, date: date, part: .floor)
                    .accessibilityHidden(true)
            }
            ForEach(layers(catDepth: frame.depth), id: \.stableID) { layer in
                switch layer {
                case let .furniture(item): furniture(item)
                case let .furnitureFront(item): furnitureFront(item)
                case .cat: cat(frame, date: date)
                }
            }
            if let treat = store.treat, !editing {
                treatView(treat, date: date)
            }
            if let trace = store.trace, !editing {
                traceView(trace)
            }
            if let beam = store.sunbeam(at: date) {
                Sunbeam(center: beam, stage: size, date: date, part: .shaft)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func layers(catDepth: CatDepth) -> [RoomLayer] {
        RoomGeometry.layers(store.world.state.room.placed, catalog: store.world.economy.catalog, cat: catDepth)
    }

    /// 家具在画布上的位置（底边中点）和大小：按透视换算（越往后越小、越往中间收）。
    private func projected(_ item: PlacedFurniture) -> (base: CGPoint, size: CGSize, onWall: Bool)? {
        guard let placement = store.world.economy.catalog.item(item.catalogID)?.placement else { return nil }
        let onWall = placement.zone == .wall
        let p = RoomPerspective.project(item.position, groundY: item.position.y, onWall: onWall)
        return (CGPoint(x: p.x * size.width, y: p.y * size.height),
                CGSize(width: placement.width * size.width * p.scale, height: placement.height * size.height * p.scale), onWall)
    }

    @ViewBuilder
    private func furniture(_ item: PlacedFurniture) -> some View {
        if let entry = store.world.economy.catalog.item(item.catalogID), let place = projected(item) {
            let frame = place.size
            let dragging = draggingID == item.itemID
            Image(RoomArt.furniture(item.catalogID))
                .resizable()
                .frame(width: frame.width, height: frame.height)
                .overlay {
                    if editing {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if editing { putAwayButton(item) }
                }
                .scaleEffect(dragging ? 1.06 : 1)
                .shadow(color: .black.opacity(dragging ? 0.2 : 0), radius: 8, y: 4)
                .position(x: place.base.x, y: place.base.y - frame.height / 2)
                .offset(dragging ? dragOffset : .zero)
                .zIndex(dragging ? 1 : 0)
                .gesture(dragGesture(item), isEnabled: editing)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text(LocalizedStringKey(entry.nameKey)))
                .accessibilityIdentifier("room.furniture.\(item.catalogID)")
        }
    }

    /// 能钻进去的家具的前半部分，盖在猫上面（只是画，不接收点击）。
    @ViewBuilder
    private func furnitureFront(_ item: PlacedFurniture) -> some View {
        if let place = projected(item) {
            Image(RoomArt.front(item.catalogID))
                .resizable()
                .frame(width: place.size.width, height: place.size.height)
                .position(x: place.base.x, y: place.base.y - place.size.height / 2)
                .offset(draggingID == item.itemID ? dragOffset : .zero)
                .opacity(editing ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func dragGesture(_ item: PlacedFurniture) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                draggingID = item.itemID
                dragOffset = value.translation
            }
            .onEnded { value in
                let onWall = projected(item)?.onWall ?? false
                let delta = RoomPerspective.unproject(dx: value.translation.width / size.width, dy: value.translation.height / size.height,
                                                      groundY: item.position.y, onWall: onWall)
                let target = RoomPoint(x: item.position.x + delta.dx, y: item.position.y + delta.dy)
                withAnimation(.snappy) {
                    try? store.moveFurniture(itemID: item.itemID, to: target, now: RoomClock.now())
                    draggingID = nil
                    dragOffset = .zero
                }
            }
    }

    private func putAwayButton(_ item: PlacedFurniture) -> some View {
        Button {
            withAnimation(.snappy) { try? store.putAway(itemID: item.itemID) }
        } label: {
            Image(systemName: "arrow.down")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor, in: Circle())
        }
        .offset(x: 8, y: -8)
        .accessibilityLabel(Text("room.putAway"))
        .accessibilityIdentifier("room.putAway.\(item.catalogID)")
    }

    // MARK: 布丁

    private var catSize: Double { RoomGeometry.catWidth * size.width }

    /// 布丁脚底在画布上的位置和这一排的缩放（透视）
    private func catPlace(_ frame: CatActor.Frame) -> (x: Double, y: Double, scale: Double, groundY: Double) {
        let ground = RoomPerspective.ground(of: frame.depth, placed: store.world.state.room.placed, catalog: store.world.economy.catalog)
        let p = RoomPerspective.project(frame.spot, groundY: ground.y, onWall: ground.onWall)
        let g = RoomPerspective.project(RoomPoint(x: frame.spot.x, y: ground.y), groundY: ground.y, onWall: ground.onWall)
        return (p.x * size.width, p.y * size.height, p.scale, g.y * size.height)
    }

    /// 此刻画面上的姿势和朝向：她停下来、正在演反应时，用反应那一段的姿势
    private func look(_ frame: CatActor.Frame, date: Date) -> (pose: CatPose, facing: Int, perf: CatPerformance.Frame?) {
        guard case .rest = frame.motion, frame.pose != .stateArt, let perf = store.performance?.frame(at: date) else {
            return (frame.pose, frame.facing, nil)
        }
        let pose = perf.step.pose ?? frame.pose
        return (pose, CatPoseArt.naturalFacing(pose) != 0 ? perf.facing : frame.facing, perf)
    }

    private func cat(_ frame: CatActor.Frame, date: Date) -> some View {
        let place = catPlace(frame)
        let s = catSize * place.scale
        let shown = look(frame, date: date)
        let w = s * CatPoseArt.wideAspect
        let bounds = CatPoseArt.bounds(shown.pose, facing: shown.facing, kind: store.activeCat)
        return ZStack {
            // AI 画的整张姿势图自带脚下的影子
            if frame.onGround, CatPoseArt.name(for: frame.pose) == nil, store.activeCat == .pudding {
                Ellipse()
                    .fill(Color(red: 0.30, green: 0.22, blue: 0.30).opacity(0.2))
                    .frame(width: s * (frame.pose == .curl || frame.pose == .sprawl || frame.pose == .stand ? 0.62 : 0.46),
                           height: s * 0.055)
                    .blur(radius: 2)
                    .position(x: place.x, y: place.groundY)
            }
            if let toy = toyProp(frame, shown: shown, date: date, size: s) {
                toy.view.position(x: place.x + toy.dx, y: place.y + toy.dy)
            }
            catArt(frame, shown: shown, date: date)
                .frame(width: w, height: s)
                .contentShape(BoundsShape(bounds: bounds, padding: 6))
                .gesture(petGesture(pose: shown.pose, facing: shown.facing, width: w, height: s))
                .position(x: place.x, y: place.y - s * RoomGeometry.catGround + s / 2)
                .opacity(editing ? 0.55 : 1)
                .allowsHitTesting(!editing && store.play == nil)
                .accessibilityElement(children: .ignore) // 猫由好几张部件叠成，朗读时是一只猫
                .accessibilityLabel(Text(LocalizedStringKey(catLabelKey(frame))))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { withAnimation(.spring) { store.tapCat(now: RoomClock.now()) } }
                .accessibilityAction(named: Text("room.cat.pet")) { store.pet(.head, now: RoomClock.now()) }
                .accessibilityIdentifier("room.cat")
        }
    }

    @ViewBuilder
    private func catArt(_ frame: CatActor.Frame, shown: (pose: CatPose, facing: Int, perf: CatPerformance.Frame?),
                        date: Date) -> some View {
        if frame.pose == .stateArt {
            CatStillImage(still: CatArt.assetName(for: store.cat, petted: store.isBeingPetted), kind: store.activeCat)
                .scaleEffect(x: 1, y: 1 + 0.012 * sin(date.timeIntervalSinceReferenceDate * 2 * .pi / 3.4), anchor: .bottom)
        } else {
            CatRigView(pose: shown.pose, facing: shown.facing, motion: frame.motion, fidget: frame.fidget,
                       fidgetElapsed: frame.fidgetElapsed, petted: store.isBeingPetted,
                       time: date.timeIntervalSinceReferenceDate, expression: expression(frame, perf: shown.perf, date: date),
                       kind: store.activeCat)
        }
    }

    /// 互动时的表情：被摸得舒服 / 慢眨眼回应时闭眼，正在演的反应，吓一跳，蹲着准备扑
    private func expression(_ frame: CatActor.Frame, perf: CatPerformance.Frame?, date: Date) -> CatExpression {
        var e = CatExpression()
        e.performance = perf
        if let stroke, stroke.petted {
            // 手指在她哪边：她往手上靠
            let w = catSize * CatPoseArt.wideAspect
            e.touch = ((stroke.last.x / max(w, 1) - 0.5) * 5).clamped(to: -1...1)
        }
        if perf == nil, let pet = store.lastPet, pet.reaction == .loves || pet.reaction == .likes {
            let t = date.timeIntervalSince(pet.at)
            e.eyesClosed = t >= 0 && t < (pet.reaction == .loves ? 1.8 : 1.0)
        }
        if let play = store.play, perf == nil {
            e.wiggle = play.arrivedAt != nil && play.feather != nil
        }
        if let flinch = store.flinchAt, perf == nil {
            let t = date.timeIntervalSince(flinch)
            if t >= 0, t < 0.5 { e.flinch = t }
        }
        return e
    }

    /// 自己玩玩具时，玩具画在她爪子前面（拨的时候会蹦，抱着蹬的时候在怀里）
    private func toyProp(_ frame: CatActor.Frame, shown: (pose: CatPose, facing: Int, perf: CatPerformance.Frame?),
                         date: Date, size s: Double) -> (view: AnyView, dx: Double, dy: Double)? {
        guard case .rest = frame.motion, shown.perf == nil, actor.target?.activity == .toy,
              let id = actor.target?.prop, let item = store.world.economy.catalog.item(id) else { return nil }
        let t = date.timeIntervalSinceReferenceDate
        let side = Double(shown.facing == 0 ? 1 : shown.facing)
        let toy = Image(Theme.art(for: item)).resizable().scaledToFit().frame(width: s * 0.17, height: s * 0.17)
        switch shown.pose {
        case .toyKick:
            return (AnyView(toy.rotationEffect(.degrees(12 * sin(t * 14)))), side * s * 0.06, -s * 0.33 + 3 * sin(t * 14))
        case .bat:
            let hop = abs(sin(t * 2 * .pi / 0.9))
            return (AnyView(toy.rotationEffect(.degrees(t * 120))), side * (s * 0.34 + 6 * sin(t * 1.7)), -s * 0.07 - hop * s * 0.12)
        default:
            return (AnyView(toy), side * s * 0.44, -s * 0.07)
        }
    }

    /// 在她身上点一下是说话；手指划过去是摸（每划一小段算摸一下，摸到哪里看 `PetMap`）。
    private func petGesture(pose: CatPose, facing: Int, width: Double, height: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                var current = stroke ?? Stroke(last: value.startLocation)
                let dx = value.location.x - current.last.x, dy = value.location.y - current.last.y
                let step = hypot(dx, dy)
                current.travelled += step
                current.sincePet += step
                current.last = value.location
                if step > 0.5 { current.delta = CGSize(width: dx, height: dy) }
                if current.travelled > 14, !current.petted || current.sincePet > 55 {
                    current.petted = true
                    current.sincePet = 0
                    if let region = petRegion(value.location, pose: pose, facing: facing, width: width, height: height) {
                        store.pet(region, now: RoomClock.now(), side: value.location.x < width / 2 ? -1 : 1)
                    }
                }
                stroke = current
            }
            .onEnded { _ in
                if stroke?.petted != true {
                    withAnimation(.spring) { store.tapCat(now: RoomClock.now()) }
                }
                stroke = nil
            }
    }

    private func petRegion(_ point: CGPoint, pose: CatPose, facing: Int, width: Double, height: Double) -> PetRegion? {
        var x = point.x / width
        let natural = CatPoseArt.naturalFacing(pose)
        if facing != 0, natural != 0, facing != natural { x = 1 - x }
        return PetMap.region(pose: pose, wideX: x, y: point.y / height, kind: store.activeCat)
    }

    /// 她玩过、丢在地板上的玩具。点一下收起来
    @ViewBuilder
    private func traceView(_ trace: RoomTrace) -> some View {
        if let item = store.world.economy.catalog.item(trace.toy) {
            let p = RoomPerspective.project(trace.spot, groundY: trace.spot.y, onWall: false)
            let w = catSize * 0.2 * p.scale
            Button {
                withAnimation(.spring) { store.pickUpTrace(now: RoomClock.now()) }
            } label: {
                ZStack {
                    Ellipse()
                        .fill(Color(red: 0.30, green: 0.22, blue: 0.30).opacity(0.16))
                        .frame(width: w * 0.9, height: w * 0.2)
                        .offset(y: w * 0.42)
                    Image(Theme.art(for: item))
                        .resizable()
                        .scaledToFit()
                        .frame(width: w, height: w)
                        .rotationEffect(.degrees(-18))
                }
                .contentShape(Rectangle().inset(by: -10))
            }
            .buttonStyle(.plain)
            .position(x: p.x * size.width, y: p.y * size.height - w * 0.45)
            .accessibilityLabel(Text("room.trace.pickUp"))
            .accessibilityIdentifier("room.trace")
        }
    }

    /// 地上的一小份零食：她跑过来，一口一口吃掉
    private func treatView(_ treat: TreatMoment, date: Date) -> some View {
        let spot = treat.treatSpot
        let p = RoomPerspective.project(spot, groundY: spot.y, onWall: false)
        let eaten = treat.eaten(at: date)
        let w = catSize * 0.3 * p.scale
        let bites = Int((eaten * 3).rounded(.down))
        return ZStack {
            Ellipse()
                .fill(Color(red: 0.30, green: 0.22, blue: 0.30).opacity(0.16))
                .frame(width: w * 1.1, height: w * 0.22)
                .offset(y: w * 0.2)
            ForEach(0..<max(0, 3 - bites), id: \.self) { i in
                Image("item-fish_cracker")
                    .resizable()
                    .scaledToFit()
                    .frame(width: w * 0.62)
                    .rotationEffect(.degrees(Double(i) * 37 - 30))
                    .offset(x: Double(i - 1) * w * 0.26, y: Double(i % 2) * -w * 0.12)
            }
        }
        .opacity(eaten >= 1 || !treat.onFloor || (treat.pickingUp && treat.eatingFrom.map { date.timeIntervalSince($0) > 0.4 } == true) ? 0 : 1)
        .position(x: p.x * size.width, y: p.y * size.height - w * 0.2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func catLabelKey(_ frame: CatActor.Frame) -> String {
        if let activity = actor.target?.activity { return "activity.\(activity.rawValue)" }
        return CatArt.stateKey(store.cat.state)
    }

    // MARK: 光线

    /// 夜里亮着的灯：落地灯、星星灯串（不受正片叠底影响，所以画在光线层上面）
    @ViewBuilder
    private func nightGlows(hour: Double) -> some View {
        let dark = RoomAtmosphere.darkness(at: hour)
        if dark > 0.05 {
            ZStack(alignment: .topLeading) {
                // 天花板垂下来的吊灯（背景里有吊灯时）：一圈暖光
                if let lamp = RoomArt.pendantLamp {
                    RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.58).opacity(0.6 * dark), .clear],
                                   center: .center, startRadius: 0, endRadius: size.width * 0.35)
                        .frame(width: size.width * 0.7, height: size.width * 0.7)
                        .position(lamp.applying(.init(scaleX: size.width, y: size.height)))
                        .blendMode(.screen)
                }
                ForEach(store.world.state.room.placed) { item in
                    if let place = projected(item) {
                        let frame = place.size
                        let glow: (CGPoint, Double)? = switch item.catalogID {
                        case "furniture.floor_lamp":
                            (CGPoint(x: place.base.x, y: place.base.y - frame.height * 0.85), size.width * 0.5)
                        case "furniture.star_lights":
                            (CGPoint(x: place.base.x, y: place.base.y - frame.height * 0.3), size.width * 0.42)
                        default: nil
                        }
                        if let glow {
                            RadialGradient(colors: [Color(red: 1, green: 0.82, blue: 0.5).opacity(0.55 * dark), .clear],
                                           center: .center, startRadius: 0, endRadius: glow.1 / 2)
                                .frame(width: glow.1, height: glow.1)
                                .position(glow.0)
                                .blendMode(.screen)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: 不受光线影响的：对话气泡、小爱心

    @ViewBuilder
    private func overlays(frame: CatActor.Frame, date: Date) -> some View {
        let place = catPlace(frame)
        let shown = look(frame, date: date)
        let s = catSize * place.scale
        let bounds = CatPoseArt.bounds(shown.pose, facing: shown.facing, kind: store.activeCat)
        // 头顶：按这个姿势的图量出来的最高点；头在哪边就往哪边偏一点（侧面、躺着的姿势）
        let catTop = place.y - s * (0.9 - bounds.y0)
        let x = place.x + s * CatPoseArt.wideAspect * ((bounds.x0 + bounds.x1) / 2 - 0.5) * 0.5
        ZStack(alignment: .topLeading) {
            if !editing, let line = store.bubble {
                let maxWidth = size.width * 0.74
                // 右边有陪她玩的按钮时，气泡别盖住它们
                let right = store.canInteract && store.play == nil ? 72.0 : 8.0
                SpeechBubble(key: line)
                    .frame(maxWidth: maxWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .position(x: min(max(x, maxWidth / 2 + 8), size.width - maxWidth / 2 - right), y: max(catTop - 26, 40))
                    .allowsHitTesting(false)
            }
            reactions(x: x, catTop: catTop, date: date)
            if !editing, store.play == nil, store.treat == nil, let request = store.request {
                RequestBubble(request: request, time: date.timeIntervalSinceReferenceDate) {
                    switch request {
                    case .play: store.startPlay(now: RoomClock.now())
                    case .treat: store.giveTreat(now: RoomClock.now())
                    case .earlySleep: store.tapCat(now: RoomClock.now())
                    }
                }
                // 在她头旁边（对话气泡在头顶上面）
                .position(x: x < size.width * 0.55 ? x + catSize * place.scale * 0.42 : x - catSize * place.scale * 0.42,
                          y: max(catTop + catSize * place.scale * 0.22, 90))
            }
            if let play = store.play, !editing {
                Feather(at: play.feather ?? RoomPoint(x: 0.5, y: 0.45), stage: size, time: date.timeIntervalSinceReferenceDate,
                        waiting: play.feather == nil)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if !editing, sky.showsHint, store.play == nil, store.bubble == nil {
                // 还没点开过"窗外"：窗台下面一行小提示
                let pane = RoomArt.windowPane
                Button(action: onWindowTap) {
                    Label("window.hint", systemImage: "cloud.sun.fill")
                        .handwritten(15, relativeTo: .footnote)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.card.opacity(0.94), in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.caramel.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .position(x: pane.midX * size.width, y: pane.maxY * size.height + 26)
                .accessibilityIdentifier("window.hint")
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// 摸她的反应：正在演反应时冒那一段的效果（爱心、音符、生气、问号……）；
    /// 没有反应时，舒服冒爱心，不熟冒"……"，摸到不喜欢的地方冒生气符号
    @ViewBuilder
    private func reactions(x: Double, catTop: Double, date: Date) -> some View {
        if let perf = store.performance, let frame = perf.frame(at: date), let effect = frame.step.effect {
            PerformanceEffect(effect: effect, elapsed: frame.elapsed, duration: frame.step.duration)
                .position(x: x, y: catTop)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            plainReactions(x: x, catTop: catTop, date: date)
        }
    }

    @ViewBuilder
    private func plainReactions(x: Double, catTop: Double, date: Date) -> some View {
        if let hearts = heartBurst(at: date) {
            let t = date.timeIntervalSince(hearts.start)
            ForEach(0..<hearts.count, id: \.self) { i in
                let delay = Double(i) * 0.14
                let p = max(0, min(1, (t - delay) / 1.3))
                let spread = Double(i) - Double(hearts.count - 1) / 2
                Heart()
                    .frame(width: 13 + Double(i % 3) * 4, height: 13 + Double(i % 3) * 4)
                    .scaleEffect(p < 0.15 ? p / 0.15 : 1)
                    .opacity(p > 0 ? 1 - p * p : 0)
                    .position(x: x + spread * 20 + sin(p * 6 + Double(i)) * 7, y: catTop + 24 - p * 64)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        if let pet = store.lastPet {
            let t = date.timeIntervalSince(pet.at)
            if pet.reaction == .tolerates, t >= 0, t < 1.4 {
                Text(verbatim: "…")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .padding(.horizontal, 10).padding(.bottom, 8).padding(.top, 2)
                    .background(Theme.card.opacity(0.92), in: Capsule())
                    .opacity(t < 1.1 ? 1 : (1.4 - t) / 0.3)
                    .position(x: x + 38, y: catTop + 6 - min(t, 0.4) * 20)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if pet.reaction == .dislikes, t >= 0, t < 1.1 {
                AngerMark()
                    .stroke(Color(red: 0.9, green: 0.33, blue: 0.36), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                    .frame(width: 26, height: 26)
                    .scaleEffect(t < 0.15 ? 0.4 + t / 0.15 * 0.8 : 1.2 - min(t - 0.15, 0.2))
                    .opacity(t < 0.85 ? 1 : (1.1 - t) / 0.25)
                    .position(x: x + 34, y: catTop + 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// 最近一次冒爱心：摸到喜欢的地方（越喜欢越多）、点她撒娇
    private func heartBurst(at date: Date) -> (start: Date, count: Int)? {
        var burst: (start: Date, count: Int)?
        if let tapped = store.pettedAt { burst = (tapped, 3) }
        if let pet = store.lastPet, pet.reaction == .loves || pet.reaction == .likes,
           pet.at >= (burst?.start ?? .distantPast) {
            burst = (pet.at, pet.reaction == .loves ? 6 : 3)
        }
        guard let burst, date.timeIntervalSince(burst.start) < 2.2 else { return nil }
        return burst
    }

    /// 逗猫时整个房间都能拖羽毛（羽毛跟着手指，她追羽毛正下方的地板）
    private var featherControl: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let u = (value.location.x / size.width).clamped(to: 0.04...0.96)
                        let v = (value.location.y / size.height).clamped(to: 0.12...0.9)
                        let groundY = (v + 0.14).clamped(to: (RoomGeometry.floorLine + 0.1)...0.95)
                        let span = RoomPerspective.span(groundY: groundY, onWall: false)
                        let roomX = ((u - span.left) / max(span.right - span.left, 0.01)).clamped(to: 0.1...0.9)
                        store.moveFeather(stage: RoomPoint(x: u, y: v), floor: RoomPoint(x: roomX, y: groundY),
                                          now: RoomClock.now())
                    }
            )
            .accessibilityHidden(true)
    }
}

extension RoomLayer {
    /// ForEach 用的稳定 id（家具拖动后位置变了，id 不变）
    var stableID: String {
        switch self {
        case let .furniture(item): "f\(item.itemID)"
        case let .furnitureFront(item): "front\(item.itemID)"
        case .cat: "cat"
        }
    }
}

/// 布置模式下房间下面的一栏：收起来的家具，点一下摆回房间。
struct StoredFurnitureTray: View {
    @Environment(WorldStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("room.edit.hint").font(.footnote).foregroundStyle(.secondary)
            let stored = store.world.storedFurniture
            if stored.isEmpty {
                Text("room.tray.empty").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(stored) { item in
                            Button {
                                withAnimation(.spring) { try? store.placeFurniture(itemID: item.id, now: RoomClock.now()) }
                            } label: {
                                VStack(spacing: 4) {
                                    Image(RoomArt.furniture(item.catalogID)).resizable().scaledToFit().frame(width: 52, height: 52)
                                    if let entry = store.world.economy.catalog.item(item.catalogID) {
                                        Text(LocalizedStringKey(entry.nameKey)).font(.caption2).lineLimit(1)
                                    }
                                }
                                .frame(width: 72)
                                .padding(8)
                                .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("room.tray.\(item.catalogID)")
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

/// 准时起床的早餐礼物。
struct GiftSheet: View {
    @Environment(WorldStore.self) private var store

    var body: some View {
        VStack(spacing: 18) {
            Text("wake.gift.title").gameTitle(26)
            CatStillImage(still: "cat-gift", kind: store.activeCat).frame(maxWidth: 180, maxHeight: 180)
                .accessibilityHidden(true)
            ForEach(Array(store.pendingGrants.enumerated()), id: \.offset) { _, grant in
                ForEach(grant.items) { item in
                    if let entry = store.world.economy.catalog.item(item.catalogID) {
                        HStack(spacing: 12) {
                            Image(Theme.art(for: entry)).resizable().scaledToFit().frame(width: 56, height: 56)
                                .background(ItemSpotlight(color: Theme.rarity(entry.rarity).mix(with: .white, by: 0.5)))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedStringKey(entry.nameKey))
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                    .foregroundStyle(Theme.ink)
                                RarityBadge(rarity: entry.rarity)
                            }
                        }
                        .gameCard(padding: 12, tint: entry.rarity >= .rare ? Theme.rarity(entry.rarity) : nil)
                    }
                }
                if grant.fish > 0 {
                    Label(localized("wake.gift.fish", grant.fish), systemImage: "fish.fill")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Theme.caramelDeep)
                }
            }
            Button("wake.gift.collect") { store.collectGift(now: RoomClock.now()) }
                .buttonStyle(CandyButtonStyle())
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperBackground())
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}

/// App 里用的时间。Debug 版本可以用 `-debugHour 21` 启动参数把时间拨到某个钟点（看傍晚、夜里的样子）。
/// 交给 Core 的时间也用它（新装的 App 配 `-debugHour 14`，半夜跑走查时猫也是醒着的）；系统闹钟相关的还是真实时间。
enum RoomClock {
    #if DEBUG
    static let offset: TimeInterval = {
        guard UserDefaults.standard.object(forKey: "debugHour") != nil else { return 0 }
        let target = UserDefaults.standard.double(forKey: "debugHour")
        return (target - RoomAtmosphere.hour(.now)) * 3600
    }()
    #else
    static let offset: TimeInterval = 0
    #endif

    static func now() -> Date { shift(.now) }
    static func shift(_ date: Date) -> Date { date.addingTimeInterval(offset) }
}
