import SwiftUI
import OAnyImportCore
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance") private var appearance = "light"
    @State private var confirmingCancel = false
    @State private var showingWarnings = false
    @State private var dropTarget = false
    private var p: Palette { Palette(scheme) }

    var body: some View {
        HStack(spacing: 0) {
            SourceSidebar(model: model).frame(width: 242)
            Rectangle().fill(p.line).frame(width: 1)
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 23) {
                        typeSection
                        destinationSection
                        if !model.warnings.isEmpty {
                            Button { showingWarnings = true } label: {
                                Label("\(model.warnings.count) 项扫描提示 · 点击查看", systemImage: "info.circle")
                                    .font(.system(size: 12)).foregroundStyle(p.secondary)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 34).padding(.top, 12).padding(.bottom, 27)
                }
                footer
            }
        }
        .background(p.background).foregroundStyle(p.ink).tint(p.accent)
        .frame(minWidth: 1020, minHeight: 760)
        .overlay(alignment: .trailing) {
            if let kind = model.detailKind {
                DetailView(model: model, kind: kind).frame(width: 390)
                    .overlay(alignment: .leading) { Rectangle().fill(p.line).frame(width: 1) }
                    .shadow(color: .black.opacity(0.08), radius: 18, x: -8, y: 0)
                    .transition(.move(edge: .trailing))
            }
        }
        .overlay {
            if model.showingReport {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ReportView(model: model).fixedSize(horizontal: false, vertical: true)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(p.line, lineWidth: 1))
                        .shadow(color: .black.opacity(0.15), radius: 30, y: 12)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.detailKind)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: scheme)
        .onExitCommand {
            if model.showingReport && !model.maintenanceBusy { model.showingReport = false }
            else { model.detailKind = nil }
        }
        .alert("暂时无法继续", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("知道了") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("取消这次导入？", isPresented: $confirmingCancel) {
            Button("继续导入", role: .cancel) {}
            Button("取消导入", role: .destructive) { model.cancelImport() }
        } message: { Text("已完成的文件会保留，当前未完成的副本会清理。卡内原文件不受影响，可以稍后继续。") }
        .sheet(isPresented: $showingWarnings) {
            VStack(alignment: .leading, spacing: 16) {
                Text("扫描提示").font(.title2)
                Text("以下内容无法读取，未加入本次导入清单。可检查权限后重新扫描。").foregroundStyle(.secondary)
                ScrollView { Text(model.warnings.joined(separator: "\n\n")).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                HStack { Spacer(); Button("完成") { showingWarnings = false }.buttonStyle(QuietButton()) }
            }.padding(25).frame(width: 550, height: 420)
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            HStack(spacing: 2) {
                themeButton("light", symbol: "sun.max", help: "奶油白")
                themeButton("dark", symbol: "moon", help: "暖夜黑")
                themeButton("system", symbol: "circle.lefthalf.filled", help: "跟随系统")
            }.padding(4).background(p.sidebar, in: Capsule())
        }.padding(.horizontal, 34).padding(.top, 25).padding(.bottom, 12)
    }

    private func themeButton(_ value: String, symbol: String, help: String) -> some View {
        Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { appearance = value } } label: {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 29, height: 25)
                .background(appearance == value ? p.panel : .clear, in: Capsule())
                .foregroundStyle(appearance == value ? p.ink : p.secondary)
        }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading("01", title: "想带回哪些素材？", subtitle: "按类型选择 · 详情里看预览", isLoading: model.isScanning)
            Surface {
                VStack(spacing: 0) {
                    ForEach(Array(MediaKind.allCases.enumerated()), id: \.element.id) { index, kind in
                        TypeRow(model: model, kind: kind)
                        if index < MediaKind.allCases.count - 1 { Rectangle().fill(p.line.opacity(0.7)).frame(height: 1).padding(.leading, 66) }
                    }
                }
            }
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading("02", title: "给素材一个新家", subtitle: "仅复制，保留卡内原文件")
            Surface {
                VStack(alignment: .leading, spacing: 17) {
                    HStack(spacing: 13) {
                        Image(systemName: "folder").font(.system(size: 24, weight: .light)).foregroundStyle(p.accent)
                            .frame(width: 44, height: 44).background(p.selected, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.destination.lastPathComponent).font(.system(size: 13, weight: .semibold))
                            Text(model.destination.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.system(size: 10)).foregroundStyle(p.secondary).lineLimit(1).truncationMode(.middle).help(model.destination.path)
                        }
                        Spacer(minLength: 6)
                        Button("更改位置…") { model.chooseDestination() }.buttonStyle(QuietButton()).disabled(model.isImporting)
                    }
                    Rectangle().fill(p.line).frame(height: 1)
                    HStack(spacing: 20) {
                        HStack(spacing: 9) {
                            Text("整理方式").font(.system(size: 11)).foregroundStyle(p.secondary)
                            Picker("整理方式", selection: $model.layout) {
                                ForEach(FolderLayout.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden().frame(width: 142).controlSize(.small)
                        }
                        Spacer(minLength: 0)
                        Toggle("按卡分文件夹", isOn: $model.separateCards).toggleStyle(.checkbox).font(.system(size: 11))
                        Toggle("导入后校验", isOn: $model.verify).toggleStyle(.checkbox).font(.system(size: 11))
                            .help("复制后读取目标文件，比较 SHA-256，确认内容一致。")
                    }.disabled(model.isImporting)
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right").font(.system(size: 10))
                        Text(pathExample).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        if dropTarget { Text("松开设为保存位置").fontWeight(.medium) }
                    }.font(.system(size: 10)).foregroundStyle(p.faint)
                }.padding(18)
            }
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(dropTarget ? p.accent : .clear, style: StrokeStyle(lineWidth: 2, dash: [5])))
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTarget) { providers in
                guard !model.isImporting, let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.setDestination(url) }
                }
                return true
            }
        }
    }

    private var pathExample: String {
        let day = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let card = model.separateCards ? "卡片名 / " : ""
        switch model.layout {
        case .typeDate: return "\(model.destination.lastPathComponent) / \(card)视频 / \(day) / C0001.MP4"
        case .dateType: return "\(model.destination.lastPathComponent) / \(card)\(day) / 视频 / C0001.MP4"
        case .original: return "\(model.destination.lastPathComponent) / \(card)DCIM / 100MEDIA / C0001.MP4"
        }
    }

    private func sectionHeading(_ number: String, title: String, subtitle: String, isLoading: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(number).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(p.faint)
            Text(title).font(.system(size: 14, weight: .semibold))
            if isLoading {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small).scaleEffect(0.75).frame(width: 14, height: 14)
                    Text("正在扫描素材…").font(.system(size: 10)).foregroundStyle(p.secondary)
                }.accessibilityElement(children: .combine)
            }
            Spacer()
            Text(subtitle).font(.system(size: 10)).foregroundStyle(p.secondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(p.line).frame(height: 1)
            HStack(spacing: 18) {
                if model.isImporting {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(model.progress?.phase ?? "准备导入").fontWeight(.medium)
                            Spacer()
                            Text("\(Int((model.progress?.fraction ?? 0) * 100))% · \(model.progress?.completedFiles ?? 0)/\(model.progress?.totalFiles ?? model.selectedFiles.count)")
                        }.font(.system(size: 11))
                        ProgressView(value: model.progress?.fraction ?? 0).progressViewStyle(.linear).tint(p.accent)
                        Text(model.progress?.currentFile ?? "正在建立导入清单…").font(.system(size: 10)).foregroundStyle(p.secondary).lineLimit(1)
                    }
                    Button("取消导入") { confirmingCancel = true }.buttonStyle(QuietButton())
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 7) {
                            Text(model.isScanning ? "正在清点素材…" : "\(model.selectedFiles.count) 个文件").font(.system(size: 14, weight: .semibold))
                            if !model.isScanning { Text("·  \(byteString(model.totalBytes))").font(.system(size: 12)).foregroundStyle(p.secondary) }
                        }
                        Text(footerHint).font(.system(size: 10)).foregroundStyle(model.insufficientSpace ? p.ink : p.secondary)
                    }
                    Spacer(minLength: 0)
                    if model.report != nil { Button("上次结果") { model.showingReport = true }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(p.secondary) }
                    Button { model.startImport() } label: {
                        HStack(spacing: 14) { Text("开始导入"); Image(systemName: "arrow.right").font(.system(size: 12, weight: .medium)) }
                            .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 23).padding(.vertical, 14)
                            .foregroundStyle(p.onButton).background(p.button.opacity(model.canImport && !model.insufficientSpace ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(.plain).disabled(!model.canImport || model.insufficientSpace).keyboardShortcut(.return, modifiers: .command)
                }
            }.padding(.horizontal, 34).padding(.vertical, 20)
        }.background(p.panel)
    }

    private var footerHint: String {
        if CommandLine.arguments.contains("--demo") { return "设计预览模式 · 不会读取或导入真实文件" }
        if model.insufficientSpace { return "目标空间不足，请更改保存位置或减少所选文件" }
        if model.selectedSources.isEmpty { return "先在左侧选择存储设备，也可以添加素材文件夹" }
        if model.isScanning { return "先统计文件，预览会在点击详情时加载" }
        if model.files.isEmpty { return "没有发现可导入文件，可查看扫描提示或重新扫描" }
        let available = model.availableBytes.map { "目标可用 \(byteString($0)) · " } ?? ""
        return available + "相同内容自动跳过，同名不同内容保留两份"
    }
}

