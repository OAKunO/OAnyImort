import SwiftUI
import AppKit

@main
struct OAnyImportApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @AppStorage("appearance") private var appearance = "light"

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
                .onAppear { delegate.model = model; NSApp.activate(ignoringOtherApps: true) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1160, height: 850)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加素材来源…") { model.addFolder() }.keyboardShortcut("o")
                Button("选择保存位置…") { model.chooseDestination() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("开始导入") { model.startImport() }.keyboardShortcut("i").disabled(!model.canImport)
                Button("重新扫描") { model.refreshSources(rescan: true) }.keyboardShortcut("r").disabled(model.isImporting)
            }
            CommandGroup(after: .toolbar) {
                Picker("外观", selection: $appearance) {
                    Text("奶油白").tag("light")
                    Text("暖夜黑").tag("dark")
                    Text("跟随系统").tag("system")
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.maintenanceBusy == true {
            let alert = NSAlert()
            alert.messageText = "内存卡正在处理中"
            alert.informativeText = "请等待操作完成后再退出，并保持内存卡连接。"
            alert.addButton(withTitle: "知道了")
            alert.runModal()
            return .terminateCancel
        }
        guard model?.isImporting == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "素材仍在导入中"
        alert.informativeText = "请等待导入完成，或在窗口中取消导入后再退出。"
        alert.addButton(withTitle: "继续导入")
        alert.runModal()
        return .terminateCancel
    }
}
