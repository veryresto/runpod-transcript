# Runpod WhisperX transcription

Transcribe Indonesian meeting recordings on an RTX 4090 Runpod Pod with
WhisperX alignment and speaker diarization. The entire workflow runs from your
laptop; opening an interactive Pod terminal is optional.

## Prerequisites

1. Install and authenticate `runpodctl`. Confirm it works:

   ```bash
   runpodctl doctor
   ```

2. Accept the Hugging Face conditions for
   `pyannote/speaker-diarization-community-1`, create a read token, and store it
   in `.env`:

   ```dotenv
   HF_TOKEN=hf_your_token
   ```

3. Put one recording URL per line in `recordings.txt`. Blank lines and lines
   beginning with `#` are ignored.

`.env`, `recordings.txt`, generated Pod helpers, recordings, and results are
excluded from Git. Never commit or print your Hugging Face token; revoke any
token that has been exposed.

## Run the complete workflow

Execute these commands from this repository on your laptop, in order:

```bash
# 1. Create the RTX 4090 Pod and generate Pod-specific helper scripts.
./create-pod.sh

# 2. Verify CUDA and the environment baked into the container image.
./setup-remote-pod.sh

# 3. Upload .env and recordings.txt.
./upload-inputs.sh

# 4. Download each recording and transcribe it on the Pod.
./transcribe-remote-pod.sh

# 5. Download all TXT outputs into ./results.
./download-results.sh

# 6. After checking ./results, permanently delete the Pod and its volume.
./destroy-pod.sh
```

Do not run the final command until the local files in `./results` have been
opened and verified. Deleting the Pod also deletes its attached volume and
cannot be undone.

The transcription command is restartable. Existing recording downloads and
completed transcripts under `/workspace/recordings` are reused.

## Generated helper scripts

`create-pod.sh` waits for SSH and then creates these local, Pod-specific files:

| Script | Purpose |
| --- | --- |
| `connect-pod.sh` | Open an interactive SSH session when needed. |
| `setup-remote-pod.sh` | Verify the baked CUDA/Python environment. |
| `upload-inputs.sh` | Upload `.env` and `recordings.txt`. |
| `transcribe-remote-pod.sh` | Run the batch transcription and stream its logs locally. |
| `download-results.sh` | Copy every generated `.txt` file into `./results`. |

These helpers are replaced whenever a new Pod is created and are intentionally
ignored by Git because their IP address and SSH port are temporary.

## Results and timing

Remote working files are stored in `/workspace/recordings`. Depending on the
processing stage, WhisperX produces:

- `*_aligned.json`
- `*_diarization.csv`
- `*_final.json`
- `*_transcript.txt`

`download-results.sh` downloads all `.txt` files to the local `./results`
directory. The batch runner prints `TIMING` lines for every recording download
and transcription.

## Pod management

List running and stopped Pods:

```bash
./list-pods.sh
```

Delete interactively by selecting a number:

```bash
./destroy-pod.sh
```

The parameterized forms remain available:

```bash
./destroy-pod.sh POD_ID
./destroy-pod.sh POD_ID --yes
```

Stopping a Pod ends GPU compute charges, but its persistent volume remains
billable. `destroy-pod.sh` permanently deletes both the Pod and its attached
volume.

## Container image

Pods use the prebuilt image:

```text
ghcr.io/veryresto/runpod-transcript:latest
```

The image contains the pinned Runpod PyTorch/CUDA base, system packages,
`/opt/venv`, and the application under `/opt/runpod-transcript`. Runtime tokens,
URLs, recordings, model caches, and results are not baked into it.

GitHub Actions builds and publishes the `linux/amd64` image after changes reach
`master`, when a `v*` tag is pushed, or through manual workflow dispatch. For a
private image, provide a Runpod registry credential:

```bash
REGISTRY_AUTH_ID=YOUR_RUNPOD_REGISTRY_AUTH_ID ./create-pod.sh
```

## Optional configuration

Restrict Pod placement to a data center:

```bash
DATA_CENTER_IDS=EU-SE-1 ./create-pod.sh
```

`create-pod.sh` also accepts overrides including `POD_NAME`, `POD_IMAGE`,
`REGISTRY_AUTH_ID`, `GPU_ID`, `GPU_COUNT`, `CLOUD_TYPE`, `CONTAINER_DISK_GB`,
`VOLUME_GB`, `VOLUME_MOUNT_PATH`, and `POD_PORTS`.

## From-scratch fallback

If `POD_IMAGE` is overridden with the original Runpod PyTorch base image, the
manual installation workflow is still supported:

```bash
./connect-pod.sh

cd /workspace
git clone https://github.com/veryresto/runpod-transcript.git
cd runpod-transcript
./setup-pod.sh
```

The fallback creates `/workspace/venv`. The prebuilt image instead uses
`/opt/venv`. In both cases, model caches and generated recordings live under
`/workspace`.
