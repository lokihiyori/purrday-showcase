import CatWorld
import Foundation

/// 手指摸到了布丁的哪里。房间里传进来的是宽画布（`CatPoseArt.wideAspect` 倍猫宽 × 猫宽）里的位置（0–1），
/// 按图本来的朝向（翻转过的先翻回来）。摸到空白处返回 nil。
enum PetMap {
    /// 宽画布坐标 → 部位。布丁最早的 8 个姿势有对着图量好的分区；其他猫、其他姿势按身体范围分。
    static func region(pose: CatPose, wideX x: Double, y: Double, kind: CatKind = .pudding) -> PetRegion? {
        guard kind == .pudding else { return boundsRegion(pose: pose, x: x, y: y, kind: kind) }
        switch pose {
        case .sit, .groom, .loaf, .purr, .stateArt, .sitBack, .curl, .sprawl, .stretch, .stand:
            return squareRegion(pose: pose, x: toSquare(x), y: y)
        case .chinUp, .headTilt, .lickLips, .meow:
            return squareRegion(pose: .sit, x: toSquare(x), y: y)
        case .knead:
            return squareRegion(pose: .loaf, x: toSquare(x), y: y)
        default:
            return boundsRegion(pose: pose, x: x, y: y)
        }
    }

    /// 宽画布的 x → 方图的 x（方图摆在宽画布中间）
    static func toSquare(_ x: Double) -> Double { 0.5 + (x - 0.5) * CatPoseArt.wideAspect }

    /// 新姿势：按猫在图里的范围（`CatPoseArt.bounds`）分头、尾巴、背、肚子
    private static func boundsRegion(pose: CatPose, x: Double, y: Double, kind: CatKind = .pudding) -> PetRegion? {
        let b = CatPoseArt.bounds(pose, kind: kind)
        guard x >= b.x0 - 0.02, x <= b.x1 + 0.02, y >= b.y0 - 0.02, y <= b.y1 + 0.02 else { return nil }
        let u = ((x - b.x0) / b.width).clamped(to: 0...1)
        let v = ((y - b.y0) / b.height).clamped(to: 0...1)
        let cu = abs(u - 0.5)
        switch pose {
        case .sit, .groom, .chinUp, .headTilt, .lickLips, .meow, .stateArt:
            // 正面坐着：头在上面，嘴下面是下巴，两边是脸颊；中间是肚子，两边算背；尾巴绕在右下
            if v > 0.8, u > 0.62 { return .tail }
            if v < 0.19 { return .head }
            if v < 0.38 { return cu < 0.14 && v > 0.27 ? .chin : (cu < 0.12 ? .head : .cheek) }
            return cu < 0.22 ? .belly : .back
        case .loaf, .knead, .purr:
            if cu < 0.23, v < 0.25 { return .head }
            if cu < 0.23, v < 0.55 { return cu < 0.1 && v > 0.37 ? .chin : .cheek }
            return .back
        case .sitBack:
            if v < 0.24 { return .head }
            return v > 0.8 ? .tail : .back
        case .curl:
            if v > 0.84 { return .tail }
            if u > 0.46, (0.12...0.74).contains(v) { return .cheek }
            return .back
        case .sprawl:
            if u > 0.82 { return .head }
            if u < 0.14 { return .tail }
            return v > 0.72 ? .belly : .back
        case .stretch:
            // 伸懒腰（朝左）：头在左下，尾巴翘在右上
            if u > 0.64, v < 0.33 { return .tail }
            if u < 0.29 { return v < 0.77 ? .head : .chin }
            return v > 0.77 ? .belly : .back
        case .bellyUp:
            // 头在左上，尾巴在左下，中间是肚子
            if u < 0.45, v < 0.42 { return v < 0.22 ? .head : .cheek }
            if u < 0.4, v > 0.75 { return .tail }
            return .belly
        case .sleepBelly, .toyKick:
            // 头在右边
            if u > 0.62, v < 0.5 { return .head }
            if u < 0.32, v > 0.62 { return .tail }
            return .belly
        case .lieSide:
            // 侧躺：头在右边，尾巴在左边，下面一条是肚子
            if u > 0.66, v < 0.62 { return v < 0.35 ? .head : .cheek }
            if u < 0.16 { return .tail }
            return v > 0.72 ? .belly : .back
        case .bat, .reach, .startled:
            // 立着的侧面：头在上面，尾巴在左下
            if v < 0.3 { return u > 0.6 && v > 0.18 ? .chin : .head }
            if u < 0.32, v > 0.6 { return .tail }
            return u > 0.55 ? .belly : .back
        default:
            // 侧面朝右：头在右上，尾巴在左边；身子上面是背，下面是肚子
            if u > 0.7, v < 0.6 { return v < 0.3 ? .head : (u > 0.85 ? .chin : .cheek) }
            if u < 0.26 { return .tail }
            return v < 0.62 ? .back : .belly
        }
    }

