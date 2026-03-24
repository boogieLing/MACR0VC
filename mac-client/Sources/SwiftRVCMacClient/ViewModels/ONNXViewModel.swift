import AppKit
import Foundation

@MainActor
final class ONNXViewModel: ObservableObject {
    @Published var modelFileURL: URL?
    @Published var exportFileURL: URL?
    @Published var isRunning = false
    @Published var outputMessage = ""
    @Published var errorMessage: String?
    @Published private(set) var lastRunSummary: String?

    private let bridgeClient: RVCBridgeClient

    init(bridgeClient: RVCBridgeClient) {
        self.bridgeClient = bridgeClient
    }

    func export() async {
        errorMessage = nil
        outputMessage = ""

        guard let modelFileURL, let exportFileURL else {
            errorMessage = "Choose both an input checkpoint and an output ONNX path."
            return
        }

        let request = ONNXExportRequest(modelPath: modelFileURL, exportPath: exportFileURL)

        do {
            try request.validate()
            isRunning = true
            let startedAt = Date()
            let result = try await bridgeClient.exportONNX(request)
            let duration = Date().timeIntervalSince(startedAt)
            outputMessage = result.message
            self.exportFileURL = result.exportedPath
            lastRunSummary = "ONNX export finished in \(duration.formatted(.number.precision(.fractionLength(1))))s"
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }

    func revealExportedFile() {
        guard let exportFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([exportFileURL])
    }
}
