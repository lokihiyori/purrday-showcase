import CatEngine
import CatWorld
import SwiftUI

/// 布丁的分层动画：每个姿势由几张同样大小（400×400）的部件叠成（Resources/Assets.xcassets/CatRig，
/// 生成脚本 design/character/tools/generate.py 的 RIG 部分）。呼吸、眨眼、甩尾巴、转头、走路摆腿都在这里按时间算。
/// 以后换成画师的分层图或 Rive，只要部件名和转轴对得上就行。
enum CatRig {
    /// 部件在 400×400 画布里的转轴
    struct Pivot {
        var x: Double
        var y: Double
        var unit: UnitPoint { UnitPoint(x: x / 400, y: y / 400) }
    }

    enum Leg: String, CaseIterable {
        case backFar = "leg-back-far", frontFar = "leg-front-far", backNear = "leg-back-near", frontNear = "leg-front-near"
        var isFront: Bool { self == .frontFar || self == .frontNear }
        /// 走路时和哪一组同步：近前腿和远后腿一起，远前腿和近后腿一起
        var phase: Double { (self == .frontNear || self == .backFar) ? 0 : .pi }
    }

    enum Layer {
        case tail(Pivot)
        case body
        /// 头（连同眼睛、嘴）绕脖子转
        case head(Pivot, hasEyes: Bool, hasMouth: Bool)
        case leg(Leg, Pivot)
        /// 舔毛时抬起来的前爪
        case paw(Pivot)
    }

    struct Spec {
        /// 资源名前缀：cat-rig-<name>-<部件>
        var name: String
        var layers: [Layer]
        /// 图本来朝哪边（1 右，-1 左，0 正面）。和要朝的方向不一样就水平翻转
        var naturalFacing: Int
        var hasHappyEyes: Bool
        var sleeping: Bool
    }

    static func spec(for pose: CatPose) -> Spec {
        switch pose {
        case .sit, .stateArt:
            Spec(name: "sit", layers: [.tail(Pivot(x: 262, y: 340)), .body, .head(Pivot(x: 200, y: 230), hasEyes: true, hasMouth: true)],
                 naturalFacing: 0, hasHappyEyes: true, sleeping: false)
        case .groom:
            Spec(name: "groom", layers: [.tail(Pivot(x: 262, y: 340)), .body, .head(Pivot(x: 204, y: 232), hasEyes: false, hasMouth: false),
                                         .paw(Pivot(x: 168, y: 266))],
                 naturalFacing: 0, hasHappyEyes: false, sleeping: false)
        case .loaf, .purr:
            Spec(name: "loaf", layers: [.tail(Pivot(x: 290, y: 338)), .body, .head(Pivot(x: 200, y: 262), hasEyes: true, hasMouth: true)],
                 naturalFacing: 0, hasHappyEyes: true, sleeping: pose == .purr)
        case .sitBack:
            Spec(name: "sitback", layers: [.body, .tail(Pivot(x: 214, y: 352)), .head(Pivot(x: 200, y: 226), hasEyes: false, hasMouth: false)],
                 naturalFacing: 0, hasHappyEyes: false, sleeping: false)
        case .curl:
            Spec(name: "curl", layers: [.body, .tail(Pivot(x: 318, y: 316)), .head(Pivot(x: 150, y: 300), hasEyes: false, hasMouth: false)],
                 naturalFacing: 0, hasHappyEyes: false, sleeping: true)
        case .sprawl:
            Spec(name: "sprawl", layers: [.tail(Pivot(x: 100, y: 318)), .body, .head(Pivot(x: 290, y: 300), hasEyes: false, hasMouth: false)],
                 naturalFacing: 0, hasHappyEyes: false, sleeping: true)
        case .stretch:
            Spec(name: "stretch", layers: [.tail(Pivot(x: 334, y: 200)), .body, .head(Pivot(x: 150, y: 270), hasEyes: false, hasMouth: false)],
                 naturalFacing: -1, hasHappyEyes: false, sleeping: false)
        case .chinUp, .headTilt, .lickLips, .meow:
            spec(for: .sit)
        case .knead:
            spec(for: .loaf)
        case .bellyUp, .lieSide, .sleepBelly, .toyKick:
            spec(for: .sprawl)
        case .rub, .crouch, .leap, .bat, .annoyed, .startled, .run, .reach:
            spec(for: .stand)
        case .stand, .eat:
            Spec(name: "stand", layers: [
                .leg(.backFar, Pivot(x: 134, y: 284)), .leg(.frontFar, Pivot(x: 246, y: 284)), .tail(Pivot(x: 124, y: 256)), .body,
                .leg(.backNear, Pivot(x: 152, y: 288)), .leg(.frontNear, Pivot(x: 264, y: 288)),
                .head(Pivot(x: 262, y: 232), hasEyes: true, hasMouth: false),
            ], naturalFacing: 1, hasHappyEyes: false, sleeping: false)
        }
    }
}

