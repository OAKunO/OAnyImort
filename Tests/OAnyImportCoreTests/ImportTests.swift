import XCTest
@testable import OAnyImportCore

final class ImportTests: XCTestCase {
    var root: URL!
    var source: SourceVolume!
    var destination: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("OAnyImportTests-\(UUID())")
        let sourceURL = root.appendingPathComponent("card")
        destination = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        source = SourceVolume(url: sourceURL, name: "CAMERA")
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    @discardableResult
    func fixture(_ path: String, data: Data = Data("a memory worth keeping".utf8), source other: SourceVolume? = nil) throws -> URL {
        let url = (other ?? source).url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }
    func plan(_ files: [MediaFile], layout: FolderLayout = .original, separateCards: Bool = false) -> ImportPlan {
        ImportPlan(files: files, destination: destination, layout: layout, separateCards: separateCards)
    }

    func testScannerSkipsHiddenFilesAndSymlinksButKeepsUnknownFormats() throws {
        try fixture("DCIM/100/one.JPG")
        try fixture("DCIM/two.MP4")
        try fixture("sidecar.XML")
        try fixture("README")
        try fixture(".hidden.JPG")
        try fixture(".cache/hidden.MP4")
        try FileManager.default.createSymbolicLink(at: source.url.appendingPathComponent("linked.JPG"), withDestinationURL: source.url.appendingPathComponent("DCIM/100/one.JPG"))
        let scan = try FileScanner.scan(source)
        XCTAssertEqual(scan.files.count, 4)
        XCTAssertEqual(Set(scan.files.map(\.kind)), [.photo, .video, .other])
        XCTAssertTrue(scan.files.contains { $0.relativePath == "DCIM/100/one.JPG" })
    }

    func testClassificationSeparatesRawAndAudio() {
        XCTAssertEqual(MediaKind.classify("ARW"), .raw)
        XCTAssertEqual(MediaKind.classify("heic"), .photo)
        XCTAssertEqual(MediaKind.classify("MXF"), .video)
        XCTAssertEqual(MediaKind.classify("wav"), .audio)
        XCTAssertEqual(MediaKind.classify("srt"), .other)
    }

