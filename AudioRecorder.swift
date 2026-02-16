import Foundation
import AVFoundation

final class AudioRecorder: NSObject, ObservableObject {
    enum RecorderError: LocalizedError {
        case microphonePermissionDenied
        case recorderUnavailable

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone permission is required to record conversations."
            case .recorderUnavailable:
                return "Unable to initialize audio recording."
            }
        }
    }

    @Published private(set) var isRecording = false

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    func requestPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func startRecording() async throws {
        let hasPermission = await requestPermission()
        guard hasPermission else {
            throw RecorderError.microphonePermissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let filename = "rapport_\(UUID().uuidString).m4a"
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: targetURL, settings: settings)
        recorder?.isMeteringEnabled = true

        guard recorder?.record() == true else {
            throw RecorderError.recorderUnavailable
        }

        recordingURL = targetURL
        isRecording = true
    }

    @discardableResult
    func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false)
        return recordingURL
    }

    func currentRecordingURL() -> URL? {
        recordingURL
    }
}
