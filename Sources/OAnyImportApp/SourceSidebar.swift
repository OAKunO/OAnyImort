import SwiftUI
import OAnyImportCore

struct SourceSidebar: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var cardToEject: SourceVolume?
    @State private var confirmingEject = false
    private var p: Palette { Palette(scheme) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sdcard").font(.system(size: 23, weight: .light)).foregroundStyle(p.accent)
                    .frame(width: 42, height: 42).background(p.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text("OAnyImport").font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text("一点一滴，好好收藏").font(.system(size: 9)).foregroundStyle(p.secondary)
                }
            }.padding(.top, 40).padding(.horizontal, 22).padding(.bottom, 32)
            HStack {
                Text("素材来源").font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary)
                Text("\(model.sources.count)").font(.system(size: 9, design: .monospaced)).foregroundStyle(p.faint)
                Spacer()
                Button { model.refreshSources(rescan: true) } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11)).frame(width: 23, height: 23) }
                    .buttonStyle(.plain).help("刷新设备与素材").disabled(model.isImporting || model.isScanning)
            }.padding(.horizontal, 23).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 10) {
                    if model.sources.isEmpty { emptyState }
                    ForEach(model.sources) { source in sourceCard(source) }
                }.padding(.horizontal, 13).padding(.top, 1)
            }
            if !model.sources.isEmpty {
                Button(model.selectedSources.count == model.sources.count ? "取消全选" : "选择全部来源") { model.selectAllSources() }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(p.secondary).padding(.horizontal, 24).padding(.vertical, 13).disabled(model.isImporting)
            }
            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 14) {
                Button { model.addFolder() } label: {
                    HStack(spacing: 8) { Image(systemName: "plus").font(.system(size: 10)); Text("添加素材文件夹").font(.system(size: 11)); Spacer(); Text("⌘O").font(.system(size: 10)).foregroundStyle(p.faint) }
                        .padding(12).background(p.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 11))
                }.buttonStyle(.plain).disabled(model.isImporting)
            }.padding(.horizontal, 18).padding(.bottom, 26)
        }.background(p.sidebar)
        .alert("安全弹出内存卡？", isPresented: $confirmingEject) {
            Button("取消", role: .cancel) { cardToEject = nil }
            Button("确认弹出") {
                if let card = cardToEject { model.eject(card) }
                cardToEject = nil
            }
        } message: {
            Text("确定要弹出「\(cardToEject?.name ?? "")」吗？弹出成功后即可拔出内存卡。")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: "sdcard").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(p.faint).padding(.top, 22)
            Text("等待素材来源").font(.system(size: 12, weight: .medium))
            Text("连接存储卡、U 盘或硬盘后显示在这里\n也可以添加一个素材文件夹")
                .font(.system(size: 10)).foregroundStyle(p.secondary).multilineTextAlignment(.center).lineSpacing(5)
        }.frame(maxWidth: .infinity).padding(.bottom, 25)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(p.faint.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }

    private func sourceCard(_ source: SourceVolume) -> some View {
        let selected = model.selectedSources.contains(source.id)
        let scanning = model.scanning.contains(source.id)
        let count = model.scans[source.id]?.files.count
        return VStack(alignment: .leading, spacing: 13) {
            Button { model.toggleSource(source) } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: source.isFolder ? "folder" : "sdcard").font(.system(size: 20, weight: .light)).foregroundStyle(p.accent)
                        Spacer()
                        CheckMark(selected: selected)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(source.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).help(source.url.path)
                        Text(source.isFolder ? "素材文件夹" : "\(byteString(source.capacity)) · 外接存储")
                            .font(.system(size: 9)).foregroundStyle(p.secondary)
                    }
                    if source.capacity > 0 {
                        GeometryReader { proxy in
                            Capsule().fill(p.line)
                            Capsule().fill(p.accent.opacity(0.5)).frame(width: proxy.size.width * CGFloat(max(0, min(1, Double(source.capacity - source.available) / Double(source.capacity)))))
                        }.frame(height: 3)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.isImporting)
            HStack(spacing: 5) {
                if scanning { ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 11, height: 11) }
                else { Circle().fill(p.accent.opacity(selected ? 0.7 : 0.3)).frame(width: 4, height: 4) }
                Text(model.currentSourceID == source.id ? "正在导入" : scanning ? "正在扫描" : count.map { "\($0) 个文件" } ?? "待选择")
                    .font(.system(size: 9)).foregroundStyle(p.secondary)
                Spacer()
                Button {
                    if source.isFolder { model.eject(source) }
                    else { cardToEject = source; confirmingEject = true }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: source.isFolder ? "xmark" : "eject").font(.system(size: 9, weight: .semibold))
                        Text(source.isFolder ? "移除" : "弹出").font(.system(size: 10, weight: .medium))
                    }.padding(.horizontal, 9).padding(.vertical, 6)
                        .foregroundStyle(p.ink).background(p.selected, in: Capsule())
                        .overlay(Capsule().stroke(p.accent.opacity(0.35), lineWidth: 1))
                }
                    .buttonStyle(.plain).disabled(model.isImporting || scanning || model.maintenanceBusy)
                    .accessibilityLabel(source.isFolder ? "移除\(source.name)" : "弹出\(source.name)")
                    .help(source.isFolder ? "移除此来源" : "安全弹出")
            }
        }.padding(15).background(selected ? p.panel : p.sidebar, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(selected ? p.accent.opacity(0.4) : p.line, lineWidth: 1))
    }
}
