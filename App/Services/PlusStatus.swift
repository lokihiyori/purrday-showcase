import Foundation
import Observation

/// Purrday Plus 的订阅状态。
///
/// TODO(Mac)：接入 RevenueCat，用 entitlement 更新 `isPlus`。
@MainActor
@Observable
final class PlusStatus {
    var isPlus = false
}
