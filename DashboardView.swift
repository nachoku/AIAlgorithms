import SwiftUI
import Charts

struct DashboardView: View {
    @StateObject private var viewModel = RapportViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 20) {
                        rapportHeader
                        talkTimeChart
                        weeklySummaryCard
                        feedbackSection
                        conversationHistory
                    }
                    .padding()
                }

                recordButton
                    .padding()
            }
            .navigationTitle("Social Dynamics Dashboard")
            .alert("Microphone / Processing Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    private var rapportHeader: some View {
        VStack(spacing: 10) {
            Text("Rapport Score")
                .font(.title2.bold())

            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 20)
                    .frame(width: 170, height: 170)

                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.rapportScore) / 100)
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 170, height: 170)

                Text("\(viewModel.rapportScore)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var talkTimeChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Talk Time Distribution")
                .font(.headline)

            if #available(iOS 17.0, *) {
                Chart(viewModel.talkDistribution) { speaker in
                    SectorMark(
                        angle: .value("Words", speaker.words),
                        innerRadius: .ratio(0.58),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("Speaker", speaker.speaker))
                    .annotation(position: .overlay) {
                        Text("\(speaker.words)")
                            .font(.caption2)
                    }
                }
                .frame(height: 240)
            } else {
                Chart(viewModel.talkDistribution) { speaker in
                    BarMark(
                        x: .value("Speaker", speaker.speaker),
                        y: .value("Words", speaker.words)
                    )
                }
                .frame(height: 220)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var weeklySummaryCard: some View {
        let summary = viewModel.currentWeekSummary

        return VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Summary")
                .font(.headline)
            Text(summary.weekLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Conversations: \(summary.conversationCount)")
            Text("Average Rapport: \(summary.averageRapport)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coach's Notes")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.coachNotes.indices, id: \.self) { idx in
                        Label(viewModel.coachNotes[idx], systemImage: "lightbulb.fill")
                            .foregroundStyle(.primary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.yellow.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var conversationHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversation Analyses")
                .font(.headline)

            ForEach(viewModel.conversations.sorted(by: { $0.date > $1.date })) { conversation in
                NavigationLink {
                    ConversationDetailView(conversation: conversation)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(conversation.date, style: .date)
                            Text(conversation.talkRatioSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("\(conversation.rapportScore)")
                            .font(.headline)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var recordButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            viewModel.toggleRecording()
        } label: {
            Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                .font(.title.bold())
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(viewModel.isRecording ? Color.red : Color.blue)
                .clipShape(Circle())
                .shadow(radius: 5)
        }
        .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")
    }
}

private struct ConversationDetailView: View {
    let conversation: RapportViewModel.ConversationAnalysis

    var body: some View {
        List {
            Section("Rapport Score") {
                Text("\(conversation.rapportScore)")
            }

            Section("Talk Ratio") {
                Text(conversation.talkRatioSummary)
            }

            Section("Coach's Notes") {
                ForEach(conversation.coachNotes, id: \.self) { note in
                    Text(note)
                }
            }
        }
        .navigationTitle("Conversation")
    }
}
