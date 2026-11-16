import CatWorld
import Economy
import SwiftUI

// 房间里陪布丁玩的小部件：下面的三个按钮、逗猫时的提示、新回忆卡片、她的小请求、羽毛、爱心、生气符号、你的慢眨眼。

/// 房间下面的三个按钮：逗猫、零食（3 条小鱼干）、慢眨眼。
struct ActionDock: View {
    @Environment(WorldStore.self) private var store

    var body: some View {
        let asleep = isAsleep
        VStack(spacing: 12) {
            DockButton(title: "room.action.play", identifier: "room.action.play") {
                Image("item-feather").resizable().scaledToFit().rotationEffect(.degrees(-20))
            } action: {
                store.startPlay(now: RoomClock.now())
            }
            DockButton(title: "room.action.treat", identifier: "room.action.treat", price: EconomyEngine.treatPrice) {
                Image("item-fish_cracker").resizable().scaledToFit()
            } action: {
                withAnimation(.spring) { _ = store.giveTreat(now: RoomClock.now()) }
            }
            // 小鱼干不够：按钮左右抖一下
            .phaseAnimator([0.0, -7.0, 7.0, -4.0, 0.0], trigger: store.treatDenied) { view, x in
                view.offset(x: x)
            } animation: { _ in .linear(duration: 0.07) }
            .sensoryFeedback(.error, trigger: store.treatDenied)
            DockButton(title: "room.action.blink", identifier: "room.action.blink") {
                ClosedEyes()
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .padding(.horizontal, 2)
                    .padding(.vertical, 8)
            } action: {
                store.slowBlink(now: RoomClock.now())
            }
            .opacity(asleep ? 0.45 : 1)
            .disabled(asleep)
        }
    }

    /// 她在睡觉时不能对她眨眼（眼睛本来就闭着）
    private var isAsleep: Bool {
        let presence = store.presence(at: RoomClock.now())
        return [.nap, .sunbathe].contains(presence.activity ?? .sit) || [.curl, .sprawl, .purr].contains(presence.pose)
    }
}

/// 一个圆形的玻璃按钮，图在里面，名字在下面。
private struct DockButton<Icon: View>: View {
    let title: LocalizedStringKey
    let identifier: String
    var price: Int?
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                icon()
                    .frame(width: 30, height: 30)
                    .frame(width: 54, height: 54)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if let price {
                            HStack(spacing: 2) {
                                Image(systemName: "fish.fill").font(.system(size: 8, weight: .bold))
                                Text(verbatim: "\(price)").font(.system(size: 11, weight: .heavy, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Theme.caramelDeep, in: Capsule())
                            .offset(x: 6, y: -2)
                        }
                    }
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.card.opacity(0.85), in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// 逗猫时房间下面：提示 + 完成
struct PlayBar: View {
    @Environment(WorldStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            Image("item-feather").resizable().scaledToFit().frame(width: 26, height: 26).accessibilityHidden(true)
            Text("room.play.hint")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 4)
            Button("common.done") { store.endPlay(now: RoomClock.now()) }
                .buttonStyle(CandyButtonStyle(compact: true))
                .accessibilityIdentifier("room.play.done")
        }
        .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
    }
}

/// 记下新回忆时，房间顶上弹出的小卡片（像贴在相册里的拍立得）。
struct MemoryToast: View {
    let memory: CatMemory
    var kind: CatKind = .pudding

    var body: some View {
        HStack(spacing: 10) {
            CatStillImage(still: MemoryArt.still(for: memory), kind: kind)
                .frame(width: 40, height: 40)
                .padding(3)
                .background(.white, in: RoundedRectangle(cornerRadius: 6))
                .rotationEffect(.degrees(-4))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .accessibilityHidden(true)
            Text(localized("room.memory.new", String(localized: String.LocalizationValue(MemoryArt.titleKey(memory)))))
                .handwritten(17, relativeTo: .subheadline)
                .foregroundStyle(Theme.ink)
        }
        .padding(.leading, 10).padding(.trailing, 16).padding(.vertical, 8)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.caramel.opacity(0.5), lineWidth: 1.5))
        .shadow(color: Theme.caramelDeep.opacity(0.2), radius: 8, y: 3)
        .accessibilityIdentifier("room.memoryToast")
    }
}

