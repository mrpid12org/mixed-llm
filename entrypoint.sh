#!/bin/bash
set -e

echo "--- Clearing previous session logs... ---"
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

COMFYUI_DIRS_TO_PERSIST="animatediff_models animatediff_motion_lora checkpoints clip clip_vision configs controlnet custom_nodes diffusers diffusion_models embeddings gligen hypernetworks ipadapter loras photomaker style_models t5 text_encoders unet upscale_models vae workflows input output"
for dir in $COMFYUI_DIRS_TO_PERSIST; do
    APP_MODEL_PATH="/opt/ComfyUI/models/${dir}"
    if [ "$dir" == "input" ] || [ "$dir" == "output" ] || [ "$dir" == "custom_nodes" ] || [ "$dir" == "workflows" ]; then
      APP_MODEL_PATH="/opt/ComfyUI/${dir}"
    fi
    
    WORKSPACE_PATH="${COMFYUI_MODELS_DIR}/${dir}"

    if [ -d "${APP_MODEL_PATH}" ] && [ ! -L "${APP_MODEL_PATH}" ]; then
        rm -rf "${APP_MODEL_PATH}"
    fi
    
    mkdir -p "${WORKSPACE_PATH}"
    mkdir -p "$(dirname "${APP_MODEL_PATH}")"
    ln -sf "${WORKSPACE_PATH}" "${APP_MODEL_PATH}"
done
echo "--- ComfyUI persistence configured. ---"

# --- 3. Text-Generation-WebUI Persistent Data Setup ---
echo "--- Ensuring Text-Generation-WebUI data is persistent in ${TEXTGEN_DATA_DIR}... ---"
# --- FIX: Reverted to the correct logic of placing all symlinks inside the 'user_data' directory. ---
TEXTGEN_DIRS_TO_PERSIST="characters extensions loras models presets training mmproj logs instruction-templates"
for dir in $TEXTGEN_DIRS_TO_PERSIST; do
    APP_PATH="/opt/text-generation-webui/user_data/${dir}"
    WORKSPACE_PATH="${TEXTGEN_DATA_DIR}/${dir}"

    # Ensure the parent directory for the symlink exists
    mkdir -p "$(dirname "${APP_PATH}")"

    if [ -d "${APP_PATH}" ] && [ ! -L "${APP_PATH}" ]; then
        rm -rf "${APP_PATH}"
    fi
    
    mkdir -p "${WORKSPACE_PATH}"
    ln -sf "${WORKSPACE_PATH}" "${APP_PATH}"
done
echo "--- Text-Generation-WebUI persistence configured. ---"

# --- 4. Start All Services via Supervisor ---
SUPERVISOR_CONF="/etc/supervisor/conf.d/all-services.conf"
if [ ! -f "$SUPERVISOR_CONF" ]; then
    echo "--- FATAL ERROR: Supervisor configuration file not found at $SUPERVISOR_CONF ---"
    exit 1
fi
echo "--- Starting all services via supervisor... ---"
exec /usr/bin/supervisord -c "$SUPERVISOR_CONF"
