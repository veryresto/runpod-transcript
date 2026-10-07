#!/usr/bin/env bash
set -Eeuo pipefail

# Recreate the RTX 4090 Pod used for meeting transcription. Override any value
# by exporting the corresponding variable before running this script.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
POD_NAME="${POD_NAME:-whisperx-meeting}"
POD_IMAGE="${POD_IMAGE:-runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404}"
GPU_ID="${GPU_ID:-NVIDIA GeForce RTX 4090}"
GPU_COUNT="${GPU_COUNT:-1}"
CLOUD_TYPE="${CLOUD_TYPE:-SECURE}"
CONTAINER_DISK_GB="${CONTAINER_DISK_GB:-30}"
VOLUME_GB="${VOLUME_GB:-50}"
VOLUME_MOUNT_PATH="${VOLUME_MOUNT_PATH:-/workspace}"
POD_PORTS="${POD_PORTS:-22/tcp,8888/http}"
DATA_CENTER_IDS="${DATA_CENTER_IDS:-}"
CONNECT_SCRIPT="${CONNECT_SCRIPT:-${SCRIPT_DIR}/connect-pod.sh}"

if ! command -v runpodctl >/dev/null 2>&1; then
  echo "ERROR: runpodctl is not installed or is not on PATH." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required to parse the Pod response." >&2
  exit 1
fi

if [[ -n "${DATA_CENTER_IDS}" ]]; then
  echo "Creating ${POD_NAME} with ${GPU_COUNT}x ${GPU_ID} in ${DATA_CENTER_IDS}..."
else
  echo "Creating ${POD_NAME} with ${GPU_COUNT}x ${GPU_ID} in any available data center..."
fi
echo "This creates a billable Runpod resource."

CREATE_ARGS=(
  --name "${POD_NAME}"
  --image "${POD_IMAGE}"
  --gpu-id "${GPU_ID}"
  --gpu-count "${GPU_COUNT}"
  --cloud-type "${CLOUD_TYPE}"
  --container-disk-in-gb "${CONTAINER_DISK_GB}"
  --volume-in-gb "${VOLUME_GB}"
  --volume-mount-path "${VOLUME_MOUNT_PATH}"
  --ports "${POD_PORTS}"
  --wait
  --wait-timeout 15m
)

if [[ -n "${DATA_CENTER_IDS}" ]]; then
  CREATE_ARGS+=(--data-center-ids "${DATA_CENTER_IDS}")
fi

CREATE_OUTPUT="$(runpodctl pod create "${CREATE_ARGS[@]}")"
printf '%s\n' "${CREATE_OUTPUT}"

SSH_COMMAND="$(printf '%s' "${CREATE_OUTPUT}" | python3 -c '
import json
import shlex
import sys

pod = json.load(sys.stdin)
command = pod.get("ssh", {}).get("ssh_command") or pod.get("ssh_command")
if not command:
    raise SystemExit("ERROR: Pod response did not contain an SSH command")
print(shlex.join(shlex.split(command)))
')"

printf '#!/usr/bin/env bash\nset -Eeuo pipefail\nexec %s "$@"\n' \
  "${SSH_COMMAND}" > "${CONNECT_SCRIPT}.tmp"
chmod 700 "${CONNECT_SCRIPT}.tmp"
mv "${CONNECT_SCRIPT}.tmp" "${CONNECT_SCRIPT}"

echo
echo "SSH helper created: ${CONNECT_SCRIPT}"
echo "Connect with: ${CONNECT_SCRIPT}"
