import Foundation

/// The socket over which the editor's Neovim talks to Ogle, through ogle.lua: JSON
/// objects, one per line. Neovim connects to it once, while it starts.
@MainActor
final class EditorConnection {
    enum Event: Decodable {
        /// The first line shown in a window on the file at `path`.
        case scroll(path: String, line: Int)
        /// The line of the cursor, in a window on the file at `path`.
        case cursor(path: String, line: Int)
        /// Whether any buffer has unsaved changes.
        case modified(Bool)
        /// The background color of Neovim's Normal highlight, as 0xRRGGBB, if it has one.
        case background(Int?)

        private enum CodingKeys: String, CodingKey {
            case event, path, line, value, color
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .event) {
            case "scroll":
                self = .scroll(
                    path: try container.decode(String.self, forKey: .path),
                    line: try container.decode(Int.self, forKey: .line))
            case "cursor":
                self = .cursor(
                    path: try container.decode(String.self, forKey: .path),
                    line: try container.decode(Int.self, forKey: .line))
            case "modified":
                self = .modified(try container.decode(Bool.self, forKey: .value))
            case "background":
                self = .background(try container.decodeIfPresent(Int.self, forKey: .color))
            case let event:
                throw DecodingError.dataCorruptedError(
                    forKey: .event, in: container, debugDescription: "Unknown event \(event)")
            }
        }
    }

    private struct Command: Encodable {
        let command: String
        let path: String
        var line: Int?
    }

    let path: String
    var onEvent: ((Event) -> Void)?
    var onError: ((Error) -> Void)?
    private let acceptSource: DispatchSourceRead
    private var connection: FileHandle?
    private var received = Data()
    /// Messages sent before Neovim connected.
    private var pending = Data()

    init() throws {
        path = (NSTemporaryDirectory() as NSString).appendingPathComponent("ogle-\(getpid()).sock")
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }

        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw Self.lastError() }
        unlink(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(listener, 1) == 0 else {
            let error = Self.lastError()
            Darwin.close(listener)
            throw error
        }

        acceptSource = DispatchSource.makeReadSource(fileDescriptor: listener, queue: .main)
        acceptSource.setCancelHandler { Darwin.close(listener) }
        acceptSource.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.accept(listener) }
        }
        acceptSource.resume()
    }

    /// Asks Neovim to show the file at `url`, with `line` at the top if given.
    func open(_ url: URL, atLine line: Int?) throws {
        try send(Command(command: "open", path: url.path, line: line))
    }

    /// Asks Neovim to scroll a window showing the file at `url` so that `line` is at the top.
    func scroll(_ url: URL, toLine line: Int) throws {
        try send(Command(command: "scroll", path: url.path, line: line))
    }

    func close() {
        acceptSource.cancel()
        unlink(path)
        connection?.readabilityHandler = nil
        connection = nil
    }

    private func send(_ message: Command) throws {
        let data = try JSONEncoder().encode(message) + Data("\n".utf8)
        if let connection {
            try connection.write(contentsOf: data)
        } else {
            pending.append(data)
        }
    }

    private func accept(_ listener: Int32) {
        let socket = Darwin.accept(listener, nil, nil)
        guard socket >= 0 else {
            onError?(Self.lastError())
            return
        }
        acceptSource.cancel()
        unlink(path)
        let connection = FileHandle(fileDescriptor: socket, closeOnDealloc: true)
        connection.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(data) }
            }
        }
        self.connection = connection
        do {
            try connection.write(contentsOf: pending)
            pending = Data()
        } catch {
            onError?(error)
        }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else {
            connection?.readabilityHandler = nil
            return
        }
        received.append(data)
        while let newline = received.firstIndex(of: UInt8(ascii: "\n")) {
            let line = received[received.startIndex..<newline]
            received.removeSubrange(received.startIndex...newline)
            do {
                onEvent?(try JSONDecoder().decode(Event.self, from: Data(line)))
            } catch {
                onError?(error)
            }
        }
    }

    private static func lastError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno)!)
    }
}
