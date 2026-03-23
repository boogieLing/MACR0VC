import Foundation

@MainActor
protocol RVCBridgeClient {
    func refreshModels() async throws -> ModelCatalog
    func selectModel(name: String) async throws -> ModelSelectionResult
    func convertSingle(_ request: SingleInferenceRequest) async throws -> SingleInferenceResult
    func convertBatch(_ request: BatchInferenceRequest) async throws -> BatchInferenceResult
    func refreshRealtimeDevices() async throws -> RealtimeDeviceSnapshot
    func fetchRealtimeStatus() async throws -> RealtimeStatusEnvelope
    func configureRealtime(_ request: RealtimeConfigureRequest) async throws -> RealtimeStatusEnvelope
    func startRealtime(_ request: RealtimeStartRequest) async throws -> RealtimeStatus
    func stopRealtime() async throws -> RealtimeStatus
}

enum BridgeError: LocalizedError {
    case engineNotReady
    case invocationFailed(String)
    case invalidResponse

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

    init(environment: AppEnvironment, baseURLProvider: @escaping () -> URL?) {
        self.environment = environment
        self.baseURLProvider = baseURLProvider
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func refreshModels() async throws -> ModelCatalog {
        let data = try await run(command: "refresh", arguments: [])
        return try decode(ModelCatalog.self, from: data)
    }

    func selectModel(name: String) async throws -> ModelSelectionResult {
        let data = try await run(command: "select-model", arguments: ["--name", name])
        return try decode(ModelSelectionResult.self, from: data)
    }

    func convertSingle(_ request: SingleInferenceRequest) async throws -> SingleInferenceResult {
        let requestData = try encoder.encode(request)
        let payload = String(decoding: requestData, as: UTF8.self)
        let data = try await run(command: "convert-single", arguments: ["--request-json", payload])
        return try decode(SingleInferenceResult.self, from: data)
    }

    func convertBatch(_ request: BatchInferenceRequest) async throws -> BatchInferenceResult {
        let requestData = try encoder.encode(request)
        let payload = String(decoding: requestData, as: UTF8.self)
        let data = try await run(command: "convert-batch", arguments: ["--request-json", payload])
        return try decode(BatchInferenceResult.self, from: data)
    }

    func refreshRealtimeDevices() async throws -> RealtimeDeviceSnapshot {
        let data = try await run(command: "realtime-devices", arguments: [])
        return try decode(RealtimeDeviceSnapshot.self, from: data)
    }

    func fetchRealtimeStatus() async throws -> RealtimeStatusEnvelope {
        let data = try await run(command: "realtime-status", arguments: [])
        return try decode(RealtimeStatusEnvelope.self, from: data)
    }

    func configureRealtime(_ request: RealtimeConfigureRequest) async throws -> RealtimeStatusEnvelope {
        let requestData = try encoder.encode(request)
        let payload = String(decoding: requestData, as: UTF8.self)
        let data = try await run(command: "realtime-configure", arguments: ["--request-json", payload])
        return try decode(RealtimeStatusEnvelope.self, from: data)
    }

    func startRealtime(_ request: RealtimeStartRequest) async throws -> RealtimeStatus {
        let requestData = try encoder.encode(request)
        let payload = String(decoding: requestData, as: UTF8.self)
        let data = try await run(command: "realtime-start", arguments: ["--request-json", payload])
        return try decode(RealtimeStatus.self, from: data)
    }

    func stopRealtime() async throws -> RealtimeStatus {
        let data = try await run(command: "realtime-stop", arguments: [])
        return try decode(RealtimeStatus.self, from: data)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw BridgeError.invocationFailed(
                L10n.tr("bridge.decode_failed", error.localizedDescription)
            )
        }
    }

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
