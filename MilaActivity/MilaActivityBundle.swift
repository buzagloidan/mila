import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct MilaActivityBundle: WidgetBundle {
    var body: some Widget { MilaRecordingActivity() }
}

struct MilaRecordingActivity: Widget {
    private let accent = Color(red: 0.78, green: 0.27, blue: 0.13)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("מילה", systemImage: "waveform").font(.headline)
                    Spacer()
                    timer(context).font(.title2.bold())
                }
                HStack {
                    Label(context.state.status == .recording ? "מקליט ומתמלל במכשיר" : "ההקלטה הסתיימה", systemImage: "mic.fill")
                        .font(.subheadline)
                    Spacer()
                    if context.state.status == .recording { stopButton(context) }
                }
            }
            .padding(18).environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "he_IL"))
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(URL(string: "mila://recording"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("מילה", systemImage: "waveform").foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) { timer(context).font(.headline) }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("מקליט במכשיר בלבד").font(.subheadline)
                        Spacer()
                        if context.state.status == .recording { stopButton(context) }
                    }.environment(\.layoutDirection, .rightToLeft)
                }
            } compactLeading: {
                Image(systemName: "mic.fill").foregroundStyle(accent).accessibilityLabel("מילה מקליטה")
            } compactTrailing: {
                timer(context).font(.caption2).frame(maxWidth: 62)
            } minimal: {
                Image(systemName: "mic.fill").foregroundStyle(accent).accessibilityLabel("מילה מקליטה")
            }
            .widgetURL(URL(string: "mila://recording"))
            .keylineTint(accent)
        }
    }

    private func timer(_ context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
            .monospacedDigit().environment(\.layoutDirection, .leftToRight)
            .accessibilityLabel("זמן הקלטה")
    }

    private func stopButton(_ context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        Button(intent: StopRecordingIntent(sessionID: context.attributes.sessionID)) {
            Label("סיום ושמירה", systemImage: "stop.fill").font(.subheadline.bold())
        }.buttonStyle(.borderedProminent).tint(accent)
    }
}
