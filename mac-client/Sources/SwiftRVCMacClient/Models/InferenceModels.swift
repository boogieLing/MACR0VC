import Foundation

enum F0Method: String, CaseIterable, Codable, Identifiable {
    case pm
    case dio
    case harvest
    case crepe
    case rmvpe
    case fcpe

    var id: String { rawValue }
}

enum OutputFormat: String, CaseIterable, Codable, Identifiable {
    case wav
    case flac
    case mp3
    case m4a

    var id: String { rawValue }
}

struct ModelCatalog: Codable {
    let models: [ModelOption]
    let indexPaths: [String]
}

struct ModelSelectionResult: Codable {
    let modelName: String
    let modelInfoSummary: String
    let indexPaths: [String]
}

struct SingleInferenceRequest: Codable {
    let modelName: String
    let inputFileURL: URL
    let transpose: Double
    let f0Method: F0Method
    let indexPath: String?
    let indexRate: Double
    let filterRadius: Double
    let resampleSR: Double
    let rmsMixRate: Double
    let protect: Double
    let f0FileURL: URL?

    func validate() throws {
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.missingModel
        }
        if !FileManager.default.fileExists(atPath: inputFileURL.path) {
            throw ValidationError.missingInputFile
        }
    }
}

struct SingleInferenceResult: Codable {
    let message: String
    let outputAudioURL: URL?
}

struct BatchInferenceRequest: Codable {
    let modelName: String
    let inputDirectoryURL: URL?
    let inputFileURLs: [URL]
    let outputDirectoryURL: URL
    let format: OutputFormat
    let transpose: Double
    let f0Method: F0Method
    let indexPath: String?
    let indexRate: Double
    let filterRadius: Double
    let resampleSR: Double
    let rmsMixRate: Double
    let protect: Double

    func validate() throws {
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.missingModel
        }

        let hasDirectory = inputDirectoryURL != nil
        let hasFiles = !inputFileURLs.isEmpty
        if hasDirectory == hasFiles {
            throw ValidationError.invalidBatchInputMode
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

struct BatchInferenceResult: Codable {
    let message: String
    let outputDirectoryURL: URL?
}

enum ValidationError: LocalizedError {
    case missingModel
    case missingInputFile
    case missingInputDirectory
    case invalidBatchInputMode
    case missingRealtimeInputDevice
    case missingRealtimeOutputDevice

    var errorDescription: String? {
        switch self {
        case .missingModel:
            return L10n.tr("validation.missing_model")
        case .missingInputFile:
            return L10n.tr("validation.missing_input_file")
        case .missingInputDirectory:
            return L10n.tr("validation.missing_input_directory")
        case .invalidBatchInputMode:
            return L10n.tr("validation.invalid_batch_input_mode")
        case .missingRealtimeInputDevice:
            return L10n.tr("validation.missing_realtime_input_device")
        case .missingRealtimeOutputDevice:
            return L10n.tr("validation.missing_realtime_output_device")
        }
    }
}
