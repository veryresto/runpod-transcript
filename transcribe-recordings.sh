#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-${SCRIPT_DIR}/.env}"
RECORDINGS_FILE="${RECORDINGS_FILE:-${SCRIPT_DIR}/recordings.txt}"
OUTPUT_DIR="${OUTPUT_DIR:-/workspace/recordings}"
PYTHON_BIN="${PYTHON_BIN:-/workspace/venv/bin/python}"

[[ -f "${ENV_FILE}" ]] || { echo "ERROR: Missing ${ENV_FILE}" >&2; exit 1; }
[[ -f "${RECORDINGS_FILE}" ]] || { echo "ERROR: Missing ${RECORDINGS_FILE}" >&2; exit 1; }
[[ -x "${PYTHON_BIN}" ]] || { echo "ERROR: Missing Python environment at ${PYTHON_BIN}" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

[[ -n "${HF_TOKEN:-}" ]] || { echo "ERROR: HF_TOKEN is not set in ${ENV_FILE}" >&2; exit 1; }

export HF_HOME="${HF_HOME:-/workspace/.cache/huggingface}"
export TORCH_HOME="${TORCH_HOME:-/workspace/.cache/torch}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/workspace/.cache}"

mkdir -p "${OUTPUT_DIR}"

recording_number=0
while IFS= read -r recording_url || [[ -n "${recording_url}" ]]; do
  recording_url="${recording_url%$'\r'}"
  [[ -n "${recording_url}" ]] || continue
  [[ "${recording_url}" =~ ^[[:space:]]*# ]] && continue

  recording_number=$((recording_number + 1))
  recording_name="$(printf 'recording-%02d' "${recording_number}")"
  recording_file="${OUTPUT_DIR}/${recording_name}.webm"
  transcript_file="${OUTPUT_DIR}/${recording_name}_transcript.txt"

  echo "============================================================"
  echo "Recording ${recording_number}: ${recording_name}"
  echo "============================================================"

  if [[ ! -s "${recording_file}" ]]; then
    echo "Downloading recording..."
    download_started="${SECONDS}"
    curl --fail --location --retry 3 --retry-all-errors \
      --output "${recording_file}.part" "${recording_url}"
    mv "${recording_file}.part" "${recording_file}"
    echo "TIMING ${recording_name}_download_seconds=$((SECONDS - download_started))"
  else
    echo "Using existing download: ${recording_file}"
  fi

  if [[ -s "${transcript_file}" ]]; then
    echo "Using existing transcript: ${transcript_file}"
  else
    processing_started="${SECONDS}"
    "${PYTHON_BIN}" "${SCRIPT_DIR}/transcribe_meeting.py" "${recording_file}"
    echo "TIMING ${recording_name}_processing_seconds=$((SECONDS - processing_started))"
  fi
done < "${RECORDINGS_FILE}"

if (( recording_number == 0 )); then
  echo "ERROR: No recording URLs found in ${RECORDINGS_FILE}" >&2
  exit 1
fi

echo "Completed ${recording_number} recording(s)."
printf 'Transcript: %s\n' "${OUTPUT_DIR}"/*_transcript.txt
