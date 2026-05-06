import Foundation

public struct QuotaEngine: Sendable {
    public init() {}

    public func remainingPercent(fromUsedPercent usedPercent: Double?) -> Double? {
        guard let usedPercent else {
            return nil
        }
        return max(0, min(100, 100 - usedPercent))
    }
}
