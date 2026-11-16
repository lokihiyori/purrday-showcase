import Economy
import SwiftUI

/// 界面的统一样式：纸张背景、卡片、插画横幅、糖果色按钮、稀有度颜色（美术在 Resources/Assets.xcassets/UI，
/// 生成脚本 design/ui/tools/paint_ui.py）。
enum Theme {
    /// 文字的暖深棕（和美术的线一个颜色）
    static let ink = Color(red: 0.35, green: 0.23, blue: 0.20)
    static let inkSoft = Color(red: 0.35, green: 0.23, blue: 0.20).opacity(0.62)
    /// 卡片的奶油白
    static let card = Color(red: 0.995, green: 0.976, blue: 0.945)
    static let caramel = Color(red: 0.87, green: 0.55, blue: 0.27)
    static let caramelDeep = Color(red: 0.72, green: 0.41, blue: 0.17)
    static let sage = Color(red: 0.55, green: 0.66, blue: 0.48)
    static let line = Color(red: 0.55, green: 0.40, blue: 0.30).opacity(0.18)

    /// 手写体（Resources/Fonts/PurrdayKai-Medium.ttf：霞鹜文楷裁剪、改名而来，SIL OFL，见 design/fonts/subset_font.py）。
    /// 字体里没有的字（很生僻的、用户起的名字里的少见字）系统会自动换成默认字体。跟着系统的字体大小设置缩放。
    static let kaiName = "PurrdayKai-Medium"

    static func kai(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(kaiName, size: size, relativeTo: style)
    }

    static func rarity(_ rarity: Rarity) -> Color {
        switch rarity {
        case .common: Color(red: 0.72, green: 0.64, blue: 0.56)
        case .uncommon: Color(red: 0.49, green: 0.68, blue: 0.47)
        case .rare: Color(red: 0.42, green: 0.62, blue: 0.86)
        case .legendary: Color(red: 0.93, green: 0.70, blue: 0.24)
        }
    }

    /// 物品的图：家具用房间里的图，礼物 / 纪念品用图标，毛色用头像
    static func art(for item: CatalogItem) -> String {
        let suffix = item.id.split(separator: ".").last.map(String.init) ?? item.id
        switch item.kind {
        case .furniture: return RoomArt.furniture(item.id)
        case .gift, .souvenir: return "item-" + suffix
        case .coat: return "coat-" + suffix
        }
    }
}

/// 纸张背景：平铺的纸纹 + 上暖下浅的渐变。
struct PaperBackground: View {
    var body: some View {
        ZStack {
            Image("paper").resizable(resizingMode: .tile)
            LinearGradient(colors: [Color(red: 1, green: 0.93, blue: 0.84).opacity(0.55), .clear, Color(red: 0.93, green: 0.88, blue: 0.95).opacity(0.35)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// 卡片：奶油白底、细边、软影子。
struct GameCard: ViewModifier {
    var padding: CGFloat = 14
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.card)
                    .overlay(alignment: .top) {
                        // 上沿一道高光，像纸卡片的厚度
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.9), lineWidth: 1.5)
                            .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(tint ?? Theme.line, lineWidth: tint == nil ? 1 : 2)
                    }
                    .shadow(color: Color(red: 0.4, green: 0.25, blue: 0.2).opacity(0.12), radius: 10, y: 5)
            }
    }
}

extension View {
    func gameCard(padding: CGFloat = 14, tint: Color? = nil) -> some View {
        modifier(GameCard(padding: padding, tint: tint))
    }

    /// 标题字：手写楷体、暖深棕
    func gameTitle(_ size: CGFloat = 28) -> some View {
        font(Theme.kai(size)).foregroundStyle(Theme.ink)
    }

    /// 手写体的正文（旁白、回忆、小纸条这些"像写下来的"文字）
    func handwritten(_ size: CGFloat = 17, relativeTo style: Font.TextStyle = .body) -> some View {
        font(Theme.kai(size, relativeTo: style))
    }
}

/// 每一页顶部的插画横幅：画铺满宽度，下面一块纸片写标题。
struct BannerHeader: View {
    let image: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 0) {
            // 宽度由外面决定（Color.clear），图片铺满后裁掉多出来的部分，不会把整页撑宽
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .overlay { Image(image).resizable().scaledToFill() }
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Color(red: 0.97, green: 0.94, blue: 0.9)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 50)
                }
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(title).gameTitle(30)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .handwritten(16, relativeTo: .subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, -18)
        }
    }
}

/// 糖果色的大按钮（焦糖色，按下去会往下沉一点）。
struct CandyButtonStyle: ButtonStyle {
    var color: Color = Theme.caramel
    var prominent = true
    /// 小号（卡片里的卖出按钮）
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .system(size: 12, weight: .bold, design: .rounded) : .system(.headline, design: .rounded).weight(.bold))
            .foregroundStyle(prominent ? .white : Theme.ink)
            .padding(.horizontal, compact ? 10 : 20)
            .padding(.vertical, compact ? 5 : 12)
            .background {
                Capsule()
                    .fill(prominent ? AnyShapeStyle(LinearGradient(colors: [color.mix(with: .white, by: 0.18), color],
                                                                   startPoint: .top, endPoint: .bottom))
                                    : AnyShapeStyle(Theme.card))
                    .overlay(Capsule().strokeBorder(prominent ? color.mix(with: .black, by: 0.12) : Theme.line, lineWidth: 1))
                    .shadow(color: (prominent ? color : .black).opacity(configuration.isPressed ? 0.1 : 0.28), radius: 0,
                            y: configuration.isPressed ? 1 : (compact ? 2 : 4))
            }
            .offset(y: configuration.isPressed ? (compact ? 1.5 : 3) : 0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// 稀有度小标签。
struct RarityBadge: View {
    let rarity: Rarity

    var body: some View {
        // 不能写成 LocalizedStringKey("rarity.\(…)")：带插值的字面量会被当成格式 key "rarity.%@"
        Text(LocalizedStringKey("rarity." + rarity.rawValue))
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.rarity(rarity), in: Capsule())
    }
}

/// 物品图下面一圈柔光（稀有的东西光更亮）。
struct ItemSpotlight: View {
    var color: Color = Color(red: 1, green: 0.93, blue: 0.8)

    var body: some View {
        RadialGradient(colors: [color.opacity(0.9), color.opacity(0)], center: .center, startRadius: 4, endRadius: 70)
            .accessibilityHidden(true)
    }
}
