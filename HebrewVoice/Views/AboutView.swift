import SwiftUI
import AppIntents

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("keepAudio") private var keepAudio = true
    @State private var runningDemo = false
    @State private var demoText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("מילה").font(.largeTitle.bold())
                        Text("תמלול בעברית. קרוב אליך.").font(.headline)
                        LocalBadge()
                    }.padding(.vertical, 10)
                }
                Section("ההקלטות שלך") {
                    Toggle("שמירת שמע לצד התמלול", isOn: $keepAudio)
                    Text("כשאפשרות זו כבויה, הקלטות חדשות נשמרות כטקסט בלבד. קובצי שמע שכבר נשמרו נשארים עד למחיקת התמלול.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("פרטיות שעובדת גם בלי אינטרנט") {
                    Label("המודל כלול באפליקציה — אין הורדה בהפעלה הראשונה.", systemImage: "shippingbox")
                    Label("השמע והתמלולים מעובדים ונשמרים במכשיר.", systemImage: "iphone")
                    Label("ללא חשבון, שרת תמלול או כלי מעקב.", systemImage: "lock.shield")
                    Text("התמלולים וקובצי השמע אינם נכללים בגיבוי iCloud של האפליקציה. מחיקת האפליקציה מוחקת אותם. ייצוא או שיתוף מעבירים רק את התוכן שבחרתם ליעד שתבחרו.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("דירוג האפליקציה") {
                    Link(destination: ReviewPromptPolicy.reviewURL) {
                        Label("דירוג מילה ב-App Store", systemImage: "star")
                    }
                    .accessibilityIdentifier("rateMila")
                }
                Section("בדיקת תמלול מקומית") {
                    Button {
                        Task { await runDemo() }
                    } label: {
                        HStack {
                            Label("תמלול קטע הדוגמה הכלול", systemImage: "waveform")
                            Spacer()
                            if runningDemo { ProgressView() }
                        }
                    }.disabled(runningDemo)
                    Text("בדיקה קצרה של המודל ללא מיקרופון או אינטרנט. התוצאה אינה נשמרת בספרייה.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let demoText { Text(demoText).textSelection(.enabled) }
                }
                Section("מילה בכל האייפון") {
                    Label("משתפים קובץ שמע ובוחרים מילה. האפליקציה נפתחת והתמלול מתחיל אוטומטית, ללא שלב שמירה נוסף.", systemImage: "square.and.arrow.down")
                    Text("בקיצורי דרך אפשר לתמלל קובץ ולהשתמש בטקסט שמוחזר, להתחיל הקלטה או לפתוח את התמלול האחרון. פעולות אלו פותחות את מילה.")
                        .font(.subheadline)
                    ShortcutsLink()
                    Text("בזמן הקלטה ניתן לראות את משך ההקלטה ולסיים אותה ממסך הנעילה ומה-Dynamic Island, כשפעילויות בזמן אמת מופעלות במכשיר.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("עותק של קובץ השמע נשמר במכשיר עד להשלמת התמלול. אם התמלול נכשל או בוטל, אפשר לנסות שוב או למחוק את העותק מהתיבה. קובץ המקור באפליקציה שממנה שיתפתם אינו נמחק.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("המודל והקרדיט") {
                    Text("Zipformer2 · 66M · INT8").environment(\.layoutDirection, .leftToRight)
                    Text("המודל העברי נוצר בידי thewh1teagle, על בסיס icefall של k2-fsa ואודיו של ivrit.ai. ההרצה המקומית מתבצעת באמצעות sherpa-onnx ו-ONNX Runtime.")
                    Link("עמוד המודל · CC BY 4.0", destination: URL(string: "https://huggingface.co/thewh1teagle/zipformer2-66m-streaming-he")!)
                    Text("קובצי המודל נכללו ללא שינוי. האפליקציה אינה מוסיפה סימני פיסוק או מזהה דוברים. מילים באנגלית ומספרים עשויים להיות פחות מדויקים.")
                        .font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("רישיונות ורכיבי קוד פתוח") { LicensesView() }
                }
                Section {
                    Text("גרסה 1.0 · מיועד ל-iOS 17 ומעלה").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("הגדרות ופרטיות").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("סגירה") { dismiss() } } }
            .interactiveDismissDisabled(runningDemo)
        }
    }

    private func runDemo() async {
        runningDemo = true
        defer { runningDemo = false }
        do {
            guard let url = Bundle.main.url(forResource: "sample-hebrew", withExtension: "wav") else { throw VoiceError.invalidAudio }
            let worker = TranscriptionWorker()
            let result = try await worker.importFile(url, copyTo: nil) { _ in }
            demoText = result.text.isEmpty ? "לא זוהה דיבור בדוגמה." : result.text
        } catch { demoText = error.localizedDescription }
    }
}

private struct LicensesView: View {
    private var files: [URL] {
        guard let root = Bundle.main.url(forResource: "Licenses", withExtension: nil) else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    var body: some View {
        List(files, id: \.lastPathComponent) { file in
            NavigationLink(file.lastPathComponent) {
                ScrollView {
                    Text((try? String(contentsOf: file, encoding: .utf8)) ?? "לא ניתן לקרוא את הקובץ.")
                        .font(.caption.monospaced()).textSelection(.enabled).padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .environment(\.layoutDirection, .leftToRight)
                .navigationTitle(file.lastPathComponent)
            }
        }.navigationTitle("רישיונות")
    }
}