/// AI 画的整张姿势图（Assets.xcassets/CatPose/cat-pose-<名字>，导入脚本 design/tools/import_ai_art.py）。
/// 有整张图的姿势就用整张图（呼吸、轻微摆动、走路时一颠一颠），没有的才用分层部件。
/// 最早的 8 个姿势是 600×600 的方图；后来的新姿势（`poses` 步骤）画布更宽（960×600），身体比例一样，脚底都在 (0.5, 0.9)。
/// 房间里按宽画布的大小摆（`wideAspect` 倍猫宽），方图摆在中间。
enum CatPoseArt {
    /// 宽画布的宽高比（和导入脚本的 POSE_WIDE 一致）
    static let wideAspect = 1.6

    /// 资源名（规则在 `CatArtNames`，小组件也用）
    static func prefix(_ kind: CatKind) -> String { CatArtNames.posePrefix(kind) }

    static func name(for pose: CatPose, kind: CatKind = .pudding) -> String? { CatArtNames.pose(pose, kind: kind) }

    static func file(_ pose: CatPose) -> String? { CatArtNames.poseFile(pose) }

    /// 方图（最早的 8 个姿势）
    static let squareNames: Set<String> = ["cat-pose-sit", "cat-pose-groom", "cat-pose-loaf", "cat-pose-curl", "cat-pose-sitback",
                                           "cat-pose-sprawl", "cat-pose-stretch", "cat-pose-stand"]

    static func aspect(of name: String) -> Double {
        squareNames.contains(name.replacingOccurrences(of: "-blink", with: "")) ? 1 : wideAspect
    }

    /// 有闭眼图（眨眼用，导入脚本的 blink / blinkframes 步骤）的姿势
    static let blinkPoses = ["sit", "loaf", "stand"]

    static func blinkName(for name: String) -> String? {
        blinkPoses.contains { name.hasSuffix("-pose-\($0)") } ? "\(name)-blink" : nil
    }

    /// 走路的四帧循环（导入脚本的 frames 步骤）
    static func walkFrames(_ kind: CatKind = .pudding) -> [String] {
        (1...4).map { "\(prefix(kind))walk-\($0)" }
    }

    static func walkFrame(_ step: Int, kind: CatKind = .pudding) -> String {
        "\(prefix(kind))walk-\(((step % 4) + 4) % 4 + 1)"
    }

    /// 坐着时小动作用的图：往左 / 右看、抖耳朵甩尾巴、打哈欠。只有正面坐着有
    static let fidgetFiles = ["sit-lookleft", "sit-lookright", "sit-twitch", "sit-yawn"]

    static func fidgetFrame(_ pose: CatPose, kind: CatKind = .pudding, look: Int = 0, twitch: Bool = false,
                            yawn: Bool = false) -> String? {
        guard pose == .sit else { return nil }
        let file = yawn ? "sit-yawn" : twitch ? "sit-twitch" : look < 0 ? "sit-lookleft" : "sit-lookright"
        return prefix(kind) + file
    }

    /// 图本来朝哪边（1 右，-1 左，0 正面）。侧面、侧躺的图可以翻过来朝另一边
    static func naturalFacing(_ pose: CatPose) -> Int {
        switch pose {
        case .stretch, .bellyUp: -1
        case .stand, .eat, .rub, .crouch, .leap, .bat, .annoyed, .startled, .run, .reach, .lieSide, .sleepBelly, .toyKick: 1
        default: 0
        }
    }

    /// 猫在宽画布里占的范围（0–1，导入后量的；碰她、冒爱心的位置都按这个）
    struct Bounds: Equatable {
        var x0, y0, x1, y1: Double
        init(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) {
            self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1
        }
        var width: Double { x1 - x0 }
        var height: Double { y1 - y0 }
    }

