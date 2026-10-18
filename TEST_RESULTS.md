# Verification · 16 October 2026

Environment: Xcode 26.3 / iOS 26.3 iPhone 17 Pro simulator on Apple silicon. Deployment target: iOS 17.0.

## Builds

- Debug simulator build: passed, no compiler warnings.
- Release `generic/platform=iOS` build (arm64, signing disabled): passed with only the Live Activity extension embedded. App Intents metadata declares all three discoverable actions, their foreground execution, and the transcription action's audio-file input/text output.
- Complete unsigned device `.app`: approximately **107 MiB**, including the unchanged **69 MiB** model folder and linked native runtime. This is the uncompressed installed bundle, not the App Store download size.
- Offline dependency integrity check: all four model files and every extracted framework file match their pinned SHA-256-verified upstream archives.

## Automated app tests: 24 passed, 0 failed

1. **Bundled Hebrew inference:** the actual local model transcribes the bundled YaronSh spoken sample as text containing `שלום`; import reaches 100%. No mocked recognition, microphone access, or network API is used.
2. **Repeated utterances and finalization:** four Hebrew utterances fed in 200 ms chunks survive endpoint resets; final flushing does not extend audio duration. A new stream clears the previous transcript.
3. **Microphone pipeline:** PCM buffers pass through the same queued inference/audio-write path used by the microphone, produce Hebrew text, and create readable AAC/M4A audio with the expected duration.
4. **Stereo downmix:** left/right samples are averaged correctly before recognition.
5. **Persistence/recovery/deletion:** an incomplete Hebrew transcript survives store recreation, completion updates replace it without duplicates, and deletion removes its metadata and retained audio.
6. **Import cancellation:** cancellation returns a partial result with valid processed duration and progress below 100%.
7. **Backpressure:** a buffer exceeding the queue's 20-second limit triggers an overload error and is excluded from inference.
8. **Audio session scheduling:** configuration, activation, and deactivation execute off the main thread, preserving recording → deactivation → playback ordering even when view teardown cannot await.
9. **Audio session errors:** category configuration failures propagate to the caller without attempting activation.
10. **Staged file lifetime:** an audio document survives removal of its external source and recreation of the durable queue.
11. **Automatic document opening:** incoming audio immediately produces a completed Hebrew transcript and recorder navigation, while preserving the external original.
12. **Unsupported input:** a non-audio file is rejected without leaving pending or staging files.
13. **Staging visibility:** incomplete staging directories do not appear as pending audio.
14. **Attachment paths:** invalid metadata cannot resolve a file outside its item directory.
15. **Shared transcription:** pending audio is recognized by the native model, saved with the source identity/title, then removed from the shared inbox.
16. **Interrupted cleanup:** a completed source is not transcribed twice if cleanup was interrupted.
17. **Cancelled shared transcription:** the pending source remains available and the saved transcript is marked partial.
18. **Latest transcript routing:** opening the latest transcript produces the correct navigation request; an empty library returns an error.
19. **Live Activity privacy:** attributes contain only session identity and start time, with no meeting title/transcript.
20. **Shortcut file input:** an IntentFile URL input produces Hebrew text and opens the recording/transcription presentation.
21. **Shortcut data input:** an IntentFile data input also produces a completed Hebrew transcript.

22. **Concurrent documents:** two incoming files both finish automatically, with distinct titles and no stranded queue entries.
23. **Invalid documents:** unsupported files surface an error and preserve the original.
24. **Undecodable audio:** the pending source remains available without an automatic retry loop.

The final 24-test app suite passed in 20.0 seconds, without warnings. The short sample recognition itself took roughly half a second on the host simulator, including loading; this is not an iPhone performance measurement.

Recording and playback now share a dedicated serial queue for AVAudioSession configuration and activation/deactivation, avoiding synchronous hardware session changes on the main thread. The installed iOS SDK supports the synchronous API; wrapping it in awaited background work retains iOS 17 compatibility. Playback ignores activation completions after its view has closed, and late streaming updates cannot replace a final saved result.

## Manual simulator checks

- Home screen: Hebrew text, RTL alignment/navigation, Hebrew labels and local privacy badge visible.
- Recording setup: Hebrew title entry, audio-retention toggle, primary record button, and LTR timer visible.
- Settings: RTL presentation, local storage explanation, model attribution, and license navigation present.
- The in-app bundled sample button produced **שלום.** through the native runtime.
- The native audio share sheet shows **מילה** alongside other audio destinations.
- Two independent-process UI tests exercise the real system share sheet: an M4A file and a WAV file shared to מילה open the app and produce **שלום.** automatically. Each asserts its unique incoming title, the foreground app state, Hebrew recognition and absence of the old save button. The WAV test terminates מילה first to check cold launch. Both passed in 25.8 seconds.
- The old Share Extension target and confirmation UI have been removed. Only the recording Live Activity is embedded.
- The test sender and UI tests are reproducible under `Tools/DocumentProbe`; this app is not part of the product.

