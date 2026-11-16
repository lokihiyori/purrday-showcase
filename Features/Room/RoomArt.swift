import CoreGraphics

/// 房间美术资源（Resources/Assets.xcassets/Room，生成脚本 design/room/tools/generate.py）。
enum RoomArt {
    /// 房间背景（AI 画的，design/incoming/room，导入脚本 design/tools/import_ai_art.py）：600×1400 单位，
    /// 墙和地板的分界在背景高度的 61.5%，房间画布（600×800）从背景 y 380.7 开始，让分界落在画布 y 480。
    static let background = "room-background"
    /// 背景图的高 / 宽
    static let backgroundAspect = 1400.0 / 600.0
    /// 画布顶部在背景图里的位置（按背景宽度算）
    static let backgroundStageTop = 380.7 / 600.0
    /// 屏幕上背景图盖不到的地方用的颜色（和天花板一样）
    static let ceilingColor = (red: 0.93, green: 0.68, blue: 0.42)
    /// 窗玻璃在画布里的位置（0–1，窗户比画布顶还高一点）。玻璃是透明的，天空画在后面
    static let windowPane = CGRect(x: 0.342, y: -0.1592, width: 0.332, height: 0.4078)
    /// 窗户横档的位置（占窗玻璃高度的比例）
    static let windowTransom = 0.48
    /// 天花板吊灯（新背景里没有，夜里不画吊灯的光）
    static let pendantLamp: CGPoint? = nil
    /// 纸张颗粒，平铺、正片叠底盖在整个房间上
    static let paperGrain = "paper-grain"

    /// "furniture.cardboard_box" → "furniture-cardboard_box"
    static func furniture(_ catalogID: String) -> String {
        "furniture-" + (catalogID.split(separator: ".").last.map(String.init) ?? catalogID)
    }

    /// 能钻进去的家具的前半部分（盖在猫上面）："furniture-cardboard_box-front"
    static func front(_ catalogID: String) -> String {
        furniture(catalogID) + "-front"
    }
}