    static func bounds(_ pose: CatPose, kind: CatKind = .pudding) -> Bounds {
        // 其他猫的范围是导入时量好的（CatPoseBounds.swift）；没有就用布丁的
        if kind != .pudding, let file = file(pose), let b = CatPoseBounds.table[kind.rawValue]?[file], b.count == 4 {
            return Bounds(b[0], b[1], b[2], b[3])
        }
        return puddingBounds(pose)
    }

    private static func puddingBounds(_ pose: CatPose) -> Bounds {
        switch pose {
        case .sit, .stateArt: Bounds(0.321, 0.102, 0.677, 0.895)
        case .groom: Bounds(0.323, 0.102, 0.677, 0.897)
        case .loaf: Bounds(0.305, 0.402, 0.693, 0.897)
        case .sitBack: Bounds(0.343, 0.140, 0.654, 0.897)
        case .curl, .purr: Bounds(0.308, 0.442, 0.690, 0.897)
        case .sprawl: Bounds(0.204, 0.562, 0.794, 0.897)
        case .stretch: Bounds(0.228, 0.280, 0.772, 0.897)
        case .stand: Bounds(0.244, 0.280, 0.751, 0.897)
        case .bellyUp: Bounds(0.285, 0.165, 0.708, 0.887)
        case .rub: Bounds(0.177, 0.093, 0.820, 0.882)
        case .chinUp: Bounds(0.315, 0.108, 0.681, 0.885)
        case .knead: Bounds(0.291, 0.340, 0.708, 0.895)
        case .lieSide: Bounds(0.149, 0.310, 0.851, 0.895)
        case .headTilt: Bounds(0.328, 0.102, 0.671, 0.893)
        case .crouch: Bounds(0.189, 0.453, 0.793, 0.895)
        case .leap: Bounds(0.127, 0.087, 0.873, 0.893)
        case .bat: Bounds(0.268, 0.082, 0.731, 0.897)
        case .eat: Bounds(0.201, 0.305, 0.798, 0.897)
        case .lickLips: Bounds(0.303, 0.087, 0.696, 0.897)
        case .meow: Bounds(0.298, 0.103, 0.701, 0.897)
        case .annoyed: Bounds(0.232, 0.078, 0.752, 0.890)
        case .startled: Bounds(0.300, 0.030, 0.701, 0.892)
        case .sleepBelly: Bounds(0.228, 0.285, 0.774, 0.892)
        case .run: Bounds(0.199, 0.133, 0.801, 0.892)
        case .toyKick: Bounds(0.247, 0.267, 0.752, 0.893)
        case .reach: Bounds(0.302, 0.022, 0.697, 0.895)
        }
    }

    /// 翻转后的范围（朝另一边时左右对调）
    static func bounds(_ pose: CatPose, facing: Int, kind: CatKind = .pudding) -> Bounds {
        let b = bounds(pose, kind: kind)
        let natural = naturalFacing(pose)
        guard facing != 0, natural != 0, facing != natural else { return b }
        return Bounds(1 - b.x1, b.y0, 1 - b.x0, b.y1)
    }
}

/// 互动时的表情和小动作（界面按 WorldStore 的互动状态算出来）
struct CatExpression: Equatable {
    /// 闭着眼（被摸得舒服、慢眨眼回应你）
    var eyesClosed = false
    /// 扑羽毛：扑起来多久了
    var pounce: TimeInterval?
    /// 吓一跳 / 被摸到不喜欢的地方：缩了多久了
    var flinch: TimeInterval?
    /// 蹲着准备扑：屁股扭一扭
    var wiggle = false
    /// 正在演的反应（身体动作由它算）
    var performance: CatPerformance.Frame?
    /// 手指正按在她身上：在她左边还是右边（-1…1），她会往手上靠
    var touch: Double?

    static let none = CatExpression()
}

/// 画出一只会动的布丁。`time` 是连续的秒数（TimelineView 的时间），所有动作都由它算出来。
struct CatRigView: View {
    let pose: CatPose
    let facing: Int
    let motion: CatActor.Motion
    let fidget: CatFidget
    let fidgetElapsed: TimeInterval?
    let petted: Bool
    let time: TimeInterval
    var expression: CatExpression = .none
    /// 哪只猫（决定用哪一套图）
    var kind: CatKind = .pudding

