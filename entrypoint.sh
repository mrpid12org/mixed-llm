#!/bin/bash
set -e

# --- Set correct permissions for the workspace directory ---
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

# --- NEW: Persist ComfyUI virtual environment to workspace ---
COMFYUI_VENV_PATH="/opt/venv-comfyui"
COMFYUI_VENV_PERSIST="/workspace/comfyui/venv"
# On the very first run (when the persistent venv doesn't exist), move the built venv into storage.
if [ ! -d "${COMFYUI_VENV_PERSIST}" ]; then
    if [ -d "${COMFYUI_VENV_PATH}" ]; then
        echo "--- First run: Moving ComfyUI venv to persistent storage... ---"
        mv "${COMFYUI_VENV_PATH}" "${COMFYUI_VENV_PERSIST}"
    fi
fi
# For ALL runs, ensure the symlink from the app dir to the persistent venv is in place.
rm -rf "${COMFYUI_VENV_PATH}"
ln -s "${COMFYUI_VENV_PERSIST}" "${COMFYUI_VENV_PATH}"

# Ensure required ComfyUI node dependencies exist in the persistent venv
COMFYUI_PIP="${COMFYUI_VENV_PATH}/bin/pip"
COMFYUI_PY="${COMFYUI_VENV_PATH}/bin/python3"
if ! "${COMFYUI_PY}" -c "import sam2" >/dev/null 2>&1; then
    echo "--- Installing Impact Pack dependencies into ComfyUI venv ---"
    if ! "${COMFYUI_PIP}" install --no-cache-dir --no-deps \
        ultralytics piexif dill \
        'git+https://github.com/facebookresearch/segment-anything.git' \
        'git+https://github.com/facebookresearch/sam2'; then
        echo "Warning: Failed to install optional Impact Pack dependencies" >&2
    fi
fi


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

ROOT_DIRS="input output custom_nodes workflows"
MODEL_SUBDIRS="animatediff_models animatediff_motion_lora checkpoints clip clip_vision configs controlnet diffusers diffusion_models embeddings gligen hypernetworks ipadapter loras photomaker style_models t5 text_encoders unet upscale_models vae"

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

for dir in $MODEL_SUBDIRS; do
    APP_PATH="/opt/ComfyUI/models/${dir}"
    WORKSPACE_PATH="${COMFYUI_MODELS_DIR}/${dir}"
    mkdir -p "${WORKSPACE_PATH}"
    chown -R root:root "${WORKSPACE_PATH}"
    rm -rf "${APP_PATH}"
    ln -sf "${WORKSPACE_PATH}" "${APP_PATH}"
done
echo "--- ComfyUI persistence configured. ---"

# --- 3. Text-Generation-WebUI Persistent Data Setup ---
echo "--- Ensuring Text-Generation-WebUI data is persistent in ${TEXTGEN_DATA_DIR}... ---"
APP_USER_DATA_PATH="/opt/text-generation-webui/user_data"
# On first run, copy the default user_data to the persistent volume
if [ -d "${APP_USER_DATA_PATH}" ] && [ ! -L "${APP_USER_DATA_PATH}" ]; then
    echo "First run detected for TextGenUI. Migrating default user data..."
    # Ensure the target directory exists before copying
    mkdir -p "${TEXTGEN_DATA_DIR}"
    rsync -a "${APP_USER_DATA_PATH}/" "${TEXTGEN_DATA_DIR}/"
    rm -rf "${APP_USER_DATA_PATH}"
fi
# Ensure the symlink exists for all subsequent runs
if [ ! -L "${APP_USER_DATA_PATH}" ]; then
    # Create the final symlink
    ln -s "${TEXTGEN_DATA_DIR}" "${APP_USER_DATA_PATH}"
fi
echo "--- Text-Generation-WebUI persistence configured. ---"

# --- 4. Start All Services via Supervisor ---
SUPERVISOR_CONF="/etc/supervisor/conf.d/all-services.conf"
if [ ! -f "$SUPERVISOR_CONF" ]; then
    echo "--- FATAL ERROR: Supervisor configuration file not found at $SUPERVISOR_CONF ---"
    exit 1
fi
echo "--- Starting all services via supervisor... ---"
exec /usr/bin/supervisord -c "$SUPERVISOR_CONF"
