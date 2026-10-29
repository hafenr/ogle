import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var windowController = MainWindowController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController.showWindow(nil)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(windowController.open)
        windowController.showWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        windowController.confirmDiscardingEditorChanges() ? .terminateNow : .terminateCancel
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Markdown.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        windowController.open(url)
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = submenu(of: mainMenu, title: "Ogle")
        appMenu.addItem(withTitle: "About Ogle", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Ogle", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Ogle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenu = submenu(of: mainMenu, title: "File")
        fileMenu.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Open Quickly…", action: #selector(MainWindowController.openQuickly(_:)), keyEquivalent: "o")
            .keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "Open in Editor", action: #selector(MainWindowController.openInEditor(_:)), keyEquivalent: "o")
            .keyEquivalentModifierMask = [.command, .option]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Export as PDF…", action: #selector(MainWindowController.exportPDF(_:)), keyEquivalent: "e")
            .keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "Print…", action: #selector(MainWindowController.printDocument(_:)), keyEquivalent: "p")

        let editMenu = submenu(of: mainMenu, title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let findMenu = NSMenu(title: "Find")
        editMenu.addItem(withTitle: "Find", action: nil, keyEquivalent: "").submenu = findMenu
        findMenu.addItem(withTitle: "Find…", action: #selector(MainWindowController.showFind(_:)), keyEquivalent: "f")
        findMenu.addItem(withTitle: "Find Next", action: #selector(MainWindowController.findNext(_:)), keyEquivalent: "g")
        findMenu.addItem(withTitle: "Find Previous", action: #selector(MainWindowController.findPrevious(_:)), keyEquivalent: "g")
            .keyEquivalentModifierMask = [.command, .shift]

        let viewMenu = submenu(of: mainMenu, title: "View")
        viewMenu.addItem(withTitle: "Toggle Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s")
            .keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(withTitle: "Toggle Editor", action: #selector(MainWindowController.toggleEditor(_:)), keyEquivalent: "e")
            .keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(withTitle: "Link Editor and Preview", action: #selector(MainWindowController.toggleLinked(_:)), keyEquivalent: "")
        viewMenu.addItem(withTitle: "Highlight Cursor in Preview", action: #selector(MainWindowController.toggleCursorHighlight(_:)), keyEquivalent: "")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(MainWindowController.actualSize(_:)), keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(MainWindowController.zoomIn(_:)), keyEquivalent: "+")
        let zoomInAlternate = viewMenu.addItem(withTitle: "Zoom In", action: #selector(MainWindowController.zoomIn(_:)), keyEquivalent: "=")
        zoomInAlternate.isHidden = true
        zoomInAlternate.allowsKeyEquivalentWhenHidden = true
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(MainWindowController.zoomOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]

        let windowMenu = submenu(of: mainMenu, title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    private func submenu(of menu: NSMenu, title: String) -> NSMenu {
        let submenu = NSMenu(title: title)
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = submenu
        return submenu
    }
}
