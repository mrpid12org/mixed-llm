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

# --- FIX: Added all model and workflow directories to the persistence list ---
COMFYUI_DIRS_TO_PERSIST="input output custom_nodes workflows checkpoints unet vae clip loras t5 controlnet embeddings hypernetworks style_models upscale_models gligen"
for dir in $COMFYUI_DIRS_TO_PERSIST; do
    # Remove the original directory in the container if it exists and is not a symlink
    if [ -d "/opt/ComfyUI/models/${dir}" ] && [ ! -L "/opt/ComfyUI/models/${dir}" ]; then
        rm -rf "/opt/ComfyUI/models/${dir}"
    fi
    # Create the target directory in the persistent volume
    mkdir -p "${COMFYUI_MODELS_DIR}/${dir}"
    # Create the symlink from the container to the persistent volume
    ln -sf "${COMFYUI_MODELS_DIR}/${dir}" "/opt/ComfyUI/models/${dir}"
done
echo "--- ComfyUI persistence configured. ---"

# --- 3. Text-Generation-WebUI Persistent Data Setup ---
echo "--- Ensuring Text-Generation-WebUI data is persistent in ${TEXTGEN_DATA_DIR}... ---"
TEXTGEN_DIRS_TO_PERSIST="characters extensions loras models presets training mmproj logs instruction-templates"
for dir in $TEXTGEN_DIRS_TO_PERSIST; do
    APP_PATH="/opt/text-generation-webui/${dir}"
    # --- FIX: For 'models', the user data symlink should go into a 'user_data' subdir to avoid conflict ---
    if [ "$dir" == "models" ]; then
      APP_PATH="/opt/text-generation-webui/user_data/models"
    fi

    WORKSPACE_PATH="${TEXTGEN_DATA_DIR}/${dir}"

    if [ -d "${APP_PATH}" ] && [ ! -L "${APP_PATH}" ]; then
        rm -rf "${APP_PATH}"
    fi
    # Create parent directory if it doesn't exist
    mkdir -p "$(dirname "${APP_PATH}")"
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
