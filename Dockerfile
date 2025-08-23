# --- BUILD VERSION IDENTIFIER ---
# v7.1-OPTIMIZED-BUILD
# This Dockerfile uses multi-stage builds to isolate each application,
# and incorporates build caching best practices.

# =====================================================================================
# STAGE 1: Build Open WebUI Assets
# =====================================================================================
# FIX: Pinned to a specific version for reproducibility
FROM node:20.12-bookworm AS openwebui-assets
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN git clone --depth=1 --branch v0.6.23 https://github.com/open-webui/open-webui.git .
# FIX: Using npm ci for faster, more deterministic builds in CI
RUN npm install --legacy-peer-deps && \
    npm install @tiptap/suggestion --legacy-peer-deps && \
    npm install lowlight --legacy-peer-deps && \
    npm install y-protocols --legacy-peer-deps
RUN npm ci --legacy-peer-deps
RUN npm run build
RUN curl -L -o /app/CHANGELOG.md https://raw.githubusercontent.com/open-webui/open-webui/v0.6.23/CHANGELOG.md

# =====================================================================================
# STAGE 2: Fetch ComfyUI Assets
# =====================================================================================
FROM alpine/git:latest AS comfyui-assets
WORKDIR /opt
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

# =====================================================================================
# STAGE 3: Fetch text-generation-webui Assets
# =====================================================================================
FROM alpine/git:latest AS text-generation-webui-assets
WORKDIR /opt
RUN git clone https://github.com/oobabooga/text-generation-webui.git

# =====================================================================================
# STAGE 4: The Python Builder
# =====================================================================================
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_ROOT_USER_ACTION=ignore
ENV PYTHON_VERSION=3.11

# --- 1. Install System Build Dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl build-essential aria2 cmake python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-venv \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 2. Copy all application assets ---
COPY --from=openwebui-assets /app /app
COPY --from=comfyui-assets /opt/ComfyUI /opt/ComfyUI
COPY --from=text-generation-webui-assets /opt/text-generation-webui /opt/text-generation-webui

# --- 3. Prepare Unified Python Virtual Environment ---
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# --- 4. Install ALL Python Dependencies ---
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
RUN python3 -m pip install --no-cache-dir -r /app/backend/requirements.txt -U
RUN python3 -m pip install --no-cache-dir -r /opt/ComfyUI/requirements.txt
RUN python3 -m pip install --no-cache-dir -r /opt/text-generation-webui/requirements/full/requirements.txt
RUN python3 -m pip install --no-cache-dir exllamav2==0.0.15 ctransformers

# --- 5. Recompile llama-cpp-python with CUDA Support ---
RUN ln -s /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/libcuda.so.1
ARG TORCH_CUDA_ARCH_LIST="8.9;9.0"
RUN CMAKE_ARGS="-DGGML_CUDA=on" \
    TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST}" \
    python3 -m pip install llama-cpp-python --no-cache-dir --force-reinstall --upgrade

# --- 6. Install ComfyUI Custom Nodes ---
RUN cd /opt/ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/was-node-suite-comfyui.git && \
    cd was-node-suite-comfyui && \
    python3 -m pip install --no-cache-dir -r requirements.txt
RUN cd /opt/ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    cd ComfyUI-Manager && \
    python3 -m pip install --no-cache-dir -r requirements.txt

# =====================================================================================
# STAGE 5: The Final Image
# =====================================================================================
FROM nvidia/cuda:12.8.1-base-ubuntu22.04

# FIX: Added a label for better metadata
LABEL org.opencontainers.image.title="Mixed-LLM Stack" \
      org.opencontainers.image.version="1.0" \
      org.opencontainers.image.description="A container running Open WebUI, ComfyUI, and Text-Generation-WebUI."

ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV PATH="/opt/venv/bin:$PATH"
ENV OLLAMA_MODELS=/workspace/ollama
ENV COMFYUI_MODELS_DIR=/workspace/comfyui
ENV OPENWEBUI_DATA_DIR=/workspace/open-webui
ENV TEXTGEN_DATA_DIR=/workspace/text-generation-webui
ENV TEXTGEN_MODELS_DIR=${TEXTGEN_DATA_DIR}/models
ENV COMFYUI_URL="http://127.0.0.1:8188"
ENV OLLAMA_BASE_URL="http://127.0.0.1:11434"

# --- 1. Install Runtime System Dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl supervisor ffmpeg libgomp1 python3.11 nano aria2 rsync \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 2. Copy ALL Built Assets from the 'builder' Stage ---
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app/backend /app/backend
COPY --from=builder /app/build /app/build
COPY --from=builder /app/CHANGELOG.md /app/CHANGELOG.md
COPY --from=builder /opt/ComfyUI /opt/ComfyUI
COPY --from=builder /opt/text-generation-webui /opt/text-generation-webui

# --- 3. Install Ollama ---
RUN curl -fsSL https://ollama.com/install.sh | sh

# --- 4. Copy Local Config Files and Scripts ---
COPY supervisord.conf /etc/supervisor/conf.d/all-services.conf
COPY entrypoint.sh /entrypoint.sh
COPY sync_models.sh /sync_models.sh
COPY idle_shutdown.sh /idle_shutdown.sh
COPY start_textgenui.sh /start_textgenui.sh
COPY extra_model_paths.yaml /etc/comfyui_model_paths.yaml
COPY download_and_join.sh /download_and_join.sh
COPY create_modelfile.sh /create_modelfile.sh
RUN chmod +x /entrypoint.sh /sync_models.sh /idle_shutdown.sh /start_textgenui.sh /download_and_join.sh /create_modelfile.sh

# --- 5. Expose ports and set entrypoint ---
EXPOSE 8080 8188 7860
ENTRYPOINT ["/entrypoint.sh"]
