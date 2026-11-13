import AppKit
import Combine
import OAnyImportCore

@MainActor
final class AppModel: ObservableObject {
    @Published var sources: [SourceVolume] = []
    @Published var selectedSources: Set<String> = []
    @Published var scans: [String: ScanResult] = [:]
    @Published var scanning: Set<String> = []
    @Published var selectedKinds: Set<MediaKind> = [.video, .photo, .raw]
    @Published var excludedExtensions: Set<String> = []
    @Published var excludedFiles: Set<String> = []
    @Published var destination: URL
    @Published var layout: FolderLayout { didSet { UserDefaults.standard.set(layout.rawValue, forKey: "layout") } }
    @Published var separateCards: Bool { didSet { UserDefaults.standard.set(separateCards, forKey: "separateCards") } }
    @Published var verify: Bool { didSet { UserDefaults.standard.set(verify, forKey: "verify") } }
    @Published var detailKind: MediaKind?
    @Published var isImporting = false
    @Published var progress: ImportProgress?
    @Published var report: ImportReport?
    @Published var showingReport = false
    @Published var errorMessage: String?
    @Published var currentSourceID: String?
    @Published var detailSourceID: String?
    @Published var maintenanceBusy = false
    @Published var maintenanceMessage: String?
    @Published private(set) var importCards: [ImportCard] = []
    private var scanTasks: [String: Task<Void, Never>] = [:]
    private var importTask: Task<Void, Never>?
    private var activePlan: ImportPlan?
    private var observers: Set<AnyCancellable> = []
    private var folders: [SourceVolume] = []
    private var activePanel: NSSavePanel?

