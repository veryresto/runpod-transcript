import sys
from pathlib import Path

import torch

from transcription import load_models, transcribe_file


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


if len(sys.argv) != 2:
    fail(f"Usage: {Path(sys.argv[0]).name} MEETING_FILE")

input_file = Path(sys.argv[1]).expanduser().resolve()
if not input_file.is_file():
    fail(f"File not found: {input_file}")

print("=" * 60)
print("WHISPERX MEETING TRANSCRIPTION")
print("=" * 60)
print(f"Input: {input_file}")
print(f"PyTorch: {torch.__version__}")
print(f"CUDA: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"GPU: {torch.cuda.get_device_name(0)}")

try:
    models = load_models()
    result = transcribe_file(input_file, models=models)
except Exception as error:
    fail(str(error))

transcript_file = result["files"]["transcript"]
print("=" * 60)
print("DONE")
print("=" * 60)
print(f"Transcript: {transcript_file}")
print(f"Segments: {result['segment_count']}")
print(f"Total time: {result['timings']['total']:.1f} seconds")
print("\nQuick preview:\n" + "-" * 60)
for line in result["transcript"].splitlines()[:30]:
    print(line)
print("\nVERIFY AND DOWNLOAD THE OUTPUT BEFORE DELETING THE POD")
