import CatWorld
import Economy
import SwiftUI

/// "我的猫"：所有的猫排成一页。换一只出来陪你、领养新的、给她起名字。
/// 房间里同一时间只有一只；每只猫有自己的好感度和回忆（docs/cat-life.md 第 7 节第 3 步）。
struct CatsSheet: View {
    @Environment(WorldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// 猫的声音（叫声、呼噜、吃东西的声音）
    @AppStorage(CatVoice.enabledKey) private var sounds = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("cats.subtitle")
                        .handwritten(16, relativeTo: .callout)
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    ForEach(CatKind.allCases, id: \.self) { kind in
                        CatCard(kind: kind) { dismiss() }
                    }
                    Toggle(isOn: $sounds) {
                        Label("cats.sounds", systemImage: "speaker.wave.2.fill")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.caramel)
                    .gameCard(padding: 14)
                    .accessibilityIdentifier("cats.sounds")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .background(PaperBackground())
            .navigationTitle("cats.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 4) {
                        Image(systemName: "fish.fill")
                        Text(verbatim: "\(store.world.state.economy.wallet.fish)").monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(localized("room.fish", store.world.state.economy.wallet.fish))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") { dismiss() }.accessibilityIdentifier("cats.done")
                }
            }
        }
    }
}

/// 一只猫的卡片：画像、名字、一句介绍，和现在能做的事。
private struct CatCard: View {
    @Environment(WorldStore.self) private var store
    let kind: CatKind
    /// 换好 / 领养好以后回房间看她
    let onChosen: () -> Void
    @State private var name = ""
    @State private var shake = 0

    var body: some View {
        let availability = store.world.availability(of: kind)
        let known = availability != .locked
        HStack(alignment: .center, spacing: 14) {
            portrait(known: known)
            VStack(alignment: .leading, spacing: 6) {
                if availability == .active || availability == .resting {
                    TextField(CatNames.defaultName(kind), text: $name)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .submitLabel(.done)
                        .onChange(of: name) { _, value in UserDefaults.standard.set(value, forKey: CatNames.key(kind)) }
                        .accessibilityIdentifier("cats.name.\(kind.rawValue)")
                } else {
                    Text(known ? CatNames.defaultName(kind) : "？？？")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(known ? Theme.ink : Theme.inkSoft)
                }
                Text(LocalizedStringKey(aboutKey))
                    .handwritten(15, relativeTo: .subheadline)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                action(availability)
            }
            Spacer(minLength: 0)
        }
        .gameCard(padding: 14, tint: availability == .active ? Theme.caramel.opacity(0.7) : nil)
        .phaseAnimator([0.0, -6.0, 6.0, -3.0, 0.0], trigger: shake) { view, x in view.offset(x: x) } animation: { _ in .linear(duration: 0.07) }
        .onAppear { name = CatNames.name(kind) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cats.card.\(kind.rawValue)")
    }

    /// 拼好的 key 要先变成 String 再交给 LocalizedStringKey（直接写插值会被当成格式）
    private var aboutKey: String { "cats.\(kind.rawValue).about" }

    /// 坐着的画像；还不能领养的只露出剪影
    private func portrait(known: Bool) -> some View {
        ZStack {
            ItemSpotlight(color: Theme.caramel.mix(with: .white, by: 0.55))
            Image(CatPoseArt.name(for: .sit, kind: kind) ?? "cat-pose-sit")
                .resizable()
                .scaledToFill()
                .frame(width: 96 * (kind == .pudding ? 1 : CatPoseArt.wideAspect), height: 96)
                .colorMultiply(known ? .white : Color(red: 0.45, green: 0.36, blue: 0.34))
                .opacity(known ? 1 : 0.28)
        }
        .frame(width: 96, height: 104)
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func action(_ availability: CatAvailability) -> some View {
        switch availability {
        case .active:
            Label("cats.active", systemImage: "heart.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.caramelDeep)
        case .resting:
            Button("cats.switch") {
                try? store.switchCat(to: kind, now: RoomClock.now())
                onChosen()
            }
            .buttonStyle(CandyButtonStyle(color: Theme.sage, compact: true))
            .accessibilityIdentifier("cats.switch.\(kind.rawValue)")
        case .adoptable, .locked:
            switch kind.adoption {
            case let .fish(price):
                Button {
                    adopt()
                } label: {
                    HStack(spacing: 4) {
                        Text("cats.adopt")
                        Image(systemName: "fish.fill").font(.system(size: 10, weight: .bold))
                        Text(verbatim: "\(price)")
                    }
                }
                .buttonStyle(CandyButtonStyle(color: availability == .adoptable ? Theme.caramel : Theme.inkSoft, compact: true))
                .accessibilityIdentifier("cats.adopt.\(kind.rawValue)")
            case .bond, .starter:
                if availability == .adoptable {
                    Button("cats.adopt") { adopt() }
                        .buttonStyle(CandyButtonStyle(compact: true))
                        .accessibilityIdentifier("cats.adopt.\(kind.rawValue)")
                } else {
                    Label("cats.locked.bond", systemImage: "lock.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func adopt() {
        do {
            try store.adoptCat(kind, now: RoomClock.now())
            onChosen()
        } catch {
            shake += 1 // 小鱼干不够：卡片抖一下
        }
    }
}
