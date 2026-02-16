import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


struct RapportAnalysis: Codable {
    struct KeyMoment: Codable, Identifiable {
        let timestamp: String
        let advice: String

        var id: String { "\(timestamp)-\(advice)" }
    }

    let rapportScore: Int
    let talkRatioSummary: String
    let keyMoments: [KeyMoment]
    let actionableFeedback: [String]

    private enum CodingKeys: String, CodingKey {
        case rapportScore = "rapport_score"
        case talkRatioSummary = "talk_ratio_summary"
        case keyMoments = "key_moments"
        case actionableFeedback = "actionable_feedback"
    }
}

struct TranscriptionResult: Codable {
    struct Utterance: Codable {
        let speaker: String
        let text: String
        let words: Int

        init(speaker: String, text: String) {
            self.speaker = speaker
            self.text = text
            self.words = text.split { $0.isWhitespace || $0.isNewline }.count
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let speaker = try container.decode(String.self, forKey: .speaker)
            let text = try container.decode(String.self, forKey: .text)
            self.init(speaker: speaker, text: text)
        }

        private enum CodingKeys: String, CodingKey {
            case speaker
            case text
        }
    }

    let id: String
    let status: String
    let utterances: [Utterance]
    let text: String?
    let error: String?
    let analysis: RapportAnalysis?
}

final class APIService {
    enum APIError: LocalizedError {
        case invalidResponse
        case serverError(String)
        case missingAPIKey

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Unexpected response from server."
            case .serverError(let message):
                return message
            case .missingAPIKey:
                return "Set ASSEMBLYAI_API_KEY before using the API service."
            }
        }
    }

    static let systemPrompt = """
    Analyze this conversation for social rapport. Return a JSON with:
    - rapport_score (0-100)
    - talk_ratio_summary (string)
    - key_moments (list of objects with timestamp and advice)
    - actionable_feedback (list of strings)
    """

    private let baseURL = URL(string: "https://api.assemblyai.com/v2")!
    private let session: URLSession
    private let apiKey: String

    init(session: URLSession = .shared, apiKey: String? = ProcessInfo.processInfo.environment["ASSEMBLYAI_API_KEY"]) throws {
        guard let apiKey, !apiKey.isEmpty else {
            throw APIError.missingAPIKey
        }
        self.session = session
        self.apiKey = apiKey
    }

    func uploadAudio(fileURL: URL) async throws -> String {
        let audioData = try Data(contentsOf: fileURL)
        let url = baseURL.appendingPathComponent("upload")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = audioData
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        struct UploadResponse: Codable { let upload_url: String }
        let response: UploadResponse = try await perform(request)
        return response.upload_url
    }

    func createTranscription(uploadURL: String) async throws -> String {
        let url = baseURL.appendingPathComponent("transcript")

        struct RequestBody: Codable {
            let audio_url: String
            let speaker_labels: Bool
            let speech_model: String
            let prompt: String
        }

        let body = RequestBody(
            audio_url: uploadURL,
            speaker_labels: true,
            speech_model: "best",
            prompt: Self.systemPrompt
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        struct TranscribeResponse: Codable { let id: String }
        let response: TranscribeResponse = try await perform(request)
        return response.id
    }

    func pollTranscription(transcriptID: String, intervalSeconds: UInt64 = 3) async throws -> TranscriptionResult {
        while true {
            let result = try await getTranscriptionStatus(transcriptID: transcriptID)
            switch result.status.lowercased() {
            case "completed":
                return result
            case "error":
                throw APIError.serverError(result.error ?? "Transcription failed")
            default:
                try await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
            }
        }
    }

    private func getTranscriptionStatus(transcriptID: String) async throws -> TranscriptionResult {
        let url = baseURL.appendingPathComponent("transcript/\(transcriptID)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

        return try await perform(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let message = String(data: data, encoding: .utf8), !message.isEmpty {
                throw APIError.serverError(message)
            }
            throw APIError.invalidResponse
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}
