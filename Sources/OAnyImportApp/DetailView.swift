import SwiftUI
import QuickLook
import QuickLookThumbnailing
import OAnyImportCore

struct DetailView: View {
    @ObservedObject var model: AppModel
    var kind: MediaKind
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var showAll = false
    @State private var previewURL: URL?
    private var p: Palette { Palette(scheme) }
    private var filtered: [MediaFile] {
        model.files.filter { $0.kind == kind && (model.detailSourceID == nil || $0.sourceID == model.detailSourceID) && (query.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query)) }
    }
    private var visible: [MediaFile] { showAll ? filtered : Array(filtered.prefix(6)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(kind.title)详情").font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text("先看一眼，再好好收藏。").font(.system(size: 10)).foregroundStyle(p.secondary)
                }
                Spacer()
                Button { model.detailKind = nil } label: { Image(systemName: "xmark").font(.system(size: 11)).frame(width: 27, height: 27).background(p.selected, in: Circle()) }
                    .buttonStyle(.plain).accessibilityLabel("关闭详情")
            }.padding(22).padding(.top, 16)
            VStack(spacing: 12) {
                if model.selectedSources.count > 1 {
                    Picker("来源", selection: $model.detailSourceID) {
                        Text("所有选中的来源").tag(String?.none)
                        ForEach(model.sources.filter { model.selectedSources.contains($0.id) }) { Text($0.name).tag(Optional($0.id)) }
                    }.labelsHidden().controlSize(.small)
                }
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(p.secondary)
                    TextField("搜索文件名", text: $query).textFieldStyle(.plain).font(.system(size: 11))
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(p.faint) }
                }.padding(10).background(p.selected, in: RoundedRectangle(cornerRadius: 9))
                HStack {
                    Text("\(filtered.count) 个文件 · 已选 \(filtered.filter(model.isFileSelected).count) 个")
                    Spacer()
                    Text("点击预览").foregroundStyle(p.faint)
                }.font(.system(size: 10)).foregroundStyle(p.secondary)
            }.padding(.horizontal, 22).padding(.bottom, 17)
            Divider().overlay(p.line)
            ScrollView {
                LazyVStack(spacing: 13) {
                    if filtered.isEmpty {
                        VStack(spacing: 10) { Image(systemName: "doc.text.magnifyingglass").font(.largeTitle); Text("没有匹配的文件").font(.system(size: 12)) }
                            .foregroundStyle(p.secondary).frame(maxWidth: .infinity).padding(.vertical, 50)
                    }
                    ForEach(visible) { file in
                        previewCard(file)
                    }
                    if !showAll, filtered.count > 6 {
                        Button("查看全部 \(filtered.count) 个文件") { showAll = true }.buttonStyle(QuietButton()).padding(.vertical, 8)
                    }
                }.padding(20)
            }
            Divider()
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.square").font(.system(size: 12))
                Text("勾选要导入的文件；点击缩略图可预览。")
                    .font(.system(size: 10)).lineSpacing(4)
            }.foregroundStyle(p.secondary).padding(20)
        }
        .background(p.background).foregroundStyle(p.ink)
        .quickLookPreview($previewURL)
        .onChange(of: kind) { _, _ in query = ""; showAll = false; previewURL = nil }
    }

    private func previewCard(_ file: MediaFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Button { previewURL = file.url } label: {
                    ZStack(alignment: .bottomTrailing) {
                        ThumbnailView(url: file.url, symbol: kind.symbol).frame(height: 136).frame(maxWidth: .infinity).clipped()
                        if kind == .video || kind == .audio {
                            Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(p.ink)
                                .padding(10).background(p.panel.opacity(0.95), in: Circle()).padding(10)
                        }
                    }
                }.buttonStyle(.plain).accessibilityLabel("预览 \(file.url.lastPathComponent)")
                Button { model.toggleFile(file) } label: {
                    CheckMark(selected: model.isFileSelected(file))
                        .padding(8).background(p.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).disabled(model.isImporting)
                    .accessibilityLabel("选择 \(file.url.lastPathComponent)")
                    .accessibilityValue(model.isFileSelected(file) ? "已选中" : "未选中")
                    .padding(9)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(file.url.lastPathComponent).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                HStack {
                    Text(file.sourceName).lineLimit(1)
                    Spacer()
                    Text(byteString(file.bytes))
                }.font(.system(size: 9)).foregroundStyle(p.secondary)
                Text(file.relativePath).font(.system(size: 9)).foregroundStyle(p.faint).lineLimit(1).truncationMode(.middle)
            }.padding(12)
        }.background(p.panel, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(p.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 13))
    }
}

private struct ThumbnailView: View {
    let url: URL
    let symbol: String
    @State private var thumbnail: NSImage?
    @State private var request: QLThumbnailGenerator.Request?
    @Environment(\.colorScheme) private var scheme
    private var p: Palette { Palette(scheme) }
    var body: some View {
        ZStack {
            p.selected
            if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit() }
            else {
                VStack(spacing: 9) {
                    Image(systemName: symbol).font(.system(size: 29, weight: .ultraLight))
                    Text("点击查看预览").font(.system(size: 9))
                }.foregroundStyle(p.faint)
            }
        }
        .task(id: url) {
            thumbnail = nil
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 600, height: 300), scale: 2, representationTypes: .thumbnail)
            self.request = request
            if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request), !Task.isCancelled {
                thumbnail = representation.nsImage
            }
        }
        .onDisappear { if let request { QLThumbnailGenerator.shared.cancel(request) } }
    }
}