/// 回忆用的画和文字
enum MemoryArt {
    static func still(for memory: CatMemory) -> String {
        switch memory {
        case .cameOut: "cat-walk"
        case .firstPet: "cat-petted"
        case .firstPurr: "cat-purr"
        case .firstPlay: "cat-stretch"
        case .firstTreat: "cat-meow"
        case .firstBlinkBack: "cat-idle"
        case .firstRequest: "cat-knead"
        case .firstGift: "cat-gift"
        case .familiar: "cat-read"
        case .close: "cat-phone"
        case .devoted: "cat-sleep"
        }
    }

    static func titleKey(_ memory: CatMemory) -> String { "memory.\(memory.rawValue).title" }
    static func detailKey(_ memory: CatMemory) -> String { "memory.\(memory.rawValue).detail" }
}

/// 她的小请求：头旁边一个想法气泡，里面画着她想要的东西。点一下就去满足她。
struct RequestBubble: View {
    let request: CatRequest
    let time: TimeInterval
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                Circle().fill(Theme.card).frame(width: 9, height: 9).offset(x: -10, y: 12)
                Circle().fill(Theme.card).frame(width: 14, height: 14).offset(x: -2, y: 4)
                icon
                    .frame(width: 30, height: 30)
                    .padding(10)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.caramel.opacity(0.35), lineWidth: 1.5))
                    .offset(x: 6, y: -6)
            }
            .shadow(color: Theme.caramelDeep.opacity(0.2), radius: 5, y: 2)
            .offset(y: 3 * sin(time * 2 * .pi / 2.2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(Self.labelKey(request))))
        .accessibilityIdentifier("room.request")
    }

    /// 拼好的 key 要先变成 String 再交给 LocalizedStringKey（直接写插值会被当成格式 "room.request.%@"）
    static func labelKey(_ request: CatRequest) -> String { "room.request.\(request.rawValue)" }

    @ViewBuilder
    private var icon: some View {
        switch request {
        case .play: Image("item-feather").resizable().scaledToFit().rotationEffect(.degrees(-20 + 10 * sin(time * 3)))
        case .treat: Image("item-fish_cracker").resizable().scaledToFit()
        case .earlySleep:
            Image(systemName: "moon.zzz.fill")
                .resizable().scaledToFit()
                .foregroundStyle(Color(red: 0.55, green: 0.5, blue: 0.78))
                .padding(3)
        }
    }
}

/// 逗猫棒的羽毛：从画面上面垂下来一根线，羽毛跟着手指，自己也轻轻晃。
struct Feather: View {
    /// 羽毛在画布上的位置（0–1）
    let at: RoomPoint
    let stage: CGSize
    let time: TimeInterval
    /// 还没碰屏幕：晃得大一点，招呼你来拖
    let waiting: Bool

    var body: some View {
        let sway = sin(time * 2 * .pi / (waiting ? 1.6 : 0.9)) * (waiting ? 18 : 6)
        let tip = CGPoint(x: at.x * stage.width + sway, y: at.y * stage.height + (waiting ? 4 * sin(time * 2.4) : 0))
        let anchor = CGPoint(x: at.x * stage.width + sway * 0.2, y: -20)
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: anchor)
                path.addQuadCurve(to: tip, control: CGPoint(x: (anchor.x + tip.x) / 2 - sway * 0.8, y: (anchor.y + tip.y) / 2))
            }
            .stroke(Theme.ink.opacity(0.55), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            Image("item-feather")
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)
                .rotationEffect(.degrees(150 + sway * 1.4), anchor: .top)
                .position(x: tip.x, y: tip.y + 26)
                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
        }
        .frame(width: stage.width, height: stage.height, alignment: .topLeading)
    }
}

/// 一颗软软的小爱心（带一点高光）
struct Heart: View {
    var body: some View {
        Image(systemName: "heart.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.66, blue: 0.7), Color(red: 0.93, green: 0.45, blue: 0.52)],
                                            startPoint: .top, endPoint: .bottom))
            .shadow(color: .white.opacity(0.9), radius: 0, x: 0, y: 0)
            .shadow(color: Color(red: 0.9, green: 0.4, blue: 0.45).opacity(0.3), radius: 3, y: 1)
    }
}

