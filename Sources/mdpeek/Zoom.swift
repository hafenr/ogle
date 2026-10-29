import Foundation

/// The zoom levels the preview and the editor step through.
enum Zoom {
    static let levels: [CGFloat] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    enum Step {
        case larger, smaller, actualSize

        /// The zoom level after this step from `zoom`.
        func apply(to zoom: CGFloat) -> CGFloat {
            switch self {
            case .larger: Zoom.levels.first { $0 > zoom + 0.001 } ?? zoom
            case .smaller: Zoom.levels.last { $0 < zoom - 0.001 } ?? zoom
            case .actualSize: 1
            }
        }
    }
}
