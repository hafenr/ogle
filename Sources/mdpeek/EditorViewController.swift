import AppKit
import SwiftTerm

/// The bundled Neovim in a terminal, with the user's own configuration, editing the
/// displayed document.
@MainActor
final class EditorViewController: NSViewController, LocalProcessTerminalViewDelegate {
    private var session: (terminal: EditorTerminalView, connection: EditorConnection)?
    private(set) var hasUnsavedChanges = false {
        didSet {
            if hasUnsavedChanges != oldValue { onUnsavedChangesChange?(hasUnsavedChanges) }
        }
    }

    /// Called with the first line Neovim shows of a file, whenever it changes.
    var onScroll: ((URL, Int) -> Void)?
    /// Called with the file and line of Neovim's cursor as it moves.
    var onCursorMove: ((URL, Int) -> Void)?
    /// Called when Neovim gets unsaved changes, and when it no longer has any.
    var onUnsavedChangesChange: ((Bool) -> Void)?
    /// Called when Neovim quits normally.
    var onQuit: (() -> Void)?

    var focusView: NSView? { session?.terminal }
    /// The text size relative to the default; it follows the preview's zoom while the two are
    /// linked.
    var zoom: CGFloat = 1 {
        didSet { session?.terminal.font = font }
    }
    private var font: NSFont { .monospacedSystemFont(ofSize: 13 * zoom, weight: .regular) }

    override func loadView() {
        view = NSView()
    }

    /// Shows the file at `url` in Neovim, with `line` at the top if given, starting Neovim if
    /// it is not running. Without a line, Neovim reports where it shows the file.
    func open(_ url: URL, atLine line: Int?) {
        do {
            if let session {
                try session.connection.open(url, atLine: line)
            } else {
                try start(with: url, atLine: line)
            }
        } catch {
            presentError(error)
        }
    }

    /// Scrolls Neovim, if it shows the file at `url`, so that `line` is at the top.
    func scroll(_ url: URL, toLine line: Int) {
        do {
            try session?.connection.scroll(url, toLine: line)
        } catch {
            presentError(error)
        }
    }

    /// Ends Neovim, discarding unsaved changes.
    func stop() {
        guard let session else { return }
        session.terminal.processDelegate = nil
        session.terminal.terminate()
        end()
    }

    private func start(with url: URL, atLine line: Int?) throws {
        let connection = try EditorConnection()
        connection.onEvent = { [weak self] event in
            switch event {
            case .scroll(let path, let line): self?.onScroll?(URL(fileURLWithPath: path), line)
            case .cursor(let path, let line): self?.onCursorMove?(URL(fileURLWithPath: path), line)
            case .modified(let modified): self?.hasUnsavedChanges = modified
            case .background(let color): self?.session?.terminal.setBackground(color)
            }
        }
        connection.onError = { [weak self] error in self?.presentError(error) }

        view.subviews.forEach { $0.removeFromSuperview() }
        let terminal = EditorTerminalView(frame: view.bounds)
        terminal.processDelegate = self
        terminal.font = font
        terminal.configureNativeColors()
        terminal.syncColorScheme()
        // Option types the characters of the keyboard layout, and acts as Meta only on keys
        // that type none (arrows, Backspace, …).
        terminal.optionAsMetaKey = false
        terminal.optionAsMetaKeyForFunctionalKeys = true
        terminal.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            terminal.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            terminal.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        // Neovim starts at the terminal's final size, so it keeps the line it is asked to show at
        // the top, rather than moving it when the terminal is resized.
        view.layoutSubtreeIfNeeded()
        session = (terminal, connection)

        let resources = Bundle.main.resourceURL!
        let shell = String(cString: getpwuid(getuid())!.pointee.pw_shell)
        let environment = Terminal.getEnvironmentVariables() + [
            "SHELL=\(shell)",
            "MDPEEK_NVIM=\(resources.appending(path: "neovim/bin/nvim").path)",
            "MDPEEK_LUA=\(resources.appending(path: "mdpeek.lua").path)",
            "MDPEEK_SOCKET=\(connection.path)",
            "MDPEEK_FILE=\(url.path)",
        ] + (line.map { ["MDPEEK_LINE=\($0)"] } ?? [])
        // Through an interactive login shell, as in a terminal, so that Neovim and its plugins
        // find the user's tools on the PATH.
        terminal.startProcess(
            executable: shell,
            args: ["-l", "-i", "-c", #"exec "$MDPEEK_NVIM" --cmd 'lua dofile(vim.env.MDPEEK_LUA)' -- "$MDPEEK_FILE""#],
            environment: environment,
            currentDirectory: url.deletingLastPathComponent().path)
    }

    private func end() {
        session?.connection.close()
        session = nil
        hasUnsavedChanges = false
    }

    // MARK: LocalProcessTerminalViewDelegate

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard let terminal = session?.terminal else { return }
        end()
        if exitCode == 0 {
            terminal.removeFromSuperview()
            onQuit?()
        } else {
            // Keeps the output, which explains what went wrong.
            let reason = exitCode.map { "exited with status \($0)" } ?? "was terminated"
            terminal.feed(text: "\r\n[Neovim \(reason)]\r\n")
        }
    }

    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        end()
        presentError(error)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}

private final class EditorTerminalView: LocalProcessTerminalView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        syncColorScheme()
    }

    /// Tells Neovim whether the system appearance is light or dark.
    func syncColorScheme() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        updateColorScheme(isDark ? .dark : .light)
    }

    /// Uses Neovim's background (0xRRGGBB) for the margins around its grid, or the system's
    /// if Neovim has none.
    func setBackground(_ color: Int?) {
        nativeBackgroundColor = color.map {
            NSColor(
                srgbRed: CGFloat($0 >> 16 & 0xFF) / 255, green: CGFloat($0 >> 8 & 0xFF) / 255,
                blue: CGFloat($0 & 0xFF) / 255, alpha: 1)
        } ?? .textBackgroundColor
    }
}
