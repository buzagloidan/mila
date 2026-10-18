import SwiftUI
import StoreKit
import UniformTypeIdentifiers

struct HomeView: View {
    let services: AppServices
    private var store: TranscriptStore { services.store }
    private var session: RecordingSession { services.session }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @State private var reviewPolicy = ReviewPromptPolicy()
    @State private var reviewCandidate: UUID?
    @FocusState private var searchFocused: Bool
    @State private var path: [UUID] = []
    @State private var sheet: HomeSheet?
    @State private var showImporter = false
    @State private var search = ""
    @State private var deleteCandidate: Transcript?
    @State private var sharedDeleteCandidate: SharedAudioItem?
    @State private var error: String?
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize = 43
    @AppStorage("keepAudio") private var keepAudio = true

    private enum HomeSheet: String, Identifiable { case recorder, about; var id: String { rawValue } }
    private struct ReviewContext: Equatable {
        let candidate: UUID?
        let libraryReady: Bool
    }
    private var reviewContext: ReviewContext {
        ReviewContext(candidate: reviewCandidate, libraryReady:
            path.isEmpty && sheet == nil && scenePhase == .active && !session.isBusy &&
            !showImporter && !searchFocused && search.isEmpty && deleteCandidate == nil &&
            sharedDeleteCandidate == nil && error == nil && store.errorMessage == nil &&
            session.errorMessage == nil && services.inbox.errorMessage == nil &&
            services.inbox.items.isEmpty && services.navigation.request == nil)
    }
    private var filtered: [Transcript] {
        store.transcripts.filter { search.isEmpty || $0.title.localizedStandardContains(search) || $0.text.localizedStandardContains(search) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            libraryContent
        }
        .onChange(of: path) { previous, current in
            if current.isEmpty, let viewed = previous.last { reviewCandidate = viewed }
        }
        .onChange(of: sheet) { previous, current in
            if previous == .recorder && current == nil { reviewCandidate = session.current?.id }
        }
        .task(id: reviewContext) { await requestReviewIfAppropriate() }
    }

