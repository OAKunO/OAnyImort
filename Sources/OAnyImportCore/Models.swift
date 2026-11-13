import Foundation

public enum MediaKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case video, photo, raw, audio, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .video: return "视频"
        case .photo: return "图片"
        case .raw: return "RAW 照片"
        case .audio: return "音频"
        case .other: return "其他文件"
        }
    }
    public var symbol: String {
        switch self {
        case .video: return "play.rectangle"
        case .photo: return "photo"
        case .raw: return "camera.aperture"
        case .audio: return "waveform"
        case .other: return "doc"
        }
    }
    public static func classify(_ ext: String) -> MediaKind {
        let ext = ext.lowercased()
        if Set(["mp4", "mov", "mts", "m2ts", "avi", "mkv", "wmv", "webm", "m4v", "3gp", "mpg", "mpeg", "flv", "f4v", "rmvb", "rm", "mxf", "braw", "r3d", "insv"]).contains(ext) { return .video }
        if Set(["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "avif", "insp"]).contains(ext) { return .photo }
        if Set(["raw", "cr2", "cr3", "nef", "nrw", "arw", "dng", "rw2", "orf", "raf", "x3f", "pef", "srw"]).contains(ext) { return .raw }
        if Set(["wav", "mp3", "m4a", "aac", "aif", "aiff", "flac", "ogg", "opus", "wma"]).contains(ext) { return .audio }
        return .other
    }
}

public struct SourceVolume: Identifiable, Hashable, Sendable {
    public let url: URL
    public var name: String
    public var capacity: Int64
    public var available: Int64
    public var isFolder: Bool
    public var id: String { url.standardizedFileURL.path }
    public init(url: URL, name: String, capacity: Int64 = 0, available: Int64 = 0, isFolder: Bool = false) {
        self.url = url.standardizedFileURL
        self.name = name
        self.capacity = capacity
        self.available = available
        self.isFolder = isFolder
    }
}

public struct MediaFile: Identifiable, Hashable, Sendable {
    public let url: URL
    public let sourceID: String
    public let sourceName: String
    public let relativePath: String
    public let bytes: Int64
    public let modifiedAt: Date
    public let createdAt: Date?
    public var id: String { url.path }
    public var kind: MediaKind { MediaKind.classify(url.pathExtension) }
    public var fileExtension: String { url.pathExtension.lowercased() }
    public init(url: URL, source: SourceVolume, relativePath: String, bytes: Int64, modifiedAt: Date, createdAt: Date? = nil) {
        self.url = url
        self.sourceID = source.id
        self.sourceName = source.name
        self.relativePath = relativePath
        self.bytes = bytes
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
    }
}

public struct ScanResult: Sendable {
    public var files: [MediaFile]
    public var warnings: [String]
    public init(files: [MediaFile] = [], warnings: [String] = []) { self.files = files; self.warnings = warnings }
}

public enum FolderLayout: String, CaseIterable, Identifiable, Sendable {
    case typeDate, dateType, original
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .typeDate: return "类型 / 日期"
        case .dateType: return "日期 / 类型"
        case .original: return "保留原目录"
        }
    }
}

public struct ImportPlan: Sendable {
    public var files: [MediaFile]
    public var destination: URL
    public var layout: FolderLayout
    public var separateCards: Bool
    public var verify: Bool
    public init(files: [MediaFile], destination: URL, layout: FolderLayout = .typeDate, separateCards: Bool = false, verify: Bool = true) {
        self.files = files; self.destination = destination; self.layout = layout
        self.separateCards = separateCards; self.verify = verify
    }
}

public enum FileOutcome: String, Codable, Sendable { case copied, skipped, failed }

public struct ImportRecord: Codable, Sendable {
    public var source: String
    public var destination: String?
    public var outcome: FileOutcome
    public var message: String?
    public init(source: String, destination: String?, outcome: FileOutcome, message: String? = nil) {
        self.source = source; self.destination = destination; self.outcome = outcome; self.message = message
    }
}

public struct ImportReport: Codable, Sendable {
    public var startedAt: Date = Date()
    public var finishedAt: Date?
    public var records: [ImportRecord] = []
    public var cancelled = false
    public var copied: Int { records.filter { $0.outcome == .copied }.count }
    public var skipped: Int { records.filter { $0.outcome == .skipped }.count }
    public var failed: Int { records.filter { $0.outcome == .failed }.count }
    public init() {}
}

public struct ImportProgress: Sendable {
    public var completedFiles: Int
    public var totalFiles: Int
    public var completedBytes: Int64
    public var totalBytes: Int64
    public var currentFile: String
    public var sourceID: String
    public var phase: String
    public var fraction: Double {
        totalBytes > 0 ? min(1, Double(completedBytes) / Double(totalBytes)) : Double(completedFiles) / Double(max(1, totalFiles))
    }
}

public enum ImportError: LocalizedError {
    case invalidDestination, insufficientSpace, verificationFailed, sourceChanged, unsafeRelativePath
    public var errorDescription: String? {
        switch self {
        case .invalidDestination: return "保存位置不能位于选中的来源目录内，请选择电脑或另一块磁盘。"
        case .insufficientSpace: return "目标磁盘的可用空间不足，请更换保存位置。"
        case .verificationFailed: return "文件校验未通过，未保留这份不完整的副本。"
        case .sourceChanged: return "来源文件已发生变化，请重新扫描后再导入。"
        case .unsafeRelativePath: return "文件的相对路径无效。"
        }
    }
}
