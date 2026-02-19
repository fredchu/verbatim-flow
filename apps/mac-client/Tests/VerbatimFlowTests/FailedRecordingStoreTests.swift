import Foundation
import XCTest
@testable import VerbatimFlow

final class FailedRecordingStoreTests: XCTestCase {
    func testSaveLoadAndClear() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceAudioURL = root.appendingPathComponent("source.m4a")
        try Data("fake-audio".utf8).write(to: sourceAudioURL)

        let saved = FailedRecordingStore.save(
            sourceAudioURL: sourceAudioURL,
            recognitionEngine: .openai,
            localeIdentifier: "zh-Hans",
            whisperModel: .small,
            whisperComputeType: "int8",
            openAIModel: .gpt4oMiniTranscribe,
            durationSeconds: 3.2,
            baseDirectory: root
        )
        XCTAssertNotNil(saved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceAudioURL.path))

        let loaded = FailedRecordingStore.load(baseDirectory: root)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.recognitionEngineRawValue, RecognitionEngine.openai.rawValue)
        XCTAssertEqual(loaded?.localeIdentifier, "zh-Hans")
        XCTAssertEqual(loaded?.openAIModelRawValue, OpenAITranscriptionModel.gpt4oMiniTranscribe.rawValue)

        FailedRecordingStore.clear(baseDirectory: root)
        XCTAssertNil(FailedRecordingStore.load(baseDirectory: root))
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("verbatimflow-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
