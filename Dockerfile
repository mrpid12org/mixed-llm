# --- BUILD VERSION IDENTIFIER ---
# v8.4-LLM-WEB-SEARCH

# =====================================================================================
# STAGE 1: Asset Fetching
# =====================================================================================
FROM alpine/git:latest AS openwebui-assets
RUN apk add --no-cache curl
WORKDIR /app
RUN git clone --depth=1 --branch v0.6.23 https://github.com/open-webui/open-webui.git .
RUN curl -L -o /app/CHANGELOG.md https://raw.githubusercontent.com/open-webui/open-webui/v0.6.23/CHANGELOG.md

FROM alpine/git:latest AS comfyui-assets
WORKDIR /opt
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

FROM alpine/git:latest AS text-generation-webui-assets
WORKDIR /opt
RUN git clone https://github.com/oobabooga/text-generation-webui.git

# =====================================================================================
# STAGE 2: Web UI Asset Builder
# =====================================================================================
FROM node:20-bookworm AS webui-builder
WORKDIR /app
COPY --from=openwebui-assets /app /app
RUN npm install --legacy-peer-deps && \
    npm install @tiptap/suggestion --legacy-peer-deps && \
    npm install lowlight --legacy-peer-deps && \
    npm install y-protocols --legacy-peer-deps
RUN npm run build

# =====================================================================================
# STAGE 3: Python Builder with Isolated Environments
# =====================================================================================
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_ROOT_USER_ACTION=ignore
ENV PYTHON_VERSION=3.11

# --- 1. Install System Build Dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl build-essential aria2 cmake python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-venv \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 2. Copy all application assets ---
COPY --from=webui-builder /app /app
COPY --from=comfyui-assets /opt/ComfyUI /opt/ComfyUI
COPY --from=text-generation-webui-assets /opt/text-generation-webui /opt/text-generation-webui

# --- 3. Install Text-Gen-WebUI Extensions ---
RUN git clone https://github.com/mamei16/LLM_Web_search.git /opt/text-generation-webui/extensions/LLM_Web_search

# --- 4. Create and Install Dependencies for ISOLATED Environments ---
RUN python3 -m venv /opt/venv-webui
RUN python3 -m venv /opt/venv-comfyui
RUN python3 -m venv /opt/venv-textgen

# Install Open WebUI dependencies
RUN /opt/venv-webui/bin/python3 -m pip install --upgrade pip
RUN /opt/venv-webui/bin/python3 -m pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
RUN /opt/venv-webui/bin/python3 -m pip install --no-cache-dir -r /app/backend/requirements.txt -U

# Install ComfyUI dependencies
RUN /opt/venv-comfyui/bin/python3 -m pip install --upgrade pip wheel setuptools
RUN /opt/venv-comfyui/bin/python3 -m pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
RUN /opt/venv-comfyui/bin/python3 -m pip install --no-cache-dir -r /opt/ComfyUI/requirements.txt
RUN /opt/venv-comfyui/bin/python3 -m pip install --no-cache-dir --force-reinstall --no-build-isolation flash-attn GitPython

# Install Text-Generation-WebUI dependencies
RUN /opt/venv-textgen/bin/python3 -m pip install --upgrade pip
RUN /opt/venv-textgen/bin/python3 -m pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
RUN /opt/venv-textgen/bin/python3 -m pip install --no-cache-dir -r /opt/text-generation-webui/requirements/full/requirements.txt
RUN /opt/venv-textgen/bin/python3 -m pip install --no-cache-dir exllamav2==0.0.15 ctransformers
# --- FIX: Install the requirements for the web search extension ---
RUN /opt/venv-textgen/bin/python3 -m pip install --no-cache-dir -r /opt/text-generation-webui/extensions/LLM_Web_search/requirements.txt


# --- 5. Install ComfyUI Custom Nodes (into the ComfyUI venv) ---
RUN cd /opt/ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/was-node-suite-comfyui.git && \
    cd was-node-suite-comfyui && \
    /opt/venv-comfyui/bin/python3 -m pip install --no-cache-dir -r requirements.txt
RUN cd /opt/ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    cd ComfyUI-Manager && \
    /opt/venv-comfyui/bin/python3 -m pip install --no-cache-dir -r requirements.txt

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
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl supervisor ffmpeg libgomp1 python3.11 nano aria2 rsync git \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 2. Copy ALL Built Assets from the 'builder' Stage ---
COPY --from=builder /opt/venv-webui /opt/venv-webui
COPY --from=builder /opt/venv-comfyui /opt/venv-comfyui
COPY --from=builder /opt/venv-textgen /opt/venv-textgen
COPY --from=builder /app /app
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
COPY start_comfyui.sh /start_comfyui.sh
COPY extra_model_paths.yaml /etc/comfyui_model_paths.yaml
COPY download_and_join.sh /download_and_join.sh
COPY create_modelfile.sh /create_modelfile.sh
# --- FIX: Added the missing script file ---
COPY on_demand_model_loader.sh /on_demand_model_loader.sh
# --- FIX: Made the new script executable ---
RUN chmod +x /entrypoint.sh /sync_models.sh /idle_shutdown.sh /start_textgenui.sh /start_comfyui.sh /download_and_join.sh /create_modelfile.sh /on_demand_model_loader.sh

# --- 5. Expose ports and set entrypoint ---
EXPOSE 8080 8188 7860
ENTRYPOINT ["/entrypoint.sh"]
