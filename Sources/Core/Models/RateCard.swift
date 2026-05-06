import Foundation

public struct RateCard: Equatable, Sendable {
    public var model: String
    public var version: String
    public var sourceURL: URL?
    public var inputCreditsPerM: Double
    public var cachedInputCreditsPerM: Double
    public var outputCreditsPerM: Double

    public init(
        model: String,
        version: String,
        sourceURL: URL? = nil,
        inputCreditsPerM: Double,
        cachedInputCreditsPerM: Double,
        outputCreditsPerM: Double
    ) {
        self.model = model
        self.version = version
        self.sourceURL = sourceURL
        self.inputCreditsPerM = inputCreditsPerM
        self.cachedInputCreditsPerM = cachedInputCreditsPerM
        self.outputCreditsPerM = outputCreditsPerM
    }
}
