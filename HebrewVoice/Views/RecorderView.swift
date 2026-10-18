import SwiftUI

struct RecorderView: View {
    let session: RecordingSession
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @ScaledMetric(relativeTo: .body) private var transcriptSize = 21
    @AppStorage("keepAudio") private var keepAudio = true

    private var fullText: String { session.current?.text ?? "" }
    // Avoid laying out an entire lecture every time a streaming hypothesis changes.
    private var visibleText: String { session.isBusy ? String(fullText.suffix(4_000)) : fullText }
    private var hasEarlierText: Bool { session.isBusy && fullText.count > 4_000 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack {
                    Label(status, systemImage: session.phase == .recording ? "record.circle" : "lock.fill")
                        .foregroundStyle(session.phase == .recording ? Theme.accent : Theme.green)
                    Spacer()
                    Text((session.current?.duration ?? 0).clockText).font(.title2.monospacedDigit().weight(.medium))
                        .environment(\.layoutDirection, .leftToRight)
                }.font(.subheadline)

                if session.current == nil && !session.isBusy {
                    setup
                } else {
                    if session.phase == .importing {
                        ProgressView(value: session.progress).accessibilityLabel("התקדמות תמלול")
                        Text("\(Int(session.progress * 100))% מהקובץ").font(.caption).foregroundStyle(.secondary)
                    }
                    transcript
                }

                if let error = session.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(Theme.accent)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                controls
                Text("התמלול מתבצע במכשיר בלבד. הטקסט נשמר אוטומטית.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity)
            .background(Theme.background)
            .navigationTitle(session.current?.title ?? "הקלטה חדשה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !session.isBusy {
                    ToolbarItem(placement: .topBarTrailing) { Button("סגירה") { dismiss() } }
                }
            }
            .interactiveDismissDisabled(session.isBusy)
        }
    }

    private var status: String {
        switch session.phase {
        case .idle: return session.current == nil ? "מוכן להקשיב" : "נשמר במכשיר"
        case .preparing: return "מכין את התמלול…"
        case .recording: return "מקליט ומתמלל"
        case .importing: return "מתמלל את הקובץ"
        case .finishing: return "שומר את המילים האחרונות…"
        }
    }

    private var setup: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            WaveformMark().frame(maxWidth: .infinity).padding(.bottom, 16)
            Text("אפשר פשוט להקשיב.")
                .font(.largeTitle.bold()).frame(maxWidth: .infinity)
            Text("הניחו את המכשיר קרוב לדוברים. התמלול יופיע כאן בזמן ההקלטה, גם כשהמסך נעול.")
                .foregroundStyle(.secondary).lineSpacing(5).multilineTextAlignment(.center)
            TextField("שם ההקלטה (למשל, הרצאת הבוקר)", text: $title)
                .padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            Toggle("שמירת קובץ השמע לצד התמלול", isOn: $keepAudio).font(.subheadline)
            Text("לפני שמתחילים, ודאו שהמשתתפים יודעים שהשיחה מוקלטת.")
                .font(.footnote).foregroundStyle(.secondary)
          }.padding(.vertical, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !visibleText.isEmpty {
                        if hasEarlierText {
                            Text("הטקסט המוקדם נשמר. כאן מוצגות המילים האחרונות.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Text(visibleText).font(.system(size: transcriptSize)).lineSpacing(10)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 18) {
                            Image(systemName: "waveform").font(.system(size: 40, weight: .light)).foregroundStyle(Theme.accent)
                            Text(session.isBusy ? "המילים יופיעו כאן…" : "לא זוהה דיבור בהקלטה.")
                                .foregroundStyle(.secondary)
                            if session.isBusy { Text("התמלול מתעדכן בכל כמה שניות.").font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity).padding(.top, 70)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(20)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
            .onChange(of: session.current?.text) { _, _ in
                if session.isBusy { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder private var controls: some View {
        switch session.phase {
        case .idle:
            if let current = session.current {
                ShareLink(item: current.text) { Label("שיתוף התמלול", systemImage: "square.and.arrow.up") }
                    .buttonStyle(PrimaryButtonStyle()).disabled(current.text.isEmpty)
            } else {
                Button { Task { await session.start(title: title, keepAudio: keepAudio) } } label: {
                    Label("התחלת הקלטה", systemImage: "mic.fill")
                }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("startRecording")
            }
        case .recording:
            Button { Task { await session.stop() } } label: { Label("סיום ושמירה", systemImage: "stop.fill") }
                .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("stopRecording")
        case .importing:
            Button("עצירת התמלול ושמירת התוצאה החלקית") { session.cancelImport() }
                .buttonStyle(.bordered).controlSize(.large)
        case .preparing, .finishing:
            ProgressView().frame(height: 54)
        }
    }
}