/// 生气符号：四道向里弯的短弧，像漫画里的青筋
struct AngerMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for k in 0..<4 {
            let angle = Double(k) * .pi / 2 + .pi / 4
            let corner = CGPoint(x: center.x + cos(angle) * r * 1.05, y: center.y + sin(angle) * r * 1.05)
            let toward = angle + .pi
            path.addArc(center: corner, radius: r * 0.62, startAngle: .radians(toward - 0.62), endAngle: .radians(toward + 0.62),
                        clockwise: false)
        }
        return path
    }
}

/// "眨眼"按钮上的图：两道弯弯的闭眼
struct ClosedEyes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width / 2
        for i in 0..<2 {
            let x0 = rect.minX + Double(i) * w + w * 0.12
            let x1 = rect.minX + Double(i + 1) * w - w * 0.12
            path.move(to: CGPoint(x: x0, y: rect.midY - rect.height * 0.15))
            path.addQuadCurve(to: CGPoint(x: x1, y: rect.midY - rect.height * 0.15),
                              control: CGPoint(x: (x0 + x1) / 2, y: rect.midY + rect.height * 0.45))
        }
        return path
    }
}

/// 你的慢眨眼：屏幕上下像眼皮一样慢慢合上，停一下，再张开。
struct BlinkLids: View {
    let elapsed: TimeInterval

    var body: some View {
        let d = BlinkMoment.playerDuration
        let t = elapsed / d
        let closed: Double = switch t {
        case ..<0: 0
        case ..<0.42: sin(t / 0.42 * .pi / 2)
        case ..<0.6: 1
        case ..<1: cos((t - 0.6) / 0.4 * .pi / 2)
        default: 0
        }
        GeometryReader { geo in
            let h = geo.size.height / 2 * 0.86 * closed
            let curve = 46 * closed
            let lid = Color(red: 0.22, green: 0.15, blue: 0.13).opacity(0.82)
            ZStack {
                Path { p in
                    p.move(to: .zero)
                    p.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    p.addLine(to: CGPoint(x: geo.size.width, y: h))
                    p.addQuadCurve(to: CGPoint(x: 0, y: h), control: CGPoint(x: geo.size.width / 2, y: h + curve))
                    p.closeSubpath()
                }
                .fill(lid)
                Path { p in
                    let bottom = geo.size.height
                    p.move(to: CGPoint(x: 0, y: bottom))
                    p.addLine(to: CGPoint(x: geo.size.width, y: bottom))
                    p.addLine(to: CGPoint(x: geo.size.width, y: bottom - h))
                    p.addQuadCurve(to: CGPoint(x: 0, y: bottom - h), control: CGPoint(x: geo.size.width / 2, y: bottom - h - curve))
                    p.closeSubpath()
                }
                .fill(lid)
            }
            .blur(radius: 6)
        }
        .opacity(closed > 0 ? 1 : 0)
    }
}

/// 反应动作冒的效果，画在她头顶（坐标原点是头顶中间）
struct PerformanceEffect: View {
    let effect: CatPerformance.Effect
    let elapsed: TimeInterval
    let duration: TimeInterval

