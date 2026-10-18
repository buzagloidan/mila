# Contributing to Mila

Mila is a native Swift/SwiftUI app for offline Hebrew transcription on iOS 17 and later.

1. Fork and clone this repository, then run `python3 scripts/bootstrap.py` to restore checksum-pinned model/runtime assets.
2. Open `HebrewVoice.xcodeproj`, select the HebrewVoice scheme, and run an iPhone simulator. Use a current Xcode with the iOS SDK and a simulator runtime installed.
3. If changing target membership or build settings, edit `project.yml`, run `xcodegen generate`, and include the generated project changes.
4. Run the app tests with `xcodebuild -project HebrewVoice.xcodeproj -scheme HebrewVoice -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test`. Substitute an installed simulator name.

Keep Hebrew text and right-to-left navigation usable, preserve on-device inference, and keep audio/inference work off the main thread. Do not add telemetry, remote transcription, or dependency downloads to the running app. Dependency setup is a developer step; the distributed app must bundle its resources.

Use synthetic or explicitly licensed audio for tests. Do not put personal recordings, transcripts, signing files, API keys, or App Review contact details in commits or public issues. For security or privacy issues, contact the public support email in [SUPPORT.md](SUPPORT.md).

Explain the behavior changed and relevant verification in pull requests. Contributions are provided under the repository's MIT license; third-party components retain their own licenses.