Screenshots are in `screenshots/`.

## Not yet validated on physical hardware

Microphone input quality, 1+ hour continuous capture, thermal/battery use, locked-screen background recording, real phone-call/Bluetooth interruptions, denied microphone permission, storage exhaustion, and VoiceOver interaction need a real-device pass. Imported-file processing has only a limited background grace period and saves a partial transcript when cancelled.

The existing development team/signing choices were preserved. Actual WhatsApp sharing, Shortcuts system invocation, and Lock Screen stop/save still need a physical-device pass. Distribution signing, App Store upload, public support/privacy URLs and submission were subsequently completed as recorded below.

## Reproduce

```sh
python3 scripts/bootstrap.py --verify-only
xcodebuild -project HebrewVoice.xcodeproj -scheme HebrewVoice \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
xcodebuild -project HebrewVoice.xcodeproj -scheme HebrewVoice \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

## App Store release verification · 18 October 2026

The signed version 1.0/build 1 IPA was uploaded through asc and processed by Apple as VALID / APP_STORE_ELIGIBLE. Strict store-readiness checks passed with zero errors and zero warnings. Both Hebrew/English localizations contain five processed iPhone and four processed iPad screenshots. Free availability is verified in all 175 current territories. The owner-approved Data Not Collected declaration was published and visually verified. Submission f02491f3-2374-4477-857b-a8f3b40a489a is independently confirmed as WAITING_FOR_REVIEW. Manual release remains enabled. These store checks do not replace the physical-device checks listed above.

## Local review-prompt update · 18 October 2026

The simulator Debug build succeeded without warnings and all **30 tests passed** (0 failed/skipped, 23.2 seconds). The six new review-policy tests cover the three-transcription/two-day threshold, exclusion of partial/blank/future entries, validation of the viewed transcript, persisted attempt state, same-version suppression, the 90-day cooldown across versions, clock rollback, and missing version information. Test defaults use disposable isolated suites, never the app's standard preferences.

Manual simulator verification confirmed the Hebrew Settings link and the actual native StoreKit star-rating dialog after viewing a completed transcript and returning to the library. No prompt appeared on launch with an eligible library. Three explicitly labelled temporary transcript fixtures were used; exactly those files and the two review-attempt preferences were removed after verification. No rating was submitted. Evidence: `screenshots/review-settings.jpg` and `screenshots/native-review-prompt.jpg`. The simulator uses English system UI, so Apple's dialog text appears in English.

Only the last attempt date/version are persisted locally. Eligibility uses the existing local transcript library; no analytics, networking, or new third-party dependency was added. Apple's production display decisions and TestFlight behavior cannot be validated by the development dialog. This source update was subsequently included in version 1.0/build 2; see the resubmission verification below.

## Build 2 resubmission verification · 18 October 2026

The final app configuration passed all 30 simulator tests (0 failed/skipped, 23.8 seconds). A Release archive and distribution export succeeded. Both the app and Live Activity identify as version 1.0/build 2; deep signature checks passed, the approved App Store profiles were embedded, and the bundled model and review-attempt keys were verified in the exported app. Project generation now uses CURRENT_PROJECT_VERSION and MARKETING_VERSION placeholders so regenerated plists retain the intended build/version.

Apple processed build `2685d87f-e462-41a4-af50-169ab061a7d3` as VALID / APP_STORE_ELIGIBLE. Strict submission checks passed with zero errors and zero warnings. Only then was the previous build 1 submission withdrawn. New submission `b82094c5-a3f1-45d9-b599-0bdb26a7b794` was submitted at 2026-10-18T08:47:46.688Z (11:47 Asia/Jerusalem) and independently verified as WAITING_FOR_REVIEW. Manual release after approval remains enabled. The published Data Not Collected declaration was preserved.

## Open-source package verification · 18 October 2026

The source was published under MIT at `buzagloidan/mila`, preserving third-party licenses. The release contains a complete source archive with all four pinned model files and both original runtime archives. A fresh extraction restored and verified every dependency with Python network access disabled. That extracted project built successfully with Xcode 26.3 and passed all **30 simulator tests** (0 failures/skips, 46.2 seconds), using separate DerivedData and no developer signing. This verifies the packaged source, rather than relying on cached products in the maintainer's working directory.

The staged source passed Gitleaks with no secrets detected. Model integrity hashes are explicitly recorded under `sha256` fields. Signing credentials, provisioning profiles, private App Review contacts, local export configuration, account screenshots and operational receipts are ignored and excluded from the public source and full source archive. The public repository and release contain no private user recordings or transcripts.
