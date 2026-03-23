import Foundation

struct AppToast: Identifiable, Equatable {
    enum Style: Equatable {
        case error
        case success
        case info
    }

    let id = UUID()
    let message: String
    let style: Style
}
