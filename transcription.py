import io
import json
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

os.environ.setdefault("TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD", "1")

import torch
import whisperx
from whisperx.diarize import DiarizationPipeline


DEVICE = "cuda"
COMPUTE_TYPE = "float16"
BATCH_SIZE = 4
LANGUAGE = "id"
WHISPER_MODEL = "large-v3"
DIARIZATION_MODEL = "pyannote/speaker-diarization-community-1"

Progress = Callable[[str], None]


@dataclass
class ModelBundle:
    asr: Any
    align: Any
    align_metadata: Any
    diarization: Any
    load_seconds: dict[str, float]


def _timed_load(label: str, loader: Callable[[], Any], progress: Progress):
    started = time.monotonic()
    value = loader()
    elapsed = time.monotonic() - started
    progress(f"TIMING model_{label}_seconds={elapsed:.1f}")
    return value, elapsed


def load_models(progress: Progress = print) -> ModelBundle:
    if not torch.cuda.is_available():
        raise RuntimeError("CUDA is unavailable; transcription requires a GPU")

    hf_token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")
    if not hf_token:
        raise RuntimeError("HF_TOKEN is required for speaker diarization")

    progress(f"Loading {WHISPER_MODEL}, Indonesian alignment, and diarization models")
    asr, asr_seconds = _timed_load(
        "whisper_vad",
        lambda: whisperx.load_model(
            WHISPER_MODEL,
            device=DEVICE,
            compute_type=COMPUTE_TYPE,
            language=LANGUAGE,
        ),
        progress,
    )
    (align, align_metadata), align_seconds = _timed_load(
        "alignment",
        lambda: whisperx.load_align_model(language_code=LANGUAGE, device=DEVICE),
        progress,
    )
    diarization, diarization_seconds = _timed_load(
        "diarization",
        lambda: DiarizationPipeline(
            model_name=DIARIZATION_MODEL,
            token=hf_token,
            device=DEVICE,
        ),
        progress,
    )

    return ModelBundle(
        asr=asr,
        align=align,
        align_metadata=align_metadata,
        diarization=diarization,
        load_seconds={
            "whisper_vad": round(asr_seconds, 3),
            "alignment": round(align_seconds, 3),
            "diarization": round(diarization_seconds, 3),
            "total": round(asr_seconds + align_seconds + diarization_seconds, 3),
        },
    )


def _format_transcript(segments: list[dict[str, Any]]) -> str:
    output = io.StringIO()
    current_speaker = None
    for segment in segments:
        speaker = segment.get("speaker", "UNKNOWN")
        text = segment.get("text", "").strip()
        if not text:
            continue

        timestamp = segment.get("start", 0)
        minutes = int(timestamp // 60)
        seconds = int(timestamp % 60)
        if speaker != current_speaker:
            if current_speaker is not None:
                output.write("\n")
            output.write(f"[{minutes:02d}:{seconds:02d}] {speaker}\n")
            current_speaker = speaker
        output.write(text + "\n")
    return output.getvalue()


def transcribe_file(
    input_file: str | Path,
    *,
    models: ModelBundle | None = None,
    output_dir: str | Path | None = None,
    min_speakers: int | None = None,
    max_speakers: int | None = None,
    progress: Progress = print,
) -> dict[str, Any]:
    source = Path(input_file).expanduser().resolve()
    if not source.is_file():
        raise FileNotFoundError(f"Recording not found: {source}")
    if min_speakers is not None and min_speakers < 1:
        raise ValueError("min_speakers must be at least 1")
    if max_speakers is not None and max_speakers < 1:
        raise ValueError("max_speakers must be at least 1")
    if min_speakers and max_speakers and min_speakers > max_speakers:
        raise ValueError("min_speakers cannot exceed max_speakers")

    bundle = models or load_models(progress)
    destination = Path(output_dir).expanduser().resolve() if output_dir else source.parent
    destination.mkdir(parents=True, exist_ok=True)
    base_name = source.stem
    aligned_file = destination / f"{base_name}_aligned.json"
    diarization_file = destination / f"{base_name}_diarization.csv"
    final_json_file = destination / f"{base_name}_final.json"
    transcript_file = destination / f"{base_name}_transcript.txt"

    timings: dict[str, float] = {}
    total_started = time.monotonic()

    started = time.monotonic()
    audio = whisperx.load_audio(str(source))
    result = bundle.asr.transcribe(audio, batch_size=BATCH_SIZE, language=LANGUAGE)
    timings["transcription"] = round(time.monotonic() - started, 3)
    progress(f"TIMING transcription_seconds={timings['transcription']:.1f}")

    started = time.monotonic()
    result = whisperx.align(
        result["segments"],
        bundle.align,
        bundle.align_metadata,
        audio,
        DEVICE,
        return_char_alignments=False,
    )
    with aligned_file.open("w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
    timings["alignment"] = round(time.monotonic() - started, 3)
    progress(f"TIMING alignment_seconds={timings['alignment']:.1f}")

    started = time.monotonic()
    diarization_options = {}
    if min_speakers is not None:
        diarization_options["min_speakers"] = min_speakers
    if max_speakers is not None:
        diarization_options["max_speakers"] = max_speakers
    diarization = bundle.diarization(audio, **diarization_options)
    diarization.to_csv(diarization_file, index=False)
    timings["diarization"] = round(time.monotonic() - started, 3)
    progress(f"TIMING diarization_seconds={timings['diarization']:.1f}")

    started = time.monotonic()
    result = whisperx.assign_word_speakers(diarization, result)
    with final_json_file.open("w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
    transcript = _format_transcript(result["segments"])
    transcript_file.write_text(transcript, encoding="utf-8")
    timings["speaker_assignment_and_output"] = round(time.monotonic() - started, 3)
    timings["total"] = round(time.monotonic() - total_started, 3)
    progress(f"TIMING output_seconds={timings['speaker_assignment_and_output']:.1f}")
    progress(f"TIMING processing_total_seconds={timings['total']:.1f}")

    return {
        "transcript": transcript,
        "segment_count": len(result["segments"]),
        "timings": timings,
        "files": {
            "aligned": str(aligned_file),
            "diarization": str(diarization_file),
            "final_json": str(final_json_file),
            "transcript": str(transcript_file),
        },
    }
