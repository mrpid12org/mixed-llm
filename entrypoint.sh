#!/bin/bash
set -e

echo "--- Clearing previous session logs... ---"
mkdir -p /workspace/logs
rm -f /workspace/logs/*

# --- 1. Open WebUI Persistent Data Setup ---
WEBUI_INTERNAL_DATA_DIR="/app/backend/data"
echo "--- Ensuring Open WebUI data is persistent in ${OPENWEBUI_DATA_DIR}... ---"
mkdir -p "${OPENWEBUI_DATA_DIR}"
if [ -d "$WEBUI_INTERNAL_DATA_DIR" ] && [ ! -L "$WEBUI_INTERNAL_DATA_DIR" ]; then
  echo "First run detected for Open WebUI. Migrating default data..."
  rsync -a "$WEBUI_INTERNAL_DATA_DIR/" "${OPENWEBUI_DATA_DIR}/"
  rm -rf "$WEBUI_INTERNAL_DATA_DIR"
fi
if [ ! -L "$WEBUI_INTERNAL_DATA_DIR" ]; then
  ln -s "${OPENWEBUI_DATA_DIR}" "$WEBUI_INTERNAL_DATA_DIR"
fi
echo "--- Open WebUI persistence configured. ---"

# --- 2. ComfyUI Model Path Setup ---
COMFYUI_MODEL_PATHS_FILE="/opt/ComfyUI/extra_model_paths.yaml"
echo "--- Ensuring ComfyUI is using the correct model path config... ---"
ln -sf /etc/comfyui_model_paths.yaml "$COMFYUI_MODEL_PATHS_FILE"
echo "--- ComfyUI model paths configured. ---"

# --- 3. Text-Generation-WebUI Persistent Data Setup (from parent build) ---
TEXTGEN_APP_DIR="/opt/text-generation-webui"
echo "--- Ensuring Text-Generation-WebUI data is persistent in ${TEXTGEN_DATA_DIR}... ---"
TEXTGEN_DIRS_TO_PERSIST="characters extensions loras models presets prompts training"
for dir in $TEXTGEN_DIRS_TO_PERSIST; do
    if [ -d "${TEXTGEN_APP_DIR}/${dir}" ] && [ ! -L "${TEXTGEN_APP_DIR}/${dir}" ]; then
        rm -rf "${TEXTGEN_APP_DIR}/${dir}"
    fi
    mkdir -p "${TEXTGEN_DATA_DIR}/${dir}"
    ln -sf "${TEXTGEN_DATA_DIR}/${dir}" "${TEXTGEN_APP_DIR}/${dir}"
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
