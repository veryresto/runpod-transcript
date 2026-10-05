#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "Usage: $0 POD_ID [--yes]" >&2
  exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage

POD_ID="$1"
AUTO_CONFIRM="${2:-}"
[[ -n "${POD_ID}" ]] || usage
[[ -z "${AUTO_CONFIRM}" || "${AUTO_CONFIRM}" == "--yes" ]] || usage

if ! command -v runpodctl >/dev/null 2>&1; then
  echo "ERROR: runpodctl is not installed or is not on PATH." >&2
  exit 1
fi

echo "Pod scheduled for permanent deletion:"
runpodctl pod get "${POD_ID}"
echo
echo "WARNING: This permanently deletes the Pod and its attached volume disk."
echo "Files in that volume cannot be recovered."

if [[ "${AUTO_CONFIRM}" != "--yes" ]]; then
  read -r -p "Type the Pod ID (${POD_ID}) to confirm: " CONFIRMATION
  if [[ "${CONFIRMATION}" != "${POD_ID}" ]]; then
    echo "Confirmation did not match. Nothing was deleted." >&2
    exit 1
  fi
fi

runpodctl pod delete "${POD_ID}"
echo "Deletion request completed for Pod ${POD_ID}."
