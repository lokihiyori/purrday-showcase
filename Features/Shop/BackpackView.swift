import CatWorld
import Economy
import SwiftUI

/// 收藏册：礼物、纪念品、家具、毛色分四页，没得到的显示剪影，像图鉴一样慢慢集齐；
/// 最后一页是和她的回忆（第一次让你摸、第一次眨眼……）。
struct BackpackView: View {
    @Environment(WorldStore.self) private var store
    @State private var tab: Page = .items(.gift)

    enum Page: Hashable {
        case items(ItemKind)
        case memories
    }

    private let tabs: [(Page, LocalizedStringKey, String, String)] = [
        (.items(.gift), "backpack.gifts", "gift.fill", "gifts"),
        (.items(.souvenir), "backpack.souvenirs", "leaf.fill", "souvenirs"),
        (.items(.furniture), "backpack.furniture", "sofa.fill", "furniture"),
        (.items(.coat), "backpack.coats", "paintpalette.fill", "coats"),
        (.memories, "backpack.memories", "heart.text.square.fill", "memories"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    BannerHeader(image: "banner-collection", title: "backpack.title", subtitle: "backpack.subtitle")
                    tabBar
                    switch tab {
                    case let .items(kind):
                        progress(have: ownedCount(kind), total: entries(kind).count)
                        if ownedCount(kind) == 0, kind != .coat {
                            Text("backpack.empty")
                                .font(.system(.callout, design: .rounded))
                                .foregroundStyle(Theme.inkSoft)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                            ForEach(entries(kind)) { entry in cell(entry) }
                        }
                        .padding(.horizontal, 16)
                    case .memories:
                        progress(have: store.world.bond.memories.count, total: CatMemory.allCases.count)
                        MemoriesPage(memories: store.world.bond.memories, kind: store.activeCat)
                    }
                }
                .padding(.bottom, 32)
            }
            .ignoresSafeArea(edges: .top)
            .background(PaperBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { FishBadge(fish: store.world.state.economy.wallet.fish) }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var catalog: Catalog { store.world.economy.catalog }

    private func owned(_ catalogID: String) -> [OwnedItem] {
        store.world.state.economy.items.filter { $0.catalogID == catalogID }
    }

    private func entries(_ kind: ItemKind) -> [CatalogItem] {
        catalog.items.filter { $0.kind == kind }
    }

    private func ownedCount(_ kind: ItemKind) -> Int {
        entries(kind).filter { !owned($0.id).isEmpty }.count
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(tabs, id: \.0) { kind, title, symbol, id in
                Button {
                    withAnimation(.snappy) { tab = kind }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                        Text(title).font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(tab == kind ? .white : Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(tab == kind ? AnyShapeStyle(Theme.caramel) : AnyShapeStyle(Theme.card))
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == kind ? .isSelected : [])
                .accessibilityIdentifier("backpack.tab.\(id)")
            }
        }
        .padding(.horizontal, 12)
    }

    private func progress(have: Int, total: Int) -> some View {
        HStack(spacing: 10) {
            ProgressView(value: Double(have), total: Double(max(total, 1)))
                .tint(Theme.caramel)
            Text(verbatim: "\(have) / \(total)")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func cell(_ entry: CatalogItem) -> some View {
        let copies = owned(entry.id)
        let have = !copies.isEmpty
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if have { ItemSpotlight(color: Theme.rarity(entry.rarity).mix(with: .white, by: 0.6)) }
                    Image(Theme.art(for: entry))
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                        .colorMultiply(have ? .white : Color(red: 0.45, green: 0.36, blue: 0.34))
                        .opacity(have ? 1 : 0.22)
                }
                .frame(height: 78)
                if copies.count > 1 {
                    Text(verbatim: "×\(copies.count)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.caramelDeep, in: Capsule())
                }
            }
            if have {
                Text(LocalizedStringKey(entry.nameKey))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                RarityBadge(rarity: entry.rarity)
                if entry.kind == .furniture, let item = copies.first {
                    Text(store.world.state.room.furniture(itemID: item.id) != nil ? "backpack.inRoom" : "backpack.stored")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                }
                if let price = entry.sellPrice, let item = copies.first {
                    Button(localized("backpack.sell", price)) { withAnimation { try? store.sell(itemID: item.id) } }
                        .buttonStyle(CandyButtonStyle(color: Theme.sage, compact: true))
                }
            } else {
                Text(verbatim: "？？？")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .accessibilityLabel(Text("backpack.notYet"))
            }
        }
        .frame(maxWidth: .infinity, minHeight: have ? 160 : 120, alignment: .top)
        .gameCard(padding: 10, tint: have && entry.rarity >= .rare ? Theme.rarity(entry.rarity).opacity(0.7) : nil)
    }
}

/// 回忆页：像一本贴满拍立得的小相册。发生过的写着日子，没发生的先空着。
struct MemoriesPage: View {
    let memories: [CatMemory: Date]
    /// 现在陪着你的那只猫（回忆是她的）
    var kind: CatKind = .pudding

    var body: some View {
        VStack(spacing: 14) {
            Text("memories.hint")
                .handwritten(16, relativeTo: .callout)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            ForEach(Array(CatMemory.allCases.enumerated()), id: \.element) { index, memory in
                card(memory, date: memories[memory], tilt: index.isMultiple(of: 2) ? -1.2 : 1.2)
            }
        }
        .padding(.horizontal, 18)
    }

    @ViewBuilder
    private func card(_ memory: CatMemory, date: Date?, tilt: Double) -> some View {
        let have = date != nil
        HStack(alignment: .top, spacing: 14) {
            // 拍立得
            VStack(spacing: 0) {
                ZStack {
                    LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.86), Color(red: 0.98, green: 0.88, blue: 0.78)],
                                   startPoint: .top, endPoint: .bottom)
                    CatStillImage(still: MemoryArt.still(for: memory), kind: kind)
                        .padding(4)
                        .colorMultiply(have ? .white : Color(red: 0.45, green: 0.36, blue: 0.34))
                        .opacity(have ? 1 : 0.2)
                }
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                Color.clear.frame(height: 14)
            }
            .padding(6)
            .background(.white, in: RoundedRectangle(cornerRadius: 5))
            .shadow(color: Theme.caramelDeep.opacity(0.18), radius: 4, y: 2)
            .overlay(alignment: .top) {
                if have {
                    // 一小段纸胶带
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.caramel.opacity(0.35))
                        .frame(width: 38, height: 13)
                        .rotationEffect(.degrees(-tilt * 4))
                        .offset(y: -6)
                }
            }
            .rotationEffect(.degrees(tilt * 2))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                if let date {
                    Text(LocalizedStringKey(MemoryArt.titleKey(memory)))
                        .handwritten(20, relativeTo: .headline)
                        .foregroundStyle(Theme.ink)
                    Text(date, format: .dateTime.year().month().day())
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.caramelDeep)
                    Text(LocalizedStringKey(MemoryArt.detailKey(memory)))
                        .handwritten(16, relativeTo: .subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(verbatim: "？？？")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.inkSoft)
                    Text("memories.locked")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .gameCard(padding: 12)
        .opacity(have ? 1 : 0.8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("memories.\(memory.rawValue)")
    }
}
