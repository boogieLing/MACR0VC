import XCTest
@testable import SwiftRVCMacClient

@MainActor
final class AppStateBusyTests: XCTestCase {
    /// 验证自举等待态在与目录刷新态并存时仍保持最高展示优先级。
    func testBootstrapBusyKeepsPriorityOverNestedCatalogBusy() {
        let appState = makeAppState()

        appState.beginBusy(.bootstrap)
        appState.beginBusy(.catalogRefresh)

        XCTAssertEqual(appState.activeBusyDescriptor?.scope, .bootstrap)
        XCTAssertEqual(appState.activeBusyDescriptor?.message, L10n.tr("label.shell_loading"))
        XCTAssertTrue(appState.isBootstrapBusy)
        XCTAssertTrue(appState.isCatalogBusy)
    }

    /// 验证目录刷新等待态可独立显示，并在结束后完全清理。
    func testCatalogBusyCanDisplayIndependentlyAndClear() {
        let appState = makeAppState()

        appState.beginBusy(.catalogRefresh)

        XCTAssertEqual(appState.activeBusyDescriptor?.scope, .catalogRefresh)
        XCTAssertEqual(appState.activeBusyDescriptor?.message, L10n.tr("status.catalog.loading"))
        XCTAssertTrue(appState.isCatalogBusy)

        appState.endBusy(.catalogRefresh)

        XCTAssertNil(appState.activeBusyDescriptor)
        XCTAssertFalse(appState.isCatalogBusy)
    }

    /// 验证模型切换等待态会持续到实时配置链路真正结束。
    func testModelSelectionBusyStaysActiveUntilRealtimeConfigureCompletes() async {
        let bridgeClient = BusyTestBridgeClient()
        bridgeClient.pauseConfigureRealtime = true
        let configureStarted = expectation(description: "configure realtime started")
        bridgeClient.onConfigureRealtimeStart = {
            configureStarted.fulfill()
        }
        let appState = makeAppState(bridgeClient: bridgeClient)

        let task = Task {
            await appState.selectModel("demo.pth")
        }

        await fulfillment(of: [configureStarted], timeout: 1)

        XCTAssertTrue(appState.isModelSelectionBusy)
        XCTAssertEqual(appState.activeBusyDescriptor?.scope, .modelSelection)
        XCTAssertEqual(appState.modelSelectionBusyMessage, L10n.tr("status.model.loading", "demo"))

        bridgeClient.resumeConfigureRealtime()
        await task.value

        XCTAssertFalse(appState.isModelSelectionBusy)
        XCTAssertNil(appState.activeBusyDescriptor)
        XCTAssertEqual(appState.selectedModelName, "demo.pth")
    }

    /// 验证模型切换失败时不会遗留等待态。
    func testModelSelectionBusyClearsAfterBridgeFailure() async {
        let bridgeClient = BusyTestBridgeClient()
        bridgeClient.selectModelError = BusyTestError.selectFailed
        let appState = makeAppState(bridgeClient: bridgeClient)

        await appState.selectModel("broken.pth")

        XCTAssertFalse(appState.isModelSelectionBusy)
        XCTAssertNil(appState.activeBusyDescriptor)
        XCTAssertEqual(appState.statusMessage, BusyTestError.selectFailed.localizedDescription)
    }

    /// 构建关闭指标轮询的测试专用 AppState，避免后台任务干扰断言。
    private func makeAppState(bridgeClient: BusyTestBridgeClient = BusyTestBridgeClient()) -> AppState {
        AppState(
            environment: .fallback(),
            bridgeClient: bridgeClient,
            startMetricsTask: false
        )
    }
}

private enum BusyTestError: LocalizedError {
    case selectFailed

    var errorDescription: String? {
        switch self {
        case .selectFailed:
            return "select failed"
        }
    }
}

@MainActor
final class BusyTestBridgeClient: RVCBridgeClient {
    var selectModelError: Error?
    var pauseConfigureRealtime = false
    var onConfigureRealtimeStart: (() -> Void)?

    private var configureRealtimeContinuation: CheckedContinuation<Void, Never>?

    /// 返回空模型目录结果，满足测试环境下的目录协议约束。
    func refreshModels() async throws -> ModelCatalog {
        ModelCatalog(models: [], indexPaths: [])
    }

    /// 返回可控的模型选择结果，便于测试等待态何时开始与结束。
    func selectModel(name: String) async throws -> ModelSelectionResult {
        if let selectModelError {
            throw selectModelError
        }

        return ModelSelectionResult(
            modelName: name,
            modelInfoSummary: "summary",
            modelInfoError: nil,
            indexPaths: ["/tmp/demo.index"],
            speakerCount: 2
        )
    }

    /// 返回空卸载结果，满足协议最小实现。
    func unloadModel() async throws -> ModelUnloadResult {
        ModelUnloadResult(
            modelName: "",
            modelInfoSummary: "",
            indexPaths: [],
            speakerCount: 0,
            unloaded: true
        )
    }

    /// 返回固定释放结果，满足统一缓存释放协议。
    func releaseRuntimeMemory() async throws -> MemoryReleaseResult {
        MemoryReleaseResult(released: true, message: "runtime released")
    }

    /// 返回空单文件推理结果，避免测试桩实现遗漏协议方法。
    func convertSingle(_ request: SingleInferenceRequest) async throws -> SingleInferenceResult {
        SingleInferenceResult(message: "", outputAudioURL: nil, outputDirectoryURL: nil)
    }

