#!/bin/bash
# SCRIPT V11 - Adds optional verbose logging via $DEBUG and optional file logging ($LOG_FILE).
set -Eeuo pipefail

cd /opt/text-generation-webui || exit 1

# Allow Gradio to access cached uploads like image attachments
export GRADIO_ALLOWED_PATH=/workspace/text-generation-webui
# Clear any preset commandline arg environment variables that may inject unsupported flags
unset COMMANDLINE_ARGS CLI_ARGS

# --- 1. Build Argument Array ---
CMD_ARGS=()

# --- 2. Networking and Base Flags ---
CMD_ARGS+=(--listen --listen-host 0.0.0.0 --listen-port 7860 --api)

# --- 3. Optional Extensions ---
if [ -d "extensions/LLM_Web_search" ]; then
  CMD_ARGS+=(--extensions LLM_Web_search)
fi

# --- 4. Model and LoRA Configuration ---
CMD_ARGS+=(--lora-dir "${TEXTGEN_DATA_DIR:-/workspace}/loras")

if [ -n "${MODEL_NAME:-}" ]; then
  CMD_ARGS+=(--model "$MODEL_NAME")
fi

if [ -n "${LORA_NAMES:-}" ]; then
  IFS=',' read -ra loras <<< "$LORA_NAMES"
  for lora in "${loras[@]}"; do
    CMD_ARGS+=(--lora "$lora")
  done
fi

# --- 5. Optional MoE config ---
if [ -n "${NUM_EXPERTS_PER_TOKEN:-}" ]; then
  CMD_ARGS+=(--num-experts-per-token "$NUM_EXPERTS_PER_TOKEN")
fi

# --- 6. Verbose toggle (ON by default) ---
if [ "${DEBUG:-1}" = "1" ]; then
  CMD_ARGS+=(--verbose)
fi

echo "--- Starting Text-Generation-WebUI with arguments: ---"
printf " %q" "${CMD_ARGS[@]}"
echo -e "\n----------------------------------------------------"

# --- 7. Launch Server (optional file logging) ---
if [ -n "${LOG_FILE:-}" ]; then
  if command -v stdbuf >/dev/null 2>&1; then
    stdbuf -oL -eL /opt/venv-textgen/bin/python3 server.py "${CMD_ARGS[@]}" 2>&1 | tee -a "$LOG_FILE"
  else
    /opt/venv-textgen/bin/python3 server.py "${CMD_ARGS[@]}" 2>&1 | tee -a "$LOG_FILE"
  fi
else
  exec /opt/venv-textgen/bin/python3 server.py "${CMD_ARGS[@]}"
fi
