# Runpod WhisperX meeting transcription

Reproducible setup for Indonesian meeting transcription with WhisperX, speaker
diarization, and an RTX 4090 Runpod Pod.

## 1. Create the Pod from your laptop

Install and authenticate `runpodctl`, then run:

```bash
./create-pod.sh
```

The script recreates the original Secure Cloud configuration and waits until SSH
is reachable. Creating the Pod starts GPU billing.

By default, Runpod selects any data center with matching capacity. To restrict
placement to a particular data center, override it explicitly:

```bash
DATA_CENTER_IDS=EU-SE-1 ./create-pod.sh
```

## 2. Install the transcription environment

Connect to the Pod using the SSH command returned by `create-pod.sh`, then clone
this repository into the persistent volume:

```bash
cd /workspace
git clone https://github.com/veryresto/runpod-transcript.git
cd runpod-transcript
./setup-pod.sh
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
line and run this inside the Pod:

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
