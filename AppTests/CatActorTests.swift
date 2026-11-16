import CatWorld
import Economy
import Foundation
import Testing
import UIKit
@testable import Purrday

@Suite("布丁在画面上怎么动")
struct CatActorTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func presence(_ pose: CatPose, _ x: Double, _ y: Double, depth: CatDepth? = nil, activity: CatActivity? = .sit,
                          facing: Int = 0, fidget: CatFidget = .none) -> CatPresence {
        CatPresence(activity: activity, pose: pose, spot: RoomPoint(x: x, y: y), depth: depth ?? .floor(y), facing: facing,
                    fidget: fidget, nextChange: t0.addingTimeInterval(20))
    }

    @Test("刚打开房间：直接出现在那里，不走路")
    func appears() {
        var actor = CatActor()
        actor.update(to: presence(.loaf, 0.3, 0.85), now: t0, animated: false, itemBottoms: [:])
        let frame = actor.frame(at: t0)
        #expect(frame.spot == RoomPoint(x: 0.3, y: 0.85))
        #expect(frame.pose == .loaf)
        #expect(frame.motion == .rest)
    }

    @Test("换个地方：走过去（侧面朝着走的方向），到了换成那件事的姿势")
    func walks() throws {
        var actor = CatActor()
        actor.update(to: presence(.sit, 0.3, 0.85), now: t0, animated: false, itemBottoms: [:])
        actor.update(to: presence(.groom, 0.7, 0.85), now: t0, animated: true, itemBottoms: [:])
        #expect(actor.segments.map(\.kind) == [.walk])
        let walk = try #require(actor.segments.first)
        let middle = actor.frame(at: t0.addingTimeInterval(walk.duration / 2))
        #expect(middle.pose == .stand)
        #expect(middle.motion == .walk)
        #expect(middle.facing == 1)
        #expect(abs(middle.spot.x - 0.5) < 0.01)
        let arrived = actor.frame(at: walk.end.addingTimeInterval(0.1))
        #expect(arrived.pose == .groom)
        #expect(arrived.spot == RoomPoint(x: 0.7, y: 0.85))
    }

    @Test("去家具上面：先走到家具前面，再跳上去；跳到一半才算到了家具上")
    func jumpsUp() throws {
        var actor = CatActor()
        actor.update(to: presence(.sit, 0.8, 0.9), now: t0, animated: false, itemBottoms: [:])
        let sofa = presence(.loaf, 0.3, 0.66, depth: .on(itemID: 5))
        actor.update(to: sofa, now: t0, animated: true, itemBottoms: [5: 0.75])
        #expect(actor.segments.map(\.kind) == [.walk, .jump])
        let walk = actor.segments[0], jump = actor.segments[1]
        #expect(abs(walk.to.y - 0.77) < 1e-9) // 沙发底边前面一点
        #expect(actor.frame(at: jump.start.addingTimeInterval(jump.duration * 0.25)).depth == .floor(walk.to.y))
        #expect(actor.frame(at: jump.start.addingTimeInterval(jump.duration * 0.75)).depth == .on(itemID: 5))
        // 跳起来的时候比起跳点和落脚点都高
        let apex = actor.frame(at: jump.start.addingTimeInterval(jump.duration * 0.5))
        #expect(apex.spot.y < min(jump.from.y, jump.to.y))
        #expect(apex.onGround == false)
        #expect(actor.frame(at: jump.end).pose == .loaf)
    }

    @Test("睡醒了要走：先伸个懒腰，从家具上跳下来，再走")
    func wakesUp() {
        var actor = CatActor()
        actor.update(to: presence(.curl, 0.5, 0.92, depth: .inside(itemID: 2), activity: .nap), now: t0, animated: false,
                     itemBottoms: [2: 0.95])
        actor.update(to: presence(.eat, 0.2, 0.8, facing: -1), now: t0, animated: true, itemBottoms: [2: 0.95])
        #expect(actor.segments.map(\.kind) == [.pause(.stretch), .jump, .walk])
        #expect(actor.frame(at: t0.addingTimeInterval(0.5)).pose == .stretch)
        let end = actor.segments.last!.end
        let frame = actor.frame(at: end)
        #expect(frame.pose == .eat)
        #expect(frame.facing == -1)
    }

    @Test("自己玩的时候是跑过去")
    func runs() {
        var actor = CatActor()
        actor.update(to: presence(.stand, 0.2, 0.8, activity: .play, facing: 1), now: t0, animated: false, itemBottoms: [:])
        actor.update(to: presence(.stand, 0.8, 0.9, activity: .play, facing: 1), now: t0, animated: true, itemBottoms: [:])
        #expect(actor.segments.map(\.kind) == [.run])
    }

    @Test("同一个地方只换小动作：不走路，小动作从这时候开始算")
    func fidgetOnly() {
        var actor = CatActor()
        actor.update(to: presence(.sit, 0.5, 0.9), now: t0, animated: false, itemBottoms: [:])
        actor.update(to: presence(.sit, 0.5, 0.9, fidget: .yawn), now: t0.addingTimeInterval(20), animated: true, itemBottoms: [:])
        #expect(actor.segments.isEmpty)
        let frame = actor.frame(at: t0.addingTimeInterval(21))
        #expect(frame.fidget == .yawn)
        #expect(frame.fidgetElapsed == 1)
    }

    @Test("叫醒、送礼物这些用专门的画：直接出现，不走路")
    func stateArt() {
        var actor = CatActor()
        actor.update(to: presence(.sit, 0.2, 0.8), now: t0, animated: false, itemBottoms: [:])
        actor.update(to: presence(.stateArt, 0.5, 0.9, activity: nil), now: t0, animated: true, itemBottoms: [:])
        #expect(actor.segments.isEmpty)
        #expect(actor.frame(at: t0).pose == .stateArt)
    }
}