    func testVerifiedCopyPreservesSourceAndOriginalLayout() async throws {
        let original = try fixture("DCIM/100/one.jpg")
        let files = try FileScanner.scan(source).files
        let report = try await ImportEngine().run(plan(files)) { _ in }
        XCTAssertEqual(report.copied, 1); XCTAssertEqual(report.failed, 0)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("DCIM/100/one.jpg")), try Data(contentsOf: original))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(report.records.first?.outcome, .copied)
    }

    func testCleanupDeletesOnlyFilesWithMatchingCopies() async throws {
        let card = SourceVolume(url: source.url.resolvingSymlinksInPath(), name: source.name)
        let good = try fixture("good.jpg", data: Data("good".utf8), source: card)
        let changed = try fixture("changed.jpg", data: Data("same".utf8), source: card)
        let unimported = try fixture("unimported.jpg", data: Data("left".utf8), source: card)
        let files = try FileScanner.scan(card).files.filter { $0.url != unimported }
        let report = try await ImportEngine().run(plan(files)) { _ in }
        try Data("else".utf8).write(to: destination.appendingPathComponent("changed.jpg"))
        let uuid = try XCTUnwrap(card.url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString)
        let result = VerifiedCleanup.run(files: files, records: report.records, sourceRoot: card.url, expectedVolumeUUID: uuid)
        XCTAssertEqual(result.deleted, 1)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: good.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: changed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unimported.path))
    }

    func testCleanupRejectsChangedVolume() async throws {
        let card = SourceVolume(url: source.url.resolvingSymlinksInPath(), name: source.name)
        let original = try fixture("one.jpg", source: card)
        let files = try FileScanner.scan(card).files
        let report = try await ImportEngine().run(plan(files)) { _ in }
        let result = VerifiedCleanup.run(files: files, records: report.records, sourceRoot: card.url, expectedVolumeUUID: "wrong-volume")
        XCTAssertEqual(result.deleted, 0)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testRepeatImportSkipsIdenticalContent() async throws {
        try fixture("one.jpg")
        let files = try FileScanner.scan(source).files
        _ = try await ImportEngine().run(plan(files)) { _ in }
        let report = try await ImportEngine().run(plan(files)) { _ in }
        XCTAssertEqual(report.skipped, 1); XCTAssertEqual(report.copied, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("one_1.jpg").path))
    }

    func testSameNameDifferentContentNeverOverwrites() async throws {
        try fixture("one.jpg", data: Data("fresh content".utf8))
        let existing = destination.appendingPathComponent("one.jpg")
        try Data("prior content".utf8).write(to: existing)
        let files = try FileScanner.scan(source).files
        let report = try await ImportEngine().run(plan(files)) { _ in }
        XCTAssertEqual(report.copied, 1)
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "prior content")
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("one_1.jpg"), encoding: .utf8), "fresh content")
        let repeatReport = try await ImportEngine().run(plan(files)) { _ in }
        XCTAssertEqual(repeatReport.skipped, 1)
    }

    func testMultipleCardsWithSameNameRemainSeparate() async throws {
        let second = SourceVolume(url: root.appendingPathComponent("card2"), name: source.name)
        try fixture("one.jpg", data: Data("first".utf8))
        try fixture("one.jpg", data: Data("second".utf8), source: second)
        let files = try FileScanner.scan(source).files + FileScanner.scan(second).files
        let report = try await ImportEngine().run(plan(files, separateCards: true)) { _ in }
        XCTAssertEqual(report.copied, 2)
        XCTAssertEqual(Set(report.records.compactMap(\.destination)).count, 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).count, 2)
    }

    func testDestinationInsideSourceIsRejected() throws {
        try fixture("one.jpg")
        var importPlan = plan(try FileScanner.scan(source).files)
        importPlan.destination = source.url.appendingPathComponent("output")
        XCTAssertThrowsError(try ImportEngine.validate(importPlan))
    }

    func testDestinationSymlinkIntoSourceIsRejected() throws {
        try fixture("one.jpg")
        let link = root.appendingPathComponent("source-alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source.url)
        var importPlan = plan(try FileScanner.scan(source).files)
        importPlan.destination = link
        XCTAssertThrowsError(try ImportEngine.validate(importPlan))
    }

    func testFolderTraversalIsRejected() async throws {
        let url = try fixture("one.jpg")
        let file = MediaFile(url: url, source: source, relativePath: "../escape.jpg", bytes: Int64(try Data(contentsOf: url).count), modifiedAt: try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!)
        let report = try await ImportEngine().run(plan([file])) { _ in }
        XCTAssertEqual(report.failed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.jpg").path))
    }

    func testExistingFolderSymlinkCannotEscapeDestination() async throws {
        try fixture("DCIM/one.jpg")
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: destination.appendingPathComponent("DCIM"), withDestinationURL: outside)
        let report = try await ImportEngine().run(plan(try FileScanner.scan(source).files)) { _ in }
        XCTAssertEqual(report.failed, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path).count, 0)
    }

    func testChangedSourceIsReportedAsFailure() async throws {
        let url = try fixture("one.jpg")
        let files = try FileScanner.scan(source).files
        try Data("changed and significantly longer".utf8).write(to: url)
        let report = try await ImportEngine().run(plan(files)) { _ in }
        XCTAssertEqual(report.failed, 1); XCTAssertEqual(report.copied, 0)
    }

    func testFilenameDateGrouping() async throws {
        try fixture("DJI_20260610093000.txt")
        let report = try await ImportEngine().run(plan(try FileScanner.scan(source).files, layout: .typeDate)) { _ in }
        XCTAssertEqual(report.copied, 1)
        XCTAssertTrue(report.records.first?.destination?.contains("/其他文件/2026-06-10/") == true)
    }

    func testCancellationCleansPartialFileAndPreservesSource() async throws {
        let original = try fixture("large.bin", data: Data(repeating: 42, count: 12 * 1024 * 1024))
        let files = try FileScanner.scan(source).files
        let importPlan = plan(files)
        let report = try await ImportEngine().run(importPlan) { progress in
            if progress.phase == "正在复制" { withUnsafeCurrentTask { $0?.cancel() } }
        }
        XCTAssertTrue(report.cancelled)
        XCTAssertEqual(report.copied, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).count, 0)
    }

    func testFailedVerificationRemovesStagingFile() async throws {
        try fixture("one.jpg")
        let importPlan = plan(try FileScanner.scan(source).files)
        let output = destination!
        let report = try await ImportEngine().run(importPlan) { progress in
            if progress.phase == "校验 SHA-256" {
                if let temporary = try? FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "part" }) {
                    try? Data("corrupted".utf8).write(to: temporary)
                }
            }
        }
        XCTAssertEqual(report.failed, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).count, 0)
    }
}
