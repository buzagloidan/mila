import SwiftUI

enum Theme {
    static let accent = Color(red: 0.78, green: 0.27, blue: 0.13)
    static let ink = Color.primary
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let green = Color(red: 0.20, green: 0.48, blue: 0.36)
}

struct LocalBadge: View {
    var body: some View {
        Label {
            Text("במכשיר שלך. בעברית שלך.")
        } icon: {
            Image(systemName: "lock.shield.fill")
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Theme.green)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.green.opacity(0.09), in: Capsule())
    }
}

struct WaveformMark: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array([16.0, 30, 45, 24, 52, 36, 18].enumerated()), id: \.offset) { _, height in
                Capsule().frame(width: 5, height: height)
            }
        }
        .foregroundStyle(Theme.accent)
        .accessibilityHidden(true)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(.white)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 19))
    }
}
