import CodexQuotaCore
import Foundation
import SQLite3

public struct SQLiteRateCardRepository: Sendable {
    private let store: SQLiteStore

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func upsert(_ rateCard: RateCard) throws {
        try store.withDatabase { db in
            let sql = """
                INSERT INTO rate_cards(
                    model,
                    version,
                    source_url,
                    input_credits_per_m,
                    cached_input_credits_per_m,
                    output_credits_per_m,
                    updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(model) DO UPDATE SET
                    version = excluded.version,
                    source_url = excluded.source_url,
                    input_credits_per_m = excluded.input_credits_per_m,
                    cached_input_credits_per_m = excluded.cached_input_credits_per_m,
                    output_credits_per_m = excluded.output_credits_per_m,
                    updated_at = excluded.updated_at
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            bindText(statement, index: 1, value: rateCard.model)
            bindText(statement, index: 2, value: rateCard.version)
            bindOptionalText(statement, index: 3, value: rateCard.sourceURL?.absoluteString)
            bindDouble(statement, index: 4, value: rateCard.inputCreditsPerM)
            bindDouble(statement, index: 5, value: rateCard.cachedInputCreditsPerM)
            bindDouble(statement, index: 6, value: rateCard.outputCreditsPerM)
            bindDouble(statement, index: 7, value: Date().timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    public func list() throws -> [RateCard] {
        try store.withDatabase { db in
            let sql = """
                SELECT model, version, source_url, input_credits_per_m,
                       cached_input_credits_per_m, output_credits_per_m
                FROM rate_cards
                ORDER BY model ASC
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            var cards: [RateCard] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                cards.append(readRateCard(from: statement))
            }
            return cards
        }
    }

    public func manager() throws -> RateCardManager {
        RateCardManager(rateCards: try list())
    }

    private func readRateCard(from statement: OpaquePointer?) -> RateCard {
        RateCard(
            model: columnText(statement, index: 0) ?? "",
            version: columnText(statement, index: 1) ?? "",
            sourceURL: columnText(statement, index: 2).flatMap(URL.init(string:)),
            inputCreditsPerM: sqlite3_column_double(statement, 3),
            cachedInputCreditsPerM: sqlite3_column_double(statement, 4),
            outputCreditsPerM: sqlite3_column_double(statement, 5)
        )
    }
}

private func bindText(_ statement: OpaquePointer?, index: Int32, value: String) {
    sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
}

private func bindOptionalText(_ statement: OpaquePointer?, index: Int32, value: String?) {
    if let value {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    } else {
        sqlite3_bind_null(statement, index)
    }
}

private func bindDouble(_ statement: OpaquePointer?, index: Int32, value: Double) {
    sqlite3_bind_double(statement, index, value)
}

private func columnText(_ statement: OpaquePointer?, index: Int32) -> String? {
    guard let text = sqlite3_column_text(statement, index) else {
        return nil
    }
    return String(cString: text)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