@Suite("房间和布丁的美术资源")
struct RoomAssetTests {
    @Test("每个姿势的每个部件都有图")
    func rigParts() {
        for pose in CatPose.allCases where pose != .stateArt {
            let spec = CatRig.spec(for: pose)
            var parts: [String] = []
            for layer in spec.layers {
                switch layer {
                case .body: parts.append("body")
                case .tail: parts.append("tail")
                case let .head(_, hasEyes, hasMouth):
                    parts.append("head")
                    if hasEyes { parts += ["eyes-open", "eyes-closed"] + (spec.hasHappyEyes ? ["eyes-happy"] : []) }
                    if hasMouth { parts += ["mouth-w", "mouth-open"] }
                case let .leg(leg, _): parts.append(leg.rawValue)
                case .paw: parts.append("paw")
                }
            }
            for part in parts {
                #expect(UIImage(named: "cat-rig-\(spec.name)-\(part)") != nil, "\(pose): \(part)")
            }
        }
    }

    @Test("每件礼物、纪念品、毛色都有图；横幅、场景、纸纹都在")
    func uiArt() throws {
        let catalog = try Catalog.bundled()
        for item in catalog.items {
            #expect(UIImage(named: Theme.art(for: item)) != nil, "\(item.id) 没有图")
        }
        for name in ["banner-shop", "banner-collection", "banner-alarms", "scene-dawn", "scene-night", "paper"] {
            #expect(UIImage(named: name) != nil, "\(name)")
        }
    }

    @Test("透视：贴着后墙的东西小、收在中间；画布最前面是原样")
    func perspective() {
        let back = RoomPerspective.project(RoomPoint(x: 0, y: RoomGeometry.floorLine), groundY: RoomGeometry.floorLine, onWall: false)
        #expect(abs(back.x - RoomPerspective.backLeft) < 1e-9)
        #expect(back.scale == RoomPerspective.backScale)
        let front = RoomPerspective.project(RoomPoint(x: 1, y: 1), groundY: 1, onWall: false)
        #expect(abs(front.x - 1) < 1e-9)
        #expect(front.scale == 1)
        // 坐在家具上：比地面高出来的部分按这一排的缩放缩短
        let seat = RoomPerspective.project(RoomPoint(x: 0.5, y: 0.7), groundY: 0.8, onWall: false)
        #expect(abs(seat.y - (0.8 - 0.1 * RoomPerspective.scale(groundY: 0.8, onWall: false))) < 1e-9)
        // 墙上的东西：y 不变，按后墙的宽度
        let shelf = RoomPerspective.project(RoomPoint(x: 0.5, y: 0.3), groundY: 0.3, onWall: true)
        #expect(shelf.y == 0.3)
        #expect(abs(shelf.x - 0.5) < 1e-9)
        // 拖动：后面一排横着拖同样距离，房间坐标走得更多
        let far = RoomPerspective.unproject(dx: 0.1, dy: 0, groundY: 0.65, onWall: false)
        let near = RoomPerspective.unproject(dx: 0.1, dy: 0, groundY: 0.95, onWall: false)
        #expect(far.dx > near.dx)
    }

    @Test("每件家具都有图；能钻进去的家具还有前半部分")
    func furniture() throws {
        let catalog = try Catalog.bundled()
        #expect(UIImage(named: RoomArt.background) != nil)
        #expect(UIImage(named: RoomArt.paperGrain) != nil)
        for item in catalog.items where item.kind == .furniture {
            #expect(UIImage(named: RoomArt.furniture(item.id)) != nil, "\(item.id)")
            if item.placement?.hasFront == true {
                #expect(UIImage(named: RoomArt.front(item.id)) != nil, "\(item.id) 的前半部分")
            }
        }
    }
}
