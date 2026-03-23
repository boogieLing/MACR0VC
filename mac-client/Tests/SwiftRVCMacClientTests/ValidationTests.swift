import XCTest
@testable import SwiftRVCMacClient

final class ValidationTests: XCTestCase {
    func testSingleInferenceValidationRequiresExistingFile() {
        let request = SingleInferenceRequest(
            modelName: "demo.pth",
            inputFileURL: URL(fileURLWithPath: "/tmp/does-not-exist.wav"),
            transpose: 0,
            f0Method: .rmvpe,
            indexPath: nil,
            indexRate: 0.75,
            filterRadius: 3,
            resampleSR: 0,
            rmsMixRate: 0.25,
            protect: 0.33,
            f0FileURL: nil
        )

        XCTAssertThrowsError(try request.validate())
    }

    func testBatchInferenceValidationRejectsMixedInputModes() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let tempFile = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let request = BatchInferenceRequest(
            modelName: "demo.pth",
            inputDirectoryURL: tempDirectory,
            inputFileURLs: [tempFile],
            outputDirectoryURL: tempDirectory,
            format: .wav,
            transpose: 0,
            f0Method: .rmvpe,
            indexPath: nil,
            indexRate: 1,
            filterRadius: 3,
            resampleSR: 0,
            rmsMixRate: 1,
            protect: 0.33
        )

        XCTAssertThrowsError(try request.validate())
    }
}
