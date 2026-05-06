import CodexQuotaCore
import CodexQuotaStorage
import Darwin
import Foundation

public struct LocalJSONLCollector: CollectorAdapter {
    public let sourceName = "local_jsonl"
    public var rootDirectory: URL
    public var rolloutPaths: [URL]
    public var accountAlias: String
    public var usageEventRepository: SQLiteUsageEventRepository?
    public var snapshotRepository: SQLiteSnapshotRepository?
    public var offsetRepository: SQLiteCollectorOffsetRepository?

    public init(
        rootDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex"),
        rolloutPaths: [URL] = [],
        accountAlias: String = "本机 Codex",
        usageEventRepository: SQLiteUsageEventRepository? = nil,
        snapshotRepository: SQLiteSnapshotRepository? = nil,
        offsetRepository: SQLiteCollectorOffsetRepository? = nil
    ) {
        self.rootDirectory = rootDirectory
        self.rolloutPaths = rolloutPaths
        self.accountAlias = accountAlias
        self.usageEventRepository = usageEventRepository
        self.snapshotRepository = snapshotRepository
        self.offsetRepository = offsetRepository
    }

    public func collect() async throws -> CollectorResult {
        let files = discoverJSONLFiles()
        let normalizer = CodexEventNormalizer(accountAlias: accountAlias)

        var usageEvents: [UsageEvent] = []
        var snapshots: [QuotaSnapshot] = []
        var usageEventsImported = 0
        var snapshotsImported = 0
        var parseFailures = 0

        for fileURL in files {
            let fileID = Self.fileID(for: fileURL)
            let metadata = try fileMetadata(for: fileURL)
            let storedOffset = try offsetRepository?.offset(for: fileID)
            let startOffset = startOffset(for: storedOffset, metadata: metadata)
            let parsed = try parseFile(
                fileURL,
                startOffset: startOffset,
                normalizer: normalizer
            )

            for event in parsed.usageEvents {
                try usageEventRepository?.save(event)
                usageEventsImported += 1
            }
            for snapshot in parsed.snapshots {
                try snapshotRepository?.save(snapshot)
                snapshotsImported += 1
            }

            usageEvents.append(contentsOf: parsed.usageEvents)
            snapshots.append(contentsOf: parsed.snapshots)
            parseFailures += parsed.parseFailures

            try offsetRepository?.upsert(
                CollectorOffset(
                    fileID: fileID,
                    path: fileURL.path,
                    lastOffset: parsed.nextOffset,
                    lastInode: metadata.inode,
                    lastSeenAt: Date()
                )
            )
        }

        return CollectorResult(
            usageEventsImported: usageEventRepository == nil ? usageEvents.count : usageEventsImported,
            snapshotsImported: snapshotRepository == nil ? snapshots.count : snapshotsImported,
            filesScanned: files.count,
            parseFailures: parseFailures,
            usageEvents: usageEvents,
            snapshots: snapshots
        )
    }

    public static func fileID(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func discoverJSONLFiles() -> [URL] {
        var paths = Set(rolloutPaths.map { $0.standardizedFileURL.path })

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootDirectory.path, isDirectory: &isDirectory) else {
            return sortedJSONLURLs(from: paths)
        }

        if !isDirectory.boolValue {
            paths.insert(rootDirectory.standardizedFileURL.path)
            return sortedJSONLURLs(from: paths)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return sortedJSONLURLs(from: paths)
        }

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            paths.insert(fileURL.standardizedFileURL.path)
        }
        return sortedJSONLURLs(from: paths)
    }

    private func sortedJSONLURLs(from paths: Set<String>) -> [URL] {
        paths
            .filter { $0.hasSuffix(".jsonl") }
            .sorted()
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func startOffset(for storedOffset: CollectorOffset?, metadata: FileMetadata) -> UInt64 {
        guard let storedOffset else {
            return 0
        }
        if let storedInode = storedOffset.lastInode, storedInode != metadata.inode {
            return 0
        }
        if metadata.size < storedOffset.lastOffset {
            return 0
        }
        return storedOffset.lastOffset
    }

    private func fileMetadata(for url: URL) throws -> FileMetadata {
        var statBuffer = stat()
        guard lstat(url.path, &statBuffer) == 0 else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return FileMetadata(
            inode: UInt64(statBuffer.st_ino),
            size: UInt64(statBuffer.st_size)
        )
    }

    private func parseFile(
        _ fileURL: URL,
        startOffset: UInt64,
        normalizer: CodexEventNormalizer
    ) throws -> ParsedFileResult {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        try handle.seek(toOffset: startOffset)
        let data = try handle.readToEnd() ?? Data()
        guard !data.isEmpty else {
            return ParsedFileResult(nextOffset: startOffset)
        }

        var usageEvents: [UsageEvent] = []
        var snapshots: [QuotaSnapshot] = []
        var parseFailures = 0
        var lineStartIndex = data.startIndex
        var cursor = data.startIndex
        var lineOffset = startOffset
        var committedOffset = startOffset

        while cursor < data.endIndex {
            if data[cursor] == newlineByte {
                let lineData = Data(data[lineStartIndex..<cursor])
                let lineLength = UInt64(lineData.count)
                parseLine(
                    lineData,
                    lineOffset: lineOffset,
                    fileURL: fileURL,
                    normalizer: normalizer,
                    usageEvents: &usageEvents,
                    snapshots: &snapshots,
                    parseFailures: &parseFailures
                )
                committedOffset = lineOffset + lineLength + 1
                cursor = data.index(after: cursor)
                lineStartIndex = cursor
                lineOffset = committedOffset
            } else {
                cursor = data.index(after: cursor)
            }
        }

        if lineStartIndex < data.endIndex {
            let lineData = Data(data[lineStartIndex..<data.endIndex])
            let failureCountBefore = parseFailures
            parseLine(
                lineData,
                lineOffset: lineOffset,
                fileURL: fileURL,
                normalizer: normalizer,
                usageEvents: &usageEvents,
                snapshots: &snapshots,
                parseFailures: &parseFailures
            )
            if parseFailures == failureCountBefore {
                committedOffset = lineOffset + UInt64(lineData.count)
            }
        }

        return ParsedFileResult(
            usageEvents: usageEvents,
            snapshots: snapshots,
            nextOffset: committedOffset,
            parseFailures: parseFailures
        )
    }

    private func parseLine(
        _ lineData: Data,
        lineOffset: UInt64,
        fileURL: URL,
        normalizer: CodexEventNormalizer,
        usageEvents: inout [UsageEvent],
        snapshots: inout [QuotaSnapshot],
        parseFailures: inout Int
    ) {
        guard !lineData.isEmpty else {
            return
        }

        do {
            guard let normalized = try normalizer.normalizeJSONLine(
                lineData,
                sourceURL: fileURL,
                lineOffset: lineOffset
            ) else {
                return
            }
            if let usageEvent = normalized.usageEvent {
                usageEvents.append(usageEvent)
            }
            if let snapshot = normalized.snapshot {
                snapshots.append(snapshot)
            }
        } catch {
            parseFailures += 1
        }
    }
}

private struct FileMetadata {
    var inode: UInt64
    var size: UInt64
}

private struct ParsedFileResult {
    var usageEvents: [UsageEvent] = []
    var snapshots: [QuotaSnapshot] = []
    var nextOffset: UInt64
    var parseFailures: Int = 0
}

private let newlineByte = UInt8(ascii: "\n")
