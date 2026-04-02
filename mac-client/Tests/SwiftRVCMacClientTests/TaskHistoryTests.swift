import XCTest
@testable import SwiftRVCMacClient

@MainActor
final class TaskHistoryTests: XCTestCase {
    /// 验证任务失败事件会写入历史，并可从持久化存储恢复。
    func testTaskHistoryPersistsFailureEntries() async {
        let defaults = makeDefaultsSuite()
        let appState = AppState(
            environment: .fallback(),
            bridgeClient: BusyTestBridgeClient(),
            startMetricsTask: false,
            userDefaults: defaults
        )
        appState.selectedModelName = "demo.pth"
        appState.setSingleInputFileURL(URL(fileURLWithPath: "/tmp/demo.wav"))

        appState.inferenceViewModel.errorMessage = "boom"
        await Task.yield()

        XCTAssertEqual(appState.taskHistory.count, 1)
        XCTAssertEqual(appState.taskHistory.first?.kind, .single)
        XCTAssertEqual(appState.taskHistory.first?.status, .failure)
        XCTAssertEqual(appState.taskHistory.first?.summary, "boom")

        let restored = AppState(
            environment: .fallback(),
            bridgeClient: BusyTestBridgeClient(),
            startMetricsTask: false,
            userDefaults: defaults
        )

        XCTAssertEqual(restored.taskHistory.count, 1)
        XCTAssertEqual(restored.taskHistory.first?.summary, "boom")
    }

    /// 验证清空历史会同步清空持久化存储。
    func testClearTaskHistoryRemovesPersistedEntries() async {
        let defaults = makeDefaultsSuite()
        let appState = AppState(
            environment: .fallback(),
            bridgeClient: BusyTestBridgeClient(),
            startMetricsTask: false,
            userDefaults: defaults
        )

        appState.inferenceViewModel.errorMessage = "to-be-cleared"
        await Task.yield()
        XCTAssertEqual(appState.taskHistory.count, 1)

        appState.clearTaskHistory()
        XCTAssertTrue(appState.taskHistory.isEmpty)

        let restored = AppState(
            environment: .fallback(),
            bridgeClient: BusyTestBridgeClient(),
            startMetricsTask: false,
            userDefaults: defaults
        )

        XCTAssertTrue(restored.taskHistory.isEmpty)
    }

