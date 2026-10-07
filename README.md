# Runpod WhisperX meeting transcription

Reproducible setup for Indonesian meeting transcription with WhisperX, speaker
diarization, and an RTX 4090 Runpod Pod.

## 1. Create the Pod from your laptop

Install and authenticate `runpodctl`, then run:

```bash
./create-pod.sh
```

The script recreates the original Secure Cloud configuration and waits until SSH
is reachable. It parses the returned SSH command and creates an executable,
Pod-specific `connect-pod.sh` helper. Creating the Pod starts GPU billing.

Connect to the newly created Pod with:

```bash
./connect-pod.sh
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

## 2. Install the transcription environment

From your laptop, run the generated remote setup helper. It clones the repository
when needed, pulls updates on subsequent runs, and executes `setup-pod.sh` inside
the Pod:

```bash
./setup-remote-pod.sh
```

The existing manual workflow is also preserved. Connect using
`./connect-pod.sh`, then run:

```bash
cd /workspace
git clone https://github.com/veryresto/runpod-transcript.git
cd runpod-transcript
./setup-pod.sh
```

After cloning the repository, run this from a separate terminal on your laptop to
upload the local `.env` and `recordings.txt` files:

```bash
./upload-inputs.sh
```

The setup creates `/workspace/venv`. Package and model caches also live under
`/workspace`, so they survive a Pod stop.

## 3. Transcribe a meeting

First accept the model conditions for
`pyannote/speaker-diarization-community-1` in Hugging Face. Create a new read
token and supply it only for the current shell:

```bash
export HF_TOKEN='hf_your_new_token'
/workspace/venv/bin/python transcribe_meeting.py /workspace/meeting.webm
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
set -a; source .env; set +a
/workspace/venv/bin/python prepare-models.py
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

The script displays the current Pod details and requires you to type the Pod ID
again before deletion. For deliberate non-interactive automation, pass `--yes`:

```bash
./destroy-pod.sh POD_ID --yes
```

Deletion cannot be undone. It removes the Pod and its attached volume disk.

## Optional overrides

`create-pod.sh` supports environment-variable overrides, including `POD_NAME`,
`POD_IMAGE`, `GPU_ID`, `DATA_CENTER_IDS`, `CONTAINER_DISK_GB`, and `VOLUME_GB`.
