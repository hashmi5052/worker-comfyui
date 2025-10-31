###############################################################################
# ComfyUI Dockerfile with CUDA 12.8 and Custom Nodes
# Supports RTX 5090 (Blackwell) and later GPUs
###############################################################################

# =========================
# BASE IMAGE SETUP
# =========================
# Use NVIDIA CUDA 12.8.1 devel image (includes compiler + headers)
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04 AS base

# Optional build arguments
ARG COMFYUI_VERSION=latest
ARG CUDA_VERSION_FOR_COMFY
ARG ENABLE_PYTORCH_UPGRADE=false
ARG PYTORCH_INDEX_URL

# Environment setup
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=8

# =========================
# SYSTEM DEPENDENCIES
# =========================
# Install Python 3.12, git, wget, ffmpeg, and libraries for GUI + video
RUN apt-get update && apt-get install -y \
    python3.12 \
    python3.12-venv \
    git \
    wget \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg && \
    ln -sf /usr/bin/python3.12 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip && \
    apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# =========================
# UV INSTALLATION
# =========================
# Install 'uv' (fast Python package installer) and create virtual environment
RUN wget -qO- https://astral.sh/uv/install.sh | sh && \
    ln -s /root/.local/bin/uv /usr/local/bin/uv && \
    ln -s /root/.local/bin/uvx /usr/local/bin/uvx && \
    uv venv /opt/venv

# Use the virtual environment for all Python commands
ENV PATH="/opt/venv/bin:${PATH}"

# =========================
# COMFYUI INSTALLATION
# =========================
# Install comfy-cli and core Python dependencies
RUN uv pip install comfy-cli pip setuptools wheel

# Install ComfyUI core with optional CUDA version
RUN if [ -n "${CUDA_VERSION_FOR_COMFY}" ]; then \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --cuda-version "${CUDA_VERSION_FOR_COMFY}" --nvidia; \
    else \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --nvidia; \
    fi

# Optional: upgrade PyTorch for newer CUDA versions
RUN if [ "${ENABLE_PYTORCH_UPGRADE}" = "true" ]; then \
      uv pip install --force-reinstall torch torchvision torchaudio --index-url "${PYTORCH_INDEX_URL}"; \
    fi

# =========================
# WORKDIR SETUP
# =========================
WORKDIR /comfyui

# Copy extra model paths if available
ADD src/extra_model_paths.yaml ./

# Add script for installing custom nodes
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

# =========================
# CUSTOM NODES SECTION
# =========================

# --- ComfyUI Manager ---
RUN rm -rf /comfyui/custom_nodes/ComfyUI-Manager && \
    git clone https://github.com/Comfy-Org/ComfyUI-Manager.git /comfyui/custom_nodes/ComfyUI-Manager && \
    uv pip install -r /comfyui/custom_nodes/ComfyUI-Manager/requirements.txt

# --- ComfyUI-GGUF ---
RUN git clone https://github.com/city96/ComfyUI-GGUF.git /comfyui/custom_nodes/ComfyUI-GGUF && \
    uv pip install -r /comfyui/custom_nodes/ComfyUI-GGUF/requirements.txt

# --- ComfyUI-VideoHelperSuite ---
RUN git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git /comfyui/custom_nodes/ComfyUI-VideoHelperSuite && \
    uv pip install -r /comfyui/custom_nodes/ComfyUI-VideoHelperSuite/requirements.txt

# =========================
# FINAL SETUP
# =========================
WORKDIR /

# Install dependencies for handler
RUN uv pip install runpod requests websocket-client

# Add app code and scripts
ADD src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

# Disable interactive prompts from pip
ENV PIP_NO_INPUT=1

# Add script to switch ComfyUI Manager mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

# =========================
# DEFAULT COMMAND
# =========================
CMD ["/start.sh"]