    /// 验证旧版历史 JSON 缺少新字段时仍可兼容解码。
    func testTaskHistoryDecodesLegacyEntriesWithoutArtifacts() throws {
        let payload = """
        {
          "id": "\(UUID().uuidString)",
          "timestamp": "2026-03-27T00:00:00Z",
          "kind": "single",
          "status": "success",
          "title": "Single convert",
          "summary": "ok",
          "modelName": "demo.pth",
          "inputLabel": "demo.wav",
          "inputPath": "/tmp/demo.wav",
          "outputLabel": "demo-out.wav",
          "outputPath": "/tmp/demo-out.wav",
          "indexPath": null,
          "f0Method": "rmvpe",
          "speakerID": 0,
          "errorMessage": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(TaskHistoryEntry.self, from: payload)

        XCTAssertTrue(entry.outputArtifacts.isEmpty)
        XCTAssertNil(entry.sourceTaskID)
    }

    /// 验证文本生成音频任务会写入历史，并自动挂上生成产物。
    func testTextAudioGenerationPersistsTextHistoryEntry() async throws {
        let defaults = makeDefaultsSuite()
        let appState = AppState(
            environment: .fallback(),
            bridgeClient: BusyTestBridgeClient(),
            startMetricsTask: false,
            userDefaults: defaults
        )

        appState.selectedModelName = "demo.pth"
        appState.engineController.forceReadyForTesting()
        appState.setTextAudioInput("hello from text audio")
        await appState.runTextAudioGenerate()

        XCTAssertEqual(appState.primaryInputMode, .text)
        XCTAssertNotNil(appState.inferenceViewModel.outputAudioURL)
        XCTAssertEqual(appState.taskHistory.first?.kind, .text)
        XCTAssertEqual(appState.taskHistory.first?.status, .success)
        XCTAssertEqual(appState.taskHistory.first?.outputArtifacts.contains(where: { $0.role == .textOutput }), true)
        XCTAssertEqual(appState.taskHistory.first?.outputArtifacts.contains(where: { $0.role == .textSource }), true)
        XCTAssertEqual(appState.taskHistory.first?.parameterSummary?.contains("RVC Voice Priority"), true)
        XCTAssertEqual(appState.taskHistory.first?.timingSummary?.contains("Convert"), true)
    }

    /// 验证删除 text 历史时会同步删除任务目录以及生成的 source/output 文件。
    func testDeletingTextHistoryRemovesStoredArtifactsFromDisk() async throws {
        let defaults = makeDefaultsSuite()
        let appState = AppState(
            environment: .fallback(),
            bridgeClient: BusyTestBridgeClient(),
            startMetricsTask: false,
            userDefaults: defaults
        )

        appState.selectedModelName = "demo.pth"
        appState.engineController.forceReadyForTesting()
        appState.setTextAudioInput("delete this text task")
        await appState.runTextAudioGenerate()

        guard let entry = appState.taskHistory.first else {
            XCTFail("Expected a text task history entry")
            return
        }

        let outputPaths = entry.outputArtifacts.map(\.path)
        let taskDirectoryPath = try XCTUnwrap(entry.taskDirectoryPath)
        let fileManager = FileManager.default

        XCTAssertTrue(outputPaths.allSatisfy(fileManager.fileExists(atPath:)))
        XCTAssertTrue(fileManager.fileExists(atPath: taskDirectoryPath))

        appState.deleteTaskHistoryEntry(entry)

        XCTAssertTrue(appState.taskHistory.isEmpty)
        XCTAssertFalse(fileManager.fileExists(atPath: taskDirectoryPath))
        XCTAssertTrue(outputPaths.allSatisfy { !fileManager.fileExists(atPath: $0) })
    }

    /// 验证旧版 text 历史缺少 artifacts 时，删除仍会推导并清理同目录下的 `-source.wav`。
    func testDeletingLegacyTextHistoryRemovesInferredSourceFile() throws {
        let defaults = makeDefaultsSuite()
        let tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectoryURL) }

        let outputURL = tempDirectoryURL.appendingPathComponent("legacy-text-20260402-143500.wav")
        let sourceURL = tempDirectoryURL.appendingPathComponent("legacy-text-20260402-143500-source.wav")
        try Data("output".utf8).write(to: outputURL)
        try Data("source".utf8).write(to: sourceURL)

        let legacyEntry = TaskHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            kind: .text,
            status: .success,
            title: "Text audio",
            summary: "legacy",
            modelName: "demo.pth",
            inputLabel: "legacy text",
            inputPath: "legacy text",
            outputLabel: outputURL.lastPathComponent,
            outputPath: outputURL.path,
            indexPath: nil,
            f0Method: "crepe",
            parameterSummary: nil,
            timingSummary: nil,
            speakerID: 0,
            errorMessage: nil,
            taskDirectoryPath: nil,
            outputArtifacts: [],
            sourceTaskID: nil
        )

        defaults.set(try JSONEncoder().encode([legacyEntry]), forKey: "local.r0.SwiftRVCMacClient.taskHistory.v1")

        let appState = AppState(
            environment: .fallback(),
            bridgeClient: BusyTestBridgeClient(),
            startMetricsTask: false,
            userDefaults: defaults
        )

        XCTAssertEqual(appState.taskHistory.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))

        appState.deleteTaskHistoryEntry(legacyEntry)

        XCTAssertTrue(appState.taskHistory.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    /// 验证输入中心只暴露磁盘上仍存在的 UVR vocal 结果。
    func testAvailableUVRVocalEntriesFiltersMissingFiles() throws {
        let defaults = makeDefaultsSuite()
        let tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectoryURL) }

        let availableVocalURL = tempDirectoryURL.appendingPathComponent("available-vocal.wav")
        try Data("vocal".utf8).write(to: availableVocalURL)
        let missingVocalURL = tempDirectoryURL.appendingPathComponent("missing-vocal.wav")

        let availableEntry = makeUVRHistoryEntry(outputURL: availableVocalURL, label: "available-vocal.wav")
        let missingEntry = makeUVRHistoryEntry(outputURL: missingVocalURL, label: "missing-vocal.wav")
        defaults.set(try JSONEncoder().encode([availableEntry, missingEntry]), forKey: "local.r0.SwiftRVCMacClient.taskHistory.v1")

        let appState = AppState(
            environment: .fallback(),
            bridgeClient: BusyTestBridgeClient(),
            startMetricsTask: false,
            userDefaults: defaults
        )

        XCTAssertEqual(appState.availableUVRVocalEntries.map(\.id), [availableEntry.id])
    }

    /// 验证选中某条 UVR vocal 历史后，会直接作为单文件输入挂到推理面板。
    func testUseUVRVocalInputLoadsSingleInferenceSource() throws {
        let defaults = makeDefaultsSuite()
        let tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectoryURL) }

        let vocalURL = tempDirectoryURL.appendingPathComponent("selected-vocal.wav")
        try Data("vocal".utf8).write(to: vocalURL)
        let entry = makeUVRHistoryEntry(outputURL: vocalURL, label: "selected-vocal.wav")
        defaults.set(try JSONEncoder().encode([entry]), forKey: "local.r0.SwiftRVCMacClient.taskHistory.v1")

        let appState = AppState(
            environment: .fallback(),
            bridgeClient: BusyTestBridgeClient(),
            startMetricsTask: false,
            userDefaults: defaults
        )

        appState.useUVRVocalInput(from: entry)

        XCTAssertEqual(appState.primaryInputMode, .file)
        XCTAssertEqual(appState.inferenceViewModel.inputFileURL?.path, vocalURL.path)
        XCTAssertEqual(appState.statusMessage, "Loaded file selected-vocal.wav. Ready for single convert.")
    }

    /// 构造隔离的 UserDefaults suite，避免污染真实本地历史。
    private func makeDefaultsSuite() -> UserDefaults {
        let suiteName = "SwiftRVCMacClientTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// 构造最小 UVR 历史项，供输入来源复用测试使用。
    private func makeUVRHistoryEntry(outputURL: URL, label: String) -> TaskHistoryEntry {
        TaskHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            kind: .uvr,
            status: .success,
            title: "UVR separate",
            summary: "ready",
            modelName: "uvr-model",
            inputLabel: "source.wav",
            inputPath: "/tmp/source.wav",
            outputLabel: label,
            outputPath: outputURL.path,
            indexPath: nil,
            f0Method: nil,
            parameterSummary: nil,
            timingSummary: nil,
            speakerID: nil,
            errorMessage: nil,
            taskDirectoryPath: outputURL.deletingLastPathComponent().path,
            outputArtifacts: [
                TaskHistoryArtifact(id: UUID(), role: .uvrVocal, label: label, path: outputURL.path)
            ],
            sourceTaskID: nil
        )
    }
}
