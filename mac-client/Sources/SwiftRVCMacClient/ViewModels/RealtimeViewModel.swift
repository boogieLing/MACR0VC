import Foundation

@MainActor
final class RealtimeViewModel: ObservableObject {
    private enum Defaults {
        static let monitorMode: RealtimeMonitorMode = .outputConverted
        static let sampleRateMode: SampleRateMode = .model
        static let wasapiExclusive = false
        static let threshold = -60
        static let formant = 0.0
        static let sampleLength = 0.25
        static let fadeLength = 0.05
        static let extraInferenceTime = 2.5
        static let inputNoiseReduction = false
        static let outputNoiseReduction = false
        static let usePhaseVocoder = false

        static var cpuProcesses: Int {
            min(ProcessInfo.processInfo.processorCount, 4)
        }
    }

    @Published var hostapis: [String] = []
    @Published var inputDevices: [String] = []
    @Published var outputDevices: [String] = []
    @Published var selectedHostapi: String?
    @Published var selectedInputDevice: String?
    @Published var selectedOutputDevice: String?
    @Published var sampleRate: Int = 0
    @Published var channels: Int = 1
    @Published var monitorMode: RealtimeMonitorMode = Defaults.monitorMode
    @Published var sampleRateMode: SampleRateMode = Defaults.sampleRateMode
    @Published var wasapiExclusive = Defaults.wasapiExclusive
    @Published var threshold = Defaults.threshold
    @Published var formant = Defaults.formant
    @Published var sampleLength = Defaults.sampleLength
    @Published var fadeLength = Defaults.fadeLength
    @Published var extraInferenceTime = Defaults.extraInferenceTime
    @Published var cpuProcesses = Defaults.cpuProcesses
    @Published var inputNoiseReduction = Defaults.inputNoiseReduction
    @Published var outputNoiseReduction = Defaults.outputNoiseReduction
    @Published var usePhaseVocoder = Defaults.usePhaseVocoder
    @Published private(set) var isRunning = false
    @Published private(set) var delayTimeMs = 0
    @Published private(set) var inferTimeMs = 0
    @Published private(set) var lastError: String?
    @Published private(set) var lastRunSummary: String?
    @Published private(set) var operation: RealtimeOperationSnapshot = .idle

    private let bridgeClient: RVCBridgeClient

    init(bridgeClient: RVCBridgeClient) {
        self.bridgeClient = bridgeClient
    }

    /// 清空本地 realtime 会话快照，避免在引擎未初始化 realtime 时保留旧路由或错误状态。
    func resetSessionState() {
        hostapis = []
        inputDevices = []
        outputDevices = []
        selectedHostapi = nil
        selectedInputDevice = nil
        selectedOutputDevice = nil
        sampleRate = 0
        channels = 1
        isRunning = false
        delayTimeMs = 0
        inferTimeMs = 0
        lastError = nil
        lastRunSummary = nil
        operation = .idle
        monitorMode = Defaults.monitorMode
        wasapiExclusive = Defaults.wasapiExclusive
    }

    /// 将 host、输入、输出与监听路由回退为默认自动配置。
    func resetRoutingDefaults() {
        selectedHostapi = nil
        selectedInputDevice = nil
        selectedOutputDevice = nil
        monitorMode = Defaults.monitorMode
        wasapiExclusive = Defaults.wasapiExclusive
    }

    /// 将实时实验区的滑杆与开关回退到默认基线。
    func resetLabDefaults() {
        sampleRateMode = Defaults.sampleRateMode
        threshold = Defaults.threshold
        formant = Defaults.formant
        sampleLength = Defaults.sampleLength
        fadeLength = Defaults.fadeLength
        extraInferenceTime = Defaults.extraInferenceTime
        cpuProcesses = Defaults.cpuProcesses
        inputNoiseReduction = Defaults.inputNoiseReduction
        outputNoiseReduction = Defaults.outputNoiseReduction
        usePhaseVocoder = Defaults.usePhaseVocoder
    }

    func refreshDevices() async throws {
        let snapshot = try await bridgeClient.refreshRealtimeDevices()
        applyDevices(snapshot)
    }

    func refreshStatus() async throws {
        let envelope = try await bridgeClient.fetchRealtimeStatus()
        applyDevices(envelope.devices)
        applyStatus(envelope.status)
        operation = envelope.operation
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
            operation = envelope.operation
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
