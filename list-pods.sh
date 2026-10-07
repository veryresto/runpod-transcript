#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 0 )); then
  echo "Usage: $0" >&2
  exit 2
fi

if ! command -v runpodctl >/dev/null 2>&1; then
  echo "ERROR: runpodctl is not installed or is not on PATH." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required to format the Pod list." >&2
  exit 1
fi

runpodctl pod list --all | python3 -c '
import json
import sys

pods = json.load(sys.stdin)
if not pods:
    print("No Pods found.")
    raise SystemExit(0)

headers = ("#", "POD ID", "NAME", "RUNTIME", "DESIRED", "GPU", "$/HR", "VOLUME")
rows = []
for number, pod in enumerate(pods, 1):
    rows.append((
        str(number),
        str(pod.get("id") or "-"),
        str(pod.get("name") or "-"),
        str(pod.get("runtimeStatus") or "unknown"),
        str(pod.get("desiredStatus") or "unknown"),
        str(pod.get("gpuCount") or 0),
        str(pod.get("costPerHr") or 0),
        "{} GB".format(pod.get("volumeInGb") or 0),
    ))

widths = [max(len(row[index]) for row in [headers, *rows]) for index in range(len(headers))]
format_row = lambda row: "  ".join(value.ljust(widths[index]) for index, value in enumerate(row))
print(format_row(headers))
print(format_row(tuple("-" * width for width in widths)))
for row in rows:
    print(format_row(row))
'
