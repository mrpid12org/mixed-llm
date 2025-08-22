#!/bin/bash
set -e

echo "--- Clearing previous session logs... ---"
mkdir -p /workspace/logs
rm -f /workspace/logs/*

# --- 1. Open WebUI Persistent Data Setup ---
WEBUI_DATA_DIR="/app/backend/data"
PERSISTENT_WEBUI_DIR="/workspace/webui-data"
echo "--- Ensuring Open WebUI data is persistent... ---"
mkdir -p "$PERSISTENT_WEBUI_DIR"
if [ -d "$WEBUI_DATA_DIR" ] && [ ! -L "$WEBUI_DATA_DIR" ]; then
  echo "First run detected for Open WebUI. Migrating default data..."
  # Use rsync to handle cases where the destination already has some files.
  rsync -a "$WEBUI_DATA_DIR/" "$PERSISTENT_WEBUI_DIR/"
  rm -rf "$WEBUI_DATA_DIR"
fi
if [ ! -L "$WEBUI_DATA_DIR" ]; then
  echo "Linking $PERSISTENT_WEBUI_DIR to $WEBUI_DATA_DIR..."
  ln -s "$PERSISTENT_WEBUI_DIR" "$WEBUI_DATA_DIR"
fi
echo "--- Open WebUI persistence configured. ---"

# --- 2. ComfyUI Model Path Setup ---
COMFYUI_MODEL_PATHS_FILE="/opt/ComfyUI/extra_model_paths.yaml"
PERSISTENT_COMFYUI_PATHS_FILE="${COMFYUI_MODELS_DIR}/extra_model_paths.yaml"
echo "--- Ensuring ComfyUI model paths are persistent... ---"
mkdir -p "$COMFYUI_MODELS_DIR"
if [ ! -f "$PERSISTENT_COMFYUI_PATHS_FILE" ]; then
    echo "Copying default model paths config for ComfyUI..."
    cp /etc/comfyui_model_paths.yaml "$PERSISTENT_COMFYUI_PATHS_FILE"
fi
# Always link the persistent config into the ComfyUI directory
ln -sf "$PERSISTENT_COMFYUI_PATHS_FILE" "$COMFYUI_MODEL_PATHS_FILE"
echo "--- ComfyUI model paths configured. ---"


# --- 3. Start All Services via Supervisor ---
SUPERVISOR_CONF="/etc/supervisor/conf.d/all-services.conf"
if [ ! -f "$SUPERVISOR_CONF" ]; then
    echo "--- FATAL ERROR: Supervisor configuration file not found at $SUPERVISOR_CONF ---"
    exit 1
fi
echo "--- Starting all services via supervisor... ---"
exec /usr/bin/supervisord -c "$SUPERVISOR_CONF"
