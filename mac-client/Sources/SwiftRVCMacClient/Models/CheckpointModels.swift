import Foundation

struct CheckpointSimilarityRequest: Codable {
    let modelIDA: String
    let modelIDB: String

    func validate() throws {
        guard !modelIDA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !modelIDB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BridgeError.invocationFailed("Enter both long model IDs before running comparison.")
        }
    }
}

struct CheckpointSimilarityResult: Codable {
    let message: String
    let similarity: String
}

struct CheckpointInfoRequest: Codable {
    let modelPath: URL

    func validate() throws {
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw ValidationError.missingInputFile
        }
    }
}

struct CheckpointInfoResult: Codable {
    let message: String
    let infoText: String
    let modelPath: URL
}

struct CheckpointModifyRequest: Codable {
    let modelPath: URL
    let infoText: String
    let saveName: String

    func validate() throws {
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw ValidationError.missingInputFile
        }
    }
}

struct CheckpointModifyResult: Codable {
    let message: String
    let outputModelPath: URL
}

struct CheckpointMergeRequest: Codable {
    let modelPathA: URL
    let modelPathB: URL
    let weightA: Double
    let targetSampleRate: String
    let hasPitchGuidance: Bool
    let infoText: String
    let saveName: String
    let version: String

    func validate() throws {
        guard FileManager.default.fileExists(atPath: modelPathA.path) else {
            throw ValidationError.missingInputFile
        }
        guard FileManager.default.fileExists(atPath: modelPathB.path) else {
            throw ValidationError.missingInputFile
        }
        guard !saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BridgeError.invocationFailed("Enter a save name before merging checkpoints.")
        }
    }
}

struct CheckpointMergeResult: Codable {
    let message: String
    let outputModelPath: URL
}

struct CheckpointExtractRequest: Codable {
    let modelPath: URL
    let saveName: String
    let author: String
    let targetSampleRate: String
    let hasPitchGuidance: Bool
    let infoText: String
    let version: String

    func validate() throws {
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw ValidationError.missingInputFile
        }
        guard !saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BridgeError.invocationFailed("Enter a save name before extracting a small model.")
        }
    }
}

struct CheckpointExtractResult: Codable {
    let message: String
    let outputModelPath: URL
}
