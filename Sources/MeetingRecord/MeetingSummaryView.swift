import SwiftUI
import AppKit

struct MeetingSummaryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let meetingID: UUID
    let store: MeetingStore
    let recordingRevision: Int
    let transcriptionRevision: Int
    let isRecording: Bool
    @ObservedObject var summaries: MeetingSummaryCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SummaryModel.preferenceKey) private var selectedModel: SummaryModel = .appleIntelligence
    @AppStorage(OpenAISummaryKey.savedPreferenceKey) private var hasOpenAIKey = false
    @State private var snapshot: MeetingSummarySnapshot?
    @State private var loadError: String?
    @State private var modelAvailability: MeetingSummarizer.Availability?
    @State private var confirmingGeneration = false

    private struct AvailabilityCheck: Equatable {
        let scenePhase: ScenePhase
        let model: SummaryModel
    }

    private var isGenerating: Bool { summaries.generating.contains(meetingID) }
    private var canGenerate: Bool {
        snapshot?.canGenerate == true && !isRecording && !isGenerating &&
        (selectedModel.usesOpenAI ? hasOpenAIKey : modelAvailability == .ready) && loadError == nil
    }

    var body: some View {
        Group {
            if let summary = snapshot?.summary {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        summaryActions
                        summaryText(summary.text)
                    }
                    .frame(maxWidth: 570, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 92)
                }
                .scrollIndicators(.never)
                .transition(.opacity)
            } else if snapshot != nil || loadError != nil {
                emptySummary
                    .offset(y: -20)
                    .transition(.opacity)
            } else {
                ProgressView("Loading summary…")
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isGenerating)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: summaries.revision)
        .alert(snapshot?.summary == nil ? "Generate Summary?" : "Regenerate Summary?",
               isPresented: $confirmingGeneration, presenting: selectedModel) { model in
            Button(snapshot?.summary == nil ? "Generate Summary" : "Regenerate Summary") {
                summaries.generate(for: meetingID, model: model)
            }
            Button("Cancel", role: .cancel) {}
        } message: { model in
            if model.usesOpenAI {
                Text("Using \(model.displayName) sends this meeting’s transcript text to OpenAI.")
            } else {
                Text("Apple Intelligence will summarize this meeting on your Mac.")
            }
        }
        .task(id: [recordingRevision, transcriptionRevision, summaries.revision]) {
            do {
                let current = try await store.summarySnapshot(for: meetingID)
                guard !Task.isCancelled else { return }
                snapshot = current
                loadError = nil
            } catch {
                guard !Task.isCancelled else { return }
                loadError = "Could not load summary. \(error.localizedDescription)"
            }
        }
        .task(id: AvailabilityCheck(scenePhase: scenePhase, model: selectedModel)) {
            guard scenePhase == .active, !selectedModel.usesOpenAI else { return }
            await MeetingSummarizer.watchAvailability { modelAvailability = $0 }
        }
    }

    private var summaryActions: some View {
        HStack(spacing: 10) {
            Text(snapshot?.isOutdated == true
                 ? "New transcript text is available."
                 : "No changes since the last summary.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                confirmingGeneration = true
            } label: {
                Image(systemName: "sparkles")
            }
            .disabled(!canGenerate)
            .help("Regenerate Summary")
            .accessibilityLabel("Regenerate Summary")
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(snapshot?.summary?.text ?? "", forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy Summary")
            .accessibilityLabel("Copy Summary")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .opacity(isGenerating ? 0.5 : 1)
    }

    private var emptySummary: some View {
        VStack(spacing: 8) {
            MeetingEmptyState("No summary yet.", detail: emptySummaryDetail) {
                SummaryShine()
                    .stroke(style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    .frame(width: 36, height: 36)
            }
            if isGenerating {
                ProgressView("Generating summary…").controlSize(.small)
            } else if let snapshot, !snapshot.transcript.isEmpty, loadError == nil {
                Button {
                    confirmingGeneration = true
                } label: {
                    Label(summaries.errors[meetingID] == nil ? "Generate Summary" : "Retry Summary",
                          systemImage: "sparkles")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay {
                            Capsule().strokeBorder(.secondary.opacity(0.55), lineWidth: 1)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canGenerate)
                .opacity(canGenerate ? 1 : 0.5)
            }
        }
        .frame(maxWidth: 420)
    }

    private var emptySummaryDetail: String? {
        if let loadError { return loadError }
        if let error = summaries.errors[meetingID] { return error }
        if isRecording || snapshot?.hasPendingAudio == true {
            return "Available after all recordings finish transcribing."
        }
        guard snapshot?.canGenerate == true else { return "There is no transcript to summarize yet." }
        if selectedModel.usesOpenAI {
            return hasOpenAIKey ? nil : "Save an OpenAI API key in Settings → Summarization."
        }
        return modelAvailability?.message
    }

    private func summaryText(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: true)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.enumerated()), id: \.offset) { index, line in
                let value = line.trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("#") {
                    formattedText(String(value.drop(while: { $0 == "#" || $0 == " " })))
                        .font(.system(size: 19, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, index == 0 ? 0 : 14)
                } else if value.hasPrefix("- ") || value.hasPrefix("* ") || value.hasPrefix("• ") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        formattedText(String(value.dropFirst(2)))
                    }
                    .padding(.leading, 4)
                } else {
                    formattedText(value)
                }
            }
        }
        .font(.system(size: 15))
        .lineSpacing(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func formattedText(_ value: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: value, options: options)).map { Text($0) } ?? Text(value)
    }
}

private struct SummaryShine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        addSparkle(to: &path, center: CGPoint(x: 20, y: 31), radius: 17)
        addSparkle(to: &path, center: CGPoint(x: 42, y: 13), radius: 9)
        addSparkle(to: &path, center: CGPoint(x: 45, y: 37), radius: 6)
        return path.applying(CGAffineTransform(scaleX: rect.width / 54, y: rect.height / 54))
    }

    private func addSparkle(to path: inout Path, center: CGPoint, radius: CGFloat) {
        let x = center.x
        let y = center.y
        path.move(to: CGPoint(x: x, y: y - radius))
        path.addQuadCurve(to: CGPoint(x: x + radius, y: y), control: center)
        path.addQuadCurve(to: CGPoint(x: x, y: y + radius), control: center)
        path.addQuadCurve(to: CGPoint(x: x - radius, y: y), control: center)
        path.addQuadCurve(to: CGPoint(x: x, y: y - radius), control: center)
        path.closeSubpath()
    }
}
