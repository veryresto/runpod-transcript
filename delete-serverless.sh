#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENDPOINT_ID="${1:-}"
TEMPLATE_ID="${2:-}"

if [[ -z "${ENDPOINT_ID}" && -f "${SCRIPT_DIR}/.serverless-endpoint-id" ]]; then
  ENDPOINT_ID="$(<"${SCRIPT_DIR}/.serverless-endpoint-id")"
fi
if [[ -z "${TEMPLATE_ID}" && -f "${SCRIPT_DIR}/.serverless-template-id" ]]; then
  TEMPLATE_ID="$(<"${SCRIPT_DIR}/.serverless-template-id")"
fi
[[ -n "${ENDPOINT_ID}" ]] || { echo "ERROR: Missing endpoint ID." >&2; exit 1; }

read -r -p "Delete Serverless endpoint ${ENDPOINT_ID}? [y/N] " CONFIRMATION
if [[ ! "${CONFIRMATION}" =~ ^[Yy]([Ee][Ss])?$ ]]; then
  echo "Deletion cancelled."
  exit 0
fi

runpodctl serverless delete "${ENDPOINT_ID}"
rm -f "${SCRIPT_DIR}/.serverless-endpoint-id"
echo "Deleted endpoint ${ENDPOINT_ID}."

if [[ -n "${TEMPLATE_ID}" ]]; then
  runpodctl template delete "${TEMPLATE_ID}"
  rm -f "${SCRIPT_DIR}/.serverless-template-id"
  echo "Deleted template ${TEMPLATE_ID}."
fi
