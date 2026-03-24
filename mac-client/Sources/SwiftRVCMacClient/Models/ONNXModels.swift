import Foundation

struct ONNXExportRequest: Codable {
    let modelPath: URL
    let exportPath: URL

    enum CodingKeys: String, CodingKey {
        case modelPath
        case exportPath = "onnxOutputPath"
    }

    func validate() throws {
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw ValidationError.missingInputFile
        }
    }
}

struct ONNXExportResult: Codable {
    let message: String
    let exportedPath: URL
}
