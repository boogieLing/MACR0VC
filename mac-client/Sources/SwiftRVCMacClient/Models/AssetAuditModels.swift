import Foundation

enum AssetIntegrityStatus: String, Codable {
    case ok
    case missing
    case mismatch
    case error

    var label: String {
        rawValue.uppercased()
    }
}

struct AssetIntegrityItem: Codable, Identifiable, Hashable {
    let title: String
    let path: String
    let status: AssetIntegrityStatus
    let note: String
    let expectedHash: String?
    let actualHash: String?

    var id: String { path }
    var isHealthy: Bool { status == .ok }
}

struct AssetIntegrityReport: Codable {
    let items: [AssetIntegrityItem]
    let allValid: Bool
    let checkedAt: String?
    let message: String
}

struct AssetDownloadResult: Codable {
    let message: String
    let report: AssetIntegrityReport?
}
