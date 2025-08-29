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

# --- 2. Text-Generation-WebUI Persistent Data Setup ---
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