    /// 上一个姿势是什么、什么时候换的（换姿势时淡入淡出 + 轻轻弹一下，不硬切）。画的时候顺手记，不触发刷新。
    private final class PoseMemory {
        var pose: CatPose?
        var name: String?
        var flip = false
        var previousName: String?
        var previousFlip = false
        var changedAt: TimeInterval = -10
    }

    @State private var memory = PoseMemory()

    @ViewBuilder
    var body: some View {
        if let name = CatPoseArt.name(for: shownPose, kind: kind) {
            wholeImage(name)
        } else {
            rig
        }
    }

    /// 实际画的姿势：跑的时候用奔跑图，跳上 / 跳下家具时用扑在半空的图
    private var shownPose: CatPose {
        switch motion {
        case .run where pose == .stand: .run
        case .jump: .leap
        default: pose
        }
    }

    /// 身体此刻的形变。单位都是"猫高"的比例（1 = 一只猫的画布高）。
    struct Deform: Equatable {
        /// 头顶往旁边弯多少（正数往图的右边）；脚不动，越往上偏得越多
        var bend = 0.0
        /// 拉长（正）/ 压扁（负），以脚底为轴；宽度反过来变一点，体积看起来不变
        var stretch = 0.0
        /// 离地多高
        var lift = 0.0
        /// 整体往旁边挪多少
        var shift = 0.0
        /// 整体转多少度（在空中的时候）
        var tilt = 0.0
        /// 呼吸（0…1），胸口那一段微微鼓起来
        var breath = 0.0
    }

