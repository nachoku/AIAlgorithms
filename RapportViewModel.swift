import Foundation

@MainActor
final class RapportViewModel: ObservableObject {
    enum ProcessingState: String {
        case idle
        case uploading
        case analyzing
        case completed
    }

    struct TalkTimeEntry: Identifiable {
        let speaker: String
        let words: Int

        var id: String { speaker }
    }

    struct ConversationAnalysis: Identifiable {
        let id: UUID
        let date: Date
        let rapportScore: Int
        let talkRatioSummary: String
        let coachNotes: [String]
        let talkDistribution: [TalkTimeEntry]
    }

    struct WeeklySummary {
        let weekLabel: String
        let averageRapport: Int
        let conversationCount: Int
    }

    @Published var isRecording = false
    @Published var processingState: ProcessingState = .idle
    @Published var rapportScore = 0
    @Published var talkDistribution: [TalkTimeEntry] = []
    @Published var coachNotes: [String] = []
    @Published var showErrorAlert = false
    @Published var errorMessage = ""
    @Published var conversations: [ConversationAnalysis] = []

    private let recorder = AudioRecorder()
    private let apiService: APIService

    init(apiService: APIService? = nil) {
        if let apiService {
            self.apiService = apiService
        } else {
            self.apiService = (try? APIService()) ?? {
                fatalError("Missing ASSEMBLYAI_API_KEY in environment.")
            }()
        }
    }

    var latestConversation: ConversationAnalysis? {
        conversations.sorted { $0.date > $1.date }.first
    }

    var currentWeekSummary: WeeklySummary {
        let calendar = Calendar.current
        let weekConversations = conversations.filter {
            calendar.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear)
        }

        let avg = weekConversations.isEmpty
            ? 0
            : Int(weekConversations.map(\.rapportScore).reduce(0, +) / weekConversations.count)

        let formatter = DateFormatter()
        formatter.dateFormat = "'Week of' MMM d"

        return WeeklySummary(
            weekLabel: formatter.string(from: Date()),
            averageRapport: avg,
            conversationCount: weekConversations.count
        )
    }

    func toggleRecording() {
        Task {
            do {
                if isRecording {
                    let fileURL = recorder.stopRecording()
                    isRecording = false
                    guard let fileURL else { return }
                    try await processRecording(fileURL: fileURL)
                } else {
                    try await recorder.startRecording()
                    isRecording = true
                }
            } catch {
                handleError(error)
            }
        }
    }

    private func processRecording(fileURL: URL) async throws {
        processingState = .uploading
        let uploadURL = try await apiService.uploadAudio(fileURL: fileURL)

        processingState = .analyzing
        let transcriptID = try await apiService.createTranscription(uploadURL: uploadURL)
        let result = try await apiService.pollTranscription(transcriptID: transcriptID)

        let distribution = calculateTalkTimeDistribution(utterances: result.utterances)
        let ratio = talkRatioSummary(from: distribution)
        let fallbackScore = heuristicRapportScore(from: distribution)

        rapportScore = result.analysis?.rapportScore ?? fallbackScore
        talkDistribution = distribution
        coachNotes = result.analysis?.actionableFeedback ?? ["Aim for balanced speaking turns to improve rapport."]

        let conversation = ConversationAnalysis(
            id: UUID(),
            date: Date(),
            rapportScore: rapportScore,
            talkRatioSummary: result.analysis?.talkRatioSummary ?? ratio,
            coachNotes: coachNotes,
            talkDistribution: distribution
        )
        conversations.append(conversation)

        processingState = .completed
    }

    func calculateTalkTimeDistribution(utterances: [TranscriptionResult.Utterance]) -> [TalkTimeEntry] {
        let counts = utterances.reduce(into: [String: Int]()) { partialResult, utterance in
            partialResult[utterance.speaker, default: 0] += utterance.words
        }

        return counts
            .map { TalkTimeEntry(speaker: $0.key, words: $0.value) }
            .sorted { $0.words > $1.words }
    }

    private func talkRatioSummary(from distribution: [TalkTimeEntry]) -> String {
        guard distribution.count >= 2,
              let first = distribution.first,
              let second = distribution.dropFirst().first,
              second.words > 0 else {
            return "Insufficient speaker data to compute ratio."
        }

        let ratio = Double(first.words) / Double(second.words)
        return "\(first.speaker) spoke \(String(format: "%.2f", ratio))x as much as \(second.speaker)."
    }

    private func heuristicRapportScore(from distribution: [TalkTimeEntry]) -> Int {
        guard distribution.count >= 2 else { return 50 }
        let totalWords = distribution.map(\.words).reduce(0, +)
        guard totalWords > 0 else { return 50 }

        let topShare = Double(distribution[0].words) / Double(totalWords)
        let balancePenalty = abs(0.5 - topShare) * 100
        let score = 100 - Int(balancePenalty * 1.5)

        return min(max(score, 0), 100)
    }

    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showErrorAlert = true
        processingState = .idle
        isRecording = false
    }
}
