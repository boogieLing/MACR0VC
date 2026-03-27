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

    /// 构造隔离的 UserDefaults suite，避免污染真实本地历史。
    private func makeDefaultsSuite() -> UserDefaults {
        let suiteName = "SwiftRVCMacClientTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
