#!/usr/bin/env bash
set -Eeuo pipefail

# Recreate the RTX 4090 Pod used for meeting transcription. Override any value
# by exporting the corresponding variable before running this script.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
POD_NAME="${POD_NAME:-whisperx-meeting}"
POD_IMAGE="${POD_IMAGE:-ghcr.io/veryresto/runpod-transcript:latest}"
GPU_ID="${GPU_ID:-NVIDIA GeForce RTX 4090}"
GPU_COUNT="${GPU_COUNT:-1}"
CLOUD_TYPE="${CLOUD_TYPE:-SECURE}"
CONTAINER_DISK_GB="${CONTAINER_DISK_GB:-30}"
VOLUME_GB="${VOLUME_GB:-50}"
VOLUME_MOUNT_PATH="${VOLUME_MOUNT_PATH:-/workspace}"
POD_PORTS="${POD_PORTS:-22/tcp,8888/http}"
DATA_CENTER_IDS="${DATA_CENTER_IDS:-}"
REGISTRY_AUTH_ID="${REGISTRY_AUTH_ID:-}"
CONNECT_SCRIPT="${CONNECT_SCRIPT:-${SCRIPT_DIR}/connect-pod.sh}"
DOWNLOAD_SCRIPT="${DOWNLOAD_SCRIPT:-${SCRIPT_DIR}/download-results.sh}"
UPLOAD_SCRIPT="${UPLOAD_SCRIPT:-${SCRIPT_DIR}/upload-inputs.sh}"
REMOTE_SETUP_SCRIPT="${REMOTE_SETUP_SCRIPT:-${SCRIPT_DIR}/setup-remote-pod.sh}"
REMOTE_TRANSCRIBE_SCRIPT="${REMOTE_TRANSCRIBE_SCRIPT:-${SCRIPT_DIR}/transcribe-remote-pod.sh}"

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

if [[ -n "${REGISTRY_AUTH_ID}" ]]; then
  CREATE_ARGS+=(--registry-auth-id "${REGISTRY_AUTH_ID}")
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

