import Foundation

@MainActor
protocol RVCBridgeClient {
    /// Refreshes the model catalog and index list from the backend.
    func refreshModels() async throws -> ModelCatalog

    /// Loads or re-selects the active model on the backend.
    func selectModel(name: String) async throws -> ModelSelectionResult

    /// Unloads the active model and returns a compact backend status payload.
    func unloadModel() async throws -> ModelUnloadResult

    /// Dispatches a single-file conversion request.
    func convertSingle(_ request: SingleInferenceRequest) async throws -> SingleInferenceResult

    /// Dispatches a batch conversion request.
    func convertBatch(_ request: BatchInferenceRequest) async throws -> BatchInferenceResult

    /// Refreshes the available UVR model catalog from the backend.
    func refreshUVRModels() async throws -> UVRModelCatalog

    /// Explicitly releases UVR-side runtime memory and cache state.
    func releaseUVRMemory() async throws -> MemoryReleaseResult

    /// Dispatches a UVR separation request.
    func convertUVR(_ request: UVRRequest) async throws -> UVRResult

    /// Runs the backend asset integrity check and returns a structured report.
    func fetchAssetIntegrityReport() async throws -> AssetIntegrityReport

    /// Triggers the backend asset downloader/update flow and returns the refreshed report when available.
    func downloadAssets() async throws -> AssetDownloadResult

    /// Exports an ONNX model from a checkpoint path to a chosen destination.
    func exportONNX(_ request: ONNXExportRequest) async throws -> ONNXExportResult

    /// Compares two checkpoint long IDs and returns the similarity result.
    func compareCheckpointHashes(_ request: CheckpointSimilarityRequest) async throws -> CheckpointSimilarityResult

    /// Loads checkpoint metadata text for the selected small model.
    func showCheckpointInfo(_ request: CheckpointInfoRequest) async throws -> CheckpointInfoResult

    /// Saves modified checkpoint metadata into the weights folder.
    func modifyCheckpointInfo(_ request: CheckpointModifyRequest) async throws -> CheckpointModifyResult

    /// Merges two checkpoints and writes the fused model into the weights folder.
    func mergeCheckpoints(_ request: CheckpointMergeRequest) async throws -> CheckpointMergeResult

    /// Extracts a small deployable model from a training checkpoint.
    func extractSmallCheckpoint(_ request: CheckpointExtractRequest) async throws -> CheckpointExtractResult

    /// Refreshes realtime device enumeration and selection state.
    func refreshRealtimeDevices() async throws -> RealtimeDeviceSnapshot

    /// Fetches the current realtime status envelope.
    func fetchRealtimeStatus() async throws -> RealtimeStatusEnvelope

    /// Applies a realtime configuration update and returns the refreshed status envelope.
    func configureRealtime(_ request: RealtimeConfigureRequest) async throws -> RealtimeStatusEnvelope

    /// Starts realtime processing with the requested configuration.
    func startRealtime(_ request: RealtimeStartRequest) async throws -> RealtimeStatus

    /// Stops realtime processing and returns the updated status.
    func stopRealtime() async throws -> RealtimeStatus
}

enum BridgeError: LocalizedError {
    case engineNotReady
    case invocationFailed(String)
    case invalidResponse

    /// Maps bridge failures to user-facing copy.
    var errorDescription: String? {
        switch self {
        case .engineNotReady:
            return L10n.tr("bridge.not_ready")
        case .invocationFailed(let message):
            return message
        case .invalidResponse:
            return L10n.tr("bridge.invalid_response")
        }
    }
}

