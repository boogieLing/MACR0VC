import Foundation

struct ModelOption: Codable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    var indexPath: String
    var infoSummary: String
}
