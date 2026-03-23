import Foundation

enum NavigationDestination: String, CaseIterable, Identifiable {
    case engine
    case models
    case singleConvert
    case batchConvert

    var id: String { rawValue }

    var title: String {
        L10n.tr(titleKey)
    }

    var titleKey: String {
        switch self {
        case .engine:
            return "nav.engine"
        case .models:
            return "nav.models"
        case .singleConvert:
            return "nav.single"
        case .batchConvert:
            return "nav.batch"
        }
    }

    var systemImage: String {
        switch self {
        case .engine:
            return "bolt.horizontal.circle"
        case .models:
            return "square.stack.3d.up"
        case .singleConvert:
            return "waveform.path.badge.plus"
        case .batchConvert:
            return "square.grid.2x2"
        }
    }
}
