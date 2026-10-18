# Bundled model and native runtime

Hebrew model: **zipformer2-66m-streaming-he**, by **thewh1teagle**.
Source: https://huggingface.co/thewh1teagle/zipformer2-66m-streaming-he
Revision: 6c07526ebfdfc71d12ed4ce6aaebe32774a2613a
License: Creative Commons Attribution 4.0 International.
License URL: https://creativecommons.org/licenses/by/4.0/
The four model files are redistributed unchanged. Base: k2-fsa/icefall (Apache-2.0). Training audio: ivrit.ai. See MODEL-CARD.md and CC-BY-4.0.txt.

sherpa-onnx 1.13.7: https://github.com/k2-fsa/sherpa-onnx/tree/v1.13.7
License: Apache-2.0. See SHERPA-LICENSE.txt and bundled dependency notices.
Unmodified native iOS static XCFramework from the official xcframework release, using the matching ONNX Runtime 1.28.1 binary specified by upstream's Package.swift.

ONNX Runtime 1.28.1: https://github.com/microsoft/onnxruntime/tree/v1.28.1
MIT. See ONNX-RUNTIME-LICENSE.txt and ONNX-RUNTIME-THIRD-PARTY-NOTICES.txt (from the matching v1.28.1 source tag).
Binary distribution: https://github.com/csukuangfj/onnxruntime-libs/releases/tag/v1.28.1

kaldi-native-fbank: https://github.com/csukuangfj/kaldi-native-fbank (Apache-2.0)
kaldi-decoder: https://github.com/k2-fsa/kaldi-decoder (Apache-2.0)
Kiss FFT: https://github.com/mborgerding/kissfft (BSD-3-Clause)
See accompanying license texts. The ONNX Runtime third-party notice contains additional native dependency licenses.

Demo recording: YaronSh, Lingua Libre / Wikimedia Commons. CC0-1.0. Resampled and padded with silence. See DEMO-SOURCE.json for the original URL, license, and source checksum.
