#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: Run this script inside the Runpod Pod, not on your laptop." >&2
  exit 1
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "ERROR: No NVIDIA runtime detected." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/.prebuilt-image" && -x /opt/venv/bin/python ]]; then
  DEFAULT_VENV_DIR=/opt/venv
else
  DEFAULT_VENV_DIR=/workspace/venv
fi
VENV_DIR="${VENV_DIR:-${DEFAULT_VENV_DIR}}"

export HF_HOME="${HF_HOME:-/workspace/.cache/huggingface}"
export TORCH_HOME="${TORCH_HOME:-/workspace/.cache/torch}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/workspace/.cache}"

verify_environment() {
  "${VENV_DIR}/bin/python" - <<'PY'
import torch
import whisperx
import hf_transfer

if not torch.cuda.is_available():
    raise SystemExit("ERROR: PyTorch cannot access CUDA")

print(f"PyTorch: {torch.__version__}")
print(f"GPU: {torch.cuda.get_device_name(0)}")
print(f"WhisperX: {getattr(whisperx, '__version__', 'installed')}")
print(f"HF Transfer: {getattr(hf_transfer, '__version__', 'installed')}")
PY
}

if [[ "${RUNPOD_IMAGE_PREBUILT:-0}" == "1" || -f "${SCRIPT_DIR}/.prebuilt-image" ]]; then
  [[ -x "${VENV_DIR}/bin/python" ]] || {
    echo "ERROR: Prebuilt environment is missing at ${VENV_DIR}." >&2
    exit 1
  }
  echo "Using the environment baked into the container image at ${VENV_DIR}."
  verify_environment
  echo "Setup verification complete; no packages were downloaded."
  exit 0
fi

echo "Installing system dependencies..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ffmpeg \
  git \
  curl \
  python3-venv

echo "Creating Python environment at ${VENV_DIR}..."
python3 -m venv --system-site-packages "${VENV_DIR}"
"${VENV_DIR}/bin/python" -m pip install --upgrade pip setuptools wheel
"${VENV_DIR}/bin/python" -m pip install -r "${SCRIPT_DIR}/requirements.txt"

echo "Checking CUDA and WhisperX..."
verify_environment

cat <<EOF

Setup complete.

Before transcription, provide a NEW Hugging Face read token at runtime:
  export HF_TOKEN='hf_...'

Then run:
  ${VENV_DIR}/bin/python ${SCRIPT_DIR}/transcribe_meeting.py /workspace/meeting.webm

Or process every URL in recordings.txt:
  ${SCRIPT_DIR}/transcribe-recordings.sh

Model caches are stored under /workspace/.cache so they survive Pod stops.
EOF
