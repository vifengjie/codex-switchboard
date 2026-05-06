import Foundation

public enum RateCardManagerError: Error, Equatable, Sendable {
    case invalidUTF8
    case decodingFailed(String)
}

public struct RateCardCatalog: Codable, Equatable, Sendable {
    public var version: String
    public var sourceURL: URL?
    public var models: [RateCard]

    public init(version: String, sourceURL: URL? = nil, models: [RateCard]) {
        self.version = version
        self.sourceURL = sourceURL
        self.models = models
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case sourceURL = "source_url"
        case models
    }
}

public struct EstimatedCredits: Equatable, Sendable {
    public var credits: Double
    public var rateCardVersion: String

    public init(credits: Double, rateCardVersion: String) {
        self.credits = credits
        self.rateCardVersion = rateCardVersion
    }
}

public struct RateCardManager: Sendable {
    private var cardsByModel: [String: RateCard]
    private let calculator: CreditsCalculator

    public init(rateCards: [RateCard], calculator: CreditsCalculator = CreditsCalculator()) {
        self.cardsByModel = Dictionary(
            uniqueKeysWithValues: rateCards.map { (Self.normalize($0.model), $0) }
        )
        self.calculator = calculator
    }

    public init(catalog: RateCardCatalog, calculator: CreditsCalculator = CreditsCalculator()) {
        let cards = catalog.models.map { card in
            RateCard(
                model: card.model,
                version: card.version.isEmpty ? catalog.version : card.version,
                sourceURL: card.sourceURL ?? catalog.sourceURL,
                inputCreditsPerM: card.inputCreditsPerM,
                cachedInputCreditsPerM: card.cachedInputCreditsPerM,
                outputCreditsPerM: card.outputCreditsPerM
            )
        }
        self.init(rateCards: cards, calculator: calculator)
    }

    public static let builtIn = RateCardManager(
        rateCards: [
            RateCard(
                model: "mock-codex",
                version: "fixture-2026-05-03",
                sourceURL: URL(string: "https://help.openai.com/en/articles/20001106-codex-rate-card"),
                inputCreditsPerM: 10,
                cachedInputCreditsPerM: 2,
                outputCreditsPerM: 40
            )
        ]
    )

    public static func decodeCatalog(from data: Data) throws -> RateCardCatalog {
        do {
            return try JSONDecoder().decode(RateCardCatalog.self, from: data)
        } catch {
            throw RateCardManagerError.decodingFailed(error.localizedDescription)
        }
    }

    public static func decodeCatalog(from json: String) throws -> RateCardCatalog {
        guard let data = json.data(using: .utf8) else {
            throw RateCardManagerError.invalidUTF8
        }
        return try decodeCatalog(from: data)
    }

    public func rateCard(for model: String?) -> RateCard? {
        guard let model, !model.isEmpty else {
            return nil
        }
        return cardsByModel[Self.normalize(model)]
    }

    public func estimatedCredits(for usage: TokenUsage, model: String?) -> EstimatedCredits? {
        guard let card = rateCard(for: model) else {
            return nil
        }
        return EstimatedCredits(
            credits: calculator.estimatedCredits(for: usage, rateCard: card),
            rateCardVersion: card.version
        )
    }

    private static func normalize(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
