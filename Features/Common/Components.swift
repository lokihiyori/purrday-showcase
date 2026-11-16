import SwiftUI

/// 读取带格式的本地化字符串（xcstrings 里用的是语义 key，例如 "wake.gift.fish" = "+%lld fish"）。
func localized(_ key: String, _ arguments: any CVarArg...) -> String {
    String(format: String(localized: String.LocalizationValue(key)), arguments: arguments)
}

/// 旁白：发生了一件事时的一句话（"她把礼物推到你面前"）。她不说话，所以这不是对话气泡，
/// 而是一张手写的小纸条：没有尖角，字是手写体。
struct SpeechBubble: View {
    let key: String

    var body: some View {
        Text(LocalizedStringKey(key))
            .handwritten(18)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Theme.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.caramel.opacity(0.3), lineWidth: 1))
            .shadow(color: Theme.caramelDeep.opacity(0.15), radius: 6, y: 2)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .id(key)
            .accessibilityIdentifier("narration")
    }
}

/// 小鱼干余额。
struct FishBadge: View {
    let fish: Int

    var body: some View {
        Label {
            Text(verbatim: "\(fish)").monospacedDigit()
        } icon: {
            Image(systemName: "fish.fill")
        }
        .labelStyle(.titleAndIcon) // 放在工具栏里时系统默认只显示图标，余额就看不到了
        .accessibilityLabel(localized("room.fish", fish))
    }
}
