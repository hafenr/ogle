import CoreServices
import Foundation

/// Watches a single file via FSEvents on its parent directory, so that editors which save
/// atomically (write a temp file, then rename it over the original) are picked up too.
@MainActor
final class FileWatcher {
    private nonisolated(unsafe) var stream: FSEventStreamRef!
    private let path: String
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        // FSEvents reports resolved paths (e.g. /private/tmp instead of /tmp).
        let directory = url.deletingLastPathComponent().path
        let resolvedDirectory = realpath(directory, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        } ?? directory
        path = (resolvedDirectory as NSString).appendingPathComponent(url.lastPathComponent).lowercased()
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(
            nil,
            { _, info, _, eventPaths, _, _ in
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info!).takeUnretainedValue()
                let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
                MainActor.assumeIsolated { watcher.handle(paths) }
            },
            &context, [resolvedDirectory] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagNoDefer))
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func handle(_ paths: [String]) {
        if paths.contains(where: { $0.lowercased() == path }) {
            onChange()
        }
    }
}
