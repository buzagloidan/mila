---
license: cc-by-4.0
language:
- he
pipeline_tag: automatic-speech-recognition
base_model: Zengwei/icefall-asr-librispeech-streaming-zipformer-2023-05-17
tags:
- speech
- asr
- hebrew
- streaming
- zipformer
- transducer
- icefall
- k2
---

# zipformer2-66m-streaming-he

Streaming Hebrew speech recognition: a 66 M-parameter Zipformer2 transducer, fine-tuned from
[icefall's English streaming Zipformer](https://huggingface.co/Zengwei/icefall-asr-librispeech-streaming-zipformer-2023-05-17)
on [ivrit.ai](https://www.ivrit.ai) Hebrew audio. Decodes in 1.28 s chunks as audio arrives.

## Usage (sherpa-onnx)

```sh
uv pip install sherpa-onnx soundfile numpy huggingface_hub
uv run hf download thewh1teagle/zipformer2-66m-streaming-he --include "sherpa-onnx/*" --local-dir .
```

```python
import numpy as np, sherpa_onnx, soundfile as sf

model_dir = "sherpa-onnx"
recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
    tokens=f"{model_dir}/tokens.txt",
    encoder=f"{model_dir}/encoder.int8.onnx",
    decoder=f"{model_dir}/decoder.int8.onnx",
    joiner=f"{model_dir}/joiner.int8.onnx",
    model_type="zipformer2",
    num_threads=4,
)

audio, sample_rate = sf.read("audio.wav", dtype="float32", always_2d=True)
stream = recognizer.create_stream()
stream.accept_waveform(sample_rate, audio.mean(axis=1))
stream.accept_waveform(sample_rate, np.zeros(int(1.5 * sample_rate), dtype=np.float32))  # flush the last chunk
stream.input_finished()
while recognizer.is_ready(stream):
    recognizer.decode_stream(stream)
print(recognizer.get_result(stream))
```

<details>
<summary><b>PyTorch checkpoint (icefall)</b></summary>

`model.pt` holds an [icefall](https://github.com/k2-fsa/icefall) Zipformer2 `AsrModel` state dict under `"model"`,
the config under `"config"` and the SentencePiece tokenizer under `"tokenizer"` (same as `bpe.model`).

| Setting | Value |
|---|---|
| `num_encoder_layers` | 2,2,3,4,3,2 |
| `downsampling_factor` | 1,2,4,8,4,2 |
| `feedforward_dim` | 512,768,1024,1536,1024,768 |
| `num_heads` | 4,4,4,8,4,4 |
| `encoder_dim` | 192,256,384,512,384,256 |
| `encoder_unmasked_dim` | 192,192,256,256,256,192 |
| `cnn_module_kernel` | 31,31,15,15,15,31 |
| `query_head_dim` / `value_head_dim` / `pos_head_dim` / `pos_dim` | 32 / 12 / 4 / 48 |
| `decoder_dim` / `joiner_dim` / `context_size` | 512 / 512 / 2 |
| `vocab_size` (blank = 0) | 1493 |
| `causal` | true; chunk 64 (1.28 s), left context 256 frames |
| Features | 80-dim fbank, 16 kHz mono |

</details>

## Results

WER (%, lower is better) on ivrit.ai's test sets with the
[leaderboard](https://huggingface.co/spaces/ivrit-ai/hebrew-transcription-leaderboard) normalization.
Other numbers are from the leaderboard; all are offline (full-utterance) except where marked.

| Model | eval-d1 ↓ | eval-whatsapp ↓ |
|---|---|---|
| Soniox | 4.8 | 9.0 |
| **🌊 zipformer2-66m-streaming-he (this model)** | **5.1** | **8.9** |
| ivrit-ai/whisper-large-v3-turbo | 5.3 | 7.1 |
| parakeet-tdt-0.6b-v3-he | 6.1 | 8.8 |
| openai/whisper-large-v3-turbo | 8.4 | 12.8 |
| NVIDIA nemotron-3.5-asr-streaming-0.6b (streaming) | 17.1 | 36.5 |

The sherpa-onnx int8 export scores 5.3 / 8.8.

## Limitations

- English is weak (spelled letter by letter).
- Numbers come out as words or digits inconsistently.

## Fine-tuning & training notes

<details>
<summary><b>Fine-tune this model</b></summary>

Load `model.pt["model"]` into icefall's Zipformer2 `AsrModel` (config above) and continue with icefall's
`finetune.py` or any transducer training loop.

- Audio 16 kHz mono; normalize text like training: strip nikud and bidi marks, geresh/gershayim → `'`/`"`.
- ScaledAdam `base_lr 0.0045`, Eden `lr_batches 7500` / `lr_epochs 2`, ~600 s of audio per step.

</details>

<details>
<summary><b>How it was trained (new language on an English streaming Zipformer)</b></summary>

- **Extend the tokenizer, don't replace it.** A 1,024-piece Hebrew SentencePiece model, trained on ~500 h of
  transcripts, appended after the English 500 pieces (1,493 total).
  New embedding and output rows start at the mean of the old rows (+1% noise).
- **10× LR on decoder + joiner**, so the new rows separate quickly.
- **Let the LR decay.** icefall's `finetune.py` defaults (`lr_batches 100000` / `lr_epochs 100`) keep the LR flat,
  which stalled a new language at ~20% WER; `lr_batches 7500` / `lr_epochs 2` fixed it.
- **Data:** ~20k h of ivrit.ai audio pseudo-labeled with ivrit.ai Whisper models. Drop labels the teacher cut
  off at its token cap (they teach deletions) and `compression_ratio > 2.6` (Whisper loops).
  Rows sharing word 8-grams with the eval sets were removed (no test leakage).
- **Finish:** weight EMA, then the joiner's blank bias lowered by 1.0 (fewer dropped words, baked into the weights).

</details>

## License

CC-BY-4.0. Base model from [k2-fsa/icefall](https://github.com/k2-fsa/icefall) (Apache-2.0).
Trained on audio from [ivrit.ai](https://www.ivrit.ai) ([license](https://www.ivrit.ai/en/the-license/)).
