# Breeze-ASR-25 模型技術參考

> 調查日期：2026-03-03
> 來源：https://huggingface.co/MediaTek-Research/Breeze-ASR-25

## 概述

Breeze-ASR-25 是聯發科研究院 (MediaTek Research) 發布的 ASR 語音辨識模型，基於 OpenAI Whisper-large-v2 微調，專為**台灣華語**與**中英夾雜 (code-switching)** 場景優化。

- 參數量：2B (BF16)
- 授權：Apache 2.0
- 論文：[A Self-Refining Framework for Enhancing ASR Using TTS-Synthesized Data](https://arxiv.org/abs/2506.11130) (arXiv:2506.11130)
- GitHub：https://github.com/mtkresearch/Breeze-ASR-25

## 核心特色

1. **原生繁體中文輸出** — 不需要 opencc s2t 後處理
2. **中英夾雜辨識極強** — 在 CSZS-zh-en 基準上 WER 從 29.49% 降到 13.01%（改善 55.88%）
3. **時間對齊增強** — 適合自動字幕/caption 生成，支援 `return_timestamps=True`
4. **全合成中文訓練資料** — 使用 BreezyVoice TTS + FineWeb2 文本生成 10,000 小時合成語音

## 效能基準

### 短音檔 (WER ↓)

| 資料集 | 語言 | Whisper-large-v2 | Breeze-ASR-25 | 改善幅度 |
|--------|------|------------------|---------------|----------|
| ASCEND-OVERALL | 中英混合 | 21.14 | **17.74** | -16.08% |
| ASCEND-EN | 英文 | 27.36 | **26.64** | -2.63% |
| ASCEND-ZH | 中文 | 17.49 | **16.04** | -8.29% |
| ASCEND-MIX | 混合段落 | 21.01 | **16.38** | -22.01% |
| CommonVoice16-zh-TW | 台灣華語 | 9.84 | **7.97** | -19.00% |
| CSZS-zh-en | 中英夾雜 | 29.49 | **13.01** | -55.88% |

### 長音檔 (WER ↓)

| 資料集 | 語言 | Whisper-large-v2 | Breeze-ASR-25 | 改善幅度 |
|--------|------|------------------|---------------|----------|
| ML-lecture-2021-long | 中文 | 6.13 | **4.98** | -18.76% |
| Formosa-Go | 中文 | 15.03 | **13.61** | -9.44% |
| Formosa-Show | 中文 | 29.18 | **27.58** | -5.48% |

## 訓練資料

全部來自開源授權資料集：

| 資料集 | 類型 | 語言 | 時數 | 授權 |
|--------|------|------|------|------|
| ODC Synth | 合成語音 | 中文 | 10,000 | ODC + Apache 2.0 |
| CommonVoice17-EN | 真人錄音 | 英文 | 1,738 | CC0 |
| NTUML2021 | 真人錄音 | 中英夾雜 | 11 | MIT |

注意：所有中文資料皆為合成語音，由 [BreezyVoice](https://huggingface.co/MediaTek-Research/BreezyVoice) TTS 模型搭配 [FineWeb2](https://huggingface.co/datasets/HuggingFaceFW/fineweb-2) 文本生成。

## 模型格式與取得方式

| 格式 | 模型 ID | 大小 | 用途 |
|------|---------|------|------|
| PyTorch (原始) | `MediaTek-Research/Breeze-ASR-25` | ~4 GB | HuggingFace Transformers |
| MLX (已轉換) | `eoleedi/Breeze-ASR-25-mlx` | 3.08 GB | mlx-whisper (Apple Silicon) |

MLX 版本由社群成員 eoleedi 轉換，MIT 授權，可直接用於 `mlx-whisper` 推理。

## 使用方式

### PyTorch (HuggingFace Transformers)

```python
import torchaudio
import torch
from transformers import WhisperProcessor, WhisperForConditionalGeneration
from transformers import AutomaticSpeechRecognitionPipeline

processor = WhisperProcessor.from_pretrained("MediaTek-Research/Breeze-ASR-25")
model = WhisperForConditionalGeneration.from_pretrained(
    "MediaTek-Research/Breeze-ASR-25"
).to("cuda").eval()

asr_pipeline = AutomaticSpeechRecognitionPipeline(
    model=model,
    tokenizer=processor.tokenizer,
    feature_extractor=processor.feature_extractor,
    chunk_length_s=0,
)

waveform, sr = torchaudio.load("audio.wav")
if sr != 16_000:
    waveform = torchaudio.transforms.Resample(sr, 16_000)(waveform)
waveform = waveform.mean(dim=0).squeeze().numpy()

output = asr_pipeline(waveform, return_timestamps=True)
print(output["text"])
```

### MLX (Apple Silicon)

```bash
pip install mlx-whisper
mlx_whisper "audio.wav" --model "eoleedi/Breeze-ASR-25-mlx"
```

Python API：

```python
import mlx_whisper

result = mlx_whisper.transcribe(
    "audio.wav",
    path_or_hf_repo="eoleedi/Breeze-ASR-25-mlx",
    language="zh",           # 可省略，auto-detect 也可
    word_timestamps=False,
)
print(result["text"])
```

## PyTorch → MLX 自行轉換

如需自行轉換（例如自訂量化位元數）：

```bash
git clone https://github.com/ml-explore/mlx-examples.git
cd mlx-examples/whisper

# FP16 轉換
python convert.py \
    --torch-name-or-path MediaTek-Research/Breeze-ASR-25 \
    --mlx-path ./breeze-asr-25-mlx

# 4-bit 量化（更小、更快）
python convert.py \
    --torch-name-or-path MediaTek-Research/Breeze-ASR-25 \
    -q --q_bits 4 \
    --mlx-path ./breeze-asr-25-mlx-4bit
```

硬體需求：轉換過程需約 8 GB 記憶體（載入 PyTorch 權重 + 寫出 MLX 權重），M1 以上 Mac 皆可勝任。

## 與其他 ASR 引擎比較

| 特性 | Whisper-large-v3 | Qwen3 ASR (mlx-audio) | Breeze-ASR-25 |
|------|-------------------|----------------------|---------------|
| 基底架構 | Whisper | Qwen2-Audio | Whisper-large-v2 |
| 參數量 | 1.5B | 0.6B / 1.7B | 2B |
| 繁中輸出 | 簡體（需 s2t） | 簡體（需 s2t） | **原生繁體** |
| 中英夾雜 | 普通 | 普通 | **極強** |
| MLX 原生 | mlx-whisper | mlx-audio | mlx-whisper |
| Apple Silicon 最佳化 | 好 | 好 (MLX 原生) | 好 (MLX 轉換) |
| 台灣華語特化 | 無 | 無 | **有** |

## 適用場景

- 台灣使用者的日常語音輸入（大量中英夾雜）
- 會議/課程逐字稿（長音檔支援良好）
- 自動字幕生成（時間戳對齊增強）
- 任何需要高品質繁中 ASR 且在 Apple Silicon 上運行的應用

## 引用

```bibtex
@article{chou2025selfrefiningframeworkenhancingasr,
    title   = {A Self-Refining Framework for Enhancing ASR Using TTS-Synthesized Data},
    author  = {Cheng Kang Chou and Chan-Jan Hsu and Ho-Lam Chung and
               Liang-Hsuan Tseng and Hsi-Chun Cheng and Yu-Kuan Fu and
               Kuan Po Huang and Hung-Yi Lee},
    journal = {arXiv preprint arXiv:2506.11130},
    year    = {2025},
}
```
