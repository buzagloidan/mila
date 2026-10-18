import SwiftUI

@main
struct HebrewVoiceApp: App {
    private let services = AppServices.shared

    var body: some Scene {
        WindowGroup {
            HomeView(services: services)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .tint(Theme.accent)
                .onOpenURL { url in
                    if url.isFileURL {
                        Task { await services.receiveAudioDocument(url) }
                    } else if url.scheme == "mila", url.host == "recording" { services.navigation.show(.recorder) }
                }
        }
    }
}
