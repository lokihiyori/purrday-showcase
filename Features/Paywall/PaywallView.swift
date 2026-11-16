import SwiftUI

/// Purrday Plus 付费墙。
///
/// TODO(Mac)：接入 RevenueCat：从 Offerings 读取价格（年费含 7 天试用、月费、终身），购买和恢复购买后更新 PlusStatus。
struct PaywallView: View {
    @Environment(WorldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let features: [(String, String)] = [
        ("paywall.feature.alarms", "alarm.fill"),
        ("paywall.feature.sounds", "waveform"),
        ("paywall.feature.coats", "paintpalette.fill"),
        ("paywall.feature.fish", "fish.fill"),
        ("paywall.feature.seasonal", "leaf.fill"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                CatStillImage(still: "cat-petted", kind: store.activeCat).frame(maxWidth: 220, maxHeight: 220)
                    .background(ItemSpotlight(color: Color(red: 1, green: 0.85, blue: 0.7)).scaleEffect(2.4))
                    .accessibilityHidden(true)
                Text("paywall.title").gameTitle(32)
                Text("paywall.headline").font(.system(.title3, design: .rounded)).foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(features, id: \.0) { key, symbol in
                        HStack(spacing: 12) {
                            Image(systemName: symbol)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Theme.caramel, in: Circle())
                            Text(LocalizedStringKey(key))
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .gameCard(padding: 18)
                Button("paywall.trial") {}
                    .buttonStyle(CandyButtonStyle())
                    .disabled(true) // TODO(Mac)：RevenueCat 购买
                Button("paywall.restore") {}
                    .font(.system(.subheadline, design: .rounded))
                    .disabled(true) // TODO(Mac)：RevenueCat 恢复购买
                Button("paywall.later") { dismiss() }
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .accessibilityIdentifier("paywall.later")
            }
            .padding(28)
        }
        .background(PaperBackground())
    }
}
