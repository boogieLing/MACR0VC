import Foundation

struct UVRModelCatalog: Codable {
    let modelNames: [String]
}

struct UVRRequest: Codable {
    let modelName: String
    let inputDirectoryURL: URL?
    let inputFileURLs: [URL]
    let vocalOutputDirectoryURL: URL
    let instrumentalOutputDirectoryURL: URL
    let format: OutputFormat

    func validate() throws {
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.missingModel
        }

        let hasDirectory = inputDirectoryURL != nil
        let hasFiles = !inputFileURLs.isEmpty
        if hasDirectory == hasFiles {
            throw ValidationError.invalidUVRInputMode
        }

        if hasDirectory, let directory = inputDirectoryURL,
           !FileManager.default.fileExists(atPath: directory.path) {
            throw ValidationError.missingInputDirectory
        }

        if hasFiles, inputFileURLs.contains(where: { !FileManager.default.fileExists(atPath: $0.path) }) {
            throw ValidationError.missingInputFile
        }
    }
}

struct UVRResult: Codable {
    let message: String
    let vocalOutputDirectoryURL: URL?
    let instrumentalOutputDirectoryURL: URL?
    let vocalOutputFileURLs: [URL]
    let instrumentalOutputFileURLs: [URL]
}