    /// 整张图画成"软"的（`SoftCatImage`）：呼吸、轻轻晃、走路一步一步、演反应时按那一段的动作动；
    /// 换姿势时旧的淡出、新的淡入，并且轻轻弹一下。视图大小是宽画布（`CatPoseArt.wideAspect` 倍猫宽 × 猫宽），方图画在中间。
    private func wholeImage(_ baseName: String) -> some View {
        let pose = shownPose
        let natural = CatPoseArt.naturalFacing(pose)
        let flip = facing != 0 && natural != 0 && facing != natural
        let sleeping = [.curl, .sprawl, .purr, .sleepBelly].contains(pose)
        let perf = expression.performance
        let style = CatStyle.of(kind)
        var body = Deform()
        var name = baseName

        switch motion {
        case .walk:
            // 走路：四帧循环，身体随着步子微微起伏、前后晃
            let step = time / (0.15 / style.speed)
            name = CatPoseArt.walkFrame(Int(step), kind: kind)
            let phase = step * .pi
            body.lift = 0.008 * abs(sin(phase))
            body.stretch = 0.012 * sin(phase * 2)
            body.bend = 0.006 * sin(phase)
        case .run:
            let phase = time * 2 * .pi / 0.36
            body.lift = 0.05 * max(0, sin(phase))
            body.stretch = 0.05 * sin(phase + 0.6)
            body.tilt = 5 * sin(phase)
        case let .jump(t):
            body.tilt = -12 + 24 * t
            body.stretch = 0.05 * sin(t * .pi)
        case .rest:
            let period = (sleeping ? 4.6 : 3.2) * style.breath
            body.breath = 0.5 + 0.5 * sin(time * 2 * .pi / period)
            body.stretch = (sleeping ? 0.012 : 0.006) * style.breath * body.breath
            if perf == nil {
                if !sleeping { body.bend = 0.004 * sin(time * 2 * .pi / 5.5) }
                if let t = fidgetElapsed {
                    switch fidget {
                    case .lookAround where t < 2.4:
                        if let frame = CatPoseArt.fidgetFrame(pose, kind: kind, look: t < 1.2 ? -1 : 1), (0.15..<2.25).contains(t) { name = frame }
                        body.bend += 0.012 * sin(t / 2.4 * 2 * .pi)
                    case .earTwitch where t < 0.5:
                        if let frame = CatPoseArt.fidgetFrame(pose, kind: kind, twitch: true), (0.08..<0.4).contains(t) { name = frame }
                    case .tailFlick where t < 1.2:
                        if let frame = CatPoseArt.fidgetFrame(pose, kind: kind, twitch: true), Int(t / 0.3) % 2 == 0 { name = frame }
                    case .yawn where t < 1.6:
                        if let frame = CatPoseArt.fidgetFrame(pose, kind: kind, yawn: true), (0.25..<1.3).contains(t) { name = frame }
                        body.stretch += 0.03 * Self.bump(t / 1.6)
                        body.bend -= 0.008 * Self.bump(t / 1.6)
                    default: break
                    }
                }
                if expression.wiggle { body.bend += 0.012 * sin(time * 2 * .pi / 0.32) }
                if let touch = expression.touch {
                    // 手按在她身上：往手那边靠，被按得矮一点
                    body.bend += 0.03 * touch * (flip ? -1 : 1)
                    body.stretch -= 0.015
                }
            }
        }
        if let perf {
            let m = Self.performanceBody(perf, time: time)
            body.bend += m.bend
            body.stretch += m.stretch
            body.lift += m.lift
            body.shift += m.shift
            body.tilt += m.tilt
        }
        if let t = expression.flinch, t < 0.5, perf == nil {
            let fade = 1 - t / 0.5
            body.shift += 0.012 * sin(t * 55) * fade
            body.stretch -= 0.05 * fade
        }
        if petted, perf == nil { body.stretch -= 0.02 }

        let closedByScript = perf?.step.eyesClosed ?? false
        let eyesClosed = closedByScript || expression.eyesClosed
            || Self.blinking(time: time, fidget: fidget, fidgetElapsed: fidgetElapsed)
        if eyesClosed, let blink = CatPoseArt.blinkName(for: name) { name = blink }

        // 换姿势：记下上一张，淡入淡出 0.22 秒，新姿势从微微压扁弹回来
        let memory = memory
        if memory.pose != pose {
            if memory.pose != nil {
                memory.previousName = memory.name
                memory.previousFlip = memory.flip
                memory.changedAt = time
            }
            memory.pose = pose
        }
        memory.name = name
        memory.flip = flip
        let since = time - memory.changedAt
        let fade = since < style.fade ? Self.smooth(since / style.fade) : 1
        if since >= 0, since < 0.6 {
            body.stretch -= 0.07 * style.bounce * exp(-since * 8) * cos(since * 16) // 轻轻弹一下（布丁弹得多，长毛猫几乎不弹）
        }
        let previous = fade < 1 ? memory.previousName : nil
        let previousFlip = memory.previousFlip

        return GeometryReader { geo in
            let cat = geo.size.height // 一只猫的大小（画布高）
            ZStack {
                if let previous {
                    SoftCatImage(name: previous, body: body)
                        .scaleEffect(x: previousFlip ? -1 : 1)
                        .opacity(1 - fade)
                }
                SoftCatImage(name: name, body: body)
                    .scaleEffect(x: flip ? -1 : 1)
                    .opacity(previous == nil ? 1 : fade)
            }
            .rotationEffect(.degrees(body.tilt * (flip ? -1 : 1)), anchor: UnitPoint(x: 0.5, y: 0.75))
            .offset(x: body.shift * cat * (flip ? -1 : 1), y: -body.lift * cat)
        }
    }

    /// 0 → 1 的平滑过渡
    static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// 0 → 1 → 0 的鼓包
    static func bump(_ x: Double) -> Double { sin(min(max(x, 0), 1) * .pi) }

    /// 弹簧：从 0 冲到 1，过头一点再回来
    static func spring(_ t: Double, speed: Double = 9) -> Double {
        t <= 0 ? 0 : 1 - exp(-speed * 0.6 * t) * cos(speed * t)
    }

