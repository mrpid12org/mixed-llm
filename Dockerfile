# =====================================================================================
# STAGE 1: The Builder - Installs dependencies and prepares all applications
# =====================================================================================
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04 AS builder

# --- BUILD VERSION IDENTIFIER ---
RUN echo "--- DOCKERFILE VERSION: v4.0-FIXED-SPLIT-BUILD ---"

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_ROOT_USER_ACTION=ignore
ENV PYTHON_VERSION=3.11

# --- 1. Install System Build Dependencies ---
# This combines the essential build tools from your original Dockerfile.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    build-essential \
    aria2 \
    ca-certificates \
    cmake \
    python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-dev \
    python${PYTHON_VERSION}-venv \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 2. Download and Extract the Pre-built Open WebUI Asset ---
# This is the key change: we use the asset you already built instead of building it again.
WORKDIR /app
ARG WEBUI_ARTIFACT_URL
RUN curl -L -o webui.tar.gz "${WEBUI_ARTIFACT_URL}" && \
    tar -xzvf webui.tar.gz && \
    rm webui.tar.gz

# --- 3. Prepare Unified Python Virtual Environment ---
# Restoring the creation of the shared Python environment.
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# --- 4. Install Core Python ML & AI Libraries ---
# Restoring the critical PyTorch installation.
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install --no-cache-dir \
    torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

# --- 5. Clone Other Application Repositories ---
# Restoring the cloning of ComfyUI and text-generation-webui.
WORKDIR /opt
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
RUN git clone https://github.com/oobabooga/text-generation-webui.git

# --- 6. Install All Application Python Dependencies into the venv ---
# Restoring the installation of all Python requirements into the single venv.
RUN python3 -m pip install --no-cache-dir -r /app/backend/requirements.txt -U
RUN python3 -m pip install --no-cache-dir -r /opt/ComfyUI/requirements.txt
RUN python3 -m pip install --no-cache-dir -r /opt/text-generation-webui/requirements/full/requirements.txt
RUN python3 -m pip install --no-cache-dir exllamav2 ctransformers

# --- 7. Recompile llama-cpp-python with CUDA Support ---
# Restoring the GPU-specific compilation for llama.cpp.
RUN ln -s /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/libcuda.so.1
ARG TORCH_CUDA_ARCH_LIST="8.9"
RUN CMAKE_ARGS="-DGGML_CUDA=on" \
    TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST}" \
    python3 -m pip install llama-cpp-python --no-cache-dir --force-reinstall --upgrade

# --- 8. Install ComfyUI Custom Nodes ---
# Restoring the installation of the WAS Node Suite.
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
ENV OLLAMA_MODELS=/workspace/ollama
ENV COMFYUI_MODELS_DIR=/workspace/comfyui
ENV OPENWEBUI_DATA_DIR=/workspace/open-webui
ENV TEXTGEN_DATA_DIR=/workspace/text-generation-webui
ENV TEXTGEN_MODELS_DIR=${TEXTGEN_DATA_DIR}/models
ENV COMFYUI_URL="http://127.0.0.1:8188"
ENV OLLAMA_BASE_URL="http://127.0.0.1:11434"

# --- 1. Install Runtime System Dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    supervisor \
    ffmpeg \
    libgomp1 \
    python3.11 \
    nano \
    aria2 \
    rsync \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 2. Copy ALL Built Assets from 'builder' Stage ---
# This now copies everything needed: the venv, and all three applications.
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
             ${OLLAMA_MODELS} \
             ${COMFYUI_MODELS_DIR} \
             ${OPENWEBUI_DATA_DIR} \
             ${TEXTGEN_DATA_DIR}

# --- 5. Copy Local Config Files and Scripts ---
COPY supervisord.conf /etc/supervisor/conf.d/all-services.conf
COPY entrypoint.sh /entrypoint.sh
COPY sync_models.sh /sync_models.sh
COPY idle_shutdown.sh /idle_shutdown.sh
COPY start_textgenui.sh /start_textgenui.sh
COPY extra_model_paths.yaml /etc/comfyui_model_paths.yaml
COPY download_and_join.sh /usr/local/bin/download_and_join.sh
RUN chmod +x /entrypoint.sh /sync_models.sh /idle_shutdown.sh /start_textgenui.sh /usr/local/bin/download_and_join.sh

# --- 6. Expose ports and set entrypoint ---
EXPOSE 8080 8188 7860
ENTRYPOINT ["/entrypoint.sh"]
