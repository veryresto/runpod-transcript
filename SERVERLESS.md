# Runpod Serverless proof of concept

This workflow transcribes the URLs in `recordings.txt` with a queue-based Runpod
Serverless endpoint. It scales to zero when idle and saves completed transcripts
under the local `./results` directory.

The existing Pod workflow remains unchanged.

## 1. Publish the worker image

After this branch is merged into `master`, push a version tag from `master`:

```bash
git switch master
git pull --ff-only
git tag v1.1.0
git push origin v1.1.0
```

GitHub Actions publishes:

```text
ghcr.io/veryresto/runpod-transcript:serverless-v1.1.0
ghcr.io/veryresto/runpod-transcript:serverless-latest
```

The PoC downloads WhisperX, alignment, and diarization models when a cold worker
starts. Model artifacts are not baked into the image.

## 2. Prepare local inputs

Store the Hugging Face read token in `.env`:

```dotenv
HF_TOKEN=hf_your_token
```

Accept the conditions for `pyannote/speaker-diarization-community-1`, and put one
HTTPS recording URL per line in `recordings.txt`. Signed URLs should remain valid
long enough to cover queueing, worker startup, download, and transcription.

## 3. Create the endpoint

```bash
./create-serverless.sh
```

This creates a Serverless template and an RTX 4090 endpoint configured with:

- minimum workers: `0`
- maximum workers: `1`
- idle timeout: `30` seconds
- execution timeout: `3600` seconds

The generated endpoint and template IDs are saved locally in ignored files.
`HF_TOKEN` is stored in the Runpod template environment and is never printed by
the script.

## 4. Transcribe recordings

```bash
./transcribe-serverless.sh
```

The submitter processes the URLs sequentially so one warm worker can reuse its
loaded models. For each recording it saves:

```text
results/recording-01_transcript.txt
results/recording-01_serverless.json
```

The JSON file contains the job ID, segment count, byte count, server timings, and
client-observed total time. The signed recording URL is not written to results.

To use an existing endpoint explicitly:

```bash
./transcribe-serverless.sh --endpoint-id ENDPOINT_ID
```

## 5. Clean up the PoC

An endpoint with zero minimum workers has no idle GPU worker, but delete test
resources when they are no longer needed:

```bash
./delete-serverless.sh
```

The script asks for confirmation, then deletes both the endpoint and its template.

## Worker request and response

The handler accepts:

```json
{
  "recording_url": "https://example.com/meeting.webm",
  "min_speakers": 2,
  "max_speakers": 10
}
```

Only `recording_url` is required. The PoC accepts HTTPS URLs only and limits a
download to 5 GiB by default. Override the worker limit with the
`MAX_DOWNLOAD_BYTES` template environment variable.

The response includes the transcript, segment count, downloaded byte count, and
timings. Temporary recordings and intermediate WhisperX artifacts are deleted
after every job.
