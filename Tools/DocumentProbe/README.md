# Test-only system share sender

This separate app and XCUITest suite checks the real document handoff to an already-installed מילה app. It is never embedded in the product.

Install the current HebrewVoice simulator build first. Then:

```sh
xcodegen generate --spec Tools/DocumentProbe/project.yml
xcodebuild -project Tools/DocumentProbe/DocumentProbe.xcodeproj \
  -scheme DocumentProbe -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The sender copies the licensed bundled Hebrew sample and encodes an M4A variant locally. Tests share each format, select מילה, assert app foregrounding and the uniquely named transcription, and wait for `שלום.`. WAV also covers a terminated receiving app. Generated transcripts are test data; use a disposable simulator or remove only `mila-handoff-*` records afterward. No WhatsApp account/network is involved.
