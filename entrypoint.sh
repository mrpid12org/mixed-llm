#!/bin/bash
set -e

# --- FIX: Set correct permissions for the workspace directory ---
echo "--- Ensuring correct workspace permissions... ---"
chown -R root:root /workspace
echo "--- Permissions set. ---"

echo "--- Clearing previous session logs... ---"
rm -f /workspace/logs/*
mkdir -p /workspace/logs

# --- Ensure ALL persistent directories are created at startup ---
echo "--- Ensuring base persistent directories exist... ---"
mkdir -p "${OLLAMA_MODELS}"
mkdir -p "${COMFYUI_MODELS_DIR}"
mkdir -p "${OPENWEBUI_DATA_DIR}"
mkdir -p "${TEXTGEN_DATA_DIR}"
mkdir -p "/workspace/temp_gguf"

# --- 1. Open WebUI Persistent Data Setup ---
echo "--- Ensuring Open WebUI data is persistent in ${OPENWEBUI_DATA_DIR}... ---"
if [ -d "/app/backend/data" ] && [ ! -L "/app/backend/data" ]; then
  echo "First run detected for Open WebUI. Migrating default data..."
  rsync -a "/app/backend/data/" "${OPENWEBUI_DATA_DIR}/"
  rm -rf "/app/backend/data"
fi
if [ ! -L "/app/backend/data" ]; then
  ln -s "${OPENWEBUI_DATA_DIR}" "/app/backend/data"
fi
echo "--- Open WebUI persistence configured. ---"

# --- 2. ComfyUI Persistence Setup ---
echo "--- Ensuring ComfyUI data is persistent... ---"
ln -sf /etc/comfyui_model_paths.yaml "/opt/ComfyUI/extra_model_paths.yaml"

# Define which directories are in the root of /opt/ComfyUI vs. in /opt/ComfyUI/models
ROOT_DIRS="input output custom_nodes workflows"
MODEL_SUBDIRS="animatediff_models animatediff_motion_lora checkpoints clip clip_vision configs controlnet diffusers diffusion_models embeddings gligen hypernetworks ipadapter loras photomaker style_models t5 text_encoders unet upscale_models vae"

# Process root directories
for dir in $ROOT_DIRS; do
    APP_PATH="/opt/ComfyUI/${dir}"
    WORKSPACE_PATH="${COMFYUI_MODELS_DIR}/${dir}"

    mkdir -p "${WORKSPACE_PATH}"
    chown -R root:root "${WORKSPACE_PATH}"

    if [ "$dir" == "custom_nodes" ] && [ -d "${APP_PATH}" ] && [ ! -L "${APP_PATH}" ] && [ -n "$(ls -A "${APP_PATH}")" ]; then
        echo "--- Migrating pre-installed ComfyUI custom nodes to workspace... ---"
        rsync -a --chown=root:root "${APP_PATH}/" "${WORKSPACE_PATH}/"
    fi

    rm -rf "${APP_PATH}"
    ln -sf "${WORKSPACE_PATH}" "${APP_PATH}"
done

# Process model subdirectories
for dir in $MODEL_SUBDIRS; do
    APP_PATH="/opt/ComfyUI/models/${dir}"
    WORKSPACE_PATH="${COMFYUI_MODELS_DIR}/${dir}"

    mkdir -p "${WORKSPACE_PATH}"
    chown -R root:root "${WORKSPACE_PATH}"

    rm -rf "${APP_PATH}"
    ln -sf "${WORKSPACE_PATH}" "${APP_PATH}"
done
echo "--- ComfyUI persistence configured. ---"


# --- 3. Text-Generation-WebUI Persistent Data Setup (FIXED) ---
echo "--- Ensuring Text-Generation-WebUI data is persistent in ${TEXTGEN_DATA_DIR}... ---"
APP_USER_DATA_PATH="/opt/text-generation-webui/user_data"
WORKSPACE_PATH="${TEXTGEN_DATA_DIR}"

# Ensure all expected subdirectories exist in the persistent volume first
TEXTGEN_DIRS_TO_PERSIST="characters extensions loras models presets training mmproj logs instruction-templates"
for dir in $TEXTGEN_DIRS_TO_PERSIST; do
    mkdir -p "${WORKSPACE_PATH}/${dir}"
done

# Remove the original user_data directory and link the entire persistent data directory to it
rm -rf "${APP_USER_DATA_PATH}"
ln -s "${WORKSPACE_PATH}" "${APP_USER_DATA_PATH}"
echo "--- Text-Generation-WebUI persistence configured. ---"


# --- 4. Start All Services via Supervisor ---
SUPERVISOR_CONF="/etc/supervisor/conf.d/all-services.conf"
if [ ! -f "$SUPERVISOR_CONF" ]; then
    echo "--- FATAL ERROR: Supervisor configuration file not found at $SUPERVISOR_CONF ---"
    exit 1
fi
echo "--- Starting all services via supervisor... ---"
exec /usr/bin/supervisord -c "$SUPERVISOR_CONF"