@MainActor
final class PythonRVCBridgeClient: RVCBridgeClient {
    private let environment: AppEnvironment
    private let baseURLProvider: () -> URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a bridge client that shells out to the local Python bridge helper.
    init(environment: AppEnvironment, baseURLProvider: @escaping () -> URL?) {
        self.environment = environment
        self.baseURLProvider = baseURLProvider
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// Refreshes the model catalog and index list from the backend.
    func refreshModels() async throws -> ModelCatalog {
        let data = try await run(command: "refresh", arguments: [])
        return try decode(ModelCatalog.self, from: data)
    }

    /// Loads or re-selects the active model on the backend.
    func selectModel(name: String) async throws -> ModelSelectionResult {
        let data = try await run(command: "select-model", arguments: ["--name", name])
        return try decode(ModelSelectionResult.self, from: data)
    }

    /// Unloads the active model and returns a compact backend status payload.
    func unloadModel() async throws -> ModelUnloadResult {
        let data = try await run(command: "unload-model", arguments: [])
        return try decode(ModelUnloadResult.self, from: data)
    }

    /// Dispatches a single-file conversion request.
    func convertSingle(_ request: SingleInferenceRequest) async throws -> SingleInferenceResult {
        let requestData = try encoder.encode(request)
        let payload = String(decoding: requestData, as: UTF8.self)
        let data = try await run(command: "convert-single", arguments: ["--request-json", payload])
        return try decode(SingleInferenceResult.self, from: data)
    }

    /// Dispatches a batch conversion request.
    func convertBatch(_ request: BatchInferenceRequest) async throws -> BatchInferenceResult {
        let requestData = try encoder.encode(request)
        let payload = String(decoding: requestData, as: UTF8.self)
        let data = try await run(command: "convert-batch", arguments: ["--request-json", payload])
        return try decode(BatchInferenceResult.self, from: data)
    }

    /// Refreshes the available UVR model catalog from the backend.
    func refreshUVRModels() async throws -> UVRModelCatalog {
        let data = try await run(command: "uvr-models", arguments: [])
        return try decode(UVRModelCatalog.self, from: data)
    }

    /// Explicitly releases UVR-side runtime memory and cache state.
    func releaseUVRMemory() async throws -> MemoryReleaseResult {
        let data = try await run(command: "uvr-release", arguments: [])
        return try decode(MemoryReleaseResult.self, from: data)
    }

    /// Dispatches a UVR separation request.
    func convertUVR(_ request: UVRRequest) async throws -> UVRResult {
        let requestData = try encoder.encode(request)
        let payload = String(decoding: requestData, as: UTF8.self)
        let data = try await run(command: "uvr-convert", arguments: ["--request-json", payload])
        return try decode(UVRResult.self, from: data)
    }

    /// Runs the backend asset integrity check and returns a structured report.
    func fetchAssetIntegrityReport() async throws -> AssetIntegrityReport {
        let data = try await run(command: "asset-check", arguments: [])
        return try decode(AssetIntegrityReport.self, from: data)
    }

    /// Triggers the backend asset downloader/update flow and returns the refreshed report when available.
    func downloadAssets() async throws -> AssetDownloadResult {
        let data = try await run(command: "asset-download", arguments: [])
        return try decode(AssetDownloadResult.self, from: data)
    }

    /// Exports an ONNX model from a checkpoint path to a chosen destination.
    func exportONNX(_ request: ONNXExportRequest) async throws -> ONNXExportResult {
        let requestData = try encoder.encode(request)
        let payload = String(decoding: requestData, as: UTF8.self)
        let data = try await run(command: "export-onnx", arguments: ["--request-json", payload])
        return try decode(ONNXExportResult.self, from: data)
    }

    /// Compares two checkpoint long IDs and returns the similarity result.
    func compareCheckpointHashes(_ request: CheckpointSimilarityRequest) async throws -> CheckpointSimilarityResult {
        let requestData = try encoder.encode(request)
        let payload = String(decoding: requestData, as: UTF8.self)
        let data = try await run(command: "ckpt-compare", arguments: ["--request-json", payload])
        return try decode(CheckpointSimilarityResult.self, from: data)
    }

    /// Loads checkpoint metadata text for the selected small model.
    func showCheckpointInfo(_ request: CheckpointInfoRequest) async throws -> CheckpointInfoResult {
        let requestData = try encoder.encode(request)
        let payload = String(decoding: requestData, as: UTF8.self)
        let data = try await run(command: "ckpt-show", arguments: ["--request-json", payload])
        return try decode(CheckpointInfoResult.self, from: data)
    }

    /// Saves modified checkpoint metadata into the weights folder.
    func modifyCheckpointInfo(_ request: CheckpointModifyRequest) async throws -> CheckpointModifyResult {
        let requestData = try encoder.encode(request)
        let payload = String(decoding: requestData, as: UTF8.self)
        let data = try await run(command: "ckpt-modify", arguments: ["--request-json", payload])
        return try decode(CheckpointModifyResult.self, from: data)
    }

    /// Merges two checkpoints and writes the fused model into the weights folder.
    func mergeCheckpoints(_ request: CheckpointMergeRequest) async throws -> CheckpointMergeResult {
        let requestData = try encoder.encode(request)
        let payload = String(decoding: requestData, as: UTF8.self)
        let data = try await run(command: "ckpt-merge", arguments: ["--request-json", payload])
        return try decode(CheckpointMergeResult.self, from: data)
    }

    /// Extracts a small deployable model from a training checkpoint.
    func extractSmallCheckpoint(_ request: CheckpointExtractRequest) async throws -> CheckpointExtractResult {
        let requestData = try encoder.encode(request)
        let payload = String(decoding: requestData, as: UTF8.self)
        let data = try await run(command: "ckpt-extract", arguments: ["--request-json", payload])
        return try decode(CheckpointExtractResult.self, from: data)
    }

    /// Refreshes realtime device enumeration and selection state.
    func refreshRealtimeDevices() async throws -> RealtimeDeviceSnapshot {
        let data = try await run(command: "realtime-devices", arguments: [])
        return try decode(RealtimeDeviceSnapshot.self, from: data)
    }

    /// Fetches the current realtime status envelope.
    func fetchRealtimeStatus() async throws -> RealtimeStatusEnvelope {
        let data = try await run(command: "realtime-status", arguments: [])
        return try decode(RealtimeStatusEnvelope.self, from: data)
    }

    /// Applies a realtime configuration update and returns the refreshed status envelope.
    func configureRealtime(_ request: RealtimeConfigureRequest) async throws -> RealtimeStatusEnvelope {
        let requestData = try encoder.encode(request)
        let payload = String(decoding: requestData, as: UTF8.self)
        let data = try await run(command: "realtime-configure", arguments: ["--request-json", payload])
        return try decode(RealtimeStatusEnvelope.self, from: data)
    }

    /// Starts realtime processing with the requested configuration.
    func startRealtime(_ request: RealtimeStartRequest) async throws -> RealtimeStatus {
        let requestData = try encoder.encode(request)
        let payload = String(decoding: requestData, as: UTF8.self)
        let data = try await run(command: "realtime-start", arguments: ["--request-json", payload])
        return try decode(RealtimeStatus.self, from: data)
    }

    /// Stops realtime processing and returns the updated status.
    func stopRealtime() async throws -> RealtimeStatus {
        let data = try await run(command: "realtime-stop", arguments: [])
        return try decode(RealtimeStatus.self, from: data)
    }

    /// Decodes bridge payloads into strongly typed Swift models and wraps decode failures consistently.
    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw BridgeError.invocationFailed(
                L10n.tr("bridge.decode_failed", error.localizedDescription)
            )
        }
    }

    /// Invokes the Python bridge helper and captures JSON output from stdout.
    private func run(command: String, arguments: [String]) async throws -> Data {
        guard let baseURL = baseURLProvider() else {
            throw BridgeError.engineNotReady
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.currentDirectoryURL = environment.engineRoot

        let pythonPath = environment.preferredPythonExecutable
        if FileManager.default.isExecutableFile(atPath: pythonPath) {
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = [environment.bridgeScriptURL.path, "--base-url", baseURL.absoluteString, command] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", environment.bridgeScriptURL.path, "--base-url", baseURL.absoluteString, command] + arguments
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: outputData)
                    return
                }

                let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let errorText, !errorText.isEmpty {
                    continuation.resume(throwing: BridgeError.invocationFailed(errorText))
                } else {
                    continuation.resume(throwing: BridgeError.invalidResponse)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: BridgeError.invocationFailed(error.localizedDescription))
            }
        }
    }
}
