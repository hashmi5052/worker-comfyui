# Use multi-stage build with caching optimizations
# Base image MUST be CUDA 12.8 or newer for RTX 5090 (Blackwell) support.
# Using the specified devel image for multi-stage build best practices.
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04 AS base

# Build arguments for this stage with sensible defaults for standalone builds
ARG COMFYUI_VERSION=latest
# Note: For CUDA 12.8, PyTorch 2.0+ is often needed. Ensure PyTorch is installed or updated correctly.
ARG CUDA_VERSION_FOR_COMFY
ARG ENABLE_PYTORCH_UPGRADE=false
ARG PYTORCH_INDEX_URL

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git and other necessary tools
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
    ffmpeg \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install uv (latest) using official installer and create isolated venv
RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && ln -s /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv venv /opt/venv

# Use the virtual environment for all subsequent commands
ENV PATH="/opt/venv/bin:${PATH}"

# Install comfy-cli + dependencies needed by it to install ComfyUI
RUN uv pip install comfy-cli pip setuptools wheel

# Install ComfyUI
RUN if [ -n "${CUDA_VERSION_FOR_COMFY}" ]; then \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --cuda-version "${CUDA_VERSION_FOR_COMFY}" --nvidia; \
    else \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --nvidia; \
    fi

# Upgrade PyTorch if needed (for newer CUDA versions)
RUN if [ "$ENABLE_PYTORCH_UPGRADE" = "true" ]; then \
      uv pip install --force-reinstall torch torchvision torchaudio --index-url ${PYTORCH_INDEX_URL}; \
    fi

# Change working directory to ComfyUI
WORKDIR /comfyui

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Add script to install custom nodes
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

---

## 🚀 Custom Nodes Section

*The following steps clone and install custom nodes and their dependencies.*

```dockerfile
# Install ComfyUI Manager
RUN git clone [https://github.com/Comfy-Org/ComfyUI-Manager.git](https://github.com/Comfy-Org/ComfyUI-Manager.git) /comfyui/custom_nodes/ComfyUI-Manager && \
    uv pip install -r /comfyui/custom_nodes/ComfyUI-Manager/requirements.txt

# Install ComfyUI-GGUF
RUN git clone [https://github.com/city96/ComfyUI-GGUF.git](https://github.com/city96/ComfyUI-GGUF.git) /comfyui/custom_nodes/ComfyUI-GGUF && \
    uv pip install -r /comfyui/custom_nodes/ComfyUI-GGUF/requirements.txt

# Install ComfyUI-VideoHelperSuite (Your new custom node)
RUN git clone [https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git](https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git) /comfyui/custom_nodes/ComfyUI-VideoHelperSuite && \
    uv pip install -r /comfyui/custom_nodes/ComfyUI-VideoHelperSuite/requirements.txt

    Go back to the root
WORKDIR /

Install Python runtime dependencies for the handler
RUN uv pip install runpod requests websocket-client

Add application code and scripts
ADD src/start.sh handler.py test_input.json ./ RUN chmod +x /start.sh

Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

Copy helper script to switch Manager network mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode RUN chmod +x /usr/local/bin/comfy-manager-set-mode

Set the default command to run when starting the container
CMD ["/start.sh"]

