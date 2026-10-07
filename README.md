# Runpod WhisperX meeting transcription

Reproducible setup for Indonesian meeting transcription with WhisperX, speaker
diarization, and an RTX 4090 Runpod Pod.

## Container image

The production environment is built from `Dockerfile` and published by GitHub
Actions as:

```text
ghcr.io/veryresto/runpod-transcript:latest
```

The image contains CUDA-compatible PyTorch, system packages, `/opt/venv`, and the
application under `/opt/runpod-transcript`. Tokens, recording URLs, recordings,
model caches, and results are never included in the image.

The publishing workflow runs after changes reach `master`, for version tags, or
when manually dispatched. A newly published GHCR package is private by default.
Either make it public in the GitHub package settings or provide a Runpod registry
credential with `REGISTRY_AUTH_ID` when creating a Pod.

## 1. Create the Pod from your laptop

Install and authenticate `runpodctl`, then run:

```bash
./create-pod.sh
```

The script deploys `ghcr.io/veryresto/runpod-transcript:latest`, waits until SSH
is reachable, and generates Pod-specific local helper scripts. Creating the Pod
starts GPU billing.

Connect to the newly created Pod with:

```bash
./connect-pod.sh
```

The complete laptop-only workflow is:

```bash
./create-pod.sh
./setup-remote-pod.sh
./upload-inputs.sh
./transcribe-remote-pod.sh
./download-results.sh
./destroy-pod.sh
```

After transcription finishes, download every text result into the local
`./results` directory with:

```bash
./download-results.sh
```

All generated helpers are replaced whenever a new Pod is created and are ignored
by Git because their host and port are temporary.

By default, Runpod selects any data center with matching capacity. To restrict
placement to a particular data center, override it explicitly:

```bash
DATA_CENTER_IDS=EU-SE-1 ./create-pod.sh
```

For a private GHCR package:

```bash
REGISTRY_AUTH_ID=YOUR_RUNPOD_REGISTRY_AUTH_ID ./create-pod.sh
```

## 2. Install the transcription environment

From your laptop, run the generated remote setup helper. With the custom image,
this only verifies CUDA and the baked Python environment; it does not download
system or Python packages:

```bash
./setup-remote-pod.sh
```

The existing from-scratch workflow remains available when overriding `POD_IMAGE`
with a base image. Connect using `./connect-pod.sh`, then run:

```bash
cd /workspace
git clone https://github.com/veryresto/runpod-transcript.git
cd runpod-transcript
./setup-pod.sh
```

Run this from your laptop to upload `.env` and `recordings.txt` into the Pod's
`/workspace/runpod-inputs` directory:

```bash
./upload-inputs.sh
```

The custom image uses `/opt/venv`. Model caches remain under `/workspace/.cache`,
so they survive a Pod stop but are removed when the Pod and its volume are
deleted. The fallback from-scratch workflow creates `/workspace/venv`.

## 3. Transcribe a meeting

First accept the model conditions for
`pyannote/speaker-diarization-community-1` in Hugging Face. Create a new read
token and supply it only for the current shell:

```bash
export HF_TOKEN='hf_your_new_token'
/opt/venv/bin/python /opt/runpod-transcript/transcribe_meeting.py /workspace/meeting.webm
```

Do not commit tokens to this repository. The token previously shared in chat
should be revoked and replaced.

The script writes these files beside the input media:

- `*_aligned.json`
- `*_diarization.csv`
- `*_final.json`
- `*_transcript.txt`

To download and transcribe every signed URL in `recordings.txt`, put one URL per
line, upload the inputs, and run this from your laptop:

```bash
./upload-inputs.sh
./transcribe-remote-pod.sh
```

The existing manual command inside the Pod remains available:

```bash
./transcribe-recordings.sh
```

Recordings and generated files are stored under `/workspace/recordings`. Existing
downloads and completed transcripts are reused if the batch command is restarted.
The runner prints machine-readable `TIMING` lines for every download and
transcription. To prepare and time all model downloads separately first, run:

```bash
set -a; source /workspace/runpod-inputs/.env; set +a
/opt/venv/bin/python /opt/runpod-transcript/prepare-models.py
```

Download and verify the results before deleting the Pod. Stopping a Pod ends
GPU compute charges but its persistent volume continues to incur storage fees;
deleting the Pod removes that volume.

## Delete a Pod and its volume disk

List all existing Pods, including stopped Pods:

```bash
./list-pods.sh
```

After downloading and verifying all output, permanently delete the Pod with:

```bash
./destroy-pod.sh POD_ID
```

If no Pod ID is supplied, the script shows a numbered list and asks which Pod
to delete, followed by a yes/no confirmation:

```bash
./destroy-pod.sh
```

When a Pod ID is supplied explicitly, the script requires you to type it again.
For deliberate non-interactive automation, pass `--yes`:

```bash
./destroy-pod.sh POD_ID --yes
```

Deletion cannot be undone. It removes the Pod and its attached volume disk.

## Optional overrides

`create-pod.sh` supports environment-variable overrides, including `POD_NAME`,
`POD_IMAGE`, `REGISTRY_AUTH_ID`, `GPU_ID`, `DATA_CENTER_IDS`,
`CONTAINER_DISK_GB`, and `VOLUME_GB`.