    /// 反应动作的身体形变。每个动作都有预备、过头、回弹，不是匀速的。
    static func performanceBody(_ perf: CatPerformance.Frame, time: TimeInterval) -> Deform {
        // 按这只猫的节奏：慢的猫同一个动作里的每一下也慢
        let t = perf.elapsed / max(perf.tempo, 0.1)
        let d = max(perf.step.duration / max(perf.tempo, 0.1), 0.01)
        let p = min(t / d, 1)
        let release = p > 0.8 ? smooth((1 - p) / 0.2) : 1 // 快结束时慢慢放松
        var b = Deform()
        switch perf.step.motion {
        case .still:
            break
        case let .lean(amount):
            // 靠过来：冲过去、过头一点、停住，然后随着呼吸轻轻晃
            b.bend = amount * 0.012 * spring(t, speed: 7) * release + 0.004 * sin(time * 2 * .pi / 1.7)
            b.stretch = -0.012 * spring(t, speed: 7) * release
        case .push:
            // 往前蹭：身子先到，头跟着顶过来，两下
            let a = 0.5 - 0.5 * cos(t * 2 * .pi / 0.75)
            let lag = 0.5 - 0.5 * cos(max(0, t - 0.09) * 2 * .pi / 0.75)
            b.shift = 0.05 * a * release
            b.bend = 0.035 * lag * release
            b.stretch = -0.015 * a
        case .purr:
            b.lift = 0.0018 * sin(time * 2 * .pi * 22) // 呼噜时身体细细地震
            b.stretch = 0.012 * sin(time * 2 * .pi / 1.5)
        case .knead:
            // 踩奶：左、右、左、右，重心跟着换
            let k = sin(t * 2 * .pi / 0.62)
            b.bend = 0.014 * k
            b.stretch = -0.018 * abs(k)
            b.lift = 0.004 * abs(cos(t * 2 * .pi / 0.62))
        case let .hop(height):
            // 蹦：先蹲（预备）→ 弹起来拉长 → 落地压扁 → 弹回
            let h = height / 400
            if p < 0.18 {
                b.stretch = -0.1 * smooth(p / 0.18)
            } else if p < 0.8 {
                let q = (p - 0.18) / 0.62
                let rise = smooth(q / 0.2)
                b.lift = h * sin(q * .pi)
                b.stretch = -0.1 * (1 - rise) + 0.07 * cos(q * .pi) * rise
                b.tilt = -7 * cos(q * .pi) * min(1, h * 8) * rise
            } else {
                let q = (p - 0.8) / 0.2
                b.stretch = -0.08 * exp(-q * 3) * cos(q * 7)
            }
        case .shake:
            b.bend = 0.018 * sin(t * 2 * .pi * 9) * exp(-t * 1.2)
            b.stretch = -0.03 * exp(-t * 2)
        case .swat:
            // 拍一爪：往后一收，快速往前，再慢慢收回来
            let q = p < 0.25 ? -0.4 * smooth(p / 0.25) : (p < 0.5 ? -0.4 + 1.4 * smooth((p - 0.25) / 0.25) : smooth((1 - p) / 0.5))
            b.bend = 0.035 * q
            b.shift = 0.02 * q
        case .wiggle:
            b.bend = 0.03 * sin(t * 2 * .pi / 0.55) * release
            b.tilt = 3 * sin(t * 2 * .pi / 0.55 + 0.5) * release
        case .nibble:
            // 一口一口吃：头往下点
            let n = pow(max(0, sin(t * 2 * .pi / 0.5)), 2)
            b.bend = 0.012 * n
            b.stretch = -0.012 * n
        case .kick:
            let k = sin(t * 2 * .pi / 0.2)
            b.bend = 0.012 * k
            b.stretch = 0.02 * k
            b.tilt = 2.5 * sin(t * 2 * .pi / 0.4)
        case let .dash(distance):
            // 冲出去再跑回来
            let out = p < 0.5 ? smooth(p / 0.5) : smooth((1 - p) / 0.5)
            let phase = time * 2 * .pi / 0.3
            b.shift = distance * out
            b.lift = 0.045 * max(0, sin(phase))
            b.stretch = 0.05 * sin(phase + 0.6)
            b.tilt = 5 * sin(phase)
        case .recoil:
            // 往后一缩再慢慢回来
            b.shift = -0.06 * exp(-t * 4) * (1 - exp(-t * 30))
            b.stretch = -0.09 * exp(-t * 5) * (1 - exp(-t * 30))
        case .settle:
            // 躺下 / 倒下去：落下来压一下再弹回
            b.lift = 0.03 * max(0, 1 - t / 0.18)
            b.stretch = -0.06 * exp(-t * 6) * cos(t * 13) * (t > 0.12 ? 1 : t / 0.12)
        }
        // 幅度：暹罗演得大，长毛猫收着
        b.bend *= perf.amplitude
        b.stretch *= perf.amplitude
        b.lift *= perf.amplitude
        b.tilt *= perf.amplitude
        return b
    }

