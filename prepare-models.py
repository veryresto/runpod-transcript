import gc
import os
import time

os.environ.setdefault("TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD", "1")

import torch
import whisperx
from whisperx.diarize import DiarizationPipeline


DEVICE = "cuda"
LANGUAGE = "id"
WHISPER_MODEL = "large-v3"
DIARIZATION_MODEL = "pyannote/speaker-diarization-community-1"


def timed(label, loader):
    started = time.monotonic()
    value = loader()
    elapsed = time.monotonic() - started
    print(f"TIMING model_{label}_seconds={elapsed:.1f}", flush=True)
    return value


if not torch.cuda.is_available():
    raise SystemExit("ERROR: CUDA is unavailable")

hf_token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")
if not hf_token:
    raise SystemExit("ERROR: Set HF_TOKEN before preparing models")

total_started = time.monotonic()

asr_model = timed(
    "whisper_vad",
    lambda: whisperx.load_model(
        WHISPER_MODEL,
        device=DEVICE,
        compute_type="float16",
        language=LANGUAGE,
    ),
)
del asr_model
gc.collect()
torch.cuda.empty_cache()

align_model, _ = timed(
    "alignment",
    lambda: whisperx.load_align_model(language_code=LANGUAGE, device=DEVICE),
)
del align_model
gc.collect()
torch.cuda.empty_cache()

diarization_model = timed(
    "diarization",
    lambda: DiarizationPipeline(
        model_name=DIARIZATION_MODEL,
        token=hf_token,
        device=DEVICE,
    ),
)
del diarization_model
gc.collect()
torch.cuda.empty_cache()

print(f"TIMING model_preparation_total_seconds={time.monotonic() - total_started:.1f}")
