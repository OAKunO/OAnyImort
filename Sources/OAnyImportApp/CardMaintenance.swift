import Foundation
import OAnyImportCore

struct ImportCard: Identifiable {
    let source: SourceVolume
    let volumeUUID: String
    var id: String { source.id }
}

enum CardMaintenance {
    private static func diskInfo(_ path: String) throws -> [String: Any] {
        let result = try run(["info", "-plist", path])
        guard let info = try PropertyListSerialization.propertyList(from: result, format: nil) as? [String: Any] else { throw Failure.invalidDevice }
        return info
    }

    static func format(_ card: ImportCard, destination: URL) throws {
        let info = try diskInfo(card.source.url.path)
        guard (info["VolumeUUID"] as? String)?.caseInsensitiveCompare(card.volumeUUID) == .orderedSame,
              info["MountPoint"] as? String == card.source.url.path,
              info["RemovableMediaOrExternalDevice"] as? Bool == true,
              info["Ejectable"] as? Bool == true,
              info["OSInternalMedia"] as? Bool == false,
              let wholeDisk = info["ParentWholeDisk"] as? String,
              wholeDisk.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else { throw Failure.invalidDevice }
        var existing = destination.resolvingSymlinksInPath()
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" { existing.deleteLastPathComponent() }
        guard let destinationVolume = try existing.resourceValues(forKeys: [.volumeURLKey]).volume else { throw Failure.destinationOnCard }
        let destinationInfo = try diskInfo(destinationVolume.path)
        guard let targetDisk = destinationInfo["ParentWholeDisk"] as? String, targetDisk != wholeDisk else { throw Failure.destinationOnCard }
        // Check the volume again immediately before launching the erase operation.
        let latest = try diskInfo(card.source.url.path)
        guard (latest["VolumeUUID"] as? String)?.caseInsensitiveCompare(card.volumeUUID) == .orderedSame,
              latest["ParentWholeDisk"] as? String == wholeDisk,
              latest["MountPoint"] as? String == card.source.url.path else { throw Failure.invalidDevice }
        _ = try run(["eraseDisk", "ExFAT", "OANYIMPORT", "MBRFormat", wholeDisk])
    }

    private static func run(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.diskUtility(String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "操作失败")
        }
        return data
    }

    enum Failure: LocalizedError {
        case invalidDevice, destinationOnCard, diskUtility(String)
        var errorDescription: String? {
            switch self {
            case .invalidDevice: return "无法确认内存卡身份，或卡已更换。请重新导入后再试。"
            case .destinationOnCard: return "保存位置与内存卡位于同一磁盘，无法格式化。"
            case .diskUtility(let message): return "磁盘工具操作失败：\(message)"
            }
        }
    }
}
