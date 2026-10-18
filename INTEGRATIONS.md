# Native iOS integrations

All integrations use the bundled on-device model and local library. The app ships one Live Activity extension; the old Share Extension and its save/confirmation screen have been removed.

## Audio sharing: select מילה and transcription starts

1. Share an audio file from WhatsApp, Voice Memos, Files, or another app.
2. Select **מילה** in the iOS audio destination row (possibly under **More**).
3. iOS opens מילה. The transcription screen appears and recognition starts automatically.

There is no **שמירה במילה** button and no instruction to save the recording and manually reopen the app. The app declares supported audio document types and receives the file through SwiftUI `onOpenURL`. This uses the system document-opening route rather than attempting to launch the containing app from a Share Extension.

Availability depends on the sender sharing an actual audio file through a system surface that offers document destinations. Actual WhatsApp behavior and codecs still need a physical-device check. If a sender does not offer מילה, its file can be saved to Files and opened/imported in מילה; the Shortcuts action below is another explicit integration.

Incoming files are staged off the main thread before recognition, with an atomic publish into a durable private queue. An iOS-created Documents/Inbox copy is removed after staging; external source files are never deleted. Audio arriving during a recording/import waits until the session is free. Pending files from earlier versions are picked up automatically when the app opens.

A failed or cancelled import retains its staged source for retry/deletion from the app. Failed sources are not retried in a loop during the current process. A source identity prevents duplicate completed transcripts after interrupted cleanup. Pending entries can be deleted from their context menu. With **שמירת שמע לצד התמלול** off, successful processing keeps only text. The saved-transcript share menu also offers **שיתוף ההקלטה** when retained audio exists.

M4A and WAV were exercised end to end. Other formats depend on AVAudioFile; OGG/Opus decoding is not guaranteed on every supported iOS version. No cloud conversion fallback is used.

## Signing

| Target | Bundle identifier | Purpose |
|---|---|---|
| HebrewVoice | `com.hebrewvoice.mila` | App, bundled model, App Intents, audio documents, library |
| MilaActivity | `com.hebrewvoice.mila.activity` | Lock Screen / Dynamic Island recording activity |

The original app's team and bundle identifiers are preserved in `project.yml`. For your own device/distribution build, choose your own team for both targets, unique app/extension identifiers, and an App Group you control. The original app uses **`group.com.hebrewvoice.mila`** for the durable queue and compatibility with earlier pending shares. Update `HebrewVoice/HebrewVoice.entitlements` and `SharedAudioStorage.groupIdentifier` together when changing it. Provision the group for HebrewVoice and enable automatic signing for the activity extension. No Share Extension identifier/profile is required. Existing queued files belong to the old group.

## Shortcuts

After installing and opening the updated app, find **מילה** under Apps in Shortcuts. There are three discoverable actions:

- **תמלול קובץ שמע** — accepts an audio file, opens מילה, saves a local transcript, and returns the text to the next Shortcut action.
- **התחלת הקלטה** — opens מילה and starts microphone recording/transcription. Microphone permission is required; an already active session is protected from replacement.
- **פתיחת התמלול האחרון** — opens the latest saved transcript. An empty library produces a Hebrew error.

To build a voice-message Shortcut:

1. Create a Shortcut and enable **Show in Share Sheet** in its details.
2. Configure its input to receive **Audio** and/or **Files**.
3. Add מילה's **תמלול קובץ שמע** action, with **Shortcut Input** as its file parameter.
4. Add **Copy to Clipboard**, **Show Result**, or **Create Note**, using the transcription result.
5. Share a WhatsApp audio attachment to this Shortcut.

The action brings the app to the foreground for recognition. Shortcuts execution is still subject to iOS runtime limits; for long lectures open the audio directly in the app. Cancellation saves a partial transcript and does not return it as a completed result.

The recording action can also be assigned through a Shortcut to the Action button on compatible iPhones. This release does not add a separate Control Center widget.

## Recording Live Activity

Start a microphone recording. If Live Activities are enabled for מילה, the app requests a local ActivityKit recording activity showing:

- App name and microphone status.
- Elapsed recording time, rendered by the system timer.
- **סיום ושמירה**, which invokes a `LiveActivityIntent` in the app process and finalizes the recording.

Tapping the activity opens the recording screen through `mila://recording`. The Dynamic Island supports compact, expanded and minimal presentations. No meeting title or transcript text is placed in activity attributes or content. No push server is used. Stale activities from an earlier terminated app process are ended on launch. If Live Activities are unavailable/disabled, ordinary in-app recording still works.

## Verification

30 app tests pass, covering native inference, automatic document import, external-source preservation, concurrent incoming files, failed-file retry behavior, durable staging, cancellation, deduplication, Shortcuts inputs, recording infrastructure and local review eligibility.

A separate test-only sender under `Tools/DocumentProbe` exercises the actual iOS share sheet. Both UI tests pass: **M4A → select מילה → app opens → uniquely named transcript → שלום.**, and the same WAV flow after explicitly terminating מילה. No save button is present. The sender is not bundled with the product.

The unsigned arm64 iPhone release build embeds only `MilaActivity.appex`. A real WhatsApp voice-message share, system Shortcuts invocation, Lock Screen stop/save, and signing/provisioning remain device checks. Simulator tests cannot verify those phone-specific contexts.