    /// 平时的眨眼：每 4.3 秒眨一下，偶尔连眨两下；自己慢眨眼时闭眼久一点
    static func blinking(time: TimeInterval, fidget: CatFidget, fidgetElapsed: TimeInterval?) -> Bool {
        if fidget == .slowBlink, let t = fidgetElapsed, (0.2..<1.1).contains(t) { return true }
        let phase = time.truncatingRemainder(dividingBy: 4.3)
        let double = Int(time / 4.3) % 3 == 0
        return phase < 0.13 || (double && (0.32..<0.45).contains(phase))
    }

    /// 分层部件（没有整张图的姿势）
    private var rig: some View {
        let spec = CatRig.spec(for: pose)
        let flip = facing != 0 && spec.naturalFacing != 0 && facing != spec.naturalFacing
        return GeometryReader { geo in
            let size = geo.size.width
            ZStack {
                ForEach(Array(spec.layers.enumerated()), id: \.offset) { _, layer in
                    part(layer, spec: spec, size: size)
                }
            }
            .frame(width: size, height: size)
            .offset(y: bodyBob * size / 400)
        }
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(x: flip ? -1 : 1)
    }

    @ViewBuilder
    private func part(_ layer: CatRig.Layer, spec: CatRig.Spec, size: Double) -> some View {
        switch layer {
        case .body:
            image(spec, "body")
                .scaleEffect(x: 1, y: 1 + breath(spec), anchor: UnitPoint(x: 0.5, y: 0.9))
        case let .tail(pivot):
            image(spec, "tail")
                .rotationEffect(.degrees(tailAngle(spec)), anchor: pivot.unit)
        case let .head(pivot, hasEyes, hasMouth):
            ZStack {
                image(spec, "head")
                if hasEyes { image(spec, eyes(spec)) }
                if hasMouth { image(spec, mouth) }
            }
            .rotationEffect(.degrees(headAngle), anchor: pivot.unit)
            .offset(y: -breath(spec) * size * 0.32)
        case let .leg(leg, pivot):
            image(spec, leg.rawValue)
                .rotationEffect(.degrees(legAngle(leg)), anchor: pivot.unit)
        case let .paw(pivot):
            image(spec, "paw")
                .rotationEffect(.degrees(4 * sin(time * 2 * .pi / 0.8)), anchor: pivot.unit)
                .offset(y: -breath(spec) * size * 0.32)
        }
    }

    private func image(_ spec: CatRig.Spec, _ part: String) -> some View {
        Image("cat-rig-\(spec.name)-\(part)").resizable()
    }

    // MARK: 动作

    /// 呼吸：身体上下起伏的比例。睡着时慢而深
    private func breath(_ spec: CatRig.Spec) -> Double {
        if case .rest = motion {
            return spec.sleeping || pose == .curl || pose == .sprawl
                ? 0.028 * (0.5 + 0.5 * sin(time * 2 * .pi / 4.6))
                : 0.012 * (0.5 + 0.5 * sin(time * 2 * .pi / 3.4))
        }
        return 0
    }

    /// 走路时身体一颠一颠（画布像素）
    private var bodyBob: Double {
        switch motion {
        case .walk: -3 * abs(sin(time * 2 * .pi / 0.6))
        case .run: -6 * abs(sin(time * 2 * .pi / 0.34))
        default: 0
        }
    }

    private func tailAngle(_ spec: CatRig.Spec) -> Double {
        switch motion {
        case .walk: return 9 * sin(time * 2 * .pi / 0.9)
        case .run: return 14 * sin(time * 2 * .pi / 0.5)
        case .jump: return -10
        case .rest: break
        }
        if fidget == .tailFlick, let t = fidgetElapsed, t < 1.8 {
            return 14 * sin(t * 2 * .pi / 0.6)
        }
        let amplitude: Double = switch pose {
        case .curl: 2
        case .sprawl, .purr: 3
        case .sitBack, .stand: 7
        default: 5
        }
        return amplitude * sin(time * 2 * .pi / 2.8)
    }

