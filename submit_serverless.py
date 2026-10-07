import argparse
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_nonempty_lines(path: Path) -> list[str]:
    if not path.is_file():
        fail(f"Missing {path}")
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]


parser = argparse.ArgumentParser(description="Submit recordings to Runpod Serverless")
parser.add_argument("--endpoint-id")
parser.add_argument("--recordings", type=Path, default=Path("recordings.txt"))
parser.add_argument("--results", type=Path, default=Path("results"))
parser.add_argument("--wait", default="90m")
args = parser.parse_args()

script_dir = Path(__file__).resolve().parent
endpoint_file = script_dir / ".serverless-endpoint-id"
endpoint_id = args.endpoint_id
if not endpoint_id and endpoint_file.is_file():
    endpoint_id = endpoint_file.read_text(encoding="utf-8").strip()
if not endpoint_id:
    fail("Provide --endpoint-id or run create-serverless.sh first")

recordings_path = args.recordings if args.recordings.is_absolute() else script_dir / args.recordings
results_path = args.results if args.results.is_absolute() else script_dir / args.results
recording_urls = read_nonempty_lines(recordings_path)
if not recording_urls:
    fail(f"No recording URLs found in {recordings_path}")
results_path.mkdir(parents=True, exist_ok=True)

for number, recording_url in enumerate(recording_urls, 1):
    recording_name = f"recording-{number:02d}"
    transcript_path = results_path / f"{recording_name}_transcript.txt"
    metadata_path = results_path / f"{recording_name}_serverless.json"
    print(f"[{number}/{len(recording_urls)}] Submitting {recording_name}", flush=True)
    started = time.monotonic()

    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".json") as payload_file:
        json.dump({"recording_url": recording_url}, payload_file)
        payload_file.flush()
        completed = subprocess.run(
            [
                "runpodctl",
                "serverless",
                "run",
                endpoint_id,
                "--input-file",
                payload_file.name,
                "--wait",
                args.wait,
            ],
            text=True,
            capture_output=True,
            check=False,
        )

    if completed.returncode != 0:
        if completed.stdout:
            print(completed.stdout, file=sys.stderr)
        if completed.stderr:
            print(completed.stderr, file=sys.stderr)
        fail(f"{recording_name} did not complete successfully")

    try:
        job = json.loads(completed.stdout)
        output = job["output"]
        transcript = output["transcript"]
    except (json.JSONDecodeError, KeyError, TypeError) as error:
        fail(f"Unexpected response for {recording_name}: {error}")

    transcript_path.write_text(transcript, encoding="utf-8")
    metadata_path.write_text(
        json.dumps(
            {
                "job_id": job.get("id"),
                "status": job.get("status"),
                "segment_count": output.get("segment_count"),
                "downloaded_bytes": output.get("downloaded_bytes"),
                "timings": output.get("timings"),
                "client_total_seconds": round(time.monotonic() - started, 3),
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"Saved {transcript_path}", flush=True)

print(f"Completed {len(recording_urls)} recording(s). Results: {results_path}")
