# =====================================================================================
# STAGE 1: The Builder - Installs all dependencies and builds applications
# =====================================================================================
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04 AS builder

# --- BUILD VERSION IDENTIFIER ---
RUN echo "--- DOCK-ERFILE VERSION: v1.7-MERGED-STACK (Tiptap Fix) ---"

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_ROOT_USER_ACTION=ignore
ENV PYTHON_VERSION=3.11

# --- 1. Install System Build Dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    build-essential \
    aria2 \
    ca-certificates \
    gnupg \
    cmake \
    python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-dev \
    python${PYTHON_VERSION}-venv \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && NODE_MAJOR=20 \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install nodejs -y \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 2. Build Open WebUI Frontend ---
WORKDIR /app
# --- CHANGE: Updated Open WebUI version to v0.6.23 ---
RUN git clone --depth 1 --branch v0.6.23 https://github.com/open-webui/open-webui.git .
# Use a higher memory limit for the Node.js build process.
# --- FIX: Added explicit installation for @tiptap/suggestion dependency ---
RUN NODE_OPTIONS="--max-old-space-size=8192" npm install --legacy-peer-deps && \
    npm install lowlight --legacy-peer-deps && \
    npm install y-protocols --legacy-peer-deps && \
    npm install @tiptap/suggestion --legacy-peer-deps && \
    npm run build && \
    npm cache clean --force && \
    rm -rf node_modules

# --- 3. Prepare Unified Python Virtual Environment ---
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# --- 4. Install Core Python ML & AI Libraries ---
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install --no-cache-dir \
        torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

# --- 5. Clone Application Repositories ---
WORKDIR /opt
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
RUN git clone https://github.com/oobabooga/text-generation-webui.git

# --- 6. Install All Application Python Dependencies into the venv ---
RUN python3 -m pip install --no-cache-dir -r /app/backend/requirements.txt -U
RUN python3 -m pip install --no-cache-dir -r /opt/ComfyUI/requirements.txt
RUN python3 -m pip install --no-cache-dir -r /opt/text-generation-webui/requirements.txt
RUN python3 -m pip install --no-cache-dir exllamav2 ctransformers

# --- 7. TACTIC: Recompile llama-cpp-python with CUDA support ---
# This ensures optimal performance for GGUF models in Text-Generation-WebUI.
RUN CMAKE_ARGS="-DGGML_CUDA=on -DCMAKE_CUDA_ARCHITECTURES=all" \
    python3 -m pip install llama-cpp-python --no-cache-dir --force-reinstall --upgrade

# --- 8. Install ComfyUI Custom Nodes ---
RUN cd /opt/ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/was-node-suite-comfyui.git && \
    cd was-node-suite-comfyui && \
    python3 -m pip install --no-cache-dir -r requirements.txt

# =====================================================================================
# STAGE 2: The Final Image - Lean and optimized for production
# =====================================================================================
FROM nvidia/cuda:12.8.1-base-ubuntu22.04

# --- Set all environment variables ---
ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV PATH="/opt/venv/bin:$PATH"
# Configure paths for persistent storage
ENV OLLAMA_MODELS=/workspace/ollama-models
ENV COMFYUI_MODELS_DIR=/workspace/comfyui-models
ENV TEXTGEN_MODELS_DIR=/workspace/textgen-models
# Make apps aware of each other
ENV COMFYUI_URL="http://12_7_0_0_1:8188"
ENV OLLAMA_BASE_URL="http://12_7_0_0_1:11434"

# --- 1. Install Runtime System Dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    supervisor \
    ffmpeg \
    libgomp1 \
    python3.11 \
    nano \
    aria2 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 2. Copy Built Assets from 'builder' Stage ---
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app/backend /app/backend
COPY --from=builder /app/build /app/build
COPY --from=builder /app/CHANGELOG.md /app/CHANGELOG.md
COPY --from=builder /opt/ComfyUI /opt/ComfyUI
COPY --from=builder /opt/text-generation-webui /opt/text-generation-webui

# --- 3. Install Ollama ---
RUN curl -fsSL https://ollama.com/install.sh | sh

# --- 4. Create Directories for Persistent Data ---
RUN mkdir -p /workspace/logs \
             /workspace/webui-data \
             ${OLLAMA_MODELS} \
             ${COMFYUI_MODELS_DIR} \
             ${TEXTGEN_MODELS_DIR}

# --- 5. Copy Local Config Files and Scripts ---
COPY supervisord.conf /etc/supervisor/conf.d/all-services.conf
COPY entrypoint.sh /entrypoint.sh
COPY sync_models.sh /sync_models.sh
COPY idle_shutdown.sh /idle_shutdown.sh
COPY extra_model_paths.yaml /etc/comfyui_model_paths.yaml
COPY download_and_join.sh /usr/local/bin/download_and_join.sh
COPY start_textgenui.sh /start_textgenui.sh

# --- 6. Set Permissions ---
RUN chmod +x /entrypoint.sh /sync_models.sh /idle_shutdown.sh /usr/local/bin/download_and_join.sh /start_textgenui.sh

# --- 7. Expose Ports and Set Entrypoint ---
EXPOSE 8080 8188 7860 11434
ENTRYPOINT ["/entrypoint.sh"]
