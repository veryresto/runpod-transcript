#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "Usage: $0 [POD_ID [--yes]]" >&2
  exit 2
}

[[ $# -le 2 ]] || usage

POD_ID="${1:-}"
AUTO_CONFIRM="${2:-}"
[[ -z "${AUTO_CONFIRM}" || "${AUTO_CONFIRM}" == "--yes" ]] || usage
[[ "${POD_ID}" != "--yes" ]] || usage

if ! command -v runpodctl >/dev/null 2>&1; then
  echo "ERROR: runpodctl is not installed or is not on PATH." >&2
  exit 1
fi

if [[ -z "${POD_ID}" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required for interactive Pod selection." >&2
    exit 1
  fi

  PODS_JSON="$(runpodctl pod list --all)"
  POD_COUNT="$(printf '%s' "${PODS_JSON}" | python3 -c 'import json, sys; print(len(json.load(sys.stdin)))')"

  if [[ "${POD_COUNT}" == "0" ]]; then
    echo "No Pods found. Nothing to delete."
    exit 0
  fi

  printf '%s' "${PODS_JSON}" | python3 -c '
import json
import sys

pods = json.load(sys.stdin)
headers = ("#", "POD ID", "NAME", "RUNTIME", "$/HR", "VOLUME")
rows = []
for number, pod in enumerate(pods, 1):
    rows.append((
        str(number),
        str(pod.get("id") or "-"),
        str(pod.get("name") or "-"),
        str(pod.get("runtimeStatus") or "unknown"),
        str(pod.get("costPerHr") or 0),
        "{} GB".format(pod.get("volumeInGb") or 0),
    ))
widths = [max(len(row[index]) for row in [headers, *rows]) for index in range(len(headers))]
for row in (headers, tuple("-" * width for width in widths), *rows):
    print("  ".join(value.ljust(widths[index]) for index, value in enumerate(row)))
'

  read -r -p "Choose the Pod number to permanently delete: " SELECTION
  if [[ ! "${SELECTION}" =~ ^[0-9]+$ ]]; then
    echo "Invalid selection. Nothing was deleted." >&2
    exit 1
  fi
  SELECTION_NUMBER=$((10#${SELECTION}))
  if (( SELECTION_NUMBER < 1 || SELECTION_NUMBER > POD_COUNT )); then
    echo "Invalid selection. Nothing was deleted." >&2
    exit 1
  fi

  POD_ID="$(printf '%s' "${PODS_JSON}" | python3 -c '
import json
import sys
pods = json.load(sys.stdin)
print(pods[int(sys.argv[1]) - 1]["id"])
' "${SELECTION_NUMBER}")"
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
