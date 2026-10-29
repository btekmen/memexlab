import AVFoundation
import Foundation
import Observation
import Speech

/// Press-to-talk dictation. On-device recognition whenever the device/language supports it
/// (and always, if the user says "on-device only"); the raw audio is optionally kept as .m4a.
@Observable
final class Dictation {
    var isRecording = false
    var transcript = ""
    var usingOnDevice = false
    var lastError: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var file: AVAudioFile?

    enum DictationError: LocalizedError {
        case denied, unavailable, onDeviceUnavailable
        var errorDescription: String? {
            switch self {
            case .denied: return "Microphone or speech permission was not granted (Settings → Slate)."
            case .unavailable: return "Speech recognition is not available for this language right now."
            case .onDeviceUnavailable: return "On-device recognition isn't available for this language on this device. Turn off “on-device only” to use Apple's server-side recognition."
            }
        }
    }

    static func requestPermissions() async -> Bool {
        let speech: Bool = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    func start(locale: Locale, onDeviceOnly: Bool, recordTo url: URL?) async throws {
        guard !isRecording else { return }
        guard await Self.requestPermissions() else { throw DictationError.denied }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { throw DictationError.unavailable }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
            usingOnDevice = true
        } else if onDeviceOnly {
            throw DictationError.onDeviceUnavailable
        } else {
            usingOnDevice = false
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        if let url {
            file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ])
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            req.append(buffer)
            try? self?.file?.write(from: buffer)
        }
        engine.prepare()
        try engine.start()

        request = req
        transcript = ""
        lastError = nil
        isRecording = true
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if let error, self.isRecording {
                    // "No speech detected" and cancellation are normal ends, not failures.
                    let code = (error as NSError).code
                    if code != 216 && code != 1110 && code != 301 { self.lastError = error.localizedDescription }
                    self.stop()
                } else if result?.isFinal == true {
                    self.stop()
                }
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        file = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
