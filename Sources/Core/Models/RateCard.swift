import Foundation

public struct RateCard: Codable, Equatable, Sendable {
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

    private enum CodingKeys: String, CodingKey {
        case model
        case version
        case sourceURL = "source_url"
        case inputCreditsPerM = "input_credits_per_m"
        case cachedInputCreditsPerM = "cached_input_credits_per_m"
        case outputCreditsPerM = "output_credits_per_m"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try container.decode(String.self, forKey: .model)
        self.version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
        self.sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
        self.inputCreditsPerM = try container.decode(Double.self, forKey: .inputCreditsPerM)
        self.cachedInputCreditsPerM = try container.decode(Double.self, forKey: .cachedInputCreditsPerM)
        self.outputCreditsPerM = try container.decode(Double.self, forKey: .outputCreditsPerM)
    }
}
