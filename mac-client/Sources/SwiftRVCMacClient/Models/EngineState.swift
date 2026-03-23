import Foundation

enum EngineState: String, Codable {
    case idle
    case starting
    case ready
    case failed
    case stopping

    var label: String {
        switch self {
        case .idle:
            return L10n.tr("engine.state.idle")
        case .starting:
            return L10n.tr("engine.state.starting")
        case .ready:
            return L10n.tr("engine.state.ready")
        case .failed:
            return L10n.tr("engine.state.failed")
        case .stopping:
            return L10n.tr("engine.state.stopping")
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "pause.circle"
        case .starting:
            return "clock.arrow.circlepath"
        case .ready:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .stopping:
            return "stop.circle"
        }
    }
}
