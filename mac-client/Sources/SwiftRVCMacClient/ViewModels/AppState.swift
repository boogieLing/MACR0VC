import Combine
import Foundation
import AppKit
import Darwin

enum BusyScope: Hashable {
    case bootstrap
    case catalogRefresh
    case modelSelection

    var priority: Int {
        switch self {
        case .bootstrap:
            return 3
        case .modelSelection:
            return 2
        case .catalogRefresh:
            return 1
        }
    }
}

struct BusyDescriptor: Equatable {
    let scope: BusyScope
    let message: String
    let priority: Int
}

enum PrimaryInputMode: String, Equatable {
    case file
    case text

    var queueLabel: String {
        switch self {
        case .file:
            return "File / audio"
        case .text:
            return "Text prompt"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var navigation: NavigationDestination = .singleConvert
    @Published var models: [ModelOption] = []
    @Published var indexPaths: [String] = []
    @Published var selectedModelName: String?
    @Published var modelInfoSummary = L10n.tr("status.model_info.initial")
    @Published var statusMessage = L10n.tr("status.waiting_engine")
    @Published var lastExecutionSummary = L10n.tr("status.last_run.none")
    @Published var isRefreshingModels = false
    @Published var isNavigating = false
    @Published var isBootstrapping = false
    @Published private(set) var activeBusyDescriptor: BusyDescriptor?
    @Published var toast: AppToast?
    @Published var selectedModelSizeLabel = "—"
    @Published var selectedIndexSizeLabel = "—"
    @Published var selectedSpeakerCount = 0
    @Published var appMemoryLabel = "—"
    @Published var engineMemoryLabel = "—"
    @Published private(set) var taskHistory: [TaskHistoryEntry] = []
    @Published var primaryInputMode: PrimaryInputMode = .file
    @Published var textAudioInput = ""
    @Published var selectedTextAudioGender: TextAudioGenderID = .female
    @Published var selectedTextAudioToneMode: TextAudioToneMode = .preset
    @Published var selectedTextAudioTonePreset: TextAudioTonePresetID? = .femaleNatural
    @Published var customTextAudioTone = ""
    @Published var selectedTextAudioMatchProfile: TextAudioMatchProfileID = .identityLock
    @Published var textAudioTranspose: Double = 11
    @Published var textAudioSpeechRate: TextAudioSpeechRateID = .medium
    @Published var textAudioF0Method: F0Method = .crepe
    @Published var textAudioIndexRate: Double = 0.92
    @Published var textAudioFilterRadius: Double = 3
    @Published var textAudioResampleSR: Double = 0
    @Published var textAudioRmsMixRate: Double = 0.88
    @Published var textAudioProtect: Double = 0.08
    @Published private(set) var textAudioErrorMessage: String?
    @Published private(set) var isGeneratingTextAudio = false
    @Published private(set) var textAudioRunStartedAt: Date?
    @Published private(set) var textAudioProgress: TextAudioProgressSnapshot?
    @Published private(set) var backgroundAudioURL: URL?
    @Published var isBackgroundMixEnabled = false
    @Published var backgroundMixLevel = 0.34
    @Published private(set) var isPreparingBackgroundMix = false
    @Published private(set) var isPersistingBackgroundMix = false
    @Published private(set) var mixedOutputURL: URL?

    let environment: AppEnvironment
    var engineController: EngineController
    var audioPlayer: AudioPreviewPlayer
    var inferenceViewModel: InferenceViewModel
    var batchViewModel: BatchViewModel
    var realtimeViewModel: RealtimeViewModel
    var uvrViewModel: UVRViewModel
    var assetAuditViewModel: AssetAuditViewModel
    var onnxViewModel: ONNXViewModel
    var checkpointToolsViewModel: CheckpointToolsViewModel

    private let bridgeClient: RVCBridgeClient
    private let managedOutputStorage: ManagedOutputStorage
    private let audioCompositeService: AudioCompositeService
    private let userDefaults: UserDefaults
    private var hasBootstrapped = false
    private var cancellables: Set<AnyCancellable> = []
    private var navigationResetTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var metricsTask: Task<Void, Never>?
    private var backgroundPreviewRefreshTask: Task<Void, Never>?
    private var textAudioProgressTask: Task<Void, Never>?
    private var busyDescriptors: [BusyScope: BusyDescriptor] = [:]
    private let taskHistoryDefaultsKey = "local.r0.SwiftRVCMacClient.taskHistory.v1"
    private let maxTaskHistoryCount = 80
    private var pendingSingleReservation: ManagedTaskOutputReservation?
    private var pendingBatchReservation: ManagedTaskOutputReservation?
    private var pendingTextAudioReservation: ManagedTaskOutputReservation?
    private var pendingUVRReservation: ManagedTaskOutputReservation?
    private var currentBackgroundPreviewURL: URL?

    /// 清洗后端返回的模型摘要，过滤空白内容和 traceback 噪音。
    private func sanitizedModelInfoSummary(_ raw: String) -> String {
        let summary = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return "" }
        if summary.contains("Traceback (most recent call last):") {
            return ""
        }
        return summary
    }

    /// 构建应用级状态容器，并允许测试注入轻量依赖替身。
    init(
        environment: AppEnvironment,
        engineController: EngineController? = nil,
        audioPlayer: AudioPreviewPlayer? = nil,
        bridgeClient: RVCBridgeClient? = nil,
        startMetricsTask: Bool = true,
        userDefaults: UserDefaults = .standard
    ) {
        self.environment = environment
        self.userDefaults = userDefaults

        let resolvedEngineController = engineController ?? EngineController(environment: environment)
        let resolvedAudioPlayer = audioPlayer ?? AudioPreviewPlayer()
        let resolvedBridgeClient = bridgeClient ?? PythonRVCBridgeClient(environment: environment) {
            resolvedEngineController.baseURL
        }

        self.engineController = resolvedEngineController
        self.audioPlayer = resolvedAudioPlayer
        self.bridgeClient = resolvedBridgeClient
        self.managedOutputStorage = ManagedOutputStorage(environment: environment)
        self.audioCompositeService = AudioCompositeService()
        self.inferenceViewModel = InferenceViewModel(bridgeClient: resolvedBridgeClient, audioPlayer: resolvedAudioPlayer)
        self.batchViewModel = BatchViewModel(bridgeClient: resolvedBridgeClient)
        self.realtimeViewModel = RealtimeViewModel(bridgeClient: resolvedBridgeClient)
        self.uvrViewModel = UVRViewModel(bridgeClient: resolvedBridgeClient)
        self.assetAuditViewModel = AssetAuditViewModel(bridgeClient: resolvedBridgeClient)
        self.onnxViewModel = ONNXViewModel(bridgeClient: resolvedBridgeClient)
        self.checkpointToolsViewModel = CheckpointToolsViewModel(bridgeClient: resolvedBridgeClient)
        self.taskHistory = Self.loadTaskHistory(from: userDefaults, key: taskHistoryDefaultsKey)
        try? managedOutputStorage.prepareBaseDirectories()
        cleanupBackgroundPreviewCache()

        batchViewModel.outputDirectoryURL = environment.defaultBatchOutputDirectory
        uvrViewModel.vocalOutputDirectoryURL = environment.defaultUVROutputDirectory.appendingPathComponent("vocals", isDirectory: true)
        uvrViewModel.instrumentalOutputDirectoryURL = environment.defaultUVROutputDirectory.appendingPathComponent("instrumentals", isDirectory: true)

        inferenceViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.lastExecutionSummary = summary
                self?.presentToast(message: summary, style: .success)
                self?.recordSingleTaskHistory(status: .success, summary: summary)
            }
            .store(in: &cancellables)

        inferenceViewModel.$outputAudioURL
            .sink { [weak self] url in
                self?.refreshBackgroundContext(forForegroundURL: url)
            }
            .store(in: &cancellables)

        batchViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.lastExecutionSummary = summary
                self?.presentToast(message: summary, style: .success)
                self?.recordBatchTaskHistory(status: .success, summary: summary)
            }
            .store(in: &cancellables)

        uvrViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.lastExecutionSummary = summary
                self?.presentToast(message: summary, style: .success)
                self?.recordUVRTaskHistory(status: .success, summary: summary)
            }
            .store(in: &cancellables)

        assetAuditViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.statusMessage = summary
                self?.presentToast(message: summary, style: .info)
            }
            .store(in: &cancellables)

        onnxViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.lastExecutionSummary = summary
                self?.presentToast(message: summary, style: .success)
            }
            .store(in: &cancellables)

        checkpointToolsViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.lastExecutionSummary = summary
                self?.presentToast(message: summary, style: .success)
            }
            .store(in: &cancellables)

        inferenceViewModel.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
                self?.recordSingleTaskHistory(status: .failure, summary: message)
            }
            .store(in: &cancellables)

        batchViewModel.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
                self?.recordBatchTaskHistory(status: .failure, summary: message)
            }
            .store(in: &cancellables)

        uvrViewModel.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
                self?.recordUVRTaskHistory(status: .failure, summary: message)
            }
            .store(in: &cancellables)

        assetAuditViewModel.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
            }
            .store(in: &cancellables)

        onnxViewModel.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
            }
            .store(in: &cancellables)

        checkpointToolsViewModel.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
            }
            .store(in: &cancellables)

        realtimeViewModel.$lastError
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
                self?.recordRealtimeTaskHistory(status: .failure, summary: message)
            }
            .store(in: &cancellables)

        realtimeViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.statusMessage = summary
                self?.presentToast(message: summary, style: .info)
                self?.recordRealtimeTaskHistory(status: .info, summary: summary)
            }
            .store(in: &cancellables)

        resolvedEngineController.$lastError
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
            }
            .store(in: &cancellables)

        if startMetricsTask {
            startMetricsPolling()
        }
    }

    var availablePortDescription: String {
        engineController.port.map(String.init) ?? "—"
    }

    var effectiveSelectedIndexPath: String? {
        inferenceViewModel.effectiveIndexPath
    }

    var isBusy: Bool {
        activeBusyDescriptor != nil
    }

    var isBootstrapBusy: Bool {
        busyDescriptors[.bootstrap] != nil
    }

    var isCatalogBusy: Bool {
        busyDescriptors[.catalogRefresh] != nil
    }

    var isModelSelectionBusy: Bool {
        busyDescriptors[.modelSelection] != nil
    }

    var modelSelectionBusyMessage: String? {
        busyDescriptors[.modelSelection]?.message
    }

    /// 进入统一等待态，并按优先级刷新当前展示中的忙碌文案。
    func beginBusy(_ scope: BusyScope, modelName: String? = nil) {
        busyDescriptors[scope] = BusyDescriptor(
            scope: scope,
            message: busyMessage(for: scope, modelName: modelName),
            priority: scope.priority
        )
        synchronizeBusyDescriptor()
    }

    /// 结束指定等待态，并在多等待源并存时恢复到剩余的最高优先级提示。
    func endBusy(_ scope: BusyScope) {
        busyDescriptors.removeValue(forKey: scope)
        synchronizeBusyDescriptor()
    }

    /// 执行首次启动自举流程，并保证启动等待态覆盖整个初始化链路。
    func performInitialBootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        beginBusy(.bootstrap)
        defer { endBusy(.bootstrap) }
        await startEngine()
    }

    /// 启动本地引擎，并在成功后刷新模型目录和实时上下文。
    func startEngine() async {
        statusMessage = L10n.tr("status.engine.starting")
        await engineController.start()
        if engineController.state == .ready {
            statusMessage = L10n.tr("status.engine.ready", availablePortDescription)
            presentToast(message: statusMessage, style: .success)
            await refreshModels()
            await refreshRealtimeContext()
        }
    }

    /// 重启本地引擎，并在成功后重新同步模型和实时状态。
    func restartEngine() async {
        statusMessage = L10n.tr("status.engine.restart")
        await engineController.restart()
        if engineController.state == .ready {
            statusMessage = L10n.tr("status.engine.restarted", availablePortDescription)
            presentToast(message: statusMessage, style: .success)
            await refreshModels()
            await refreshRealtimeContext()
        }
    }

    /// 重新探测并切换到兼容版本的后端实例，避免前端挂到旧引擎。
    func refreshEngineConnection() async {
        statusMessage = "Refreshing backend connection..."
        await engineController.refreshConnection()
        if engineController.state == .ready {
            statusMessage = "Connected to backend \(engineController.backendVersionLabel) on \(availablePortDescription)."
            presentToast(message: statusMessage, style: .success)
            await refreshModels()
            await refreshRealtimeContext()
        } else if let lastError = engineController.lastError {
            statusMessage = lastError
            presentToast(message: lastError, style: .error)
        }
    }

    /// 停止本地引擎并广播已停止状态。
    func stopEngine() {
        engineController.stop()
        statusMessage = L10n.tr("status.engine.stopped")
        presentToast(message: statusMessage, style: .info)
    }

    /// 刷新模型与索引目录，并在非自举阶段独立维护目录刷新等待态。
    func refreshModels() async {
        guard engineController.state == .ready else {
            statusMessage = L10n.tr("status.engine.refresh_first")
            presentToast(message: statusMessage, style: .info)
            return
        }

        let managesCatalogBusy = !isBootstrapping
        if managesCatalogBusy {
            beginBusy(.catalogRefresh)
        }
        isRefreshingModels = true
        defer {
            isRefreshingModels = false
            if managesCatalogBusy {
                endBusy(.catalogRefresh)
            }
        }

        do {
            let catalog = try await bridgeClient.refreshModels()
            models = catalog.models.map { model in
                var sanitized = model
                sanitized.infoSummary = sanitizedModelInfoSummary(model.infoSummary)
                return sanitized
            }
            indexPaths = catalog.indexPaths
            inferenceViewModel.ensureSelectedIndexAvailable(indexPaths)
            batchViewModel.ensureSelectedIndexAvailable(indexPaths)
            try await uvrViewModel.refreshModels()
            statusMessage = L10n.tr("status.catalog.loaded", models.count, indexPaths.count)
            presentToast(message: statusMessage, style: .success)
        } catch {
            statusMessage = error.localizedDescription
            presentToast(message: error.localizedDescription, style: .error)
        }
    }

    /// 将同一个索引路径同步给单文件和批处理两个推理面板。
    func selectSharedIndexPath(_ path: String?) {
        inferenceViewModel.customIndexURL = nil
        batchViewModel.customIndexURL = nil
        inferenceViewModel.selectedIndexPath = path
        batchViewModel.selectedIndexPath = path
    }

    /// 设置单文件输入音频，保留批处理输入队列不变。
    func setSingleInputFileURL(_ url: URL?) {
        primaryInputMode = .file
        inferenceViewModel.inputFileURL = url
        guard let url else { return }
        let message = "Loaded file \(url.lastPathComponent). Ready for single convert."
        statusMessage = message
        presentToast(message: message, style: .success)
    }

    /// 设置批处理输入目录，并清理互斥的显式文件队列与单文件输入。
    func setBatchInputDirectoryURL(_ url: URL?) {
        primaryInputMode = .file
        batchViewModel.inputDirectoryURL = url
        if url != nil {
            batchViewModel.inputFileURLs = []
            inferenceViewModel.inputFileURL = nil
        }
    }

    /// 设置批处理输入文件集合，并在仅选中一个文件时同步为单文件输入。
    func setBatchInputFileURLs(_ urls: [URL]) {
        primaryInputMode = .file
        batchViewModel.inputFileURLs = urls
        if !urls.isEmpty {
            batchViewModel.inputDirectoryURL = nil
        }
        inferenceViewModel.inputFileURL = urls.count == 1 ? urls[0] : nil
        guard !urls.isEmpty else { return }
        let message: String
        if urls.count == 1, let first = urls.first {
            message = "Loaded 1 file: \(first.lastPathComponent). Single convert is ready."
        } else {
            message = "Loaded \(urls.count) files into the batch queue."
        }
        statusMessage = message
        presentToast(message: message, style: .success)
    }

    /// 设置文本转音频输入，并清理互斥的文件型输入来源。
    func setTextAudioInput(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        primaryInputMode = .text
        textAudioInput = trimmedText
        textAudioErrorMessage = nil
        textAudioProgress = nil
        inferenceViewModel.inputFileURL = nil
        batchViewModel.inputDirectoryURL = nil
        batchViewModel.inputFileURLs = []
        guard !trimmedText.isEmpty else { return }
        let preview = String(trimmedText.prefix(32))
        let message = "Loaded text prompt: \(preview)"
        statusMessage = message
        presentToast(message: message, style: .success)
    }

    /// 返回当前性别下可用的 tone preset，避免 UI 继续展示无效组合。
    var availableTextAudioTonePresets: [TextAudioTonePresetID] {
        TextAudioTonePresetID.presets(for: selectedTextAudioGender)
    }

    /// 统一返回当前 text-audio 要使用的 tone preset，自定义语气时回退到性别默认基线。
    var effectiveTextAudioTonePreset: TextAudioTonePresetID {
        if let selectedTextAudioTonePreset, availableTextAudioTonePresets.contains(selectedTextAudioTonePreset) {
            return selectedTextAudioTonePreset
        }
        return selectedTextAudioGender.defaultTonePreset
    }

    /// 当前语气标签需要同时支持预设与自定义文本。
    var effectiveTextAudioToneLabel: String {
        if selectedTextAudioToneMode == .custom {
            let trimmedCustomTone = customTextAudioTone.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedCustomTone.isEmpty ? "Custom tone" : trimmedCustomTone
        }
        return effectiveTextAudioTonePreset.displayName
    }

    /// 根据当前目标模型做保守性别推断，仅用于 text-to-audio 自动参数收敛。
    var effectiveTextAudioTargetGenderHint: TargetVoiceGenderHint {
        TargetVoiceGenderHint.infer(
            modelName: selectedModelName,
            infoSummary: modelInfoSummary
        )
    }

    /// 将当前可调主参数打包成统一结构，便于请求、摘要和历史共用。
    var effectiveTextAudioParameterBundle: TextAudioParameterBundle {
        TextAudioParameterBundle(
            transpose: textAudioTranspose,
            speechRate: textAudioSpeechRate,
            f0Method: textAudioF0Method,
            indexRate: textAudioIndexRate,
            filterRadius: textAudioFilterRadius,
            resampleSR: textAudioResampleSR,
            rmsMixRate: textAudioRmsMixRate,
            protect: textAudioProtect
        )
        .normalized(
            for: selectedTextAudioGender,
            targetGenderHint: effectiveTextAudioTargetGenderHint
        )
    }

    /// 切换文本任务性别基线时，顺带修正 tone preset 与默认参数。
    func setTextAudioGender(_ gender: TextAudioGenderID) {
        guard selectedTextAudioGender != gender else { return }
        selectedTextAudioGender = gender
        if let selectedTextAudioTonePreset {
            if !availableTextAudioTonePresets.contains(selectedTextAudioTonePreset) {
                self.selectedTextAudioTonePreset = gender.defaultTonePreset
            }
        } else {
            selectedTextAudioTonePreset = gender.defaultTonePreset
        }
        applyTextAudioDefaultsFromSelection()
    }

    /// 预设模式下直接选择 tone，并重新套用目标音色匹配参数。
    func setTextAudioTonePreset(_ preset: TextAudioTonePresetID) {
        selectedTextAudioGender = preset.gender
        selectedTextAudioToneMode = .preset
        selectedTextAudioTonePreset = preset
        if selectedTextAudioMatchProfile == .customToneLock {
            selectedTextAudioMatchProfile = .identityLock
        }
        applyTextAudioDefaultsFromSelection()
    }

    /// 在 preset / custom 间切换时，同时校正允许使用的匹配策略。
    func setTextAudioToneMode(_ mode: TextAudioToneMode) {
        guard selectedTextAudioToneMode != mode else { return }
        selectedTextAudioToneMode = mode
        switch mode {
        case .preset:
            if selectedTextAudioTonePreset == nil {
                selectedTextAudioTonePreset = selectedTextAudioGender.defaultTonePreset
            }
            if selectedTextAudioMatchProfile == .customToneLock {
                selectedTextAudioMatchProfile = .identityLock
            }
        case .custom:
            selectedTextAudioMatchProfile = .customToneLock
        }
        applyTextAudioDefaultsFromSelection()
    }

    /// 匹配策略直接映射到参数默认值，因此在切换后立即覆盖当前 tune。
    func setTextAudioMatchProfile(_ profile: TextAudioMatchProfileID) {
        guard selectedTextAudioMatchProfile != profile else { return }
        selectedTextAudioMatchProfile = profile
        applyTextAudioDefaultsFromSelection()
    }

    /// 当用户回到自动推荐值时，用当前 gender / tone / match profile 重新铺满主参数。
    func applyTextAudioDefaultsFromSelection() {
        let defaultBundle = effectiveTextAudioTonePreset
            .baseParameterBundle
            .applying(matchProfile: selectedTextAudioMatchProfile)
            .normalized(
                for: selectedTextAudioGender,
                targetGenderHint: effectiveTextAudioTargetGenderHint
            )
        textAudioTranspose = defaultBundle.transpose
        textAudioSpeechRate = defaultBundle.speechRate
        textAudioF0Method = defaultBundle.f0Method
        textAudioIndexRate = defaultBundle.indexRate
        textAudioFilterRadius = defaultBundle.filterRadius
        textAudioResampleSR = defaultBundle.resampleSR
        textAudioRmsMixRate = defaultBundle.rmsMixRate
        textAudioProtect = defaultBundle.protect
    }

    /// 当目标模型已明显是女声且源声线也选择女声时，主动撤掉自动升调，避免二次抬高。
    private func syncTextAudioTransposeForSelectedModel() {
        guard selectedTextAudioGender == .female, effectiveTextAudioTargetGenderHint == .female else {
            return
        }
        if textAudioTranspose > 0 {
            textAudioTranspose = 0
        }
    }

    /// 设置共享自定义索引文件，并覆盖两个推理面板的当前索引来源。
    func setSharedCustomIndexURL(_ url: URL) {
        inferenceViewModel.customIndexURL = url
        batchViewModel.customIndexURL = url
        inferenceViewModel.selectedIndexPath = url.path
        batchViewModel.selectedIndexPath = url.path
    }

    /// 清空共享自定义索引文件，并回退仍指向该文件的索引选择状态。
    func clearSharedCustomIndexURL() {
        let currentCustomPath = inferenceViewModel.customIndexURL?.path ?? batchViewModel.customIndexURL?.path
        inferenceViewModel.customIndexURL = nil
        batchViewModel.customIndexURL = nil
        if inferenceViewModel.selectedIndexPath == currentCustomPath {
            inferenceViewModel.selectedIndexPath = nil
        }
        if batchViewModel.selectedIndexPath == currentCustomPath {
            batchViewModel.selectedIndexPath = nil
        }
    }

    /// 从后端重新拉取实时设备和运行状态。
    func refreshRealtimeContext() async {
        guard engineController.state == .ready else { return }
        do {
            try await realtimeViewModel.refreshDevices()
            try await realtimeViewModel.refreshStatus()
        } catch {
            statusMessage = error.localizedDescription
            presentToast(message: error.localizedDescription, style: .error)
        }
    }

    /// 刷新 UVR 模型目录，供 UVR 面板下拉框使用。
    func refreshUVRModels() async {
        guard engineController.state == .ready else { return }
        do {
            try await uvrViewModel.refreshModels()
        } catch {
            statusMessage = error.localizedDescription
            presentToast(message: error.localizedDescription, style: .error)
        }
    }

    /// 使用当前模型和索引启动实时变声链路。
    func startRealtime() async {
        await realtimeViewModel.start(
            selectedModelName: selectedModelName,
            selectedIndexPath: effectiveSelectedIndexPath,
            inferenceViewModel: inferenceViewModel
        )
        await refreshRealtimeContext()
    }

    /// 停止实时变声链路，并刷新后端状态快照。
    func stopRealtime() async {
        await realtimeViewModel.stop()
        await refreshRealtimeContext()
    }

    /// 将当前实时参数重新推送到运行中的实时链路。
    func applyRealtimeConfiguration() async {
        await realtimeViewModel.configure(
            selectedModelName: selectedModelName,
            selectedIndexPath: effectiveSelectedIndexPath,
            inferenceViewModel: inferenceViewModel
        )
    }

    /// 切换当前模型，并让等待态持续到实时配置同步结束为止。
    func selectModel(_ name: String) async {
        guard !name.isEmpty else { return }

        beginBusy(.modelSelection, modelName: name)
        defer { endBusy(.modelSelection) }

        do {
            if let currentModel = selectedModelName, currentModel != name {
                _ = try await bridgeClient.unloadModel()
            }
            let result = try await bridgeClient.selectModel(name: name)
            let sanitizedSummary = sanitizedModelInfoSummary(result.modelInfoSummary)
            selectedModelName = result.modelName
            modelInfoSummary = sanitizedSummary.isEmpty ? L10n.tr("models.no_info") : sanitizedSummary
            selectedSpeakerCount = result.speakerCount
            if !result.indexPaths.isEmpty {
                indexPaths = result.indexPaths
            }
            clearSharedCustomIndexURL()
            inferenceViewModel.speakerID = 0
            batchViewModel.speakerID = 0
            let normalizedModelName = name.replacingOccurrences(of: ".pth", with: "")
            let indexMatch = indexPaths.first {
                $0.localizedCaseInsensitiveContains(normalizedModelName)
            }

            selectSharedIndexPath(indexMatch)

            if let modelIndex = models.firstIndex(where: { $0.name == name }) {
                models[modelIndex].indexPath = indexMatch ?? ""
                models[modelIndex].infoSummary = sanitizedSummary
                models[modelIndex].speakerCount = result.speakerCount
            }
            syncTextAudioTransposeForSelectedModel()
            if let modelInfoError = result.modelInfoError?.trimmingCharacters(in: .whitespacesAndNewlines),
               !modelInfoError.isEmpty {
                statusMessage = "Model loaded, but metadata inspection failed: \(modelInfoError)"
                presentToast(message: statusMessage, style: .error)
            } else {
                statusMessage = L10n.tr("status.model.loaded", name)
                presentToast(message: statusMessage, style: .success)
            }
            await realtimeViewModel.configure(
                selectedModelName: selectedModelName,
                selectedIndexPath: effectiveSelectedIndexPath,
                inferenceViewModel: inferenceViewModel
            )
        } catch {
            statusMessage = error.localizedDescription
            presentToast(message: error.localizedDescription, style: .error)
        }
    }

    /// 卸载当前模型，并清空与模型相关的本地派生状态。
    func unloadModel() async {
        guard engineController.state == .ready else {
            statusMessage = L10n.tr("status.engine.refresh_first")
            presentToast(message: statusMessage, style: .info)
            return
        }

        do {
            let result = try await bridgeClient.unloadModel()
            resetLoadedModelState(indexPaths: result.indexPaths, speakerCount: result.speakerCount)
            statusMessage = result.unloaded ? "Model unloaded." : "Model unload returned no-op."
            presentToast(message: statusMessage, style: .info)
            await refreshRealtimeContext()
        } catch {
            statusMessage = error.localizedDescription
            presentToast(message: error.localizedDescription, style: .error)
        }
    }

    /// 统一释放模型、实时与 UVR 占用的运行时缓存。
    func releaseRuntimeCaches() async {
        guard engineController.state == .ready else {
            statusMessage = L10n.tr("status.engine.refresh_first")
            presentToast(message: statusMessage, style: .info)
            return
        }

        do {
            let result = try await bridgeClient.releaseRuntimeMemory()
            resetLoadedModelState(indexPaths: indexPaths, speakerCount: 0)
            uvrViewModel.errorMessage = nil
            uvrViewModel.outputMessage = ""
            statusMessage = result.message
            presentToast(message: result.message, style: .info)
            await refreshRealtimeContext()
        } catch {
            statusMessage = error.localizedDescription
            presentToast(message: error.localizedDescription, style: .error)
        }
    }

    /// 切换当前页面，并短暂标记导航过渡状态。
    func navigate(to destination: NavigationDestination) {
        guard navigation != destination else { return }
        navigation = destination
        isNavigating = true
        navigationResetTask?.cancel()
        navigationResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard let self, !Task.isCancelled else { return }
            self.isNavigating = false
        }
    }

    /// 打开模型权重目录。
    func openWeightsDirectory() {
        openDirectory(environment.weightsDirectory, label: L10n.tr("status.folder.model_weights"))
    }

    /// 清空当前已加载模型相关的本地派生状态。
    private func resetLoadedModelState(indexPaths: [String], speakerCount: Int) {
        selectedModelName = nil
        modelInfoSummary = L10n.tr("status.model_info.initial")
        self.indexPaths = indexPaths
        selectedSpeakerCount = speakerCount
        selectedModelSizeLabel = "—"
        selectedIndexSizeLabel = "—"
        inferenceViewModel.selectedIndexPath = nil
        inferenceViewModel.customIndexURL = nil
        inferenceViewModel.f0FileURL = nil
        inferenceViewModel.speakerID = 0
        batchViewModel.selectedIndexPath = nil
        batchViewModel.customIndexURL = nil
        batchViewModel.speakerID = 0
    }

    /// 打开索引文件目录。
    func openIndicesDirectory() {
        openDirectory(environment.indicesDirectory, label: L10n.tr("status.folder.index_files"))
    }

    /// 确保目录存在后在 Finder 中打开，并反馈结果 toast。
    private func openDirectory(_ directoryURL: URL, label: String) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directoryURL)
            statusMessage = L10n.tr("status.folder.opened", label)
            presentToast(message: statusMessage, style: .info)
        } catch {
            let message = L10n.tr("status.folder.failed", label, error.localizedDescription)
            statusMessage = message
            presentToast(message: message, style: .error)
        }
    }

    /// 立即关闭当前 toast，并取消自动消失任务。
    func dismissToast() {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        toast = nil
    }

    /// 展示一条新的 toast，并启动自动消失计时。
    func presentToast(message: String, style: AppToast.Style) {
        toastDismissTask?.cancel()
        toast = AppToast(message: message, style: style)
        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            self.toast = nil
            self.toastDismissTask = nil
        }
    }

    deinit {
        backgroundPreviewRefreshTask?.cancel()
        metricsTask?.cancel()
    }

    /// 按分类清空任务历史，并同步删除这些历史关联的真实产物。
    func clearTaskHistory(kind: TaskHistoryKind? = nil) {
        let entriesToDelete = kind.map { selectedKind in
            taskHistory.filter { $0.kind == selectedKind }
        } ?? taskHistory
        deleteTaskHistoryEntries(entriesToDelete)
    }

    /// 删除一条 RES 历史及其关联的产物目录。
    func deleteTaskHistoryEntry(_ entry: TaskHistoryEntry) {
        deleteTaskHistoryEntries([entry])
    }

    /// 预留统一存储目录并执行单文件变声，确保输出不再落到 engine 目录中。
    func runSingleConvert() async {
        guard let inputFileURL = inferenceViewModel.inputFileURL else {
            await inferenceViewModel.convert(
                selectedModelName: selectedModelName,
                outputDirectoryURL: environment.defaultSingleOutputDirectory
            )
            return
        }

        do {
            let reservation = try managedOutputStorage.reserveSingleOutput(for: inputFileURL)
            pendingSingleReservation = reservation
            await inferenceViewModel.convert(
                selectedModelName: selectedModelName,
                outputDirectoryURL: reservation.primaryOutputDirectoryURL
            )
        } catch {
            inferenceViewModel.errorMessage = error.localizedDescription
        }
    }

    /// 预留统一存储目录并执行批处理变声。
    func runBatchConvert() async {
        do {
            let reservation = try managedOutputStorage.reserveBatchOutput()
            pendingBatchReservation = reservation
            batchViewModel.outputDirectoryURL = reservation.primaryOutputDirectoryURL
            await batchViewModel.convert(selectedModelName: selectedModelName)
        } catch {
            batchViewModel.errorMessage = error.localizedDescription
        }
    }

    /// 使用后端 ChatTTS 先生成源语音，再套用当前模型做文本转音频。
    func runTextAudioGenerate() async {
        let trimmedText = textAudioInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            textAudioErrorMessage = "Enter some text before generating audio."
            statusMessage = textAudioErrorMessage ?? "Enter some text before generating audio."
            presentToast(message: statusMessage, style: .info)
            return
        }
        guard let selectedModelName else {
            textAudioErrorMessage = ValidationError.missingModel.errorDescription
            statusMessage = textAudioErrorMessage ?? "Load a voice model before generating text audio."
            presentToast(message: statusMessage, style: .info)
            return
        }
        if engineController.state != .ready {
            textAudioErrorMessage = "Start the engine before generating target voice audio."
            statusMessage = textAudioErrorMessage ?? "Start the engine before generating target voice audio."
            presentToast(message: statusMessage, style: .info)
            return
        }
        do {
            let reservation = try managedOutputStorage.reserveTextAudioOutput(for: trimmedText)
            pendingTextAudioReservation = reservation
            textAudioErrorMessage = nil
            textAudioProgress = TextAudioProgressSnapshot(
                active: true,
                stage: .preparing,
                title: "Prepare task",
                detail: "Validating text input and reserving the output path.",
                completedSteps: 0,
                totalSteps: 5,
                modelName: selectedModelName,
                stageElapsedSeconds: 0,
                totalElapsedSeconds: 0,
                stageDurations: [:]
            )
            isGeneratingTextAudio = true
            let startedAt = Date()
            textAudioRunStartedAt = startedAt
            startTextAudioProgressPolling()
            defer {
                textAudioProgressTask?.cancel()
                textAudioProgressTask = nil
                isGeneratingTextAudio = false
                textAudioRunStartedAt = nil
            }
            let normalizedBundle = effectiveTextAudioParameterBundle

            let request = TextAudioRequest(
                modelName: selectedModelName,
                text: trimmedText,
                outputDirectoryURL: reservation.primaryOutputDirectoryURL,
                gender: selectedTextAudioGender,
                toneMode: selectedTextAudioToneMode,
                tonePreset: selectedTextAudioToneMode == .preset ? effectiveTextAudioTonePreset : nil,
                customToneText: customTextAudioTone,
                matchProfile: selectedTextAudioMatchProfile,
                speakerID: inferenceViewModel.speakerID,
                transpose: normalizedBundle.transpose,
                speechRate: normalizedBundle.speechRate,
                f0Method: normalizedBundle.f0Method,
                indexPath: inferenceViewModel.selectedIndexPath,
                customIndexURL: inferenceViewModel.customIndexURL,
                indexRate: normalizedBundle.indexRate,
                filterRadius: normalizedBundle.filterRadius,
                resampleSR: normalizedBundle.resampleSR,
                rmsMixRate: normalizedBundle.rmsMixRate,
                protect: normalizedBundle.protect
            )
            try request.validate()
            let result = try await bridgeClient.convertTextAudio(request)
            let outputURL = result.outputAudioURL
            let duration = Date().timeIntervalSince(startedAt)
            let completionSnapshot = (try? await bridgeClient.fetchTextAudioProgress())
                ?? TextAudioProgressSnapshot(
                    active: false,
                    stage: .completed,
                    title: "Text task complete",
                    detail: "Generated speech and converted it into the selected voice model.",
                    completedSteps: 5,
                    totalSteps: 5,
                    modelName: selectedModelName,
                    stageElapsedSeconds: 0,
                    totalElapsedSeconds: duration,
                    stageDurations: nil
                )
            let summary = textAudioExecutionSummary(from: completionSnapshot, fallbackDuration: duration)

            inferenceViewModel.outputAudioURL = outputURL
            inferenceViewModel.outputMessage = result.message
            mixedOutputURL = nil
            isBackgroundMixEnabled = false
            backgroundAudioURL = nil
            cleanupBackgroundPreviewCache()
            audioPlayer.load(url: outputURL)
            lastExecutionSummary = summary
            statusMessage = "Generated audio from text."
            textAudioProgress = completionSnapshot
            presentToast(message: statusMessage, style: .success)
            recordTextTaskHistory(status: .success, summary: summary, outputURL: outputURL, sourceURL: result.sourceAudioURL, snapshot: completionSnapshot)
        } catch {
            textAudioErrorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
            textAudioProgress = TextAudioProgressSnapshot(
                active: false,
                stage: .failed,
                title: "Text task failed",
                detail: error.localizedDescription,
                completedSteps: textAudioProgress?.completedSteps ?? 0,
                totalSteps: textAudioProgress?.totalSteps ?? 5,
                modelName: selectedModelName,
                stageElapsedSeconds: textAudioProgress?.stageElapsedSeconds,
                totalElapsedSeconds: textAudioProgress?.totalElapsedSeconds,
                stageDurations: textAudioProgress?.stageDurations
            )
            presentToast(message: error.localizedDescription, style: .error)
            recordTextTaskHistory(status: .failure, summary: error.localizedDescription, outputURL: nil, sourceURL: nil, snapshot: textAudioProgress)
        }
    }

    /// 把后端返回的阶段耗时压成一行摘要，方便直接落到状态与历史里。
    private func textAudioExecutionSummary(from snapshot: TextAudioProgressSnapshot?, fallbackDuration: TimeInterval) -> String {
        let totalDuration = snapshot?.totalElapsedSeconds ?? fallbackDuration
        let summaryPrefix = "Text audio generated in \(totalDuration.formatted(.number.precision(.fractionLength(1))))s"
        guard let timingSummary = textAudioTimingSummary(from: snapshot), !timingSummary.isEmpty else {
            return summaryPrefix
        }
        return "\(summaryPrefix) · \(timingSummary)"
    }

    /// 统一格式化每一步耗时，避免任务历史只剩一个总时长。
    private func textAudioTimingSummary(from snapshot: TextAudioProgressSnapshot?) -> String? {
        guard let stageDurations = snapshot?.stageDurations, !stageDurations.isEmpty else { return nil }
        let orderedPairs: [(TextAudioStage, String)] = [
            (.preparing, "Prepare"),
            (.loadingChatTTS, "Load"),
            (.generatingSpeech, "Generate"),
            (.convertingVoice, "Convert"),
            (.finalizing, "Finalize"),
        ]
        let fragments = orderedPairs.compactMap { stage, label -> String? in
            guard let duration = stageDurations[stage.rawValue] else { return nil }
            return "\(label) \(duration.formatted(.number.precision(.fractionLength(1))))s"
        }
        return fragments.isEmpty ? nil : fragments.joined(separator: " · ")
    }

    /// 轮询后端文本任务阶段，给任务面板提供真实的多阶段反馈。
    private func startTextAudioProgressPolling() {
        textAudioProgressTask?.cancel()
        textAudioProgressTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let snapshot = try await bridgeClient.fetchTextAudioProgress()
                    if Task.isCancelled { return }
                    self.textAudioProgress = snapshot
                } catch {
                    if Task.isCancelled { return }
                }

                if !self.isGeneratingTextAudio {
                    return
                }

                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    /// 预留统一存储目录并执行 UVR 分离，统一收口 vocals / instrumentals 目录。
    func runUVRConvert() async {
        let inputLabel = uvrViewModel.inputDirectoryURL?.lastPathComponent
            ?? uvrViewModel.inputFileURLs.first?.deletingPathExtension().lastPathComponent
        do {
            let reservation = try managedOutputStorage.reserveUVROutputs(inputLabel: inputLabel)
            pendingUVRReservation = reservation
            uvrViewModel.vocalOutputDirectoryURL = reservation.primaryOutputDirectoryURL
            uvrViewModel.instrumentalOutputDirectoryURL = reservation.secondaryOutputDirectoryURL
            await uvrViewModel.convert()
        } catch {
            uvrViewModel.errorMessage = error.localizedDescription
        }
    }

    /// 切换背景声预览，并在可用时把 UVR instrumental 合成进当前波形试听。
    func toggleBackgroundMix() async {
        let nextValue = !isBackgroundMixEnabled
        guard nextValue else {
            backgroundPreviewRefreshTask?.cancel()
            isBackgroundMixEnabled = false
            cleanupBackgroundPreviewCache()
            reloadForegroundPreview()
            return
        }

        guard let backgroundAudioURL else {
            let message = "No related background stem is available. Run UVR first, then convert from the vocal stem."
            statusMessage = message
            presentToast(message: message, style: .info)
            return
        }

        isBackgroundMixEnabled = true
        await applyBackgroundPreviewIfNeeded(backgroundAudioURL: backgroundAudioURL)
    }

    /// 更新背景声混音音量，并在短暂防抖后重建试听结果，避免拖动滑杆时频繁打断播放。
    func setBackgroundMixLevel(_ value: Double) {
        backgroundMixLevel = min(max(value, 0), 1)
        guard isBackgroundMixEnabled else { return }
        scheduleBackgroundPreviewRefresh(after: .milliseconds(180))
    }

    /// 将当前变声产物与其关联的背景声一键合并，并把合并结果登记到 RES 历史中。
    func mergeBackgroundMix() async {
        guard let foregroundURL = inferenceViewModel.outputAudioURL else {
            presentToast(message: "Convert a file before merging background audio.", style: .info)
            return
        }
        guard let backgroundAudioURL else {
            presentToast(message: "No background stem is available for the current output.", style: .info)
            return
        }

        isPersistingBackgroundMix = true
        defer { isPersistingBackgroundMix = false }

        do {
            let outputDirectoryURL = inferenceViewModel.outputDirectoryURL ?? environment.defaultSingleOutputDirectory
            let mergedURL = try await audioCompositeService.exportMergedOutput(
                foregroundURL: foregroundURL,
                backgroundURL: backgroundAudioURL,
                outputDirectoryURL: outputDirectoryURL,
                backgroundGain: Float(backgroundMixLevel)
            )
            let shouldResumePlayback = audioPlayer.isPlaying
            let progress = audioPlayer.playbackProgress
            mixedOutputURL = mergedURL
            attachMixedOutputArtifact(mergedURL, foregroundURL: foregroundURL)
            isBackgroundMixEnabled = true
            audioPlayer.load(
                url: mergedURL,
                waveformSourceURL: foregroundURL,
                restoreProgress: progress,
                autoPlay: shouldResumePlayback,
                preserveWaveformWhileLoading: true
            )
            statusMessage = "Background merged and loaded."
            presentToast(message: statusMessage, style: .success)
        } catch {
            statusMessage = error.localizedDescription
            presentToast(message: error.localizedDescription, style: .error)
        }
    }

    /// 将历史中的输出重新载入预览播放器，方便直接回听旧产物。
    func loadTaskHistoryOutput(_ entry: TaskHistoryEntry) {
        guard let url = primaryPlayableURL(for: entry) else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        inferenceViewModel.outputAudioURL = url
        audioPlayer.load(url: url)
    }

    /// 将历史中的产物重新载入预览播放器并立即开始播放。
    func playTaskHistoryOutput(_ entry: TaskHistoryEntry) {
        loadTaskHistoryOutput(entry)
        audioPlayer.play()
    }

    /// 在 Finder 中定位历史记录关联的产物文件。
    func revealTaskHistoryOutput(_ entry: TaskHistoryEntry) {
        if let url = primaryPlayableURL(for: entry), FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        guard let directoryPath = entry.taskDirectoryPath else { return }
        let directoryURL = URL(fileURLWithPath: directoryPath)
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        NSWorkspace.shared.open(directoryURL)
    }

    /// 周期轮询应用、引擎、模型和索引的体积标签。
    private func startMetricsPolling() {
        metricsTask?.cancel()
        metricsTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let selectedModelName = self.selectedModelName
                let selectedIndexPath = self.effectiveSelectedIndexPath
                let weightsDirectory = self.environment.weightsDirectory
                let enginePID = self.engineController.processIdentifier

                let appMemoryBytes = Self.currentAppResidentBytes()
                let engineMemoryBytes = await Self.processResidentBytes(pid: enginePID)
                let modelSizeBytes = await Self.fileSizeBytes(
                    at: selectedModelName.map { weightsDirectory.appendingPathComponent($0) }
                )
                let indexSizeBytes = await Self.fileSizeBytes(
                    at: selectedIndexPath.map { URL(fileURLWithPath: $0) }
                )

                self.appMemoryLabel = Self.byteLabel(appMemoryBytes)
                self.engineMemoryLabel = Self.byteLabel(engineMemoryBytes)
                self.selectedModelSizeLabel = Self.byteLabel(modelSizeBytes)
                self.selectedIndexSizeLabel = Self.byteLabel(indexSizeBytes)

                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// 记录单文件推理任务结果，并将其持久化到 RES 历史。
    private func recordSingleTaskHistory(status: TaskHistoryStatus, summary: String) {
        let reservation = pendingSingleReservation
        let outputArtifacts = status == .success ? artifacts(
            from: inferenceViewModel.outputAudioURL.map { [$0] } ?? [],
            role: .singleOutput
        ) : []
        appendTaskHistory(
            TaskHistoryEntry(
                id: reservation?.taskID ?? UUID(),
                timestamp: Date(),
                kind: .single,
                status: status,
                title: status == .failure ? "Single convert failed" : "Single convert",
                summary: summary,
                modelName: selectedModelName,
                inputLabel: inferenceViewModel.inputFileURL?.lastPathComponent,
                inputPath: inferenceViewModel.inputFileURL?.path,
                outputLabel: status == .success ? inferenceViewModel.outputAudioURL?.lastPathComponent : nil,
                outputPath: status == .success ? inferenceViewModel.outputAudioURL?.path : nil,
                indexPath: effectiveSelectedIndexPath,
                f0Method: inferenceViewModel.f0Method.rawValue,
                parameterSummary: nil,
                timingSummary: nil,
                speakerID: inferenceViewModel.speakerID,
                errorMessage: status == .failure ? inferenceViewModel.errorMessage ?? summary : nil,
                taskDirectoryPath: reservation?.taskDirectoryURL.path ?? inferenceViewModel.outputDirectoryURL?.path,
                outputArtifacts: outputArtifacts,
                sourceTaskID: sourceTaskID(forInputPath: inferenceViewModel.inputFileURL?.path)
            )
        )
        pendingSingleReservation = nil
    }

    /// 记录批处理任务结果，并保留目录级输入输出上下文。
    private func recordBatchTaskHistory(status: TaskHistoryStatus, summary: String) {
        let reservation = pendingBatchReservation
        let batchInputLabel: String?
        let batchInputPath: String?
        if let directory = batchViewModel.inputDirectoryURL {
            batchInputLabel = directory.lastPathComponent
            batchInputPath = directory.path
        } else if let firstFile = batchViewModel.inputFileURLs.first {
            batchInputLabel = batchViewModel.inputFileURLs.count == 1 ? firstFile.lastPathComponent : "\(batchViewModel.inputFileURLs.count) files"
            batchInputPath = batchViewModel.inputFileURLs.map(\.path).joined(separator: "\n")
        } else {
            batchInputLabel = nil
            batchInputPath = nil
        }

        appendTaskHistory(
            TaskHistoryEntry(
                id: reservation?.taskID ?? UUID(),
                timestamp: Date(),
                kind: .batch,
                status: status,
                title: status == .failure ? "Batch convert failed" : "Batch convert",
                summary: summary,
                modelName: selectedModelName,
                inputLabel: batchInputLabel,
                inputPath: batchInputPath,
                outputLabel: batchViewModel.outputDirectoryURL?.lastPathComponent,
                outputPath: batchViewModel.outputDirectoryURL?.path,
                indexPath: batchViewModel.effectiveIndexPath,
                f0Method: batchViewModel.f0Method.rawValue,
                parameterSummary: nil,
                timingSummary: nil,
                speakerID: batchViewModel.speakerID,
                errorMessage: status == .failure ? batchViewModel.errorMessage ?? summary : nil,
                taskDirectoryPath: reservation?.taskDirectoryURL.path ?? batchViewModel.outputDirectoryURL?.path,
                outputArtifacts: status == .success ? artifacts(from: batchViewModel.outputFileURLs, role: .batchOutput) : [],
                sourceTaskID: nil
            )
        )
        pendingBatchReservation = nil
    }

    /// 记录文本生成音频任务，并将其作为独立任务类型写入 RES 历史。
    private func recordTextTaskHistory(status: TaskHistoryStatus, summary: String, outputURL: URL?, sourceURL: URL?, snapshot: TextAudioProgressSnapshot?) {
        let reservation = pendingTextAudioReservation
        let parameterSummary = [
            selectedTextAudioGender.displayName,
            effectiveTextAudioToneLabel,
            selectedTextAudioMatchProfile.displayName,
            "P\(Int(textAudioTranspose.rounded()))",
            textAudioSpeechRate.displayName,
            textAudioF0Method.displayName,
            "IDX \(Int(textAudioIndexRate * 100))%",
            "PR \(textAudioProtect.formatted(.number.precision(.fractionLength(2))))",
        ].joined(separator: " · ")
        let textArtifacts = status == .success
            ? artifacts(from: outputURL.map { [$0] } ?? [], role: .textOutput)
            + artifacts(from: sourceURL.map { [$0] } ?? [], role: .textSource)
            : []
        appendTaskHistory(
            TaskHistoryEntry(
                id: reservation?.taskID ?? UUID(),
                timestamp: Date(),
                kind: .text,
                status: status,
                title: status == .failure ? "Text audio failed" : "Text audio",
                summary: summary,
                modelName: selectedModelName,
                inputLabel: String(textAudioInput.prefix(48)),
                inputPath: textAudioInput,
                outputLabel: outputURL?.lastPathComponent,
                outputPath: outputURL?.path,
                indexPath: effectiveSelectedIndexPath,
                f0Method: textAudioF0Method.rawValue,
                parameterSummary: parameterSummary,
                timingSummary: textAudioTimingSummary(from: snapshot),
                speakerID: inferenceViewModel.speakerID,
                errorMessage: status == .failure ? textAudioErrorMessage ?? summary : nil,
                taskDirectoryPath: reservation?.taskDirectoryURL.path,
                outputArtifacts: textArtifacts,
                sourceTaskID: nil
            )
        )
        pendingTextAudioReservation = nil
    }

    /// 记录 UVR 成功或失败任务，并保留 vocals/instrumentals 的配对关联。
    private func recordUVRTaskHistory(status: TaskHistoryStatus, summary: String) {
        let reservation = pendingUVRReservation
        let primaryOutput = uvrViewModel.vocalOutputFileURLs.first ?? uvrViewModel.vocalOutputDirectoryURL
        let artifacts = status == .success
            ? artifacts(from: uvrViewModel.vocalOutputFileURLs, role: .uvrVocal)
            + artifacts(from: uvrViewModel.instrumentalOutputFileURLs, role: .uvrInstrumental)
            : []

        appendTaskHistory(
            TaskHistoryEntry(
                id: reservation?.taskID ?? UUID(),
                timestamp: Date(),
                kind: .uvr,
                status: status,
                title: status == .failure ? "UVR separate failed" : "UVR separate",
                summary: summary,
                modelName: uvrViewModel.selectedModelName,
                inputLabel: uvrViewModel.inputDirectoryURL?.lastPathComponent
                    ?? uvrViewModel.inputFileURLs.first?.lastPathComponent,
                inputPath: uvrViewModel.inputDirectoryURL?.path
                    ?? joinedPaths(uvrViewModel.inputFileURLs.map(\.path)),
                outputLabel: primaryOutput?.lastPathComponent,
                outputPath: primaryOutput?.path,
                indexPath: nil,
                f0Method: nil,
                parameterSummary: nil,
                timingSummary: nil,
                speakerID: nil,
                errorMessage: status == .failure ? uvrViewModel.errorMessage ?? summary : nil,
                taskDirectoryPath: reservation?.taskDirectoryURL.path,
                outputArtifacts: artifacts,
                sourceTaskID: nil
            )
        )
        pendingUVRReservation = nil
    }

    /// 记录实时链路的启动、停止与错误事件，便于回顾设备和模型上下文。
    private func recordRealtimeTaskHistory(status: TaskHistoryStatus, summary: String) {
        let inputLabel = realtimeViewModel.selectedInputDevice
        let outputLabel = realtimeViewModel.selectedOutputDevice
        let ioPath = [inputLabel, outputLabel]
            .compactMap { $0 }
            .joined(separator: " -> ")

        appendTaskHistory(
            TaskHistoryEntry(
                id: UUID(),
                timestamp: Date(),
                kind: .realtime,
                status: status,
                title: realtimeViewModel.isRunning ? "Live monitor active" : "Live monitor update",
                summary: summary,
                modelName: selectedModelName,
                inputLabel: inputLabel,
                inputPath: ioPath.isEmpty ? nil : ioPath,
                outputLabel: outputLabel,
                outputPath: nil,
                indexPath: effectiveSelectedIndexPath,
                f0Method: inferenceViewModel.f0Method.rawValue,
                parameterSummary: nil,
                timingSummary: nil,
                speakerID: inferenceViewModel.speakerID,
                errorMessage: status == .failure ? realtimeViewModel.lastError ?? summary : nil,
                taskDirectoryPath: nil,
                outputArtifacts: [],
                sourceTaskID: nil
            )
        )
    }

    /// 将任务历史插入队首，并同步写入本地持久化存储。
    private func appendTaskHistory(_ entry: TaskHistoryEntry) {
        taskHistory.insert(entry, at: 0)
        if taskHistory.count > maxTaskHistoryCount {
            taskHistory = Array(taskHistory.prefix(maxTaskHistoryCount))
        }
        persistTaskHistory()
    }

    /// 批量删除历史记录，并清理任务目录、文件以及播放器/背景声的失效引用。
    private func deleteTaskHistoryEntries(_ entries: [TaskHistoryEntry]) {
        guard !entries.isEmpty else { return }

        let fileManager = FileManager.default
        let idsToDelete = Set(entries.map(\.id))
        let pathsToDelete = Set(entries.flatMap(storagePaths(for:)))
        let loadedURLPath = audioPlayer.loadedURL?.path
        let currentOutputPath = inferenceViewModel.outputAudioURL?.path
        let currentMixedPath = mixedOutputURL?.path
        let currentBackgroundPath = backgroundAudioURL?.path

        for path in pathsToDelete.sorted(by: { $0.count > $1.count }) {
            guard fileManager.fileExists(atPath: path) else { continue }
            try? fileManager.removeItem(atPath: path)
        }

        taskHistory.removeAll { idsToDelete.contains($0.id) }
        persistTaskHistory()

        if let loadedURLPath, pathsToDelete.contains(where: { loadedURLPath.hasPrefix($0) || loadedURLPath == $0 }) {
            audioPlayer.load(url: nil)
        }
        if let currentOutputPath, pathsToDelete.contains(where: { currentOutputPath.hasPrefix($0) || currentOutputPath == $0 }) {
            inferenceViewModel.outputAudioURL = nil
        }
        if let currentMixedPath, pathsToDelete.contains(where: { currentMixedPath.hasPrefix($0) || currentMixedPath == $0 }) {
            mixedOutputURL = nil
        }
        if let currentBackgroundPath, pathsToDelete.contains(where: { currentBackgroundPath.hasPrefix($0) || currentBackgroundPath == $0 }) {
            backgroundAudioURL = nil
            isBackgroundMixEnabled = false
        }

        if let currentBackgroundPreviewURL,
           pathsToDelete.contains(where: { currentBackgroundPreviewURL.path.hasPrefix($0) || currentBackgroundPreviewURL.path == $0 }) {
            self.currentBackgroundPreviewURL = nil
        }
        refreshBackgroundContext(forForegroundURL: inferenceViewModel.outputAudioURL)
    }

    /// 将当前内存中的任务历史写回 UserDefaults。
    private func persistTaskHistory() {
        guard let data = try? JSONEncoder().encode(taskHistory) else { return }
        userDefaults.set(data, forKey: taskHistoryDefaultsKey)
    }

    /// 从 UserDefaults 中恢复历史任务列表，兼容首次启动或损坏数据。
    private static func loadTaskHistory(from defaults: UserDefaults, key: String) -> [TaskHistoryEntry] {
        guard
            let data = defaults.data(forKey: key),
            let entries = try? JSONDecoder().decode([TaskHistoryEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    /// 从历史中定位生成指定输入文件的上游任务，建立单文件变声与 UVR 产物之间的关联。
    private func sourceTaskID(forInputPath inputPath: String?) -> UUID? {
        guard let inputPath, !inputPath.isEmpty else { return nil }
        return taskHistory.first(where: { entry in
            entry.outputPath == inputPath || entry.outputArtifacts.contains(where: { $0.path == inputPath })
        })?.id
    }

    /// 把一组 URL 转成可持久化的历史产物引用。
    private func artifacts(from urls: [URL], role: TaskHistoryArtifactRole) -> [TaskHistoryArtifact] {
        urls.map {
            TaskHistoryArtifact(id: UUID(), role: role, label: $0.lastPathComponent, path: $0.path)
        }
    }

    /// 拼接多路径输入，避免在历史里丢失批处理和多文件 UVR 的来源信息。
    private func joinedPaths(_ paths: [String]) -> String? {
        let filtered = paths.filter { !$0.isEmpty }
        guard !filtered.isEmpty else { return nil }
        return filtered.joined(separator: "\n")
    }

    /// 收集单条历史可安全删除的路径，优先删 task 目录，其余补充独立文件路径。
    private func storagePaths(for entry: TaskHistoryEntry) -> [String] {
        var paths = Set<String>()
        if let taskDirectoryPath = entry.taskDirectoryPath, !taskDirectoryPath.isEmpty {
            paths.insert(taskDirectoryPath)
        }
        if let outputPath = entry.outputPath, !outputPath.isEmpty {
            paths.insert(outputPath)
        }
        entry.outputArtifacts
            .map(\.path)
            .filter { !$0.isEmpty }
            .forEach { paths.insert($0) }
        return Array(paths)
    }

    /// 优先取可播放音频，用于 RES 里的回放和主波形预览。
    private func primaryPlayableURL(for entry: TaskHistoryEntry) -> URL? {
        if let mixedArtifact = entry.outputArtifacts.first(where: { $0.role == .mixedOutput }) {
            return URL(fileURLWithPath: mixedArtifact.path)
        }
        if let outputPath = entry.outputPath, !outputPath.isEmpty {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: outputPath, isDirectory: &isDirectory), !isDirectory.boolValue {
                return URL(fileURLWithPath: outputPath)
            }
        }
        if let artifact = entry.outputArtifacts.first(where: { artifact in
            switch artifact.role {
            case .singleOutput, .textOutput, .uvrVocal:
                return true
            case .batchOutput, .textSource, .uvrInstrumental, .mixedOutput:
                return false
            }
        }) {
            return URL(fileURLWithPath: artifact.path)
        }
        return nil
    }

    /// 随当前前景产物刷新背景声来源，优先复用历史中的 UVR instrument 关联。
    private func refreshBackgroundContext(forForegroundURL foregroundURL: URL?) {
        mixedOutputURL = existingMixedOutputURL(forForegroundURL: foregroundURL)
        backgroundAudioURL = resolveBackgroundAudioURL(forForegroundURL: foregroundURL)

        if backgroundAudioURL == nil {
            backgroundPreviewRefreshTask?.cancel()
            isBackgroundMixEnabled = false
            cleanupBackgroundPreviewCache()
            return
        }

        guard isBackgroundMixEnabled else { return }
        scheduleBackgroundPreviewRefresh(after: .zero)
    }

    /// 统一调度背景预览刷新，取消旧任务并在滑杆停顿后再执行，减少播放中断。
    private func scheduleBackgroundPreviewRefresh(after delay: Duration) {
        backgroundPreviewRefreshTask?.cancel()
        let backgroundURL = backgroundAudioURL
        backgroundPreviewRefreshTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard let self, !Task.isCancelled else { return }
            await self.applyBackgroundPreviewIfNeeded(backgroundAudioURL: backgroundURL)
        }
    }

    /// 根据当前前景产物或其输入链路，反查是否存在可用的 UVR instrumental。
    private func resolveBackgroundAudioURL(forForegroundURL foregroundURL: URL?) -> URL? {
        if let foregroundURL, let relatedEntry = taskHistoryEntry(forOutputPath: foregroundURL.path) {
            if let sourceEntry = relatedEntry.sourceTaskID.flatMap({ sourceID in
                taskHistory.first(where: { $0.id == sourceID })
            }) {
                return firstInstrumentalURL(for: sourceEntry)
            }
        }

        if let sourceEntry = sourceTaskID(forInputPath: inferenceViewModel.inputFileURL?.path)
            .flatMap({ sourceID in taskHistory.first(where: { $0.id == sourceID }) }) {
            return firstInstrumentalURL(for: sourceEntry)
        }

        return nil
    }

    /// 从历史里找出当前前景产物已经生成过的 merged 版本，方便直接复用而不是重复导出。
    private func existingMixedOutputURL(forForegroundURL foregroundURL: URL?) -> URL? {
        guard let foregroundURL, let entry = taskHistoryEntry(forOutputPath: foregroundURL.path) else { return nil }
        guard let artifact = entry.outputArtifacts.first(where: { $0.role == .mixedOutput }) else { return nil }
        let url = URL(fileURLWithPath: artifact.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// 把主播放器切回纯变声输出，避免关闭背景预览后仍停留在混音结果上。
    private func reloadForegroundPreview() {
        guard let foregroundURL = inferenceViewModel.outputAudioURL else {
            cleanupBackgroundPreviewCache()
            audioPlayer.load(url: nil)
            return
        }
        cleanupBackgroundPreviewCache()
        let shouldResumePlayback = audioPlayer.isPlaying
        let progress = audioPlayer.playbackProgress
        audioPlayer.load(
            url: foregroundURL,
            restoreProgress: progress,
            autoPlay: shouldResumePlayback,
            preserveWaveformWhileLoading: true
        )
    }

    /// 在开启背景预览后，为当前前景产物生成或复用一个试听混音文件，并更新波形图。
    private func applyBackgroundPreviewIfNeeded(backgroundAudioURL: URL?) async {
        guard isBackgroundMixEnabled else {
            reloadForegroundPreview()
            return
        }
        guard
            let foregroundURL = inferenceViewModel.outputAudioURL,
            let backgroundAudioURL
        else {
            reloadForegroundPreview()
            return
        }

        isPreparingBackgroundMix = true
        defer { isPreparingBackgroundMix = false }

        do {
            let shouldResumePlayback = audioPlayer.isPlaying
            let progress = audioPlayer.playbackProgress
            let previewURL = try await audioCompositeService.exportPreviewMix(
                foregroundURL: foregroundURL,
                backgroundURL: backgroundAudioURL,
                cacheDirectoryURL: environment.backgroundPreviewCacheDirectory,
                backgroundGain: Float(backgroundMixLevel)
            )
            currentBackgroundPreviewURL = previewURL
            cleanupBackgroundPreviewCache(keeping: previewURL)
            audioPlayer.load(
                url: previewURL,
                waveformSourceURL: foregroundURL,
                restoreProgress: progress,
                autoPlay: shouldResumePlayback,
                preserveWaveformWhileLoading: true
            )
        } catch {
            isBackgroundMixEnabled = false
            cleanupBackgroundPreviewCache()
            reloadForegroundPreview()
            statusMessage = error.localizedDescription
            presentToast(message: error.localizedDescription, style: .error)
        }
    }

    /// 清理背景预览缓存，默认只保留当前活跃的 preview，防止 background-mix 目录无限增长。
    private func cleanupBackgroundPreviewCache(keeping keepURL: URL? = nil) {
        let directoryURL = environment.backgroundPreviewCacheDirectory
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            currentBackgroundPreviewURL = keepURL
            return
        }

        for fileURL in contents where fileURL != keepURL {
            try? fileManager.removeItem(at: fileURL)
        }
        currentBackgroundPreviewURL = keepURL
    }

    /// 根据产物路径定位其对应历史记录，便于建立 merged 产物与原始单文件输出的关联。
    private func taskHistoryEntry(forOutputPath path: String) -> TaskHistoryEntry? {
        taskHistory.first { entry in
            entry.outputPath == path || entry.outputArtifacts.contains(where: { $0.path == path })
        }
    }

    /// 提取某条 UVR 历史记录的首个 instrumental，用作背景声来源。
    private func firstInstrumentalURL(for entry: TaskHistoryEntry) -> URL? {
        guard let artifact = entry.outputArtifacts.first(where: { $0.role == .uvrInstrumental }) else { return nil }
        let url = URL(fileURLWithPath: artifact.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// 将一键合并后的背景混音产物挂回原始单文件任务，方便在 RES 中回顾完整链路。
    private func attachMixedOutputArtifact(_ mixedURL: URL, foregroundURL: URL) {
        guard let index = taskHistory.firstIndex(where: { entry in
            entry.kind == .single && (entry.outputPath == foregroundURL.path || entry.outputArtifacts.contains(where: { $0.path == foregroundURL.path }))
        }) else {
            return
        }

        var entry = taskHistory[index]
        var artifacts = entry.outputArtifacts.filter { $0.role != .mixedOutput }
        artifacts.append(
            TaskHistoryArtifact(
                id: UUID(),
                role: .mixedOutput,
                label: mixedURL.lastPathComponent,
                path: mixedURL.path
            )
        )
        entry = TaskHistoryEntry(
            id: entry.id,
            timestamp: entry.timestamp,
            kind: entry.kind,
            status: entry.status,
            title: entry.title,
            summary: entry.summary,
            modelName: entry.modelName,
            inputLabel: entry.inputLabel,
            inputPath: entry.inputPath,
            outputLabel: entry.outputLabel,
            outputPath: entry.outputPath,
            indexPath: entry.indexPath,
            f0Method: entry.f0Method,
            parameterSummary: entry.parameterSummary,
            timingSummary: entry.timingSummary,
            speakerID: entry.speakerID,
            errorMessage: entry.errorMessage,
            taskDirectoryPath: entry.taskDirectoryPath,
            outputArtifacts: artifacts,
            sourceTaskID: entry.sourceTaskID
        )
        taskHistory[index] = entry
        persistTaskHistory()
    }

    /// 读取当前 app 进程的驻留内存大小。
    private static func currentAppResidentBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
    }

    /// 通过 `ps` 查询指定进程的驻留内存大小。
    private static func processResidentBytes(pid: Int32?) async -> UInt64? {
        guard let pid else { return nil }
        return await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-o", "rss=", "-p", "\(pid)"]

            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      let kilobytes = UInt64(output) else { return nil }
                return kilobytes * 1024
            } catch {
                return nil
            }
        }.value
    }

    /// 异步读取单个文件的体积。
    private static func fileSizeBytes(at url: URL?) async -> UInt64? {
        guard let url else { return nil }
        return await Task.detached(priority: .utility) {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let fileSize = values?.fileSize else { return nil }
            return UInt64(fileSize)
        }.value
    }

    /// 将字节数格式化为适合 UI 展示的容量标签。
    private static func byteLabel(_ bytes: UInt64?) -> String {
        guard let bytes, bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// 将所有活跃等待态压缩成当前界面真正应该展示的那一个。
    private func synchronizeBusyDescriptor() {
        activeBusyDescriptor = busyDescriptors.values.max { lhs, rhs in
            lhs.priority < rhs.priority
        }
        isBootstrapping = busyDescriptors[.bootstrap] != nil
    }

    /// 为每种等待态生成统一文案，避免不同视图各自拼接提示文本。
    private func busyMessage(for scope: BusyScope, modelName: String?) -> String {
        switch scope {
        case .bootstrap:
            return L10n.tr("label.shell_loading")
        case .catalogRefresh:
            return L10n.tr("status.catalog.loading")
        case .modelSelection:
            return L10n.tr("status.model.loading", displayedModelName(from: modelName))
        }
    }

    /// 将模型文件名裁剪成更适合等待提示展示的短标签。
    private func displayedModelName(from rawName: String?) -> String {
        guard let rawName, !rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return L10n.tr("picker.select_model")
        }
        return rawName.replacingOccurrences(of: ".pth", with: "")
    }
}
