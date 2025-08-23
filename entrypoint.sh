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
# Link the model paths configuration file
ln -sf /etc/comfyui_model_paths.yaml "/opt/ComfyUI/extra_model_paths.yaml"

# Symlink important data directories to the workspace
COMFYUI_DIRS_TO_PERSIST="input output custom_nodes workflows"
for dir in $COMFYUI_DIRS_TO_PERSIST; do
    # If the directory exists in the app and is not a link, remove it
    if [ -d "/opt/ComfyUI/${dir}" ] && [ ! -L "/opt/ComfyUI/${dir}" ]; then
        rm -rf "/opt/ComfyUI/${dir}"
    fi
    # Create the directory in the persistent volume
    mkdir -p "${COMFYUI_MODELS_DIR}/${dir}"
    # Create the symlink from the app to the persistent volume
    ln -sf "${COMFYUI_MODELS_DIR}/${dir}" "/opt/ComfyUI/${dir}"
done
echo "--- ComfyUI persistence configured. ---"

# --- 3. Text-Generation-WebUI Persistent Data Setup ---
echo "--- Ensuring Text-Generation-WebUI data is persistent in ${TEXTGEN_DATA_DIR}... ---"
TEXTGEN_DIRS_TO_PERSIST="characters extensions loras models presets prompts training"
for dir in $TEXTGEN_DIRS_TO_PERSIST; do
    if [ -d "/opt/text-generation-webui/${dir}" ] && [ ! -L "/opt/text-generation-webui/${dir}" ]; then
        rm -rf "/opt/text-generation-webui/${dir}"
    fi
    mkdir -p "${TEXTGEN_DATA_DIR}/${dir}"
    ln -sf "${TEXTGEN_DATA_DIR}/${dir}" "/opt/text-generation-webui/${dir}"
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