private struct TypeRow: View {
    @ObservedObject var model: AppModel
    let kind: MediaKind
    @Environment(\.colorScheme) private var scheme
    @State private var expanded = false
    private var p: Palette { Palette(scheme) }
    private var files: [MediaFile] { model.files.filter { $0.kind == kind } }
    private var extensions: [String] { Set(files.map(\.fileExtension)).sorted() }
    private var included: [MediaFile] { files.filter(model.isFileSelected) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Button { model.toggleKind(kind) } label: {
                    HStack(spacing: 13) {
                        CheckMark(selected: !included.isEmpty, mixed: !included.isEmpty && included.count < files.count)
                        Image(systemName: kind.symbol).font(.system(size: 20, weight: .light)).foregroundStyle(p.accent)
                            .frame(width: 35, height: 35).background(p.selected.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(kind.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.ink)
                            Text(extensions.isEmpty ? (model.selectedSources.isEmpty ? "等待选择素材来源" : "未发现此类文件") : extensions.map { $0.isEmpty ? "无扩展名" : $0.uppercased() }.joined(separator: " / "))
                                .font(.system(size: 9)).foregroundStyle(p.secondary).lineLimit(1).truncationMode(.tail)
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(model.isImporting || files.isEmpty).accessibilityLabel("选择\(kind.title)")
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(files.count) 个").font(.system(size: 11, weight: .medium)).monospacedDigit()
                    Text(byteString(files.reduce(0) { $0 + $1.bytes })).font(.system(size: 9)).foregroundStyle(p.secondary)
                }.frame(minWidth: 60, alignment: .trailing)
                Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9)).frame(width: 22, height: 28)
                }.buttonStyle(.plain).foregroundStyle(p.faint).disabled(files.isEmpty)
                    .help("按格式选择").accessibilityLabel("按格式选择\(kind.title)")
                Button { model.detailSourceID = nil; model.detailKind = kind } label: {
                    HStack(spacing: 5) { Text("详情"); Image(systemName: "arrow.up.right").font(.system(size: 8)) }.font(.system(size: 10))
                }.buttonStyle(.plain).foregroundStyle(p.secondary).disabled(files.isEmpty).accessibilityLabel("查看\(kind.title)详情")
            }.padding(.horizontal, 18).padding(.vertical, 12)
            if expanded {
                VStack(spacing: 11) {
                    ForEach(extensions, id: \.self) { ext in
                        let count = files.filter { $0.fileExtension == ext }.count
                        let selectedCount = included.filter { $0.fileExtension == ext }.count
                        Button { model.toggleExtension(ext, kind: kind) } label: {
                            HStack(spacing: 9) {
                                CheckMark(selected: selectedCount > 0, mixed: selectedCount > 0 && selectedCount < count)
                                Text(ext.isEmpty ? "无扩展名" : ".\(ext)").font(.system(size: 11, design: .monospaced))
                                Spacer(); Text("\(count) 个").font(.system(size: 10)).foregroundStyle(p.secondary)
                            }
                        }.buttonStyle(.plain).disabled(model.isImporting)
                    }
                }.padding(.leading, 66).padding(.trailing, 81).padding(.bottom, 17)
            }
        }
    }
}
