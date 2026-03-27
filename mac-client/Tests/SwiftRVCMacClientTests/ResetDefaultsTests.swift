import XCTest
@testable import SwiftRVCMacClient

@MainActor
final class ResetDefaultsTests: XCTestCase {
    /// 验证仅选择一个 batch 输入文件时，会同时回填单文件输入。
    func testSingleBatchFileAlsoFeedsSingleInferenceInput() {
        let appState = AppState(
            environment: .fallback(),
            bridgeClient: BusyTestBridgeClient(),
            startMetricsTask: false
        )
        let selectedFile = URL(fileURLWithPath: "/tmp/demo.wav")

        appState.setBatchInputFileURLs([selectedFile])

        XCTAssertEqual(appState.batchViewModel.inputFileURLs, [selectedFile])
        XCTAssertNil(appState.batchViewModel.inputDirectoryURL)
        XCTAssertEqual(appState.inferenceViewModel.inputFileURL, selectedFile)
    }

    /// 验证多文件 batch 输入不会误当成单文件转换输入。
    func testMultipleBatchFilesClearSingleInferenceInput() {
        let appState = AppState(
            environment: .fallback(),
            bridgeClient: BusyTestBridgeClient(),
            startMetricsTask: false
        )
        let files = [
            URL(fileURLWithPath: "/tmp/one.wav"),
            URL(fileURLWithPath: "/tmp/two.wav"),
        ]

        appState.setSingleInputFileURL(URL(fileURLWithPath: "/tmp/old.wav"))
        appState.setBatchInputFileURLs(files)

        XCTAssertEqual(appState.batchViewModel.inputFileURLs, files)
        XCTAssertNil(appState.inferenceViewModel.inputFileURL)
    }

    /// 验证选择 batch 目录时会清理互斥的显式文件输入状态。
    func testBatchDirectoryClearsExplicitFileSelections() {
        let appState = AppState(
            environment: .fallback(),
            bridgeClient: BusyTestBridgeClient(),
            startMetricsTask: false
        )
        let directory = URL(fileURLWithPath: "/tmp/batch-input", isDirectory: true)

        appState.setSingleInputFileURL(URL(fileURLWithPath: "/tmp/old.wav"))
        appState.setBatchInputFileURLs([URL(fileURLWithPath: "/tmp/queued.wav")])
        appState.setBatchInputDirectoryURL(directory)

        XCTAssertEqual(appState.batchViewModel.inputDirectoryURL, directory)
        XCTAssertTrue(appState.batchViewModel.inputFileURLs.isEmpty)
        XCTAssertNil(appState.inferenceViewModel.inputFileURL)
    }

    /// 验证单文件推理视图模型可以将 patch 与参数区回退到默认值。
    func testInferenceViewModelResetMethodsRestoreDefaults() {
        let viewModel = InferenceViewModel(bridgeClient: BusyTestBridgeClient(), audioPlayer: AudioPreviewPlayer())
        viewModel.speakerID = 5
        viewModel.f0Method = .crepe
        viewModel.transpose = 12
        viewModel.indexRate = 0.21
        viewModel.filterRadius = 7
        viewModel.resampleSR = 22_050
        viewModel.rmsMixRate = 0.91
        viewModel.protect = 0.12

        viewModel.resetPatchDefaults()
        viewModel.resetParameterDefaults()

        XCTAssertEqual(viewModel.speakerID, 0)
        XCTAssertEqual(viewModel.f0Method, .crepe)
        XCTAssertEqual(viewModel.transpose, 0)
        XCTAssertEqual(viewModel.indexRate, 0.75)
        XCTAssertEqual(viewModel.filterRadius, 3)
        XCTAssertEqual(viewModel.resampleSR, 0)
        XCTAssertEqual(viewModel.rmsMixRate, 1)
        XCTAssertEqual(viewModel.protect, 0.33)
    }

    /// 验证批处理视图模型可以将 patch 与参数区回退到默认值。
    func testBatchViewModelResetMethodsRestoreDefaults() {
        let viewModel = BatchViewModel(bridgeClient: BusyTestBridgeClient())
        viewModel.speakerID = 3
        viewModel.f0Method = .fcpe
        viewModel.transpose = -7
        viewModel.indexRate = 0.2
        viewModel.filterRadius = 6
        viewModel.resampleSR = 16_000
        viewModel.rmsMixRate = 0.44
        viewModel.protect = 0.18
        viewModel.format = .flac

        viewModel.resetPatchDefaults()
        viewModel.resetParameterDefaults()

        XCTAssertEqual(viewModel.speakerID, 0)
        XCTAssertEqual(viewModel.f0Method, .crepe)
        XCTAssertEqual(viewModel.transpose, 0)
        XCTAssertEqual(viewModel.indexRate, 0.75)
        XCTAssertEqual(viewModel.filterRadius, 3)
        XCTAssertEqual(viewModel.resampleSR, 0)
        XCTAssertEqual(viewModel.rmsMixRate, 1)
        XCTAssertEqual(viewModel.protect, 0.33)
        XCTAssertEqual(viewModel.format, .wav)
    }

    /// 验证实时视图模型可以分别重置路由区与实验区的默认参数。
    func testRealtimeViewModelResetMethodsRestoreDefaults() {
        let viewModel = RealtimeViewModel(bridgeClient: BusyTestBridgeClient())
        viewModel.selectedHostapi = "Core Audio"
        viewModel.selectedInputDevice = "Mic"
        viewModel.selectedOutputDevice = "Speaker"
        viewModel.monitorMode = .inputMonitor
        viewModel.wasapiExclusive = true
        viewModel.sampleRateMode = .device
        viewModel.threshold = -25
        viewModel.formant = 4.2
        viewModel.sampleLength = 1.2
        viewModel.fadeLength = 0.44
        viewModel.extraInferenceTime = 5.5
        viewModel.cpuProcesses = 1
        viewModel.inputNoiseReduction = true
        viewModel.outputNoiseReduction = true
        viewModel.usePhaseVocoder = true

        viewModel.resetRoutingDefaults()
        viewModel.resetLabDefaults()

        XCTAssertNil(viewModel.selectedHostapi)
        XCTAssertNil(viewModel.selectedInputDevice)
        XCTAssertNil(viewModel.selectedOutputDevice)
        XCTAssertEqual(viewModel.monitorMode, .outputConverted)
        XCTAssertFalse(viewModel.wasapiExclusive)
        XCTAssertEqual(viewModel.sampleRateMode, .model)
        XCTAssertEqual(viewModel.threshold, -60)
        XCTAssertEqual(viewModel.formant, 0)
        XCTAssertEqual(viewModel.sampleLength, 0.25)
        XCTAssertEqual(viewModel.fadeLength, 0.05)
        XCTAssertEqual(viewModel.extraInferenceTime, 2.5)
        XCTAssertEqual(viewModel.cpuProcesses, min(ProcessInfo.processInfo.processorCount, 4))
        XCTAssertFalse(viewModel.inputNoiseReduction)
        XCTAssertFalse(viewModel.outputNoiseReduction)
        XCTAssertFalse(viewModel.usePhaseVocoder)
    }
}
