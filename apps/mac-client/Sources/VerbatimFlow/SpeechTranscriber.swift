import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechTranscriber {
    private let localeIdentifier: String
    private let requireOnDeviceRecognition: Bool

    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechRecognizer: SFSpeechRecognizer?

    private var latestTranscript: String = ""
    private var stopContinuation: CheckedContinuation<String, Never>?

    init(localeIdentifier: String, requireOnDeviceRecognition: Bool) {
        self.localeIdentifier = localeIdentifier
        self.requireOnDeviceRecognition = requireOnDeviceRecognition
    }

    func ensurePermissions() async -> Bool {
        let speechAuthorized = await requestSpeechAuthorization()
        let micAuthorized = await requestMicrophoneAuthorization()
        return speechAuthorized && micAuthorized
    }

    func startRecording() throws {
        latestTranscript = ""
        recognitionTask?.cancel()
        recognitionTask = nil

        let locale = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw AppError.speechRecognizerUnavailable(localeIdentifier)
        }
        speechRecognizer = recognizer

        guard recognizer.isAvailable else {
            throw AppError.speechServiceUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = requireOnDeviceRecognition
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.latestTranscript = result.bestTranscription.formattedString
                if result.isFinal {
                    self.finishStopIfNeeded()
                }
            }
            if error != nil {
                self.finishStopIfNeeded()
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stopRecording() async -> String {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        return await withCheckedContinuation { continuation in
            stopContinuation = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.finishStopIfNeeded()
            }
        }
    }

    private func finishStopIfNeeded() {
        guard let continuation = stopContinuation else {
            return
        }
        stopContinuation = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        continuation.resume(returning: latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
