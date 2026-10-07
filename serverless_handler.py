import os
import tempfile
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

import runpod

from transcription import ModelBundle, load_models, transcribe_file


MAX_DOWNLOAD_BYTES = int(os.environ.get("MAX_DOWNLOAD_BYTES", str(5 * 1024**3)))

MODELS: ModelBundle | None = None


def initialize_models() -> ModelBundle:
    global MODELS
    if MODELS is None:
        print("Initializing WhisperX models for the worker", flush=True)
        MODELS = load_models(lambda message: print(message, flush=True))
        print("Worker models are ready", flush=True)
    return MODELS


def _positive_integer(value: Any, field: str) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise ValueError(f"{field} must be a positive integer")
    return value


def _download_recording(url: str, destination: Path) -> int:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or not parsed.netloc:
        raise ValueError("recording_url must be a valid HTTPS URL")

    request = urllib.request.Request(url, headers={"User-Agent": "runpod-whisperx/1.0"})
    downloaded = 0
    with urllib.request.urlopen(request, timeout=60) as response, destination.open("wb") as output:
        content_length = response.headers.get("Content-Length")
        if content_length and int(content_length) > MAX_DOWNLOAD_BYTES:
            raise ValueError("recording exceeds MAX_DOWNLOAD_BYTES")
        while chunk := response.read(1024 * 1024):
            downloaded += len(chunk)
            if downloaded > MAX_DOWNLOAD_BYTES:
                raise ValueError("recording exceeds MAX_DOWNLOAD_BYTES")
            output.write(chunk)
    if downloaded == 0:
        raise ValueError("recording download was empty")
    return downloaded


def handler(job: dict[str, Any]) -> dict[str, Any]:
    models = initialize_models()
    payload = job.get("input")
    if not isinstance(payload, dict):
        raise ValueError("input must be an object")

    recording_url = payload.get("recording_url")
    if not isinstance(recording_url, str) or not recording_url:
        raise ValueError("recording_url is required")
    min_speakers = _positive_integer(payload.get("min_speakers"), "min_speakers")
    max_speakers = _positive_integer(payload.get("max_speakers"), "max_speakers")

    job_started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="whisperx-") as temporary_directory:
        workdir = Path(temporary_directory)
        suffix = Path(urllib.parse.urlparse(recording_url).path).suffix or ".webm"
        recording = workdir / f"recording{suffix}"

        download_started = time.monotonic()
        downloaded_bytes = _download_recording(recording_url, recording)
        download_seconds = time.monotonic() - download_started

        result = transcribe_file(
            recording,
            models=models,
            output_dir=workdir,
            min_speakers=min_speakers,
            max_speakers=max_speakers,
            progress=lambda message: print(message, flush=True),
        )

    return {
        "transcript": result["transcript"],
        "segment_count": result["segment_count"],
        "downloaded_bytes": downloaded_bytes,
        "timings": {
            "model_load": models.load_seconds,
            "download": round(download_seconds, 3),
            **result["timings"],
            "job_total": round(time.monotonic() - job_started, 3),
        },
    }


if __name__ == "__main__":
    initialize_models()
    runpod.serverless.start({"handler": handler})
