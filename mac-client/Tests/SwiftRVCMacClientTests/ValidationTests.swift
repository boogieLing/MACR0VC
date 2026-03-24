import XCTest
@testable import SwiftRVCMacClient

final class ValidationTests: XCTestCase {
    func testSingleInferenceEncodingUsesSpeakerIdKey() throws {
        let request = SingleInferenceRequest(
            modelName: "demo.pth",
            inputFileURL: URL(fileURLWithPath: "/tmp/demo.wav"),
            speakerID: 7,
            transpose: 0,
            f0Method: .rmvpe,
            indexPath: nil,
            customIndexURL: nil,
            indexRate: 0.75,
            filterRadius: 3,
            resampleSR: 0,
            rmsMixRate: 0.25,
            protect: 0.33,
            f0FileURL: nil
        )

        let data = try JSONEncoder().encode(request)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(payload["speakerId"] as? Int, 7)
        XCTAssertNil(payload["speakerID"])
    }

    func testBatchInferenceEncodingUsesSpeakerIdKey() throws {
        let request = BatchInferenceRequest(
            modelName: "demo.pth",
            inputDirectoryURL: URL(fileURLWithPath: "/tmp/in", isDirectory: true),
            inputFileURLs: [],
            outputDirectoryURL: URL(fileURLWithPath: "/tmp/out", isDirectory: true),
            format: .wav,
            speakerID: 11,
            transpose: 0,
            f0Method: .rmvpe,
            indexPath: nil,
            customIndexURL: nil,
            indexRate: 1,
            filterRadius: 3,
            resampleSR: 0,
            rmsMixRate: 1,
            protect: 0.33
        )

        let data = try JSONEncoder().encode(request)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(payload["speakerId"] as? Int, 11)
        XCTAssertNil(payload["speakerID"])
    }

    func testSingleInferenceValidationRequiresExistingFile() {
        let request = SingleInferenceRequest(
            modelName: "demo.pth",
            inputFileURL: URL(fileURLWithPath: "/tmp/does-not-exist.wav"),
            speakerID: 0,
            transpose: 0,
            f0Method: .rmvpe,
            indexPath: nil,
            customIndexURL: nil,
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
            speakerID: 0,
            transpose: 0,
            f0Method: .rmvpe,
            indexPath: nil,
            customIndexURL: nil,
            indexRate: 1,
            filterRadius: 3,
            resampleSR: 0,
            rmsMixRate: 1,
            protect: 0.33
        )

        XCTAssertThrowsError(try request.validate())
    }

    func testSingleInferenceValidationRejectsMissingCustomIndexFile() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let inputFile = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        FileManager.default.createFile(atPath: inputFile.path, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(at: inputFile) }

        let request = SingleInferenceRequest(
            modelName: "demo.pth",
            inputFileURL: inputFile,
            speakerID: 0,
            transpose: 0,
            f0Method: .rmvpe,
            indexPath: nil,
            customIndexURL: URL(fileURLWithPath: "/tmp/missing.index"),
            indexRate: 0.75,
            filterRadius: 3,
            resampleSR: 0,
            rmsMixRate: 0.25,
            protect: 0.33,
            f0FileURL: nil
        )

        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? ValidationError, .missingCustomIndexFile)
        }
    }

    func testSingleInferenceValidationRejectsMissingF0CurveFile() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let inputFile = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        FileManager.default.createFile(atPath: inputFile.path, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(at: inputFile) }

        let request = SingleInferenceRequest(
            modelName: "demo.pth",
            inputFileURL: inputFile,
            speakerID: 0,
            transpose: 0,
            f0Method: .rmvpe,
            indexPath: nil,
            customIndexURL: nil,
            indexRate: 0.75,
            filterRadius: 3,
            resampleSR: 0,
            rmsMixRate: 0.25,
            protect: 0.33,
            f0FileURL: URL(fileURLWithPath: "/tmp/missing_f0.txt")
        )

        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? ValidationError, .missingF0CurveFile)
        }
    }

    func testBatchInferenceValidationRejectsMissingCustomIndexFile() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let inputDirectory = tempDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: inputDirectory) }

        let request = BatchInferenceRequest(
            modelName: "demo.pth",
            inputDirectoryURL: inputDirectory,
            inputFileURLs: [],
            outputDirectoryURL: tempDirectory,
            format: .wav,
            speakerID: 0,
            transpose: 0,
            f0Method: .rmvpe,
            indexPath: nil,
            customIndexURL: URL(fileURLWithPath: "/tmp/missing.index"),
            indexRate: 1,
            filterRadius: 3,
            resampleSR: 0,
            rmsMixRate: 1,
            protect: 0.33
        )

        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? ValidationError, .missingCustomIndexFile)
        }
    }

    func testUVRValidationRejectsMixedInputModes() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let tempFile = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let request = UVRRequest(
            modelName: "HP5",
            inputDirectoryURL: tempDirectory,
            inputFileURLs: [tempFile],
            vocalOutputDirectoryURL: tempDirectory,
            instrumentalOutputDirectoryURL: tempDirectory,
            format: .flac
        )

        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? ValidationError, .invalidUVRInputMode)
        }
    }

    func testUVRValidationRejectsMissingExplicitInputFile() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let request = UVRRequest(
            modelName: "HP5",
            inputDirectoryURL: nil,
            inputFileURLs: [URL(fileURLWithPath: "/tmp/missing-uvr.wav")],
            vocalOutputDirectoryURL: tempDirectory,
            instrumentalOutputDirectoryURL: tempDirectory,
            format: .wav
        )

        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? ValidationError, .missingInputFile)
        }
    }
}
