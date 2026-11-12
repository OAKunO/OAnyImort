import Foundation

public enum FileScanner {
    public static func scan(_ source: SourceVolume) throws -> ScanResult {
        let fm = FileManager.default
        let scanRoot = source.url.resolvingSymlinksInPath().standardizedFileURL
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        var result = ScanResult()
        guard let enumerator = fm.enumerator(at: scanRoot, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in
            result.warnings.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            return true
        }) else { throw CocoaError(.fileReadNoPermission) }
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            do {
                let values = try url.resourceValues(forKeys: keys)
                guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
                let normalized = url.resolvingSymlinksInPath().standardizedFileURL
                guard normalized.path.hasPrefix(scanRoot.path + "/") else { continue }
                let relative = String(normalized.path.dropFirst(scanRoot.path.count + 1))
                result.files.append(MediaFile(url: normalized, source: source, relativePath: relative, bytes: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate ?? Date(), createdAt: values.creationDate))
            } catch { result.warnings.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
        }
        result.files.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        return result
    }
}
