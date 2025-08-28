# syntax=docker/dockerfile:1.4

# --- BUILD VERSION IDENTIFIER ---
# v8.5-GGUF-Tools

# =====================================================================================
# STAGE 1: Asset Fetching & llama.cpp compilation
# =====================================================================================
# --- FIX: Updated the build process from 'make' to 'cmake' for llama.cpp ---added libcurl too
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04 AS llama-cpp-builder
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    git build-essential cmake libcurl4-openssl-dev && \
    rm -rf /var/lib/apt/lists/*
RUN git clone --depth=1 https://github.com/ggerganov/llama.cpp.git
WORKDIR /llama.cpp
RUN mkdir build && cd build && cmake .. && make -j"$(nproc)" llama-gguf-split

FROM alpine/git:2.49.1 AS openwebui-assets
RUN apk add --no-cache curl
WORKDIR /app
RUN git clone --depth=1 https://github.com/open-webui/open-webui.git .
RUN curl -L -o /app/CHANGELOG.md https://raw.githubusercontent.com/open-webui/open-webui/main/CHANGELOG.md

FROM alpine/git:2.49.1 AS comfyui-assets
WORKDIR /opt
RUN git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git && rm -rf ComfyUI/.git

FROM alpine/git:2.49.1 AS text-generation-webui-assets
WORKDIR /opt
RUN git clone --depth=1 https://github.com/oobabooga/text-generation-webui.git && rm -rf text-generation-webui/.git

# =====================================================================================
# STAGE 2: Web UI Asset Builder
# =====================================================================================
FROM node:20-bookworm AS webui-builder
WORKDIR /app
# Install dependencies before copying source to leverage layer caching
COPY --from=openwebui-assets /app/package*.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm install --legacy-peer-deps && \
    npm install @tiptap/suggestion lowlight y-protocols --legacy-peer-deps
COPY --from=openwebui-assets /app /app
RUN npm run build && rm -rf node_modules

# =====================================================================================
# STAGE 3: Python Builder with Isolated Environments
# =====================================================================================
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_ROOT_USER_ACTION=ignore
ENV PYTHON_VERSION=3.11

# --- 1. Install System Build Dependencies ---
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    git curl build-essential aria2 cmake python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-venv \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 2. Prepare dependency files ---
COPY --from=webui-builder /app/backend/requirements.txt /tmp/req-webui.txt
COPY --from=comfyui-assets /opt/ComfyUI/requirements.txt /tmp/req-comfyui.txt
COPY --from=text-generation-webui-assets /opt/text-generation-webui/requirements /tmp/req-textgen

# --- 3. Create Python virtual environments ---
RUN python3 -m venv /opt/venv-webui && \
    python3 -m venv /opt/venv-comfyui && \
    python3 -m venv /opt/venv-textgen

# --- 4. Install dependencies into isolated environments ---
RUN --mount=type=cache,target=/root/.cache/pip \
    /opt/venv-webui/bin/python3 -m pip install --upgrade pip && \
    /opt/venv-webui/bin/python3 -m pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128 && \
    /opt/venv-webui/bin/python3 -m pip install --no-cache-dir -r /tmp/req-webui.txt -U

RUN --mount=type=cache,target=/root/.cache/pip \
    /opt/venv-comfyui/bin/python3 -m pip install --upgrade pip wheel setuptools && \
    /opt/venv-comfyui/bin/python3 -m pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128 && \
    /opt/venv-comfyui/bin/python3 -m pip install --no-cache-dir -r /tmp/req-comfyui.txt && \
    /opt/venv-comfyui/bin/python3 -m pip install --no-cache-dir --force-reinstall --no-build-isolation flash-attn GitPython

RUN --mount=type=cache,target=/root/.cache/pip \
    /opt/venv-textgen/bin/python3 -m pip install --upgrade pip && \
    /opt/venv-textgen/bin/python3 -m pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128 && \
    /opt/venv-textgen/bin/python3 -m pip install --no-cache-dir -r /tmp/req-textgen/full/requirements.txt && \
    /opt/venv-textgen/bin/python3 -m pip install --no-cache-dir exllamav2==0.0.15 ctransformers

# --- 5. Copy application source code ---
COPY --from=webui-builder /app /app
COPY --from=comfyui-assets /opt/ComfyUI /opt/ComfyUI
COPY --from=text-generation-webui-assets /opt/text-generation-webui /opt/text-generation-webui

# --- 6. Install Text-Gen-WebUI Extensions ---
RUN git clone --depth=1 https://github.com/mamei16/LLM_Web_search.git /opt/text-generation-webui/extensions/LLM_Web_search
RUN --mount=type=cache,target=/root/.cache/pip \
    /opt/venv-textgen/bin/python3 -m pip install --no-cache-dir -r /opt/text-generation-webui/extensions/LLM_Web_search/requirements.txt

# --- 7. Install ComfyUI Custom Nodes (into the ComfyUI venv) ---
RUN cd /opt/ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/was-node-suite-comfyui.git && \
    cd was-node-suite-comfyui && \
    /opt/venv-comfyui/bin/python3 -m pip install --no-cache-dir -r requirements.txt
RUN cd /opt/ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    cd ComfyUI-Manager && \
    /opt/venv-comfyui/bin/python3 -m pip install --no-cache-dir -r requirements.txt

# Pre-install dependencies for common community node packs
RUN --mount=type=cache,target=/root/.cache/pip \
    /opt/venv-comfyui/bin/python3 -m pip install --no-cache-dir ultralytics piexif

# --- 8. Remove VCS metadata to trim image ---
RUN rm -rf /app/.git /opt/ComfyUI/.git /opt/text-generation-webui/.git

# --- Clean up the builder stage to reduce cache size ---
RUN apt-get purge -y --auto-remove build-essential cmake python${PYTHON_VERSION}-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# =====================================================================================
# STAGE 4: The Final Image
# =====================================================================================
FROM nvidia/cuda:12.8.1-base-ubuntu22.04

LABEL org.opencontainers.image.title="Mixed-LLM Stack" \
      org.opencontainers.image.version="1.0" \
      org.opencontainers.image.description="A container running Open WebUI, ComfyUI, and Text-Generation-WebUI."
ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV OLLAMA_MODELS=/workspace/ollama
ENV COMFYUI_MODELS_DIR=/workspace/comfyui
ENV OPENWEBUI_DATA_DIR=/workspace/open-webui
ENV TEXTGEN_DATA_DIR=/workspace/text-generation-webui
ENV TEXTGEN_MODELS_DIR=${TEXTGEN_DATA_DIR}/models
ENV COMFYUI_URL="http://127.0.0.1:8188"
ENV OLLAMA_BASE_URL="http://127.0.0.1:11434"

# --- 1. Install Runtime System Dependencies ---
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    curl supervisor ffmpeg libgomp1 python3.11 nano aria2 rsync git git-lfs iproute2 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 2. Copy ALL Built Assets from the 'builder' Stage ---
COPY --from=builder /opt/venv-webui /opt/venv-webui
COPY --from=builder /opt/venv-comfyui /opt/venv-comfyui
COPY --from=builder /opt/venv-textgen /opt/venv-textgen
COPY --from=builder /app /app
COPY --from=builder /opt/ComfyUI /opt/ComfyUI
COPY --from=builder /opt/text-generation-webui /opt/text-generation-webui
# --- FIX: Copy the compiled tool from its new location inside the correct 'build' directory ---
COPY --from=llama-cpp-builder /llama.cpp/build/bin/llama-gguf-split /usr/local/bin/gguf-split
# Bring in the shared library required by gguf-split and make it discoverable at runtime
COPY --from=llama-cpp-builder /llama.cpp/build/bin/libllama.so* /usr/local/lib/
ENV LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH}
RUN ldconfig


# --- 3. Install Ollama ---
RUN curl -fsSL https://ollama.com/install.sh | sh

# --- 4. Copy Local Config Files and Scripts ---
COPY supervisord.conf /etc/supervisor/conf.d/all-services.conf
COPY entrypoint.sh /entrypoint.sh
COPY sync_models.sh /sync_models.sh
COPY idle_shutdown.sh /idle_shutdown.sh
COPY start_textgenui.sh /start_textgenui.sh
COPY start_comfyui.sh /start_comfyui.sh
COPY extra_model_paths.yaml /etc/comfyui_model_paths.yaml
COPY download_and_join.sh /download_and_join.sh
COPY create_modelfile.sh /create_modelfile.sh
COPY on_demand_model_loader.sh /on_demand_model_loader.sh
COPY download_multi_part.sh /download_multi_part.sh
COPY join_gguf.sh /join_gguf.sh
COPY download_and_join_multipart_gguf.sh /download_and_join_multipart_gguf.sh

# --- Make all scripts executable ---
RUN chmod +x \
    /entrypoint.sh \
    /sync_models.sh \
    /idle_shutdown.sh \
    /start_textgenui.sh \
    /start_comfyui.sh \
    /download_and_join.sh \
    /create_modelfile.sh \
    /on_demand_model_loader.sh \
    /download_multi_part.sh \
    /join_gguf.sh \
    /download_and_join_multipart_gguf.sh


# --- 5. Expose ports and set entrypoint ---
EXPOSE 8080 8188 7860
ENTRYPOINT ["/entrypoint.sh"]
