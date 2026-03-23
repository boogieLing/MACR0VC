import Foundation

@MainActor
final class RealtimeViewModel: ObservableObject {
    @Published var hostapis: [String] = []
    @Published var inputDevices: [String] = []
    @Published var outputDevices: [String] = []
    @Published var selectedHostapi: String?
    @Published var selectedInputDevice: String?
    @Published var selectedOutputDevice: String?
    @Published var sampleRate: Int = 0
    @Published var channels: Int = 1
    @Published var monitorMode: RealtimeMonitorMode = .outputConverted
    @Published var sampleRateMode: SampleRateMode = .model
    @Published var wasapiExclusive = false
    @Published var threshold = -60
    @Published var formant = 0.0
    @Published var sampleLength = 0.25
    @Published var fadeLength = 0.05
    @Published var extraInferenceTime = 2.5
    @Published var cpuProcesses = min(ProcessInfo.processInfo.processorCount, 4)
    @Published var inputNoiseReduction = false
    @Published var outputNoiseReduction = false
    @Published var usePhaseVocoder = false
    @Published private(set) var isRunning = false
    @Published private(set) var delayTimeMs = 0
    @Published private(set) var inferTimeMs = 0
    @Published private(set) var lastError: String?
    @Published private(set) var lastRunSummary: String?

    private let bridgeClient: RVCBridgeClient

    init(bridgeClient: RVCBridgeClient) {
        self.bridgeClient = bridgeClient
    }

    func refreshDevices() async throws {
        let snapshot = try await bridgeClient.refreshRealtimeDevices()
        applyDevices(snapshot)
    }

    func refreshStatus() async throws {
        let envelope = try await bridgeClient.fetchRealtimeStatus()
        applyDevices(envelope.devices)
        applyStatus(envelope.status)
    }

    func start(selectedModelName: String?, selectedIndexPath: String?, inferenceViewModel: InferenceViewModel) async {
        lastError = nil
        guard let selectedModelName else {
            lastError = ValidationError.missingModel.errorDescription
            return
        }

        let request = RealtimeStartRequest(
            modelName: selectedModelName,
            indexPath: selectedIndexPath,
            transpose: inferenceViewModel.transpose,
            formant: formant,
            indexRate: inferenceViewModel.indexRate,
            rmsMixRate: inferenceViewModel.rmsMixRate,
            f0Method: inferenceViewModel.f0Method,
            threshold: threshold,
            sampleLength: sampleLength,
            fadeLength: fadeLength,
            extraInferenceTime: extraInferenceTime,
            cpuProcesses: cpuProcesses,
            inputNoiseReduction: inputNoiseReduction,
            outputNoiseReduction: outputNoiseReduction,
            usePhaseVocoder: usePhaseVocoder,
            sampleRateMode: sampleRateMode,
            hostapi: selectedHostapi,
            inputDevice: selectedInputDevice,
            outputDevice: selectedOutputDevice,
            wasapiExclusive: wasapiExclusive,
            function: monitorMode
        )

        do {
            try request.validate()
            let status = try await bridgeClient.startRealtime(request)
            applyStatus(status)
            lastRunSummary = L10n.tr("status.realtime.started")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() async {
        do {
            let status = try await bridgeClient.stopRealtime()
            applyStatus(status)
            lastRunSummary = L10n.tr("status.realtime.stopped")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func configure(selectedModelName: String?, selectedIndexPath: String?, inferenceViewModel: InferenceViewModel) async {
        let request = RealtimeConfigureRequest(
            modelName: selectedModelName,
            indexPath: selectedIndexPath,
            transpose: inferenceViewModel.transpose,
            formant: formant,
            indexRate: inferenceViewModel.indexRate,
            rmsMixRate: inferenceViewModel.rmsMixRate,
            f0Method: inferenceViewModel.f0Method,
            threshold: threshold,
            sampleLength: sampleLength,
            fadeLength: fadeLength,
            extraInferenceTime: extraInferenceTime,
            cpuProcesses: cpuProcesses,
            inputNoiseReduction: inputNoiseReduction,
            outputNoiseReduction: outputNoiseReduction,
            usePhaseVocoder: usePhaseVocoder,
            sampleRateMode: sampleRateMode,
            hostapi: selectedHostapi,
            inputDevice: selectedInputDevice,
            outputDevice: selectedOutputDevice,
            wasapiExclusive: wasapiExclusive,
            function: monitorMode
        )

        do {
            let envelope = try await bridgeClient.configureRealtime(request)
            applyDevices(envelope.devices)
            applyStatus(envelope.status)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func applyDevices(_ snapshot: RealtimeDeviceSnapshot) {
        hostapis = snapshot.hostapis
        inputDevices = snapshot.inputDevices
        outputDevices = snapshot.outputDevices
        selectedHostapi = snapshot.selectedHostapi.isEmpty ? nil : snapshot.selectedHostapi
        selectedInputDevice = snapshot.selectedInputDevice.isEmpty ? nil : snapshot.selectedInputDevice
        selectedOutputDevice = snapshot.selectedOutputDevice.isEmpty ? nil : snapshot.selectedOutputDevice
        sampleRate = snapshot.sampleRate ?? sampleRate
        channels = snapshot.channels ?? channels
    }

    private func applyStatus(_ status: RealtimeStatus) {
        isRunning = status.running
        delayTimeMs = status.delayTimeMs
        inferTimeMs = status.inferTimeMs
        if !status.selectedHostapi.isEmpty {
            selectedHostapi = status.selectedHostapi
        }
        if !status.selectedInputDevice.isEmpty {
            selectedInputDevice = status.selectedInputDevice
        }
        if !status.selectedOutputDevice.isEmpty {
            selectedOutputDevice = status.selectedOutputDevice
        }
        sampleRate = status.sampleRate
        channels = status.channels
        if status.function == RealtimeMonitorMode.inputMonitor.rawValue {
            monitorMode = .inputMonitor
        } else {
            monitorMode = .outputConverted
        }
        lastError = status.lastError
    }
}