    /// 返回空批量推理结果，避免测试桩实现遗漏协议方法。
    func convertBatch(_ request: BatchInferenceRequest) async throws -> BatchInferenceResult {
        BatchInferenceResult(message: "", outputDirectoryURL: nil, outputFileURLs: [])
    }

    /// 返回空 UVR 模型目录，满足测试桩最小协议实现。
    func refreshUVRModels() async throws -> UVRModelCatalog {
        UVRModelCatalog(modelNames: [])
    }

    /// 返回固定释放结果，满足 UVR 内存清理协议。
    func releaseUVRMemory() async throws -> MemoryReleaseResult {
        MemoryReleaseResult(released: true, message: "released")
    }

    /// 返回空 UVR 结果，满足测试桩最小协议实现。
    func convertUVR(_ request: UVRRequest) async throws -> UVRResult {
        UVRResult(
            message: "",
            vocalOutputDirectoryURL: nil,
            instrumentalOutputDirectoryURL: nil,
            vocalOutputFileURLs: [],
            instrumentalOutputFileURLs: []
        )
    }

    /// 返回健康的资产巡检结果，避免无关逻辑影响等待态测试。
    func fetchAssetIntegrityReport() async throws -> AssetIntegrityReport {
        AssetIntegrityReport(items: [], allValid: true, checkedAt: nil, message: "ok")
    }

    /// 返回空下载结果，满足协议实现完整性。
    func downloadAssets() async throws -> AssetDownloadResult {
        AssetDownloadResult(message: "ok", report: AssetIntegrityReport(items: [], allValid: true, checkedAt: nil, message: "ok"))
    }

    /// 返回固定导出路径，满足协议实现完整性。
    func exportONNX(_ request: ONNXExportRequest) async throws -> ONNXExportResult {
        ONNXExportResult(message: "", exportedPath: URL(fileURLWithPath: "/tmp/demo.onnx"))
    }

    /// 返回固定相似度结果，满足协议实现完整性。
    func compareCheckpointHashes(_ request: CheckpointSimilarityRequest) async throws -> CheckpointSimilarityResult {
        CheckpointSimilarityResult(message: "", similarity: "1.0")
    }

    /// 返回空元信息文本，满足协议实现完整性。
    func showCheckpointInfo(_ request: CheckpointInfoRequest) async throws -> CheckpointInfoResult {
        CheckpointInfoResult(message: "", infoText: "", modelPath: request.modelPath)
    }

    /// 返回固定修改产物路径，满足协议实现完整性。
    func modifyCheckpointInfo(_ request: CheckpointModifyRequest) async throws -> CheckpointModifyResult {
        CheckpointModifyResult(message: "", outputModelPath: URL(fileURLWithPath: "/tmp/demo.pth"))
    }

    /// 返回固定融合产物路径，满足协议实现完整性。
    func mergeCheckpoints(_ request: CheckpointMergeRequest) async throws -> CheckpointMergeResult {
        CheckpointMergeResult(message: "", outputModelPath: URL(fileURLWithPath: "/tmp/demo-merge.pth"))
    }

    /// 返回固定抽取产物路径，满足协议实现完整性。
    func extractSmallCheckpoint(_ request: CheckpointExtractRequest) async throws -> CheckpointExtractResult {
        CheckpointExtractResult(message: "", outputModelPath: URL(fileURLWithPath: "/tmp/demo-small.pth"))
    }

    /// 返回空实时设备快照，避免等待态测试依赖真实硬件环境。
    func refreshRealtimeDevices() async throws -> RealtimeDeviceSnapshot {
        RealtimeDeviceSnapshot(
            hostapis: [],
            selectedHostapi: "",
            inputDevices: [],
            outputDevices: [],
            selectedInputDevice: "",
            selectedOutputDevice: "",
            sampleRate: 0,
            channels: 1
        )
    }

    /// 返回空闲实时状态，满足状态查询协议。
    func fetchRealtimeStatus() async throws -> RealtimeStatusEnvelope {
        RealtimeStatusEnvelope(devices: try await refreshRealtimeDevices(), status: idleRealtimeStatus)
    }

    /// 在需要时挂起实时配置，以验证模型切换等待态不会提前结束。
    func configureRealtime(_ request: RealtimeConfigureRequest) async throws -> RealtimeStatusEnvelope {
        onConfigureRealtimeStart?()

        if pauseConfigureRealtime {
            await withCheckedContinuation { continuation in
                configureRealtimeContinuation = continuation
            }
        }

        return RealtimeStatusEnvelope(devices: try await refreshRealtimeDevices(), status: idleRealtimeStatus)
    }

    /// 返回空闲实时状态，满足实时启动协议。
    func startRealtime(_ request: RealtimeStartRequest) async throws -> RealtimeStatus {
        idleRealtimeStatus
    }

    /// 返回空闲实时状态，满足实时停止协议。
    func stopRealtime() async throws -> RealtimeStatus {
        idleRealtimeStatus
    }

    /// 主动恢复被挂起的实时配置调用，用于推进异步测试流程。
    func resumeConfigureRealtime() {
        configureRealtimeContinuation?.resume()
        configureRealtimeContinuation = nil
    }

    private var idleRealtimeStatus: RealtimeStatus {
        RealtimeStatus(
            running: false,
            function: RealtimeMonitorMode.outputConverted.rawValue,
            sampleRate: 0,
            channels: 1,
            delayTimeMs: 0,
            inferTimeMs: 0,
            selectedHostapi: "",
            selectedInputDevice: "",
            selectedOutputDevice: "",
            modelName: "",
            indexPath: "",
            lastError: nil
        )
    }
}
