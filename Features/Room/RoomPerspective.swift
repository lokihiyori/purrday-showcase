import CatWorld
import Economy
import Foundation

/// 房间的透视：像从斜上方看进一个小房间。Core 里的坐标不变（x 0–1、y 0–1，`RoomGeometry`），
/// 只是画的时候换算一下：后墙在中间（画布 x 0.1–0.9），地板越往后越窄、东西越往后越小。
/// 数字和美术脚本 design/room/tools/paint_room.py 的 BACK_L / BACK_R 一致。
enum RoomPerspective {
    /// 后墙左右边在画布里的位置（和房间背景图量出来的一致，见 RoomArt）
    static let backLeft = 0.035
    static let backRight = 0.965
    /// 贴着后墙的东西（墙上的、地板最里面的）画多大
    static let backScale = 0.9

    /// 地板上的深度：0 贴着后墙，1 在画布最前面
    static func depth(_ groundY: Double) -> Double {
        ((groundY - RoomGeometry.floorLine) / (1 - RoomGeometry.floorLine)).clamped(to: 0...1)
    }

    /// 站在 groundY 那一排的东西画多大（墙上的东西按后墙算）
    static func scale(groundY: Double, onWall: Bool) -> Double {
        onWall ? backScale : backScale + (1 - backScale) * depth(groundY)
    }

    /// 这一排地板（或者后墙）从左到右在画布里占多宽
    static func span(groundY: Double, onWall: Bool) -> (left: Double, right: Double) {
        let t = onWall ? 0 : depth(groundY)
        return (backLeft * (1 - t), backRight + (1 - backRight) * t)
    }

    /// 房间坐标 → 画布坐标（0–1）和缩放。`groundY`：这个东西"站"在哪一排（在家具上时是家具的底边）。
    /// 比地面高出来的部分（比如坐在沙发上）按这一排的缩放缩短。
    static func project(_ point: RoomPoint, groundY: Double, onWall: Bool) -> (x: Double, y: Double, scale: Double) {
        let s = scale(groundY: groundY, onWall: onWall)
        let (left, right) = span(groundY: groundY, onWall: onWall)
        let x = left + (right - left) * point.x
        let y = onWall ? point.y : groundY + (point.y - groundY) * s
        return (x, y, s)
    }

    /// 拖动家具：屏幕上的位移（画布比例）→ 房间坐标的位移
    static func unproject(dx: Double, dy: Double, groundY: Double, onWall: Bool) -> (dx: Double, dy: Double) {
        let (left, right) = span(groundY: groundY, onWall: onWall)
        return (dx / max(right - left, 0.01), dy)
    }

    /// 布丁站在哪一排、在不在墙上（在墙上的家具上时按后墙算）
    static func ground(of depth: CatDepth, placed: [PlacedFurniture], catalog: Catalog) -> (y: Double, onWall: Bool) {
        switch depth {
        case let .floor(y):
            return (y, false)
        case let .on(id), let .inside(id):
            guard let item = placed.first(where: { $0.itemID == id }) else { return (RoomGeometry.catHome.y, false) }
            let onWall = catalog.item(item.catalogID)?.placement?.zone == .wall
            return (item.position.y, onWall)
        }
    }
}
