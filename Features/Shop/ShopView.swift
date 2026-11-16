import CatWorld
import Economy
import SwiftUI

/// 商店：顶部是布丁看店的插画，然后是今日推荐，下面按"猫咪用品 / 家居装饰"分两栏，卡片上写着她会拿它做什么。
/// 点一件家具的图，可以先看看它摆在你房间里的样子再决定买不买。
struct ShopView: View {
    @Environment(WorldStore.self) private var store
    @State private var shortBy: Int?
    /// 正在看哪件家具的详情
    @State private var previewing: CatalogItem?

    /// 猫自己用的东西；其余算家居装饰（只是商店里的分栏，不影响玩法）
    private static let catStuff: Set<String> = [
        "furniture.cardboard_box", "furniture.cushion", "furniture.food_bowl", "furniture.water_fountain",
        "furniture.scratching_post", "furniture.cat_tunnel", "furniture.bed_cloud", "furniture.cat_tree",
        "furniture.window_hammock", "furniture.wall_shelf",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    BannerHeader(image: "banner-shop", title: "shop.title", subtitle: "shop.subtitle")
                    let items = store.world.economy.shopItems()
                    todaysPicks
                    section("shop.section.cat", items: items.filter { Self.catStuff.contains($0.id) })
                    section("shop.section.home", items: items.filter { !Self.catStuff.contains($0.id) })
                }
                .padding(.bottom, 32)
            }
            .ignoresSafeArea(edges: .top)
            .background(PaperBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { FishBadge(fish: store.world.state.economy.wallet.fish) }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .alert(Text(localized("shop.notEnough", shortBy ?? 0)), isPresented: Binding(get: { shortBy != nil }, set: { if !$0 { shortBy = nil } })) {
                Button("common.close", role: .cancel) {}
            }
            .sheet(item: $previewing) { item in
                ShopItemSheet(item: item) { buy(item) }
            }
        }
    }

    /// 今日推荐：每天换三件你还没有的（`CatWorld.dailyPicks`）。横着排，图大一点
    @ViewBuilder
    private var todaysPicks: some View {
        let picks = store.world.dailyPicks(at: RoomClock.now(), isPlus: store.isPlus)
        if !picks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.caramel)
                    Text("shop.picks.title").gameTitle(20)
                }
                .padding(.horizontal, 20)
                Text("shop.picks.subtitle")
                    .handwritten(15, relativeTo: .footnote)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(picks) { item in
                            Button { previewing = item } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        ItemSpotlight(color: Theme.caramel.mix(with: .white, by: 0.45))
                                        Image(Theme.art(for: item)).resizable().scaledToFit().padding(6)
                                    }
                                    .frame(width: 124, height: 110)
                                    Text(LocalizedStringKey(item.nameKey))
                                        .font(.system(.footnote, design: .rounded).weight(.bold))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                    HStack(spacing: 3) {
                                        Image(systemName: "fish.fill").font(.system(size: 10, weight: .bold))
                                        Text(verbatim: "\(item.price ?? 0)").font(.system(.caption, design: .rounded).weight(.heavy))
                                    }
                                    .foregroundStyle(Theme.caramelDeep)
                                }
                                .frame(width: 132)
                                .gameCard(padding: 10, tint: Theme.caramel.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("shop.pick.\(item.id)")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, items: [CatalogItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "pawprint.fill").foregroundStyle(Theme.caramel)
                Text(title).gameTitle(20)
            }
            .padding(.horizontal, 20)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(items) { item in card(item) }
            }
            .padding(.horizontal, 16)
        }
    }

    private func card(_ item: CatalogItem) -> some View {
        let owned = store.world.state.economy.owns(item.id)
        return VStack(spacing: 8) {
            // 点图：看看它摆在房间里的样子
            Button { previewing = item } label: {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        ItemSpotlight()
                        Image(Theme.art(for: item)).resizable().scaledToFit().padding(8)
                    }
                    Image(systemName: "eye.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.caramelDeep)
                        .frame(width: 22, height: 22)
                        .background(Theme.card.opacity(0.9), in: Circle())
                }
                .frame(height: 104)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("shop.preview"))
            .accessibilityIdentifier("shop.item.\(item.id)")
            Text(LocalizedStringKey(item.nameKey))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            uses(item)
            if item.plusOnly {
                Text("shop.plusOnly").font(.caption.bold()).foregroundStyle(Theme.caramelDeep)
            }
            if owned {
                Label("shop.owned", systemImage: "checkmark.circle.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.sage)
                    .padding(.vertical, 8)
            } else {
                Button { buy(item) } label: {
                    Label { Text(verbatim: "\(item.price ?? 0)").monospacedDigit() } icon: { Image(systemName: "fish.fill") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CandyButtonStyle())
                .accessibilityIdentifier("shop.buy.\(item.id)")
            }
        }
        .frame(maxWidth: .infinity)
        .gameCard(padding: 12)
        .opacity(owned ? 0.85 : 1)
    }

    /// 她会拿它做什么（小图标，来自目录里家具的猫位置）
    @ViewBuilder
    private func uses(_ item: CatalogItem) -> some View {
        let uses = Array(Set((item.placement?.spots ?? []).flatMap(\.uses).map(Self.symbol))).sorted().prefix(4)
        HStack(spacing: 6) {
            ForEach(Array(uses), id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.caramelDeep.opacity(0.8))
                    .frame(width: 22, height: 22)
                    .background(Theme.caramel.opacity(0.14), in: Circle())
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }

    static func symbol(_ use: FurnitureUse) -> String {
        switch use {
        case .nap: "moon.zzz.fill"
        case .sit, .loaf, .groom: "pawprint.fill"
        case .hide: "shippingbox.fill"
        case .perch: "arrow.up.circle.fill"
        case .eat: "fork.knife"
        case .drink: "drop.fill"
        case .scratch: "scribble"
        case .watch: "eye.fill"
        case .sunbathe: "sun.max.fill"
        }
    }

    private func buy(_ item: CatalogItem) {
        do {
            try store.buy(item.id, now: RoomClock.now())
        } catch let EconomyError.insufficientFish(needed, balance) {
            shortBy = needed - balance
        } catch {
            // requiresPlus 已经由 WorldStore 触发付费墙
        }
    }
}

/// 一件家具的详情：摆在你房间里的样子、她会拿它做什么、价格。
struct ShopItemSheet: View {
    @Environment(WorldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: CatalogItem
    let buy: () -> Void

    var body: some View {
        let owned = store.world.state.economy.owns(item.id)
        ScrollView {
            VStack(spacing: 16) {
                Text(LocalizedStringKey(item.nameKey)).gameTitle(24)
                RoomPreview(catalogID: item.id)
                    .frame(maxWidth: 300)
                    .accessibilityIdentifier("shop.roomPreview")
                usesList
                if owned {
                    Label("shop.owned", systemImage: "checkmark.circle.fill")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Theme.sage)
                } else {
                    Button {
                        buy()
                        dismiss()
                    } label: {
                        Label { Text(verbatim: "\(item.price ?? 0)").monospacedDigit() } icon: { Image(systemName: "fish.fill") }
                            .frame(maxWidth: 220)
                    }
                    .buttonStyle(CandyButtonStyle())
                    .accessibilityIdentifier("shop.sheet.buy")
                }
                Button("common.close") { dismiss() }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .accessibilityIdentifier("shop.sheet.close")
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(PaperBackground())
        .presentationDetents([.large])
    }

    /// 她会拿它做什么：一行一件
    @ViewBuilder
    private var usesList: some View {
        let uses = Self.uses(of: item)
        if !uses.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(uses, id: \.self) { use in
                    HStack(spacing: 10) {
                        Image(systemName: ShopView.symbol(use))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.caramelDeep)
                            .frame(width: 26, height: 26)
                            .background(Theme.caramel.opacity(0.14), in: Circle())
                        Text(LocalizedStringKey(Self.useKey(use)))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .gameCard(padding: 14)
        }
    }

    /// 这件家具的用途（去重，按固定顺序）
    static func uses(of item: CatalogItem) -> [FurnitureUse] {
        let all = Set((item.placement?.spots ?? []).flatMap(\.uses))
        return FurnitureUse.allCases.filter(all.contains)
    }

    static func useKey(_ use: FurnitureUse) -> String { "shop.use.\(use.rawValue)" }
}

/// 把一件还没买的家具摆进你现在的房间看看（小小的一张房间画，新家具亮着，其余的淡一点；她坐在旁边）。
struct RoomPreview: View {
    @Environment(WorldStore.self) private var store
    let catalogID: String

    var body: some View {
        GeometryReader { geo in
            let size = CGSize(width: geo.size.width, height: geo.size.width * 4 / 3)
            let pane = RoomArt.windowPane
            let bgHeight = size.width * RoomArt.backgroundAspect
            let date = RoomClock.now()
            ZStack(alignment: .topLeading) {
                WindowSky(date: date, weather: store.weather(at: date), season: store.world.season(at: date), sceneHour: store.sceneHour(at: date))
                    .frame(width: pane.width * size.width, height: pane.height * size.height)
                    .position(x: pane.midX * size.width, y: pane.midY * size.height)
                Image(RoomArt.background)
                    .resizable()
                    .frame(width: size.width, height: bgHeight)
                    .position(x: size.width / 2, y: -size.width * RoomArt.backgroundStageTop + bgHeight / 2)
                if let preview = store.world.roomPreview(adding: catalogID, at: date) {
                    ForEach(preview.furniture) { piece in
                        furniture(piece, size: size, highlighted: piece == preview.added)
                    }
                    cat(at: preview.cat, size: size)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.caramel.opacity(0.5), lineWidth: 2))
        }
        .aspectRatio(3.0 / 4, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("shop.preview"))
    }

    @ViewBuilder
    private func furniture(_ piece: PlacedFurniture, size: CGSize, highlighted: Bool) -> some View {
        if let placement = store.world.economy.catalog.item(piece.catalogID)?.placement {
            let onWall = placement.zone == .wall
            let p = RoomPerspective.project(piece.position, groundY: piece.position.y, onWall: onWall)
            let w = placement.width * size.width * p.scale
            let h = placement.height * size.height * p.scale
            Image(RoomArt.furniture(piece.catalogID))
                .resizable()
                .frame(width: w, height: h)
                .opacity(highlighted ? 1 : 0.55)
                .shadow(color: highlighted ? Color.white.opacity(0.9) : .clear, radius: 8)
                .position(x: p.x * size.width, y: p.y * size.height - h / 2)
        }
    }

    private func cat(at spot: RoomPoint, size: CGSize) -> some View {
        let p = RoomPerspective.project(spot, groundY: spot.y, onWall: false)
        let s = RoomGeometry.catWidth * size.width * p.scale
        return Image(CatPoseArt.name(for: .sit, kind: store.activeCat) ?? "cat-pose-sit")
            .resizable()
            .scaledToFill()
            .frame(width: s * (store.activeCat == .pudding ? 1 : CatPoseArt.wideAspect), height: s)
            .position(x: p.x * size.width, y: p.y * size.height - s * RoomGeometry.catGround + s / 2)
    }
}