    var body: some View {
        let t = elapsed
        let fadeOut = t > duration - 0.3 ? max(0, (duration - t) / 0.3) : 1
        ZStack {
            switch effect {
            case let .hearts(count):
                ForEach(0..<count, id: \.self) { i in
                    let delay = Double(i) * 0.22
                    let p = max(0, min(1, (t - delay) / 1.3))
                    let spread = Double(i) - Double(count - 1) / 2
                    Heart()
                        .frame(width: 12 + Double(i % 3) * 4, height: 12 + Double(i % 3) * 4)
                        .scaleEffect(p < 0.15 ? p / 0.15 : 1)
                        .opacity(p > 0 ? 1 - p * p : 0)
                        .offset(x: spread * 18 + sin(p * 6 + Double(i)) * 7, y: 20 - p * 62)
                }
            case .notes:
                ForEach(0..<3, id: \.self) { i in
                    let p = max(0, min(1, (t - Double(i) * 0.35) / 1.2))
                    Text(verbatim: i == 1 ? "♫" : "♪")
                        .font(.system(size: 17 + Double(i) * 2, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.caramelDeep.opacity(0.85))
                        .opacity(p > 0 ? 1 - p : 0)
                        .offset(x: 26 + Double(i) * 10 + sin(p * 5) * 6, y: 4 - p * 46)
                }
            case .anger:
                AngerMark()
                    .stroke(Color(red: 0.9, green: 0.33, blue: 0.36), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                    .frame(width: 26, height: 26)
                    .scaleEffect(t < 0.15 ? 0.4 + t / 0.15 * 0.8 : 1.15 + 0.08 * sin(t * 12))
                    .offset(x: 30, y: 8)
            case .dots:
                Text(verbatim: "…")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .padding(.horizontal, 10).padding(.bottom, 8).padding(.top, 2)
                    .background(Theme.card.opacity(0.92), in: Capsule())
                    .offset(x: 34, y: 4 - min(t, 0.4) * 18)
            case .question, .exclaim:
                Text(verbatim: effect == .question ? "?" : "!")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(effect == .question ? Theme.caramelDeep : Color(red: 0.9, green: 0.4, blue: 0.3))
                    .frame(width: 32, height: 32)
                    .background(Theme.card.opacity(0.95), in: Circle())
                    .scaleEffect(t < 0.18 ? t / 0.18 * 1.2 : 1 + 0.05 * sin(t * 9))
                    .offset(x: 30, y: -2)
            case .sparkles:
                ForEach(0..<5, id: \.self) { i in
                    let angle = Double(i) / 5 * 2 * .pi - .pi / 2
                    let p = min(1, t / 0.6)
                    Image(systemName: "sparkle")
                        .font(.system(size: 12 + Double(i % 2) * 5, weight: .bold))
                        .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.35))
                        .opacity(1 - p * 0.8)
                        .scaleEffect(0.6 + p * 0.6)
                        .offset(x: cos(angle) * (14 + p * 30), y: 30 + sin(angle) * (14 + p * 30))
                }
            case .crumbs:
                EmptyView()
            }
        }
        .opacity(fadeOut)
    }
}

/// 碰她的范围：按姿势图量出来的身体范围（`CatPoseArt.Bounds`），四周放宽一点
struct BoundsShape: Shape {
    let bounds: CatPoseArt.Bounds
    var padding = 0.0

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX + bounds.x0 * rect.width - padding, y: rect.minY + bounds.y0 * rect.height - padding,
                    width: bounds.width * rect.width + padding * 2, height: bounds.height * rect.height + padding * 2))
    }
}

/// 你不在的时候她做了什么：回来时房间顶上的一张小纸条（像她留的日记），点一下或过几秒收起来。
struct AwayCard: View {
    let report: AwayReport
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "pawprint.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.caramel)
                    Text("away.title")
                        .handwritten(17, relativeTo: .subheadline)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                    Text(Self.duration(report.minutes))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                ForEach(report.highlights, id: \.self) { highlight in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: Self.symbol(highlight.kind))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.caramelDeep)
                            .frame(width: 16)
                        Text(Self.sentence(highlight))
                            .handwritten(16, relativeTo: .subheadline)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.caramel.opacity(0.45), lineWidth: 1.5))
            .shadow(color: Theme.caramelDeep.opacity(0.2), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("room.away")
    }

    /// "2 小时" / "40 分钟"
    static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? localized("away.hours", (minutes + 30) / 60) : localized("away.minutes", max(minutes, 1))
    }

    static func sentenceKey(_ kind: AwayHighlight.Kind) -> String {
        switch kind {
        case .night: "away.night"
        case let .activity(activity): "away.\(activity.rawValue)"
        }
    }

    static func sentence(_ highlight: AwayHighlight) -> String {
        localized(sentenceKey(highlight.kind), duration(highlight.minutes))
    }

    static func symbol(_ kind: AwayHighlight.Kind) -> String {
        switch kind {
        case .night: "moon.zzz.fill"
        case let .activity(activity):
            switch activity {
            case .nap: "zzz"
            case .sunbathe: "sun.max.fill"
            case .watch: "bird.fill"
            case .eat: "fork.knife"
            case .drink: "drop.fill"
            case .toy, .play: "tennisball.fill"
            case .hide: "shippingbox.fill"
            case .perch: "arrow.up.to.line"
            case .scratch: "scribble"
            case .groom: "sparkles"
            case .explore: "pawprint.fill"
            case .bellyUp, .knead: "heart.fill"
            case .sit, .loaf: "cloud.fill"
            }
        }
    }
}
