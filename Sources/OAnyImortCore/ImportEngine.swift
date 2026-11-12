import Foundation
import CryptoKit
import ImageIO
import AVFoundation

public actor ImportEngine {
    private let fm = FileManager.default
    private let chunkSize = 4 * 1024 * 1024
    public init() {}

    public static func validate(_ plan: ImportPlan) throws {
        let destination = plan.destination.resolvingSymlinksInPath().standardizedFileURL.path
        for source in Set(plan.files.map(\.sourceID)) {
            let root = URL(fileURLWithPath: source).resolvingSymlinksInPath().standardizedFileURL.path
            if destination == root || destination.hasPrefix(root + "/") { throw ImportError.invalidDestination }
        }
        var existingParent = plan.destination
        while !FileManager.default.fileExists(atPath: existingParent.path), existingParent.path != "/" { existingParent.deleteLastPathComponent() }
        if let available = try? existingParent.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity,
           Int64(available) < plan.files.reduce(Int64(0), { $0 + $1.bytes }) {
            throw ImportError.insufficientSpace
        }
    }

    public func run(_ plan: ImportPlan, onProgress: @escaping @Sendable (ImportProgress) async -> Void) async throws -> ImportReport {
        try Self.validate(plan)
        var report = ImportReport()
        let totalBytes = plan.files.reduce(Int64(0)) { $0 + $1.bytes }
        var settledBytes: Int64 = 0
        let root = plan.destination.resolvingSymlinksInPath().standardizedFileURL
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for file in plan.files {
            if Task.isCancelled { report.cancelled = true; break }
            var staging: URL?
            let completedCount = report.records.count
            let priorBytes = settledBytes
            func publish(_ bytes: Int64, _ phase: String) async {
                await onProgress(ImportProgress(completedFiles: completedCount, totalFiles: plan.files.count, completedBytes: priorBytes + bytes, totalBytes: totalBytes, currentFile: file.url.lastPathComponent, sourceID: file.sourceID, phase: phase))
            }
            do {
                await publish(0, "准备文件")
                let initial = try file.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                guard Int64(initial.fileSize ?? -1) == file.bytes,
                      abs((initial.contentModificationDate ?? file.modifiedAt).timeIntervalSince(file.modifiedAt)) < 1 else { throw ImportError.sourceChanged }
                let folder = try await outputFolder(file, root: root, plan: plan)
                try ensureInside(folder, root: root)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let choice = try await chooseDestination(file, in: folder, progress: { await publish(0, "检查重复") })
                if choice.duplicate {
                    report.records.append(ImportRecord(source: file.url.path, destination: choice.url.path, outcome: .skipped, message: "内容相同，已跳过"))
                } else {
                    let temporary = folder.appendingPathComponent(".oanyimort-\(UUID().uuidString).part")
                    staging = temporary
                    let sourceHash = try await copy(file, to: temporary) { bytes in await publish(bytes, "正在复制") }
                    if plan.verify {
                        await publish(file.bytes, "校验 SHA-256")
                        let targetHash = try digest(temporary)
                        guard sourceHash == targetHash else { throw ImportError.verificationFailed }
                    }
                    let finalValues = try file.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    guard finalValues.fileSize == initial.fileSize, finalValues.contentModificationDate == initial.contentModificationDate else { throw ImportError.sourceChanged }
                    try Task.checkCancellation()
                    // moveItem refuses an existing target, so concurrent external writes cannot be overwritten.
                    try fm.moveItem(at: temporary, to: choice.url)
                    staging = nil
                    var attributes: [FileAttributeKey: Any] = [.modificationDate: file.modifiedAt]
                    if let date = file.createdAt { attributes[.creationDate] = date }
                    try? fm.setAttributes(attributes, ofItemAtPath: choice.url.path)
                    report.records.append(ImportRecord(source: file.url.path, destination: choice.url.path, outcome: .copied))
                }
            } catch is CancellationError {
                if let staging { try? fm.removeItem(at: staging) }
                report.cancelled = true
                break
            } catch {
                if let staging { try? fm.removeItem(at: staging) }
                report.records.append(ImportRecord(source: file.url.path, destination: nil, outcome: .failed, message: error.localizedDescription))
            }
            settledBytes += file.bytes
            await onProgress(ImportProgress(completedFiles: report.records.count, totalFiles: plan.files.count, completedBytes: settledBytes, totalBytes: totalBytes, currentFile: file.url.lastPathComponent, sourceID: file.sourceID, phase: "已处理"))
        }
        report.finishedAt = Date()
        return report
    }

    private func ensureInside(_ url: URL, root: URL) throws {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved == root.path || resolved.hasPrefix(root.path + "/") else { throw ImportError.unsafeRelativePath }
    }

    private func outputFolder(_ file: MediaFile, root: URL, plan: ImportPlan) async throws -> URL {
        var folder = root
        if plan.separateCards {
            var name = Self.safeName(file.sourceName)
            let sameNames = Set(plan.files.filter { $0.sourceName == file.sourceName }.map(\.sourceID))
            if sameNames.count > 1 {
                name += "-" + SHA256.hash(data: Data(file.sourceID.utf8)).prefix(3).map { String(format: "%02x", $0) }.joined()
            }
            folder.appendPathComponent(name, isDirectory: true)
        }
        if plan.layout == .original {
            let components = file.relativePath.split(separator: "/", omittingEmptySubsequences: false)
            guard !file.relativePath.hasPrefix("/"), !components.contains(".."), !components.contains("."), !components.contains("") else { throw ImportError.unsafeRelativePath }
            for part in components.dropLast() { folder.appendPathComponent(String(part), isDirectory: true) }
            return folder
        }
        let date = await captureDate(file)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        let components = plan.layout == .typeDate ? [file.kind.title, day] : [day, file.kind.title]
        for part in components { folder.appendPathComponent(part, isDirectory: true) }
        return folder
    }

    public static func safeName(_ name: String) -> String {
        let result = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty || result == "." || result == ".." ? "SD 卡" : result
    }

    private func captureDate(_ file: MediaFile) async -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.isLenient = false
        if file.kind == .photo || file.kind == .raw,
           let image = CGImageSourceCreateWithURL(file.url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
           let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
           let date = formatter.date(from: text) { return date }
        if file.kind == .video {
            let asset = AVURLAsset(url: file.url)
            if let metadata = try? await asset.load(.commonMetadata) {
                for item in metadata where item.commonKey == .commonKeyCreationDate {
                    if let date = try? await item.load(.dateValue) { return date }
                    if let text = try? await item.load(.stringValue), let date = ISO8601DateFormatter().date(from: text) { return date }
                }
            }
        }
        if let range = file.url.lastPathComponent.range(of: #"(?<!\d)(?:19|20)\d{2}[-_]?[01]\d[-_]?[0-3]\d(?!\d)|(?:19|20)\d{6}(?=\d{6})"#, options: .regularExpression) {
            let text = String(file.url.lastPathComponent[range]).filter(\.isNumber)
            formatter.dateFormat = "yyyyMMdd"
            if let date = formatter.date(from: text), formatter.string(from: date) == text { return date }
        }
        return file.createdAt ?? file.modifiedAt
    }

    private func chooseDestination(_ file: MediaFile, in folder: URL, progress: () async -> Void) async throws -> (url: URL, duplicate: Bool) {
        let name = file.url.deletingPathExtension().lastPathComponent
        let ext = file.url.pathExtension
        var index = 0
        var sourceHash: SHA256.Digest?
        while true {
            try Task.checkCancellation()
            let filename = index == 0 ? file.url.lastPathComponent : name + "_\(index)" + (ext.isEmpty ? "" : "." + ext)
            let candidate = folder.appendingPathComponent(filename)
            if !fm.fileExists(atPath: candidate.path) { return (candidate, false) }
            let values = try candidate.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            if values.isRegularFile == true, values.isSymbolicLink != true, Int64(values.fileSize ?? -1) == file.bytes {
                await progress()
                if sourceHash == nil { sourceHash = try digest(file.url) }
                if try digest(candidate) == sourceHash { return (candidate, true) }
            }
            index += 1
        }
    }

    private func digest(_ url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: chunkSize), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize()
    }

    private func copy(_ file: MediaFile, to destination: URL, onBytes: (Int64) async -> Void) async throws -> SHA256.Digest {
        guard fm.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let input = try FileHandle(forReadingFrom: file.url)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var hash = SHA256()
        var copied: Int64 = 0
        var lastUpdate = Date.distantPast
        while let data = try input.read(upToCount: chunkSize), !data.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: data)
            hash.update(data: data)
            copied += Int64(data.count)
            if Date().timeIntervalSince(lastUpdate) > 0.12 {
                await onBytes(copied)
                lastUpdate = Date()
            }
        }
        try output.synchronize()
        guard copied == file.bytes else { throw ImportError.sourceChanged }
        await onBytes(copied)
        return hash.finalize()
    }
}