IFS=$'\t' read -r SSH_IP SSH_PORT SSH_KEY < <(printf '%s' "${CREATE_OUTPUT}" | python3 -c '
import json
import sys

pod = json.load(sys.stdin)
ssh = pod.get("ssh") or {}
ip = ssh.get("ip")
port = ssh.get("port")
key = (ssh.get("ssh_key") or {}).get("path")
if not all((ip, port, key)):
    raise SystemExit("ERROR: Pod response did not contain complete SCP connection details")
for value in (ip, str(port), key):
    if "\t" in value or "\n" in value:
        raise SystemExit("ERROR: Pod response contained invalid SCP connection details")
print(ip, port, key, sep="\t")
')

printf '#!/usr/bin/env bash\nset -Eeuo pipefail\nexec %s "$@"\n' \
  "${SSH_COMMAND}" > "${CONNECT_SCRIPT}.tmp"
chmod 700 "${CONNECT_SCRIPT}.tmp"
mv "${CONNECT_SCRIPT}.tmp" "${CONNECT_SCRIPT}"

{
  printf '#!/usr/bin/env bash\nset -Eeuo pipefail\n\n'
  printf 'SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"\n'
  printf 'RESULTS_DIR="${1:-${SCRIPT_DIR}/results}"\n'
  printf 'SSH_IP=%q\n' "${SSH_IP}"
  printf 'SSH_PORT=%q\n' "${SSH_PORT}"
  printf 'SSH_KEY=%q\n\n' "${SSH_KEY}"
  printf 'mkdir -p "${RESULTS_DIR}"\n'
  printf 'scp -i "${SSH_KEY}" -P "${SSH_PORT}" "root@${SSH_IP}:/workspace/recordings/*.txt" "${RESULTS_DIR}/"\n'
  printf 'echo "Downloaded text results to ${RESULTS_DIR}"\n'
} > "${DOWNLOAD_SCRIPT}.tmp"
chmod 700 "${DOWNLOAD_SCRIPT}.tmp"
mv "${DOWNLOAD_SCRIPT}.tmp" "${DOWNLOAD_SCRIPT}"

{
  printf '#!/usr/bin/env bash\nset -Eeuo pipefail\n\n'
  printf 'SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"\n'
  printf 'SSH_IP=%q\n' "${SSH_IP}"
  printf 'SSH_PORT=%q\n' "${SSH_PORT}"
  printf 'SSH_KEY=%q\n\n' "${SSH_KEY}"
  printf 'for input_file in .env recordings.txt; do\n'
  printf '  if [[ ! -f "${SCRIPT_DIR}/${input_file}" ]]; then\n'
  printf '    echo "ERROR: Missing ${SCRIPT_DIR}/${input_file}" >&2\n'
  printf '    exit 1\n'
  printf '  fi\n'
  printf 'done\n\n'
  printf 'ssh -i "${SSH_KEY}" -p "${SSH_PORT}" "root@${SSH_IP}" '\''mkdir -p /workspace/runpod-inputs'\''\n'
  printf 'scp -i "${SSH_KEY}" -P "${SSH_PORT}" "${SCRIPT_DIR}/.env" "${SCRIPT_DIR}/recordings.txt" "root@${SSH_IP}:/workspace/runpod-inputs/"\n'
  printf 'echo "Uploaded .env and recordings.txt to /workspace/runpod-inputs/"\n'
} > "${UPLOAD_SCRIPT}.tmp"
chmod 700 "${UPLOAD_SCRIPT}.tmp"
mv "${UPLOAD_SCRIPT}.tmp" "${UPLOAD_SCRIPT}"

{
  printf '#!/usr/bin/env bash\nset -Eeuo pipefail\n\n'
  printf 'SSH_IP=%q\n' "${SSH_IP}"
  printf 'SSH_PORT=%q\n' "${SSH_PORT}"
  printf 'SSH_KEY=%q\n\n' "${SSH_KEY}"
  printf 'ssh -i "${SSH_KEY}" -p "${SSH_PORT}" "root@${SSH_IP}" '\''bash -s'\'' <<'\''REMOTE_SETUP'\''\n'
  printf 'set -Eeuo pipefail\n'
  printf 'if [[ -x /opt/runpod-transcript/setup-pod.sh ]]; then\n'
  printf '  /opt/runpod-transcript/setup-pod.sh\n'
  printf 'else\n'
  printf '  cd /workspace\n'
  printf '  if [[ -d runpod-transcript/.git ]]; then\n'
  printf '    git -C runpod-transcript pull --ff-only\n'
  printf '  elif [[ -e runpod-transcript ]]; then\n'
  printf '    echo "ERROR: /workspace/runpod-transcript exists but is not a Git repository." >&2\n'
  printf '    exit 1\n'
  printf '  else\n'
  printf '    git clone https://github.com/veryresto/runpod-transcript.git\n'
  printf '  fi\n'
  printf '  cd runpod-transcript\n'
  printf '  ./setup-pod.sh\n'
  printf 'fi\n'
  printf 'REMOTE_SETUP\n'
} > "${REMOTE_SETUP_SCRIPT}.tmp"
chmod 700 "${REMOTE_SETUP_SCRIPT}.tmp"
mv "${REMOTE_SETUP_SCRIPT}.tmp" "${REMOTE_SETUP_SCRIPT}"

{
  printf '#!/usr/bin/env bash\nset -Eeuo pipefail\n\n'
  printf 'SSH_IP=%q\n' "${SSH_IP}"
  printf 'SSH_PORT=%q\n' "${SSH_PORT}"
  printf 'SSH_KEY=%q\n\n' "${SSH_KEY}"
  printf 'ssh -i "${SSH_KEY}" -p "${SSH_PORT}" "root@${SSH_IP}" '\''bash -s'\'' <<'\''REMOTE_TRANSCRIBE'\''\n'
  printf 'set -Eeuo pipefail\n'
  printf 'if [[ -x /opt/runpod-transcript/transcribe-recordings.sh ]]; then\n'
  printf '  APP_DIR=/opt/runpod-transcript\n'
  printf 'else\n'
  printf '  APP_DIR=/workspace/runpod-transcript\n'
  printf 'fi\n'
  printf 'for input_file in .env recordings.txt; do\n'
  printf '  if [[ ! -f "/workspace/runpod-inputs/${input_file}" ]]; then\n'
  printf '    echo "ERROR: Missing /workspace/runpod-inputs/${input_file}. Run upload-inputs.sh from the laptop first." >&2\n'
  printf '    exit 1\n'
  printf '  fi\n'
  printf 'done\n'
  printf 'ENV_FILE=/workspace/runpod-inputs/.env RECORDINGS_FILE=/workspace/runpod-inputs/recordings.txt "${APP_DIR}/transcribe-recordings.sh"\n'
  printf 'REMOTE_TRANSCRIBE\n'
} > "${REMOTE_TRANSCRIBE_SCRIPT}.tmp"
chmod 700 "${REMOTE_TRANSCRIBE_SCRIPT}.tmp"
mv "${REMOTE_TRANSCRIBE_SCRIPT}.tmp" "${REMOTE_TRANSCRIBE_SCRIPT}"

echo
echo "SSH helper created: ${CONNECT_SCRIPT}"
echo "Connect with: ${CONNECT_SCRIPT}"
echo "Download helper created: ${DOWNLOAD_SCRIPT}"
echo "Download results with: ${DOWNLOAD_SCRIPT}"
echo "Upload helper created: ${UPLOAD_SCRIPT}"
echo "Upload inputs with: ${UPLOAD_SCRIPT}"
echo "Remote setup helper created: ${REMOTE_SETUP_SCRIPT}"
echo "Set up the Pod with: ${REMOTE_SETUP_SCRIPT}"
echo "Remote transcription helper created: ${REMOTE_TRANSCRIBE_SCRIPT}"
echo "Transcribe recordings with: ${REMOTE_TRANSCRIBE_SCRIPT}"