    private var libraryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                intro
                actions
                sharedInbox
                library
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("מילה")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { id in
            if let transcript = store.transcripts.first(where: { $0.id == id }) {
                TranscriptDetailView(transcript: transcript, store: store)
            } else { ContentUnavailableView("התמלול אינו זמין", systemImage: "doc.text") }
        }
        .task {
            handleNavigation()
            await services.processPendingAudio()
            if !session.isBusy { await RecordingLiveActivity.endStaleActivity() }
        }
        .onChange(of: services.navigation.request?.id) { _, _ in handleNavigation() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await services.processPendingAudio() } }
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .idle { Task { await services.processPendingAudio() } }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { sheet = .about } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("הגדרות ופרטיות")
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .recorder: RecorderView(session: session)
            case .about: AboutView()
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                session.clearPresentation()
                sheet = .recorder
                Task { await session.importAudio(url, keepAudio: keepAudio) }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .confirmationDialog("למחוק את התמלול ואת ההקלטה שלו?", isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }), titleVisibility: .visible) {
            Button("מחיקה מהמכשיר", role: .destructive) {
                if let candidate = deleteCandidate {
                    do { try store.delete(candidate) } catch { self.error = error.localizedDescription }
                }
                deleteCandidate = nil
            }
        }
        .confirmationDialog("למחוק את ההקלטה מתיבת השמע המשותף?", isPresented: Binding(get: { sharedDeleteCandidate != nil }, set: { if !$0 { sharedDeleteCandidate = nil } }), titleVisibility: .visible) {
            Button("מחיקה מהמכשיר", role: .destructive) {
                if let item = sharedDeleteCandidate {
                    Task { do { try await services.inbox.remove(item) } catch { self.error = error.localizedDescription } }
                }
                sharedDeleteCandidate = nil
            }
        }
        .alert("לא ניתן להשלים את הפעולה", isPresented: Binding(get: { error != nil || store.errorMessage != nil }, set: { if !$0 { error = nil; store.errorMessage = nil } })) {
            Button("אישור", role: .cancel) { error = nil; store.errorMessage = nil }
        } message: { Text(error ?? store.errorMessage ?? "") }
    }

    @MainActor
    private func requestReviewIfAppropriate() async {
        guard let candidate = reviewCandidate else { return }
        guard reviewContext.libraryReady else { reviewCandidate = nil; return }
        do { try await Task.sleep(for: .seconds(2)) }
        catch { return }
        guard !Task.isCancelled, reviewContext.libraryReady, reviewCandidate == candidate else { return }
        reviewCandidate = nil
        // Native share sheets and system presentations can exist outside our SwiftUI state.
        let activeScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let hasPresentation = activeScenes.flatMap(\.windows).contains {
            $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil
        }
        guard !hasPresentation else { return }
        if reviewPolicy.claimRequest(afterViewing: candidate, transcripts: store.transcripts) {
            requestReview()
        }
    }

    private func handleNavigation() {
        guard let request = services.navigation.request else { return }
        switch request.destination {
        case .recorder: sheet = .recorder
        case .transcript(let id): sheet = nil; path = [id]
        }
        services.navigation.consume(request.id)
    }

    @ViewBuilder private var sharedInbox: some View {
        if !services.inbox.items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("שיתפו איתך מילים").font(.title2.bold())
                    Spacer()
                    Text(services.inbox.items.count == 1 ? "הקלטה אחת" : "\(services.inbox.items.count) הקלטות").font(.caption).foregroundStyle(.secondary)
                }
                Text("התמלול מתחיל אוטומטית כשהאפליקציה פנויה. אם תמלול נעצר, אפשר לנסות שוב כאן.")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(services.inbox.items) { item in
                    HStack(spacing: 14) {
                        Image(systemName: "tray.and.arrow.down").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(.headline).lineLimit(2)
                            Text(item.createdAt, format: .dateTime.day().month(.abbreviated)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button("תמלול") {
                            Task {
                                do { try await services.transcribeShared(item) }
                                catch { self.error = error.localizedDescription }
                            }
                        }.buttonStyle(.bordered).disabled(session.isBusy)
                            .accessibilityLabel("תמלול \(item.title)")
                    }.padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                        .contextMenu {
                            Button("מחיקה", role: .destructive) { sharedDeleteCandidate = item }.disabled(session.isBusy)
                        }
                }
            }.accessibilityIdentifier("sharedAudioInbox")
        }
        if let message = services.inbox.errorMessage {
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.circle").font(.footnote)
                Button("ניסיון נוסף") { Task { await services.inbox.refresh() } }.font(.footnote.bold())
            }.foregroundStyle(Theme.accent)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("פחות לכתוב. יותר להקשיב.")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Text("כל מילה.\nנשארת איתך.")
                        .font(.system(size: headingSize, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                WaveformMark().padding(.top, 38)
            }
            Text("פגישות, הרצאות ורעיונות — הופכים לטקסט בעברית, גם בלי אינטרנט.")
                .font(.body).foregroundStyle(.secondary).lineSpacing(5)
            LocalBadge()
        }.padding(.top, 14)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                session.clearPresentation()
                sheet = .recorder
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "mic.fill").font(.title2)
                        .frame(width: 52, height: 56).background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("הקלטה חדשה").font(.title3.bold())
                        Text("להקשיב עכשיו. לקרוא אחר כך.").font(.subheadline).opacity(0.85)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.left").font(.title3)
                }
                .foregroundStyle(.white).padding(20)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 26))
            }.buttonStyle(.plain).accessibilityIdentifier("newRecording")
            Button { showImporter = true } label: {
                HStack(spacing: 16) {
                    Image(systemName: "waveform.badge.plus").font(.title2).frame(width: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ייבוא קובץ שמע").font(.headline)
                        Text("יש כבר הקלטה? נתחיל ממנה.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(.caption.bold())
                }
                .foregroundStyle(Theme.ink).padding(20)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
            }.buttonStyle(.plain).accessibilityIdentifier("importAudio")
        }
        .disabled(session.isBusy)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("המילים שלך").font(.title2.bold())
                Spacer()
                Text(store.transcripts.count == 1 ? "תמלול אחד" : "\(store.transcripts.count) תמלולים").font(.footnote).foregroundStyle(.secondary)
            }
            if !store.transcripts.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("חיפוש בתמלולים", text: $search).submitLabel(.search).focused($searchFocused)
                }.padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            }
            if store.transcripts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.alignright").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.accent)
                    Text("כאן מתחיל מקום למילים").font(.headline)
                    Text("התמלולים שלך יישמרו כאן,\nויהיו זמינים גם במצב טיסה.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 32)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { transcript in
                        NavigationLink(value: transcript.id) { TranscriptRow(transcript: transcript) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            ShareLink(item: transcript.text) { Label("שיתוף טקסט", systemImage: "square.and.arrow.up") }
                            Button(role: .destructive) { deleteCandidate = transcript } label: { Label("מחיקה", systemImage: "trash") }
                        }
                    }
                }
            }
        }
    }
}

private struct TranscriptRow: View {
    let transcript: Transcript
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.text").font(.title3).foregroundStyle(Theme.accent)
                .frame(width: 44, height: 52).background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 7) {
                Text(transcript.title).font(.headline).lineLimit(1)
                HStack(spacing: 8) {
                    Text(transcript.createdAt, format: .dateTime.day().month(.abbreviated))
                    Text("·")
                    Text(transcript.duration.clockText).monospacedDigit().environment(\.layoutDirection, .leftToRight)
                    if !transcript.isComplete { Text("· חלקי") }
                }.font(.caption).foregroundStyle(.secondary)
                if !transcript.text.isEmpty { Text(transcript.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
    }
}
