import Foundation

struct ModelOption: Codable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    var indexPath: String
    var infoSummary: String
    var speakerCount: Int

    init(name: String, indexPath: String, infoSummary: String, speakerCount: Int) {
        self.name = name
        self.indexPath = indexPath
        self.infoSummary = infoSummary
        self.speakerCount = speakerCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        indexPath = try container.decode(String.self, forKey: .indexPath)
        infoSummary = try container.decode(String.self, forKey: .infoSummary)
        speakerCount = try container.decodeIfPresent(Int.self, forKey: .speakerCount) ?? 0
    }
}
