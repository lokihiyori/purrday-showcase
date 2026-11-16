import CatWorld
import Foundation

/// 她发出的声音（`App/Services/CatVoice.swift` 按名字放 Resources/Sounds 里的录音，每种猫的音调不一样）。
enum CatSound: String, CaseIterable {
    /// 叫一声
    case meow
    /// 短促上扬的"咕？"/ 蹭你时的颤音
    case trill
    /// 讨东西吃的叫声
    case ask
    /// 不高兴的嘟囔
    case grumble
    /// 吓一跳的短促尖叫
    case squeak
    /// 吃东西咔嚓咔嚓
    case crunch
}

/// 她的一段反应动作：几个姿势按顺序播，每一段可以带动作（蹭、抖、跳、踩奶……）和效果（爱心、音符、生气……）。
/// Core 决定她做哪种反应（`CatReaction`），这里决定这种反应怎么演。纯计算（时间作为参数），方便测试。
struct CatPerformance: Equatable {
    /// 一段里的身体动作，都由时间算出来（`CatRigView` 里画）
    enum Motion: Equatable {
        case still
        /// 往一边靠过去（角度，正数往她面朝的方向）
        case lean(Double)
        /// 往前蹭两下
        case push
        /// 打呼噜：身体轻轻震
        case purr
        /// 踩奶：一左一右地压
        case knead
        /// 蹦起来（高度，画布像素，400 为一只猫的高度）
        case hop(Double)
        /// 抖一抖（生气、吓一跳）
        case shake
        /// 拍一爪
        case swat
        /// 躺着扭来扭去
        case wiggle
        /// 低头一口一口吃
        case nibble
        /// 抱着蹬
        case kick
        /// 满屋子跑：先冲出去再跑回来（距离，猫宽的倍数）
        case dash(Double)
        /// 往后缩一下
        case recoil
        /// 侧躺下去时往下一沉
        case settle
    }

    /// 冒在她头上的效果
    enum Effect: Equatable {
        case hearts(Int)
        /// 呼噜呼噜的小音符
        case notes
        case anger
        /// "……"
        case dots
        case question
        case exclaim
        /// 闪闪的小星星（扑中了）
        case sparkles
        /// 吃东西掉的碎屑
        case crumbs
    }

    struct Step: Equatable {
        var pose: CatPose?
        var duration: TimeInterval
        var motion: Motion = .still
        var eyesClosed = false
        var effect: Effect?
        /// 这一段开始时发出的声音
        var sound: CatSound?

        /// pose 为 nil：保持她原来的姿势
        init(_ pose: CatPose?, _ duration: TimeInterval, _ motion: Motion = .still, eyesClosed: Bool = false,
             effect: Effect? = nil) {
            self.pose = pose
            self.duration = duration
            self.motion = motion
            self.eyesClosed = eyesClosed
            self.effect = effect
        }
    }

    /// 此刻在演哪一段
    struct Frame: Equatable {
        var step: Step
        var index: Int
        /// 这一段开始了多久
        var elapsed: TimeInterval
        /// 侧面姿势朝哪边（演的时候固定）
        var facing: Int
        /// 这只猫演得多快、幅度多大（`CatStyle`）
        var tempo = 1.0
        var amplitude = 1.0
    }

    var reaction: CatReaction
    var start: Date
    var steps: [Step]
    var facing: Int
    var tempo = 1.0
    var amplitude = 1.0

    var duration: TimeInterval { steps.reduce(0) { $0 + $1.duration } }
    var end: Date { start.addingTimeInterval(duration) }

    func frame(at date: Date) -> Frame? {
        var t = date.timeIntervalSince(start)
        guard t >= 0, date < end else { return nil }
        for (index, step) in steps.enumerated() {
            if t < step.duration || index == steps.count - 1 {
                return Frame(step: step, index: index, elapsed: min(t, step.duration), facing: facing,
                             tempo: tempo, amplitude: amplitude)
            }
            t -= step.duration
        }
        return nil
    }

    /// `style`：这只猫怎么演。时长按她的节奏拉长 / 缩短；慢半拍的猫先愣一下再动。
    init(_ reaction: CatReaction, start: Date, facing: Int, base: CatPose, style: CatStyle = CatStyle()) {
        self.reaction = reaction
        self.start = start
        self.facing = facing == 0 ? 1 : facing
        tempo = style.tempo
        amplitude = style.amplitude
        var script = Self.script(for: reaction, base: base)
        Self.addSounds(to: &script, reaction: reaction)
        for index in script.indices { script[index].duration *= style.tempo }
        if style.delay > 0 { script.insert(Step(nil, style.delay), at: 0) }
        steps = script
    }

