FROM runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404

LABEL org.opencontainers.image.source="https://github.com/veryresto/runpod-transcript"
LABEL org.opencontainers.image.description="Runpod WhisperX meeting transcription environment"

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    VENV_DIR=/opt/venv \
    RUNPOD_IMAGE_PREBUILT=1 \
    HF_HOME=/workspace/.cache/huggingface \
    TORCH_HOME=/workspace/.cache/torch \
    XDG_CACHE_HOME=/workspace/.cache

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ffmpeg \
        git \
        curl \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/runpod-transcript

COPY requirements.txt ./
RUN python3 -m venv --system-site-packages "${VENV_DIR}" \
    && "${VENV_DIR}/bin/python" -m pip install --upgrade pip setuptools wheel \
    && "${VENV_DIR}/bin/python" -m pip install --no-cache-dir -r requirements.txt

COPY . ./
RUN chmod +x ./*.sh \
    && touch /opt/runpod-transcript/.prebuilt-image

ENV PATH="/opt/venv/bin:${PATH}"
WORKDIR /workspace

# Inherit the Runpod base image CMD so /start.sh continues to provide SSH and
# the web terminal. Do not add a CMD or ENTRYPOINT here.
