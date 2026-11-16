import Economy
import Foundation

// 她的反应（docs/cat-life.md 4.2）：同一种互动有好几种可能的动作，按好感阶段、性格、部位和一点运气挑，
// 连着两次不重样。Core 只决定"她这次做什么"，界面按反应播一段动作（`Features/Room/CatPerformance.swift`）。

/// 一次互动里她具体怎么反应。
public enum CatReaction: String, Codable, Sendable, CaseIterable {
    // 摸到喜欢的地方
    /// 闭眼往你手上靠
    case leanIn
    /// 用头顶你的手、蹭过来
    case headbutt
    /// 抬起下巴让你挠
    case chinUp
    /// 揣手眯眼打呼噜
    case purrLoaf
    /// 踩奶
    case knead
    /// 翻过来露肚皮
    case rollOver
    /// 往旁边一倒，侧躺着看你
    case flop
    // 还不熟
    /// 僵住不动
    case freeze
    /// 凑过来闻闻你的手
    case sniffHand
    /// 吓一跳，往后缩
    case scoot
    // 不喜欢
    /// 耳朵往后、尾巴甩，嘟囔
    case grumble
    /// 拍你一爪（不伸指甲）
    case swat
    /// 抱住你的手轻轻咬一口、蹬两下（露肚皮的陷阱）
    case loveBite
    // 零食
    /// 开心地吃
    case eatHappily
    /// 先闻一闻再吃
    case sniffFirst
    /// 先拿爪子拨来拨去玩一会儿再吃
    case batTreat
    /// 叼起来跑到一边去吃
    case carryAway
    /// 吃完坐起来抬爪子还要
    case beg
    // 逗猫棒：每扑一下
    /// 扑中了
    case catchIt
    /// 扑空了，假装没事
    case miss
    /// 坐着用爪子拍
    case batAtIt
    /// 抱住羽毛躺下蹬
    case bunnyKick
    /// 兴奋得满屋子跑
    case zoomies
    // 点她
    /// 歪头"咕？"
    case chirp
    /// 张嘴叫一声
    case meow
    /// 甩一下尾巴，不理你
    case tailFlick
    /// 朝你走过来
    case comeCloser
    /// 歪着头看你
    case headTilt
    // 慢眨眼的回应
    /// 慢慢眨回来
    case blinkBack
    /// 把眼睛移开（猫表示放松、信任的另一种方式）
    case lookAway
    /// 打个哈欠
    case yawn
}

/// 是什么互动引起的反应。
public enum ReactionTrigger: Hashable, Sendable {
    case pet(PetRegion, PetReaction)
    case treat
    /// 逗猫棒扑的第几下（从 0 开始）
    case pounce(Int)
    case tap
    case blink(returned: Bool)
}

extension CatWorld {
    /// 挑她这一下的反应。用好感度里的随机数（存档里），所以每次不一样；和上一次一样时重挑一次。
    public mutating func react(to trigger: ReactionTrigger, at date: Date) -> CatReaction {
        let weights = Self.reactionWeights(trigger, stage: state.bond.stage, personality: state.bond.personality,
                                           activity: presence(at: date).activity, kind: state.activeCat)
        var rng = state.bond.rng
        var pick = Self.pickReaction(weights, rng: &rng)
        if pick == state.bond.lastReaction, weights.count > 1 {
            pick = Self.pickReaction(weights.filter { $0.0 != pick }, rng: &rng)
        }
        state.bond.rng = rng
        state.bond.lastReaction = pick
        return pick
    }

    /// 各种反应的权重（docs/cat-life.md 4.2 的表）。按 `CatReaction.allCases` 的顺序排好，保证可复现。
    static func reactionWeights(_ trigger: ReactionTrigger, stage: BondStage, personality: Personality,
                                activity: CatActivity?, kind: CatKind = .pudding) -> [(CatReaction, Double)] {
        var w: [CatReaction: Double] = [:]
        func boost(_ reaction: CatReaction, _ factor: Double, when condition: Bool) {
            if condition, let value = w[reaction] { w[reaction] = value * factor }
        }
        switch trigger {
        case let .pet(region, reaction):
            switch reaction {
            case .loves, .likes:
                let loves = reaction == .loves
                w[.leanIn] = 3
                if [.head, .cheek].contains(region) { w[.headbutt] = 2 }
                if region == .chin { w[.chinUp] = 3 } else if region == .cheek { w[.chinUp] = 1 }
                w[.purrLoaf] = loves ? 2 : 1
                if stage >= .familiar { w[.flop] = 1.5 }
                if loves, stage >= .close {
                    w[.knead] = 2
                    if personality != .shy { w[.rollOver] = 1.5 }
                }
                if region == .belly { w[.rollOver] = 4 } // 肚子被摸得舒服：干脆翻过来
                boost(.headbutt, 1.6, when: personality == .clingy)
                boost(.knead, 1.6, when: personality == .clingy)
                boost(.leanIn, 0.6, when: personality == .aloof)
                boost(.flop, 1.5, when: activity == .sunbathe || activity == .bellyUp)
            case .tolerates:
                w[.freeze] = 3
                w[.scoot] = stage == .newcomer ? 3 : 1.5
                if stage >= .curious { w[.sniffHand] = 2 }
                boost(.scoot, 1.5, when: personality == .shy)
            case .dislikes:
                if region == .belly, stage >= .close {
                    w[.loveBite] = 3
                    w[.swat] = 1
                    w[.grumble] = 1
                } else {
                    w[.grumble] = 3
                    w[.swat] = 2
                    boost(.swat, 1.5, when: personality == .aloof || personality == .playful)
                }
            }
        case .treat:
            w[.eatHappily] = 3
            w[.sniffFirst] = stage <= .curious || personality == .shy ? 3 : 1
            w[.batTreat] = personality == .playful ? 3 : 1.2
            w[.carryAway] = personality == .shy ? 2 : (personality == .aloof ? 1.5 : 0.8)
            if stage >= .familiar { w[.beg] = personality == .foodie ? 3.5 : 1.5 }
        case let .pounce(index):
            w[.catchIt] = 3
            w[.miss] = 2
            w[.batAtIt] = 2
            if stage >= .familiar, index >= 1 { w[.bunnyKick] = 1.5 }
            w[.zoomies] = personality == .playful ? 1.6 : 0.8
        case .tap:
            if stage == .newcomer {
                w[.scoot] = 2
                w[.freeze] = 1
            } else {
                w[.chirp] = 3
                w[.meow] = 3
                w[.headTilt] = 2
                w[.tailFlick] = personality == .aloof ? 3 : 1
                if stage >= .familiar { w[.comeCloser] = personality == .clingy ? 4 : 2 }
            }
        case let .blink(returned):
            if returned {
                w[.blinkBack] = 4
                w[.lookAway] = 1
                w[.yawn] = 1
            } else {
                w[.headTilt] = 2
                w[.tailFlick] = 1
            }
        }
        // 每种猫的脾气：同样的互动，她们各有各爱做的反应
        for (reaction, factor) in kind.temperament.reactions {
            if let weight = w[reaction] { w[reaction] = weight * factor }
        }
        return CatReaction.allCases.compactMap { r in w[r].map { (r, $0) } }
    }

    static func pickReaction(_ entries: [(CatReaction, Double)], rng: inout SeededRandom) -> CatReaction {
        let total = entries.reduce(0) { $0 + $1.1 }
        var roll = unit(&rng) * total
        for (reaction, weight) in entries {
            roll -= weight
            if roll < 0 { return reaction }
        }
        return entries.last?.0 ?? .leanIn
    }
}