    init() {
        let defaults = UserDefaults.standard
        PreferencesMigration.migrate(defaults: defaults)
        destination = URL(fileURLWithPath: defaults.string(forKey: "destination") ?? NSHomeDirectory() + "/Documents/视频素材", isDirectory: true)
        layout = FolderLayout(rawValue: defaults.string(forKey: "layout") ?? "") ?? .typeDate
        separateCards = defaults.bool(forKey: "separateCards")
        verify = defaults.object(forKey: "verify") as? Bool ?? true
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name).receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.refreshSources()
            }.store(in: &observers)
        }
        refreshSources()
        if CommandLine.arguments.contains("--demo") { loadDemo() }
    }

    var files: [MediaFile] {
        var seen: Set<String> = []
        return sources.filter { selectedSources.contains($0.id) }.flatMap { scans[$0.id]?.files ?? [] }.filter { seen.insert($0.url.resolvingSymlinksInPath().path).inserted }
    }
    var selectedFiles: [MediaFile] { files.filter(isFileSelected) }
    func isFileSelected(_ file: MediaFile) -> Bool {
        selectedKinds.contains(file.kind) && !excludedExtensions.contains(file.fileExtension) && !excludedFiles.contains(file.id)
    }
    var totalBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.bytes } }
    var isScanning: Bool { !scanning.intersection(selectedSources).isEmpty }
    var canImport: Bool { !isImporting && !isScanning && !selectedFiles.isEmpty && !CommandLine.arguments.contains("--demo") }
    var warnings: [String] { selectedSources.sorted().flatMap { scans[$0]?.warnings ?? [] } }
    var availableBytes: Int64? {
        var url = destination
        while !FileManager.default.fileExists(atPath: url.path), url.path != "/" { url.deleteLastPathComponent() }
        return (try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity).map(Int64.init)
    }
    var insufficientSpace: Bool { availableBytes.map { $0 < totalBytes } ?? false }

    func refreshSources(rescan: Bool = false) {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        let external = volumes.compactMap { url -> SourceVolume? in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.volumeIsRemovable == true || values.volumeIsEjectable == true ||
                    (values.volumeIsInternal != true && url.path.hasPrefix("/Volumes/")) else { return nil }
            return SourceVolume(url: url, name: values.volumeName ?? url.lastPathComponent, capacity: Int64(values.volumeTotalCapacity ?? 0), available: Int64(values.volumeAvailableCapacity ?? 0))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let externalIDs = Set(external.map(\.id))
        sources = external + folders.filter { !externalIDs.contains($0.id) }
        let availableIDs = Set(sources.map(\.id))
        let removed = selectedSources.subtracting(availableIDs)
        selectedSources.formIntersection(availableIDs)
        for id in removed { scanTasks[id]?.cancel(); scans[id] = nil; scanning.remove(id) }
        if rescan {
            for source in sources where selectedSources.contains(source.id) { scan(source) }
        }
    }

    func toggleSource(_ source: SourceVolume) {
        guard !isImporting else { return }
        if selectedSources.contains(source.id) {
            selectedSources.remove(source.id)
        } else {
            selectedSources.insert(source.id)
            if scans[source.id] == nil { scan(source) }
        }
    }

    func selectAllSources() {
        guard !isImporting else { return }
        if selectedSources.count == sources.count { selectedSources.removeAll() }
        else { for source in sources where !selectedSources.contains(source.id) { toggleSource(source) } }
    }

    private func scan(_ source: SourceVolume) {
        scanTasks[source.id]?.cancel()
        scanning.insert(source.id)
        scans[source.id] = nil
        let task = Task.detached(priority: .userInitiated) { () throws -> ScanResult in try FileScanner.scan(source) }
        scanTasks[source.id] = Task { [weak self] in
            do {
                let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                guard !Task.isCancelled else { return }
                self?.scans[source.id] = result
                self?.scanning.remove(source.id)
            } catch {
                guard !Task.isCancelled else { return }
                self?.scanning.remove(source.id)
                self?.errorMessage = "无法读取「\(source.name)」：\(error.localizedDescription)"
            }
        }
    }

    func addFolder() {
        guard !isImporting, activePanel == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "选择存储设备或素材文件夹"
        panel.message = "可以选择存储卡、U 盘、硬盘或电脑上的素材文件夹。"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.prompt = "添加来源"
        present(panel) { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                guard let self else { return }
                for url in panel.urls {
                    let source = SourceVolume(url: url, name: url.lastPathComponent, isFolder: true)
                    if !self.sources.contains(where: { $0.id == source.id }) { self.folders.append(source); self.sources.append(source) }
                    if !self.selectedSources.contains(source.id) { self.toggleSource(source) }
                }
            }
        }
    }

    func chooseDestination() {
        guard !isImporting, activePanel == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "选择素材保存位置"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.directoryURL = destination; panel.prompt = "保存到这里"
        present(panel) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.setDestination(url) }
        }
    }

    func setDestination(_ url: URL) {
        guard !isImporting else { return }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
            errorMessage = "请选择一个文件夹作为保存位置。"; return
        }
        destination = url
        UserDefaults.standard.set(url.path, forKey: "destination")
    }

    func toggleKind(_ kind: MediaKind) {
        if files.contains(where: { $0.kind == kind && isFileSelected($0) }) { selectedKinds.remove(kind) }
        else {
            selectedKinds.insert(kind)
            for file in files where file.kind == kind { excludedExtensions.remove(file.fileExtension); excludedFiles.remove(file.id) }
        }
    }

    func toggleExtension(_ ext: String, kind: MediaKind) {
        if files.contains(where: { $0.kind == kind && $0.fileExtension == ext && isFileSelected($0) }) {
            excludedExtensions.insert(ext)
        } else {
            if !selectedKinds.contains(kind) {
                selectedKinds.insert(kind)
                excludedExtensions.formUnion(files.filter { $0.kind == kind }.map(\.fileExtension))
            }
            excludedExtensions.remove(ext)
            for file in files where file.kind == kind && file.fileExtension == ext { excludedFiles.remove(file.id) }
        }
    }

    func toggleFile(_ file: MediaFile) {
        guard !isImporting else { return }
        if isFileSelected(file) {
            excludedFiles.insert(file.id)
        } else {
            if !selectedKinds.contains(file.kind) {
                excludedFiles.formUnion(files.filter { $0.kind == file.kind }.map(\.id))
                selectedKinds.insert(file.kind)
            }
            if excludedExtensions.contains(file.fileExtension) {
                excludedFiles.formUnion(files.filter { $0.kind == file.kind && $0.fileExtension == file.fileExtension }.map(\.id))
                excludedExtensions.remove(file.fileExtension)
            }
            excludedFiles.remove(file.id)
        }
    }

    func startImport(files retryFiles: [MediaFile]? = nil) {
        guard !isImporting, !maintenanceBusy, activePanel == nil, !CommandLine.arguments.contains("--demo") else { return }
        let plan = ImportPlan(files: retryFiles ?? selectedFiles, destination: destination, layout: layout, separateCards: separateCards, verify: verify)
        guard !plan.files.isEmpty else { return }
        do { try ImportEngine.validate(plan) } catch { errorMessage = error.localizedDescription; return }
        let planSourceIDs = Set(plan.files.map(\.sourceID))
        importCards = sources.filter { !$0.isFolder && planSourceIDs.contains($0.id) }.compactMap { source in
            guard let uuid = try? source.url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString, !uuid.isEmpty else { return nil }
            return ImportCard(source: source, volumeUUID: uuid)
        }
        activePlan = plan; report = nil; progress = nil; isImporting = true; showingReport = false
        importTask = Task { [weak self] in
            do {
                let engine = ImportEngine()
                let result = try await engine.run(plan) { [weak self] progress in
                    await self?.receiveProgress(progress)
                }
                self?.report = result; self?.showingReport = true
            } catch { self?.errorMessage = error.localizedDescription }
            self?.isImporting = false; self?.currentSourceID = nil
        }
    }

    func cancelImport() { importTask?.cancel() }

    func deleteImportedOriginals(on card: ImportCard) {
        guard !maintenanceBusy, let plan = activePlan, let report, !report.cancelled, report.failed == 0,
              importCards.contains(where: { $0.id == card.id && $0.volumeUUID == card.volumeUUID }) else { return }
        maintenanceBusy = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                VerifiedCleanup.run(files: plan.files, records: report.records, sourceRoot: card.source.url, expectedVolumeUUID: card.volumeUUID)
            }.value
            maintenanceBusy = false
            maintenanceMessage = "已删除 \(result.deleted) 个原文件。" + (result.errors.isEmpty ? "" : "\n以下文件未删除：\n" + result.errors.joined(separator: "\n"))
            refreshSources(rescan: true)
        }
    }

    func formatCard(_ card: ImportCard) {
        guard !maintenanceBusy, let plan = activePlan, let report, !report.cancelled, report.failed == 0,
              importCards.contains(where: { $0.id == card.id && $0.volumeUUID == card.volumeUUID }) else { return }
        maintenanceBusy = true
        Task {
            let error = await Task.detached(priority: .userInitiated) { () -> String? in
                do { try CardMaintenance.format(card, destination: plan.destination); return nil }
                catch { return error.localizedDescription }
            }.value
            maintenanceBusy = false
            if let error { maintenanceMessage = error }
            else {
                importCards.removeAll { $0.id == card.id }
                maintenanceMessage = "「\(card.source.name)」已格式化为 ExFAT，名称为 OANYIMPORT。"
            }
            refreshSources(rescan: true)
        }
    }

    private func receiveProgress(_ value: ImportProgress) {
        progress = value; currentSourceID = value.sourceID
    }

    func retryUnfinished() {
        guard let plan = activePlan, let report else { return }
        let completed = Set(report.records.filter { $0.outcome != .failed }.map(\.source))
        // Keep the original destination and options for a partial retry.
        destination = plan.destination; layout = plan.layout; separateCards = plan.separateCards; verify = plan.verify
        startImport(files: plan.files.filter { !completed.contains($0.url.path) })
    }

    func eject(_ source: SourceVolume) {
        guard !isImporting, !maintenanceBusy else { return }
        if source.isFolder {
            folders.removeAll { $0.id == source.id }; selectedSources.remove(source.id); refreshSources(); return
        }
        do { try NSWorkspace.shared.unmountAndEjectDevice(at: source.url); refreshSources() }
        catch { errorMessage = "无法弹出「\(source.name)」：\(error.localizedDescription)" }
    }

    func openDestination() { NSWorkspace.shared.open(destination) }

    func exportReport() {
        guard let report, activePanel == nil else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "OAnyImport-导入记录.json"
        present(panel) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(report).write(to: url, options: .atomic)
            } catch { Task { @MainActor in self?.errorMessage = error.localizedDescription } }
        }
    }

    private func present(_ panel: NSSavePanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        activePanel = panel
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.activePanel = nil
            completion(response)
        }
        panel.begin(completionHandler: handler)
    }

    private func loadDemo() {
        let first = SourceVolume(url: URL(fileURLWithPath: "/Volumes/SONY_A7C"), name: "SONY_A7C", capacity: 128_000_000_000, available: 84_000_000_000)
        let second = SourceVolume(url: URL(fileURLWithPath: "/Volumes/DJI_POCKET"), name: "DJI_POCKET", capacity: 64_000_000_000, available: 41_000_000_000)
        sources = [first, second]; selectedSources = [first.id, second.id]
        for (index, source) in sources.enumerated() {
            let names = index == 0 ? ["C0001.MP4", "C0002.MP4", "DSC00123.JPG", "DSC00124.JPG", "DSC00123.ARW", "C0001.XML"] : ["DJI_20261029093000.MP4", "DJI_20261029100000.MOV", "DJI_0012.JPG", "REC001.WAV"]
            scans[source.id] = ScanResult(files: names.enumerated().map { i, name in
                MediaFile(url: source.url.appendingPathComponent(name), source: source, relativePath: name, bytes: name.lowercased().hasSuffix("mp4") || name.hasSuffix("MOV") ? Int64(2_500_000_000 + i * 500_000_000) : Int64(8_000_000 + i * 1_000_000), modifiedAt: Date())
            })
        }
    }
}

func byteString(_ bytes: Int64) -> String { bytes == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
