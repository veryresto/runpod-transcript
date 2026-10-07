#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-${SCRIPT_DIR}/.env}"
SERVERLESS_IMAGE="${SERVERLESS_IMAGE:-ghcr.io/veryresto/runpod-transcript:serverless-latest}"
TEMPLATE_NAME="${TEMPLATE_NAME:-whisperx-serverless}"
ENDPOINT_NAME="${ENDPOINT_NAME:-whisperx-transcription}"
GPU_ID="${GPU_ID:-NVIDIA GeForce RTX 4090}"
CONTAINER_DISK_GB="${CONTAINER_DISK_GB:-30}"
WORKERS_MAX="${WORKERS_MAX:-1}"
IDLE_TIMEOUT="${IDLE_TIMEOUT:-30}"
EXECUTION_TIMEOUT="${EXECUTION_TIMEOUT:-3600}"
REGISTRY_AUTH_ID="${REGISTRY_AUTH_ID:-}"

for command in runpodctl python3; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "ERROR: ${command} is not installed or is not on PATH." >&2
    exit 1
  }
done

[[ -f "${ENV_FILE}" ]] || { echo "ERROR: Missing ${ENV_FILE}" >&2; exit 1; }
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a
[[ -n "${HF_TOKEN:-}" ]] || { echo "ERROR: HF_TOKEN is not set in ${ENV_FILE}" >&2; exit 1; }

TEMPLATE_ENV="$(python3 -c '
import json
import os
print(json.dumps({
    "HF_TOKEN": os.environ["HF_TOKEN"],
    "HF_HUB_ENABLE_HF_TRANSFER": "1",
}))
')"

TEMPLATE_ARGS=(
  --name "${TEMPLATE_NAME}"
  --serverless
  --image "${SERVERLESS_IMAGE}"
  --container-disk-in-gb "${CONTAINER_DISK_GB}"
  --env "${TEMPLATE_ENV}"
)
if [[ -n "${REGISTRY_AUTH_ID}" ]]; then
  TEMPLATE_ARGS+=(--registry-auth-id "${REGISTRY_AUTH_ID}")
fi

echo "Creating Serverless template from ${SERVERLESS_IMAGE}..."
TEMPLATE_OUTPUT="$(runpodctl template create "${TEMPLATE_ARGS[@]}")"
TEMPLATE_ID="$(printf '%s' "${TEMPLATE_OUTPUT}" | python3 -c '
import json
import sys
value = json.load(sys.stdin).get("id")
if not value:
    raise SystemExit("ERROR: Template response did not contain an id")
print(value)
')"
printf '%s\n' "${TEMPLATE_ID}" > "${SCRIPT_DIR}/.serverless-template-id"
chmod 600 "${SCRIPT_DIR}/.serverless-template-id"

cleanup_template_on_error() {
  echo "Endpoint creation failed; deleting template ${TEMPLATE_ID}." >&2
  runpodctl template delete "${TEMPLATE_ID}" >/dev/null || true
}
trap cleanup_template_on_error ERR

echo "Creating scale-to-zero RTX 4090 endpoint..."
ENDPOINT_OUTPUT="$(runpodctl serverless create \
  --template-id "${TEMPLATE_ID}" \
  --name "${ENDPOINT_NAME}" \
  --gpu-id "${GPU_ID}" \
  --gpu-count 1 \
  --workers-min 0 \
  --workers-max "${WORKERS_MAX}" \
  --idle-timeout "${IDLE_TIMEOUT}" \
  --execution-timeout "${EXECUTION_TIMEOUT}" \
  --scale-by requests \
  --scale-threshold 1)"
trap - ERR

ENDPOINT_ID="$(printf '%s' "${ENDPOINT_OUTPUT}" | python3 -c '
import json
import sys
value = json.load(sys.stdin).get("id")
if not value:
    raise SystemExit("ERROR: Endpoint response did not contain an id")
print(value)
')"
printf '%s\n' "${ENDPOINT_ID}" > "${SCRIPT_DIR}/.serverless-endpoint-id"
chmod 600 "${SCRIPT_DIR}/.serverless-endpoint-id"

echo "Serverless endpoint created."
echo "Endpoint ID: ${ENDPOINT_ID}"
echo "Template ID: ${TEMPLATE_ID}"
echo "Minimum workers: 0 (scale to zero)"
echo "Maximum workers: ${WORKERS_MAX}"
echo "Submit recordings with: ${SCRIPT_DIR}/transcribe-serverless.sh"
