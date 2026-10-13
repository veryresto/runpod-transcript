# Pod transcription run — 2026-10-13

This report records an end-to-end transcription run launched from a laptop
against a temporary Runpod Pod. It is intended as a practical performance
baseline for future runs.

## Outcome

- One 1.16 GB WebM recording was transcribed successfully.
- WhisperX produced 56 timestamped speaker segments.
- The downloaded transcript contained 146 lines and was 13,717 bytes.
- The transcript was saved locally as `results/recording-01_transcript.txt`.
- The temporary Pod and its attached volume were permanently deleted after the
  local result was verified.
- Runpod reported no remaining Pods and a current spend rate of `$0/hour` after
  cleanup.

Recording URLs, credentials, SSH connection details, and the transcript content
are intentionally omitted from this report.

## Runtime environment

| Item | Value |
| --- | --- |
| Runpod Pod | Secure Cloud, US-NC-1 |
| GPU | 1× NVIDIA GeForce RTX 4090, 23.5 GB VRAM |
| Pod price | $0.89/hour while running |
| Container image | `ghcr.io/veryresto/runpod-transcript:latest` |
| PyTorch | 2.8.0+cu128 |
| Whisper model | `large-v3` |
| Language | Indonesian (`id`) |
| Compute type | `float16` |
| Batch size | 4 |
| Container disk | 30 GB |
| Attached volume | 50 GB mounted at `/workspace` |

The container image already included CUDA, WhisperX, and `hf_transfer`, so the
setup verification did not install or download Python packages.

## Timing summary

| Process | Elapsed time | Notes |
| --- | ---: | --- |
| Create Pod and wait for SSH | 50.66 s | Includes image pull, container startup, and SSH readiness |
| Verify baked environment | 5.85 s | Ran concurrently with input upload |
| Upload `.env` and `recordings.txt` | 8.07 s | Ran concurrently with environment verification |
| Download recording to Pod | 47 s | 1.16 GB WebM |
| WhisperX processing | 67 s | Batch-reported processing time |
| Core model pipeline | 59.4 s | Sum reported by the Python transcription script |
| └ Transcription | 30.8 s | Produced 56 segments |
| └ Word alignment | 15.6 s | Wrote aligned JSON |
| └ Speaker diarization | 13.0 s | Wrote diarization CSV |
| └ Speaker assignment | 0.1 s | Wrote final JSON |
| └ Transcript creation | <0.1 s | Wrote timestamped TXT |
| Complete remote batch command | 118.62 s | Includes recording download and processing overhead |
| Download TXT result to laptop | 7.22 s | Followed by local size/content verification |
| Delete Pod and attached volume | 3.27 s | Confirmed with an empty Pod list afterward |

The environment verification and input upload overlapped. Their combined
wall-clock contribution was therefore about 8.07 seconds, not 13.92 seconds.

## Commands used

The normal laptop workflow was executed in this order:

```bash
./create-pod.sh
./setup-remote-pod.sh
./upload-inputs.sh
./transcribe-remote-pod.sh
./download-results.sh
./destroy-pod.sh POD_ID --yes
```

After downloading, the transcript was checked locally for a non-zero size, line
count, byte count, and readable opening lines before the destructive cleanup
step ran.

## Observations

- Pod startup was under one minute.
- The prebuilt image made setup inexpensive: verification took under six
  seconds and required no package installation.
- For this run, moving the 1.16 GB source recording took nearly as long as the
  core WhisperX pipeline.
- The full remote batch command took about two minutes, while the GPU processing
  portion took about one minute.
- Deleting the Pod, rather than merely stopping it, removed the attached volume
  and returned the account to a `$0/hour` current spend rate.

These measurements describe one run on one host and should be treated as a
baseline, not a guaranteed duration. Recording length, network throughput,
model-cache state, GPU availability, and Runpod image-pull time can all change
future results.
