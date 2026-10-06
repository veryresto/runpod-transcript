import json
import os
import sys
import time
from pathlib import Path

# Some WhisperX/Pyannote checkpoints contain trusted OmegaConf objects. PyTorch
# 2.6+ otherwise defaults torch.load to weights_only=True and may reject them.
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


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


if len(sys.argv) != 2:
    fail(f"Usage: {Path(sys.argv[0]).name} MEETING_FILE")

input_file = Path(sys.argv[1]).expanduser().resolve()
if not input_file.is_file():
    fail(f"File not found: {input_file}")

hf_token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")
if not hf_token:
    fail("Set HF_TOKEN to a Hugging Face read token before running diarization.")

output_dir = input_file.parent
base_name = input_file.stem
aligned_file = output_dir / f"{base_name}_aligned.json"
diarization_file = output_dir / f"{base_name}_diarization.csv"
final_json_file = output_dir / f"{base_name}_final.json"
transcript_file = output_dir / f"{base_name}_transcript.txt"

print("=" * 60)
print("WHISPERX MEETING TRANSCRIPTION")
print("=" * 60)
print(f"Input:        {input_file}")
print(f"Output:       {transcript_file}")
print("\nGPU CHECK\n" + "-" * 60)
print("PyTorch:", torch.__version__)
print("CUDA:", torch.cuda.is_available())

if not torch.cuda.is_available():
    fail("CUDA is unavailable; this script requires a GPU Pod.")

gpu_name = torch.cuda.get_device_name(0)
gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1024**3
print("GPU:", gpu_name)
print(f"VRAM: {gpu_memory:.1f} GB")
if gpu_memory < 15:
    print("WARNING: GPU has less than 15 GB VRAM; reduce BATCH_SIZE if needed.")

print(f"Model:        {WHISPER_MODEL}")
print(f"Language:     {LANGUAGE}")
print(f"Batch size:   {BATCH_SIZE}")
print(f"Compute type: {COMPUTE_TYPE}\n")
total_start = time.time()

print("=" * 60)
print("STEP 1/5 - TRANSCRIPTION")
print("=" * 60)
start = time.time()
model = whisperx.load_model(
    WHISPER_MODEL,
    device=DEVICE,
    compute_type=COMPUTE_TYPE,
    language=LANGUAGE,
)
audio = whisperx.load_audio(str(input_file))
result = model.transcribe(audio, batch_size=BATCH_SIZE, language=LANGUAGE)
print(f"Transcription complete: {len(result['segments'])} segments")
print(f"Time: {time.time() - start:.1f} seconds\n")

print("=" * 60)
print("STEP 2/5 - WORD ALIGNMENT")
print("=" * 60)
start = time.time()
align_model, metadata = whisperx.load_align_model(
    language_code=LANGUAGE,
    device=DEVICE,
)
result = whisperx.align(
    result["segments"],
    align_model,
    metadata,
    audio,
    DEVICE,
    return_char_alignments=False,
)
with aligned_file.open("w", encoding="utf-8") as handle:
    json.dump(result, handle, ensure_ascii=False, indent=2)
print(f"Saved: {aligned_file.name}")
print(f"Time: {time.time() - start:.1f} seconds\n")

print("=" * 60)
print("STEP 3/5 - SPEAKER DIARIZATION")
print("=" * 60)
start = time.time()
diarize_model = DiarizationPipeline(
    model_name=DIARIZATION_MODEL,
    token=hf_token,
    device=DEVICE,
)
diarization = diarize_model(audio)
diarization.to_csv(diarization_file, index=False)
print(f"Saved: {diarization_file.name}")
print(f"Time: {time.time() - start:.1f} seconds\n")

print("=" * 60)
print("STEP 4/5 - ASSIGN SPEAKERS")
print("=" * 60)
start = time.time()
result = whisperx.assign_word_speakers(diarization, result)
with final_json_file.open("w", encoding="utf-8") as handle:
    json.dump(result, handle, ensure_ascii=False, indent=2)
print(f"Saved: {final_json_file.name}")
print(f"Time: {time.time() - start:.1f} seconds\n")

print("=" * 60)
print("STEP 5/5 - CREATE TXT")
print("=" * 60)
start = time.time()
with transcript_file.open("w", encoding="utf-8") as handle:
    current_speaker = None
    for segment in result["segments"]:
        speaker = segment.get("speaker", "UNKNOWN")
        text = segment.get("text", "").strip()
        if not text:
            continue

        timestamp = segment.get("start", 0)
        minutes = int(timestamp // 60)
        seconds = int(timestamp % 60)
        if speaker != current_speaker:
            if current_speaker is not None:
                handle.write("\n")
            handle.write(f"[{minutes:02d}:{seconds:02d}] {speaker}\n")
            current_speaker = speaker
        handle.write(text + "\n")

print(f"Saved: {transcript_file.name}")
print(f"Time: {time.time() - start:.1f} seconds\n")
total_time = time.time() - total_start

print("=" * 60)
print("DONE")
print("=" * 60)
print(f"Transcript : {transcript_file}")
print(f"Size       : {transcript_file.stat().st_size / 1024:.1f} KB")
print(f"Total time : {total_time:.1f} seconds ({total_time / 60:.1f} minutes)")
print("\nQuick preview:\n" + "-" * 60)
with transcript_file.open("r", encoding="utf-8") as handle:
    for line_number, line in enumerate(handle):
        if line_number >= 30:
            break
        print(line.rstrip())

print("\n" + "=" * 60)
print("VERIFY AND DOWNLOAD THE OUTPUT BEFORE DELETING THE POD")
print("=" * 60)
