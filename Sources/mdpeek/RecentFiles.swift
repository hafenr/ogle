import Foundation

@MainActor
final class RecentFiles {
    private static let defaultsKey = "recentFiles"
    private static let datesKey = "recentFileDates"
    private static let limit = 50

    private(set) var urls: [URL]
    private var dates: [String: Date]
    private var observers: [() -> Void] = []

    init() {
        urls = (UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
        dates = UserDefaults.standard.dictionary(forKey: Self.datesKey) as? [String: Date] ?? [:]
    }

    /// When the file was last opened in mdpeek (unknown for entries recorded by older versions).
    func lastOpened(_ url: URL) -> Date? {
        dates[url.path]
    }

    /// Calls `observer` whenever the list changes.
    func observe(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    func add(_ url: URL) {
        urls.removeAll { $0 == url }
        urls.insert(url, at: 0)
        urls = Array(urls.prefix(Self.limit))
        dates[url.path] = Date()
        save()
    }

    func remove(_ url: URL) {
        urls.removeAll { $0 == url }
        save()
    }

    private func save() {
        let paths = urls.map(\.path)
        dates = dates.filter { paths.contains($0.key) }
        UserDefaults.standard.set(paths, forKey: Self.defaultsKey)
        UserDefaults.standard.set(dates, forKey: Self.datesKey)
        observers.forEach { $0() }
    }

    /// When a file was opened, as the lists of recent files show it: "now", "5m", "3h",
    /// "Yesterday", "Mon", "Oct 14".
    nonisolated static func shortDate(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        let calendar = Calendar.current
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if calendar.isDateInToday(date) { return "\(Int(seconds / 3600))h" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if seconds < 6 * 86400 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
