# Third-party notices

The MIT license at the repository root covers Mila's original app code and documentation. It does not replace the licenses of the model, native dependencies, or sample recording.

| Component | Version/source | License |
|---|---|---|
| Hebrew Zipformer2 66M streaming model | [thewh1teagle/zipformer2-66m-streaming-he](https://huggingface.co/thewh1teagle/zipformer2-66m-streaming-he), revision `6c07526ebfdfc71d12ed4ce6aaebe32774a2613a` | CC BY 4.0 |
| sherpa-onnx | [k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx/tree/v1.13.7), 1.13.7 | Apache-2.0 |
| ONNX Runtime | [microsoft/onnxruntime](https://github.com/microsoft/onnxruntime/tree/v1.28.1), 1.28.1 | MIT and bundled dependency notices |
| kaldi-native-fbank and kaldi-decoder | Included by sherpa-onnx | Apache-2.0 |
| Kiss FFT | Included by sherpa-onnx | BSD-3-Clause |
| Hebrew spoken sample | YaronSh / Lingua Libre / Wikimedia Commons | CC0-1.0 |

The model is redistributed **unchanged**, including its tokens. Its base is k2-fsa/icefall and its training audio comes from ivrit.ai. Model quantization and export were performed upstream, not by this app.

The model card, attribution, complete license texts, ONNX Runtime third-party notices, and sample provenance are preserved in [HebrewVoice/Resources/Licenses](HebrewVoice/Resources/Licenses/). These notices also ship inside the iOS app. Native framework archives in GitHub Releases are unchanged upstream binaries; original download URLs and SHA-256 values are recorded in [assets-lock.json](assets-lock.json).

When redistributing the full source bundle or building a derivative app, retain the applicable third-party attribution and license files along with Mila's MIT notice.