    /// 每种反应怎么演。`base` 是她原来的姿势（有些反应在原姿势上演，比如闭眼往你手上靠）。
    static func script(for reaction: CatReaction, base: CatPose) -> [Step] {
        let upright: CatPose = [.sit, .loaf, .chinUp, .headTilt].contains(base) ? base : .sit
        let lying = [.curl, .sprawl, .purr, .sleepBelly, .bellyUp, .lieSide].contains(base)
        switch reaction {
        // 摸到喜欢的地方
        case .leanIn:
            return [Step(lying ? base : upright, 1.8, .lean(7), eyesClosed: true, effect: .hearts(3))]
        case .headbutt:
            return [Step(.rub, 1.4, .push, effect: .hearts(3)), Step(upright, 0.6, eyesClosed: true)]
        case .chinUp:
            return [Step(.chinUp, 2.0, .lean(-3), effect: .hearts(4))]
        case .purrLoaf:
            return [Step(.loaf, 2.4, .purr, eyesClosed: true, effect: .notes)]
        case .knead:
            return [Step(.knead, 2.6, .knead, effect: .hearts(3))]
        case .rollOver:
            return [Step(.lieSide, 0.45, .settle), Step(.bellyUp, 2.2, .wiggle, effect: .hearts(4))]
        case .flop:
            return [Step(.lieSide, 2.4, .settle, effect: .hearts(2))]
        // 还不熟
        case .freeze:
            return [Step(nil, 1.2, .recoil, effect: .dots)]
        case .sniffHand:
            return [Step(.headTilt, 0.9, .lean(4), effect: .question), Step(.crouch, 0.9, .nibble)]
        case .scoot:
            return [Step(.startled, 0.55, .recoil, effect: .exclaim), Step(.loaf, 0.9, .still)]
        // 不喜欢
        case .grumble:
            return [Step(.annoyed, 1.5, .shake, effect: .anger)]
        case .swat:
            return [Step(.bat, 0.55, .swat, effect: .anger), Step(.annoyed, 0.9, .still)]
        case .loveBite:
            return [Step(.bellyUp, 0.4, .wiggle), Step(.toyKick, 1.4, .kick, effect: .anger), Step(.lieSide, 0.6)]
        // 零食（吃的过程由 TreatMoment 管，这里是她吃的样子）
        case .eatHappily:
            return [Step(.eat, 3.4, .nibble, effect: .crumbs), Step(.lickLips, 1.2, effect: .hearts(2))]
        case .sniffFirst:
            return [Step(.crouch, 1.0, .nibble, effect: .question), Step(.eat, 2.8, .nibble, effect: .crumbs),
                    Step(.lickLips, 1.0)]
        case .batTreat:
            return [Step(.bat, 0.5, .swat), Step(.crouch, 0.7, .wiggle), Step(.bat, 0.5, .swat),
                    Step(.eat, 2.4, .nibble, effect: .crumbs), Step(.lickLips, 1.0)]
        case .carryAway:
            return [Step(.eat, 3.0, .nibble, effect: .crumbs), Step(.lickLips, 1.0)]
        case .beg:
            return [Step(.eat, 3.0, .nibble, effect: .crumbs), Step(.lickLips, 0.8), Step(.reach, 1.3, .hop(10), effect: .question)]
        // 逗猫棒
        case .catchIt:
            return [Step(.leap, 0.55, .hop(70), effect: .sparkles), Step(.crouch, 0.5, .wiggle)]
        case .miss:
            return [Step(.leap, 0.55, .hop(60)), Step(.groom, 1.0, .still, effect: .dots)]
        case .batAtIt:
            return [Step(.reach, 0.5, .hop(16)), Step(.bat, 0.45, .swat), Step(.bat, 0.45, .swat)]
        case .bunnyKick:
            return [Step(.leap, 0.45, .hop(50)), Step(.toyKick, 1.6, .kick, effect: .sparkles)]
        case .zoomies:
            return [Step(.run, 1.6, .dash(1.2), effect: .exclaim)]
        // 点她
        case .chirp:
            return [Step(.headTilt, 1.3, .lean(5), effect: .notes)]
        case .meow:
            return [Step(.meow, 1.0, .hop(4), effect: .notes), Step(upright, 0.3)]
        case .tailFlick:
            return [Step(nil, 0.9, .still, effect: .dots)]
        case .comeCloser:
            return [Step(.rub, 1.2, .push, effect: .hearts(2))]
        case .headTilt:
            return [Step(.headTilt, 1.4, .lean(4), effect: .question)]
        // 慢眨眼
        case .blinkBack:
            return [Step(nil, 1.4, .still, eyesClosed: true, effect: .hearts(2))]
        case .lookAway:
            return [Step(.sitBack, 1.0), Step(upright, 0.6, eyesClosed: true, effect: .hearts(1))]
        case .yawn:
            return [Step(.meow, 0.9, .lean(-3), eyesClosed: true), Step(nil, 0.8, eyesClosed: true, effect: .hearts(1))]
        }
    }

    /// 这种反应配什么声音：整段的声音放在第一段；吃东西的每一段都咔嚓；讨零食的叫声在站起来那一下
    static func addSounds(to steps: inout [Step], reaction: CatReaction) {
        guard !steps.isEmpty else { return }
        let opening: CatSound? = switch reaction {
        case .meow: .meow
        case .chirp, .comeCloser, .headbutt, .zoomies: .trill
        case .grumble, .swat, .loveBite: .grumble
        case .scoot: .squeak
        default: nil
        }
        if reaction == .loveBite || reaction == .swat, let angry = steps.firstIndex(where: { $0.effect == .anger }) {
            steps[angry].sound = .grumble
        } else {
            steps[0].sound = opening
        }
        for index in steps.indices where steps[index].pose == .eat && steps[index].motion == .nibble {
            steps[index].sound = .crunch
        }
        if reaction == .beg, let last = steps.indices.last { steps[last].sound = .ask }
    }

    /// 每一段的声音和它开始的时间（从反应开始算，秒）
    var soundCues: [(offset: TimeInterval, sound: CatSound)] {
        var offset = 0.0
        var cues: [(TimeInterval, CatSound)] = []
        for step in steps {
            if let sound = step.sound { cues.append((offset, sound)) }
            offset += step.duration
        }
        return cues
    }

    /// 打呼噜的反应（放呼噜声、手机连着轻震）
    var purrs: Bool {
        [.leanIn, .headbutt, .chinUp, .purrLoaf, .knead, .rollOver, .flop, .comeCloser, .blinkBack].contains(reaction)
    }
}