    /// 最早的 8 个方图姿势（600×600）里的位置 → 部位。数字是对着图量的，脚底在 0.9。
    static func squareRegion(pose: CatPose, x: Double, y: Double) -> PetRegion? {
        let cx = abs(x - 0.5)
        switch pose {
        case .sit, .groom:
            // 正面坐着：头在上面，下巴在嘴下面，两边是脸颊；肚子在中间，两边算背；尾巴绕在右下角
            guard (0.2...0.8).contains(x), (0.08...0.92).contains(y) else { return nil }
            if y > 0.72, x > 0.58 { return .tail }
            if y < 0.25 { return .head }
            if y < 0.4 { return cx < 0.09 && y > 0.3 ? .chin : (cx < 0.08 ? .head : .cheek) }
            return cx < 0.15 ? .belly : .back
        case .loaf, .purr, .stateArt:
            // 揣手趴着：头在中间偏上，其余都是背
            guard (0.18...0.82).contains(x), (0.38...0.92).contains(y) else { return nil }
            if cx < 0.14, y < 0.52 { return .head }
            if cx < 0.14, y < 0.67 { return cx < 0.06 && y > 0.58 ? .chin : .cheek }
            return .back
        case .sitBack:
            // 背对你坐着：头、背、尾巴
            guard (0.24...0.76).contains(x), (0.12...0.92).contains(y) else { return nil }
            if y < 0.32 { return .head }
            if y > 0.75 { return .tail }
            return .back
        case .curl:
            // 蜷成一团：脸在右边，尾巴绕在下面
            guard (0.18...0.82).contains(x), (0.42...0.92).contains(y) else { return nil }
            if y > 0.82 { return .tail }
            if x > 0.47, (0.5...0.78).contains(y) { return .cheek }
            return .back
        case .sprawl:
            // 侧躺：头在右边，尾巴在左边，下面一条是肚子
            guard (0.02...0.98).contains(x), (0.55...0.92).contains(y) else { return nil }
            if x > 0.8 { return .head }
            if x < 0.17 { return .tail }
            return y > 0.8 ? .belly : .back
        case .stretch:
            // 伸懒腰（朝左）：头在左下，尾巴翘在右上
            guard (0.06...0.95).contains(x), (0.26...0.92).contains(y) else { return nil }
            if x > 0.62, y < 0.48 { return .tail }
            if x < 0.32 { return y < 0.76 ? .head : .chin }
            return y > 0.76 ? .belly : .back
        case .stand:
            // 侧面站着（朝右）：头在右上，尾巴翘在左上；身子上面是背，下面是肚子
            guard (0.08...0.92).contains(x), (0.26...0.92).contains(y) else { return nil }
            if x < 0.33, y < 0.6 { return .tail }
            if x > 0.7, y < 0.64 { return y < 0.48 ? .head : (x > 0.82 ? .chin : .cheek) }
            if y < 0.63 { return .back }
            return y < 0.76 ? .belly : nil
        default:
            return nil
        }
    }
}