    private var headAngle: Double {
        if case .run = motion { return 3 * sin(time * 2 * .pi / 0.34) }
        if case .walk = motion { return 2 * sin(time * 2 * .pi / 0.6) }
        if case .jump = motion { return -6 }
        if petted { return 7 }
        var angle = 1.5 * sin(time * 2 * .pi / 6.5)
        if pose == .eat { angle = 26 + 4 * sin(time * 2 * .pi / 0.7) }
        if pose == .groom { angle += 2 * sin(time * 2 * .pi / 0.8) }
        if let t = fidgetElapsed {
            switch fidget {
            case .lookAround where t < 2.4: angle += 9 * sin(t / 2.4 * 2 * .pi)
            case .earTwitch where t < 0.35: angle += 2.5 * sin(t * 60)
            case .yawn where t < 1.4: angle -= 5 * envelope(t, 1.4)
            case .sniff where t < 2: angle += 14 * envelope(t, 2) + 3 * sin(t * 18)
            default: break
            }
        }
        return angle
    }

    private func legAngle(_ leg: CatRig.Leg) -> Double {
        switch motion {
        case .walk: return 20 * sin(time * 2 * .pi / 0.6 + leg.phase)
        case .run: return 30 * sin(time * 2 * .pi / 0.34 + leg.phase)
        case .jump: return leg.isFront ? -28 : 24
        case .rest: return 0
        }
    }

    private func eyes(_ spec: CatRig.Spec) -> String {
        if petted { return spec.hasHappyEyes ? "eyes-happy" : "eyes-closed" }
        if spec.sleeping { return "eyes-closed" }
        if let t = fidgetElapsed {
            if fidget == .yawn, t < 1.4 { return "eyes-closed" }
            if fidget == .slowBlink, (0.2..<0.9).contains(t) { return "eyes-closed" }
        }
        return expression.eyesClosed || Self.blinking(time: time, fidget: .none, fidgetElapsed: nil) ? "eyes-closed" : "eyes-open"
    }

    private var mouth: String {
        if fidget == .yawn, let t = fidgetElapsed, (0.15..<1.25).contains(t) { return "mouth-open" }
        return "mouth-w"
    }

    /// 0 → 1 → 0 的包络（小动作的开始和结束都是平滑的）
    private func envelope(_ t: Double, _ duration: Double) -> Double {
        sin(min(max(t / duration, 0), 1) * .pi)
    }
}

/// 把一张姿势图画成"软"的：从脚底往上切成很多横条，越往上偏得越多——身体是弯过去的，不是整张图硬转；
/// 胸口那一段随呼吸微微鼓起来；拉长 / 压扁以脚底为轴。离地、横移、在空中的旋转由外面整体做。
struct SoftCatImage: View {
    let name: String
    let body_: CatRigView.Deform

    init(name: String, body: CatRigView.Deform) {
        self.name = name
        body_ = body
    }

    /// 画布上面多留一截（拉长、抬头时不被裁掉）
    private static let headroom = 0.25
    private static let bands = 40

    var body: some View {
        let b = body_
        let aspect = CatPoseArt.aspect(of: name)
        GeometryReader { geo in
            let cat = geo.size.height
            Canvas(rendersAsynchronously: false) { context, size in
                let image = context.resolve(Image(name))
                let top = Self.headroom * cat
                let ground = top + 0.9 * cat
                let width = cat * aspect
                let sy = 1 + b.stretch
                let widen = 1 - b.stretch * 0.45
                let bandHeight = cat / Double(Self.bands)
                for i in 0..<Self.bands {
                    let y0 = Double(i) * bandHeight      // 这一条在原图里的位置（0 在图的最上面）
                    let mid = y0 + bandHeight / 2
                    let v = max(0, (0.9 * cat - mid) / (0.8 * cat)) // 离地多高（0 脚底，1 头顶）
                    let dx = b.bend * cat * pow(v, 1.6)
                    let chest = exp(-pow((v - 0.36) / 0.22, 2))
                    let sx = widen * (1 + 0.022 * b.breath * chest)
                    // 这一条画到哪：以脚底为轴拉长
                    let destTop = ground - (0.9 * cat - y0) * sy
                    let destHeight = bandHeight * sy
                    var band = context
                    band.clip(to: Path(CGRect(x: 0, y: destTop - 0.3, width: size.width, height: destHeight + 0.8)))
                    let imageTop = ground - 0.9 * cat * sy
                    band.draw(image, in: CGRect(x: (size.width - width * sx) / 2 + dx, y: imageTop,
                                                width: width * sx, height: cat * sy))
                }
            }
            .frame(width: geo.size.width, height: cat * (1 + Self.headroom))
            .offset(y: -Self.headroom * cat / 2)
            .frame(width: geo.size.width, height: cat)
        }
    }
}
