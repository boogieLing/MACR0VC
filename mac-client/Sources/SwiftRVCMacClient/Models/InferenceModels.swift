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
    let modelInfoError: String?
    let indexPaths: [String]
    let speakerCount: Int
}

struct ModelUnloadResult: Codable {
    let modelName: String
    let modelInfoSummary: String
    let indexPaths: [String]
    let speakerCount: Int
    let unloaded: Bool
}

struct MemoryReleaseResult: Codable {
    let released: Bool
    let message: String
}

struct SingleInferenceRequest: Encodable {
    let modelName: String
    let inputFileURL: URL
    let speakerID: Int
    let transpose: Double
    let f0Method: F0Method
    let indexPath: String?
    let customIndexURL: URL?
    let indexRate: Double
    let filterRadius: Double
    let resampleSR: Double
    let rmsMixRate: Double
    let protect: Double
    let f0FileURL: URL?

    /// Returns the index path that should be sent to the backend, preferring an explicit override.
    var resolvedIndexPath: String? {
        if let customIndexURL {
            return customIndexURL.path
        }
        return indexPath
    }

    /// Validates local file inputs before serialization.
    func validate() throws {
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.missingModel
        }
        if !FileManager.default.fileExists(atPath: inputFileURL.path) {
            throw ValidationError.missingInputFile
        }
        try Self.validateOptionalFileURL(customIndexURL, error: .missingCustomIndexFile)
        try Self.validateOptionalFileURL(f0FileURL, error: .missingF0CurveFile)
    }

    /// Encodes the request using the resolved index path so backend payloads stay compatible.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(inputFileURL, forKey: .inputFileURL)
        try container.encode(speakerID, forKey: .speakerID)
        try container.encode(transpose, forKey: .transpose)
        try container.encode(f0Method, forKey: .f0Method)
        try container.encode(resolvedIndexPath, forKey: .indexPath)
        try container.encode(indexRate, forKey: .indexRate)
        try container.encode(filterRadius, forKey: .filterRadius)
        try container.encode(resampleSR, forKey: .resampleSR)
        try container.encode(rmsMixRate, forKey: .rmsMixRate)
        try container.encode(protect, forKey: .protect)
        try container.encode(f0FileURL, forKey: .f0FileURL)
    }

    private enum CodingKeys: String, CodingKey {
        case modelName
        case inputFileURL
        case speakerID = "speakerId"
        case transpose
        case f0Method
        case indexPath
        case indexRate
        case filterRadius
        case resampleSR
        case rmsMixRate
        case protect
        case f0FileURL
    }

    /// Reuses the same existence gate for optional path-based overrides.
    private static func validateOptionalFileURL(_ url: URL?, error: ValidationError) throws {
        guard let url else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            throw error
        }
    }
}

struct SingleInferenceResult: Codable {
    let message: String
    let outputAudioURL: URL?
}

struct BatchInferenceRequest: Encodable {
    let modelName: String
    let inputDirectoryURL: URL?
    let inputFileURLs: [URL]
    let outputDirectoryURL: URL
    let format: OutputFormat
    let speakerID: Int
    let transpose: Double
    let f0Method: F0Method
    let indexPath: String?
    let customIndexURL: URL?
    let indexRate: Double
    let filterRadius: Double
    let resampleSR: Double
    let rmsMixRate: Double
    let protect: Double

    /// Returns the index path that should be sent to the backend, preferring an explicit override.
    var resolvedIndexPath: String? {
        if let customIndexURL {
            return customIndexURL.path
        }
        return indexPath
    }

    /// Validates local file inputs before serialization.
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

        try Self.validateOptionalFileURL(customIndexURL, error: .missingCustomIndexFile)
    }

    /// Encodes the batch request using the resolved index path so backend payloads stay compatible.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(inputDirectoryURL, forKey: .inputDirectoryURL)
        try container.encode(inputFileURLs, forKey: .inputFileURLs)
        try container.encode(outputDirectoryURL, forKey: .outputDirectoryURL)
        try container.encode(format, forKey: .format)
        try container.encode(speakerID, forKey: .speakerID)
        try container.encode(transpose, forKey: .transpose)
        try container.encode(f0Method, forKey: .f0Method)
        try container.encode(resolvedIndexPath, forKey: .indexPath)
        try container.encode(indexRate, forKey: .indexRate)
        try container.encode(filterRadius, forKey: .filterRadius)
        try container.encode(resampleSR, forKey: .resampleSR)
        try container.encode(rmsMixRate, forKey: .rmsMixRate)
        try container.encode(protect, forKey: .protect)
    }

    private enum CodingKeys: String, CodingKey {
        case modelName
        case inputDirectoryURL
        case inputFileURLs
        case outputDirectoryURL
        case format
        case speakerID = "speakerId"
        case transpose
        case f0Method
        case indexPath
        case indexRate
        case filterRadius
        case resampleSR
        case rmsMixRate
        case protect
    }

    /// Reuses the same existence gate for optional path-based overrides.
    private static func validateOptionalFileURL(_ url: URL?, error: ValidationError) throws {
        guard let url else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            throw error
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
    case invalidUVRInputMode
    case missingRealtimeInputDevice
    case missingRealtimeOutputDevice
    case missingCustomIndexFile
    case missingF0CurveFile

    /// Maps validation failures to user-facing copy while keeping the existing localization behavior.
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
        case .invalidUVRInputMode:
            return "Choose either an input folder or explicit audio files for UVR."
        case .missingRealtimeInputDevice:
            return L10n.tr("validation.missing_realtime_input_device")
        case .missingRealtimeOutputDevice:
            return L10n.tr("validation.missing_realtime_output_device")
        case .missingCustomIndexFile:
            return "Custom index file does not exist."
        case .missingF0CurveFile:
            return "F0 curve file does not exist."
        }
    }
}
