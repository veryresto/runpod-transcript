#!/usr/bin/env bash
set -Eeuo pipefail

# Recreate the RTX 4090 Pod used for meeting transcription. Override any value
# by exporting the corresponding variable before running this script.
POD_NAME="${POD_NAME:-whisperx-meeting}"
POD_IMAGE="${POD_IMAGE:-runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404}"
GPU_ID="${GPU_ID:-NVIDIA GeForce RTX 4090}"
GPU_COUNT="${GPU_COUNT:-1}"
CLOUD_TYPE="${CLOUD_TYPE:-SECURE}"
CONTAINER_DISK_GB="${CONTAINER_DISK_GB:-30}"
VOLUME_GB="${VOLUME_GB:-50}"
VOLUME_MOUNT_PATH="${VOLUME_MOUNT_PATH:-/workspace}"
POD_PORTS="${POD_PORTS:-22/tcp,8888/http}"
DATA_CENTER_IDS="${DATA_CENTER_IDS:-EUR-IS-2}"

if ! command -v runpodctl >/dev/null 2>&1; then
  echo "ERROR: runpodctl is not installed or is not on PATH." >&2
  exit 1
fi

echo "Creating ${POD_NAME} with ${GPU_COUNT}x ${GPU_ID} in ${DATA_CENTER_IDS}..."
echo "This creates a billable Runpod resource."

runpodctl pod create \
  --name "${POD_NAME}" \
  --image "${POD_IMAGE}" \
  --gpu-id "${GPU_ID}" \
  --gpu-count "${GPU_COUNT}" \
  --cloud-type "${CLOUD_TYPE}" \
  --container-disk-in-gb "${CONTAINER_DISK_GB}" \
  --volume-in-gb "${VOLUME_GB}" \
  --volume-mount-path "${VOLUME_MOUNT_PATH}" \
  --ports "${POD_PORTS}" \
  --data-center-ids "${DATA_CENTER_IDS}" \
  --wait \
  --wait-timeout 15m
