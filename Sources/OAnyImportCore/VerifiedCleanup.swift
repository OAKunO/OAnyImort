import Foundation
import CryptoKit

public struct CleanupResult: Sendable {
    public var deleted: Int = 0
    public var errors: [String] = []
    public init() {}
}

public enum VerifiedCleanup {
    /// Deletes only recorded copies that still match both the scanned source and the destination.
    public static func run(files: [MediaFile], records: [ImportRecord], sourceRoot: URL, expectedVolumeUUID: String) -> CleanupResult {
        var result = CleanupResult()
        let fm = FileManager.default
        let root = sourceRoot.resolvingSymlinksInPath().standardizedFileURL
        let eligible = Dictionary(records.filter { $0.outcome != .failed && $0.destination != nil }.map { ($0.source, $0) }, uniquingKeysWith: { _, last in last })
        for file in files where file.sourceID == sourceRoot.standardizedFileURL.path {
            guard let record = eligible[file.url.path], let destinationPath = record.destination else { continue }
            do {
                let uuid = try sourceRoot.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
                guard uuid == expectedVolumeUUID else { throw CleanupError.changedVolume }
                let original = file.url.standardizedFileURL
                let resolved = original.resolvingSymlinksInPath().standardizedFileURL
                guard resolved.path == original.path, resolved.path.hasPrefix(root.path + "/") else { throw CleanupError.unsafePath }
                let destination = URL(fileURLWithPath: destinationPath).resolvingSymlinksInPath().standardizedFileURL
                guard !destination.path.hasPrefix(root.path + "/"), destination.path != root.path else { throw CleanupError.unsafePath }
                let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
                let before = try original.resourceValues(forKeys: keys)
                let target = try destination.resourceValues(forKeys: keys)
                guard before.isRegularFile == true, before.isSymbolicLink != true,
                      target.isRegularFile == true, target.isSymbolicLink != true,
                      Int64(before.fileSize ?? -1) == file.bytes,
                      abs((before.contentModificationDate ?? .distantPast).timeIntervalSince(file.modifiedAt)) < 1,
                      before.fileSize == target.fileSize else { throw CleanupError.changedFile }
                guard try digest(original) == digest(destination) else { throw CleanupError.changedFile }
                let after = try URL(fileURLWithPath: original.path).resourceValues(forKeys: keys)
                let targetAfter = try URL(fileURLWithPath: destination.path).resourceValues(forKeys: keys)
                guard after.fileSize == before.fileSize, after.contentModificationDate == before.contentModificationDate,
                      targetAfter.fileSize == target.fileSize, targetAfter.contentModificationDate == target.contentModificationDate,
                      URL(fileURLWithPath: destinationPath).resolvingSymlinksInPath().standardizedFileURL == destination,
                      URL(fileURLWithPath: original.path).resolvingSymlinksInPath().standardizedFileURL == original,
                      try URL(fileURLWithPath: sourceRoot.path).resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString == expectedVolumeUUID else { throw CleanupError.changedFile }
                try fm.removeItem(at: original)
                result.deleted += 1
            } catch {
                result.errors.append("\(file.url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        return result
    }

    private static func digest(_ url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize()
    }

    private enum CleanupError: LocalizedError {
        case changedVolume, changedFile, unsafePath
        var errorDescription: String? {
            switch self {
            case .changedVolume: return "来源卡已更换或无法确认身份"
            case .changedFile: return "文件或电脑副本已变化，未删除"
            case .unsafePath: return "文件路径不安全，未删除"
            }
        }
    }
}
