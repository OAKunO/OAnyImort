import SwiftUI
import OAnyImportCore

struct ReportView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var showingRecords = false
    @State private var deleteCard: ImportCard?
    @State private var showingDeleteConfirmation = false
    @State private var formatCard: ImportCard?
    @State private var choosingDeleteCard = false
    @State private var choosingFormatCard = false
    @State private var choosingEjectCard = false
    private var p: Palette { Palette(scheme) }
    private var canManageCards: Bool {
        guard let report = model.report else { return false }
        return !report.cancelled && report.failed == 0 && report.copied + report.skipped > 0 && !model.importCards.isEmpty
    }
    private var selectedCards: [SourceVolume] { model.sources.filter { model.selectedSources.contains($0.id) && !$0.isFolder } }
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("MEMORIES, SAFELY HOME").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(p.secondary)
                    Text(title).font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(p.secondary)
                }
                Spacer()
                Image(systemName: model.report?.failed ?? 0 > 0 ? "doc.badge.ellipsis" : "checkmark.seal")
                    .font(.system(size: 40, weight: .ultraLight)).foregroundStyle(p.accent)
            }
            if let report = model.report {
                HStack(spacing: 12) {
                    metric("已导入", count: report.copied)
                    metric("重复跳过", count: report.skipped)
                    metric("失败", count: report.failed)
                }
                if report.failed > 0 || report.cancelled {
                    Text(report.cancelled ? "未完成的副本已清理。点击「继续未完成项」即可继续。" : "其他文件已保留，可以仅重试失败项。")
                        .font(.system(size: 11)).foregroundStyle(p.secondary)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showingRecords.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showingRecords ? "chevron.down" : "chevron.right")
                            .foregroundStyle(p.faint)
                        Text("查看文件记录")
                    }
                    .font(.system(size: 11))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showingRecords ? "已展开" : "已收起")
                if showingRecords {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 13) {
                            ForEach(Array(report.records.enumerated()), id: \.offset) { _, record in
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: record.outcome == .copied ? "checkmark.circle" : record.outcome == .skipped ? "equal.circle" : "exclamationmark.circle")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(URL(fileURLWithPath: record.source).lastPathComponent).font(.system(size: 11, weight: .medium))
                                        Text(record.message ?? record.destination ?? "").font(.system(size: 10)).foregroundStyle(p.secondary).textSelection(.enabled)
                                    }
                                }
                            }
                        }.padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 150)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
                if canManageCards {
                    Text("删除前会再次校验电脑上的副本。格式化会清除卡上的所有内容。")
                        .font(.system(size: 10)).foregroundStyle(p.secondary)
                }
            }
            if model.maintenanceBusy {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("正在处理，请勿拔出内存卡…").font(.system(size: 11)) }
            }
            HStack(spacing: 10) {
                Button("导出记录") { model.exportReport() }.buttonStyle(QuietButton())
                Button("打开文件夹") { model.openDestination() }.buttonStyle(QuietButton())
                Spacer()
                if let report = model.report, report.failed > 0 || report.cancelled {
                    Button(report.cancelled ? "继续未完成项" : "重试失败项") { model.retryUnfinished() }.buttonStyle(QuietButton())
                }
                if canManageCards {
                    Button("删除已导入文件") {
                        if let card = model.importCards.first, model.importCards.count == 1 { deleteCard = card; showingDeleteConfirmation = true }
                        else { choosingDeleteCard = true }
                    }.buttonStyle(QuietButton())
                    Button("格式化内存卡") {
                        if let card = model.importCards.first, model.importCards.count == 1 { formatCard = card }
                        else { choosingFormatCard = true }
                    }.buttonStyle(QuietButton())
                }
                Button("完成") { model.showingReport = false }.buttonStyle(QuietButton()).keyboardShortcut(.defaultAction)
            }
            if !selectedCards.isEmpty {
                HStack {
                    Text("可以安全弹出来源卡了").font(.system(size: 10)).foregroundStyle(p.secondary)
                    Spacer()
                    Button("弹出") {
                        if let card = selectedCards.first, selectedCards.count == 1 { model.eject(card) }
                        else { choosingEjectCard = true }
                    }.buttonStyle(.plain).font(.system(size: 10))
                }
            }
        }.padding(30).frame(width: 630).background(p.background).foregroundStyle(p.ink).tint(p.accent)
        .disabled(model.maintenanceBusy)
        .confirmationDialog("选择要删除原文件的卡", isPresented: $choosingDeleteCard) {
            ForEach(model.importCards) { card in
                Button("\(card.source.name) · \(byteString(card.source.capacity)) · \(card.source.url.path)") {
                    deleteCard = card
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showingDeleteConfirmation = true }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("选择要格式化的卡", isPresented: $choosingFormatCard) {
            ForEach(model.importCards) { card in
                Button("\(card.source.name) · \(byteString(card.source.capacity)) · \(card.source.url.path)") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { formatCard = card }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("选择要弹出的卡", isPresented: $choosingEjectCard) {
            ForEach(selectedCards) { card in Button("\(card.name) · \(card.url.path)") { model.eject(card) } }
            Button("取消", role: .cancel) {}
        }
        .alert("删除内存卡上的原文件？", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) { deleteCard = nil }
            Button("确认删除原文件", role: .destructive) {
                if let card = deleteCard { model.deleteImportedOriginals(on: card) }
                deleteCard = nil
            }
        } message: {
            Text("将从「\(deleteCard?.source.name ?? "")」永久删除本次成功导入或重复跳过的原文件。只有重新校验与电脑副本完全一致的文件才会删除。")
        }
        .sheet(item: $formatCard) { card in FormatCardSheet(card: card) { model.formatCard(card) } }
        .alert("处理结果", isPresented: Binding(get: { model.maintenanceMessage != nil }, set: { if !$0 { model.maintenanceMessage = nil } })) {
            Button("知道了") { model.maintenanceMessage = nil }
        } message: { Text(model.maintenanceMessage ?? "") }
    }

    private var title: String {
        guard let report = model.report else { return "导入结果" }
        if report.cancelled { return "先休息一下，稍后继续。" }
        if report.failed > 0 { return report.copied > 0 ? "素材已整理，部分文件待处理。" : "这次还没收好，再试一次。" }
        if report.copied == 0 && report.skipped > 0 { return "这些回忆，已经在这里了。" }
        return "导入完成"
    }
    private var subtitle: String {
        guard let report = model.report else { return "" }
        let duration = Int((report.finishedAt ?? Date()).timeIntervalSince(report.startedAt))
        return "用时 \(duration < 60 ? "\(duration) 秒" : "\(duration / 60) 分 \(duration % 60) 秒")"
    }
    private func metric(_ label: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(count)").font(.system(size: 28, weight: .medium, design: .rounded))
            Text(label).font(.system(size: 10)).foregroundStyle(p.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(17).background(p.panel, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(p.line, lineWidth: 1))
    }
}

private struct FormatCardSheet: View {
    let card: ImportCard
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var slider = 0.0
    @State private var showingFinalConfirmation = false
    private var p: Palette { Palette(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("格式化内存卡").font(.system(size: 21, weight: .semibold))
            Text("「\(card.source.name)」 · \(byteString(card.source.capacity))")
                .font(.system(size: 13, weight: .medium))
            Text("将永久清除这张卡上的所有分区和文件，包括没有导入的文件。完成后卡将使用 ExFAT 格式，名称为 OANYIMPORT。此操作无法撤销。")
                .font(.system(size: 12)).foregroundStyle(p.secondary).fixedSize(horizontal: false, vertical: true)
            Text("向右滑到底，再进行最后确认")
                .font(.system(size: 11, weight: .medium))
            Slider(value: $slider, in: 0...1, onEditingChanged: { editing in
                if !editing {
                    if slider >= 0.98 { showingFinalConfirmation = true }
                    else { slider = 0 }
                }
            }).accessibilityLabel("滑动确认格式化")
            HStack { Spacer(); Button("取消") { dismiss() }.buttonStyle(QuietButton()) }
        }
        .padding(25).frame(width: 450).background(p.background).foregroundStyle(p.ink).tint(p.accent)
        .alert("最后确认：格式化「\(card.source.name)」？", isPresented: $showingFinalConfirmation) {
            Button("取消", role: .cancel) { slider = 0 }
            Button("永久清除并格式化", role: .destructive) { dismiss(); onConfirm() }
        } message: {
            Text("整张卡的所有分区和文件都会永久删除，包括未导入的内容。请确认你选择了正确的卡。")
        }
    }
}
