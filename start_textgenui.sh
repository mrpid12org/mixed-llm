#!/bin/bash
# SCRIPT V5 - Updated for isolated venv environment.

cd /opt/text-generation-webui

# --- 1. Build Argument Array ---
CMD_ARGS=()

# --- 2. Networking and Base Flags ---
CMD_ARGS+=(--listen --listen-host 0.0.0.0 --listen-port 7860 --api)

# --- 3. Model and LoRA Configuration ---
CMD_ARGS+=(--lora-dir "${TEXTGEN_DATA_DIR}/loras")

if [ -n "$MODEL_NAME" ]; then
    CMD_ARGS+=(--model "$MODEL_NAME")
fi

if [ -n "$LORA_NAMES" ]; then
    IFS=',' read -ra loras <<< "$LORA_NAMES"
    for lora in "${loras[@]}"; do
        CMD_ARGS+=(--lora "$lora")
    done
fi

# --- 4. Optional MoE config ---
if [ -n "$NUM_EXPERTS_PER_TOKEN" ]; then
    CMD_ARGS+=(--num-experts-per-token "$NUM_EXPERTS_PER_TOKEN")
fi

echo "--- Starting Text-Generation-WebUI with arguments: ---"
printf " %q" "${CMD_ARGS[@]}"
echo -e "\n----------------------------------------------------"

# --- 5. Launch Server ---
# --- FIX: Use the dedicated python from the textgen venv ---
exec /opt/venv-textgen/bin/python3 server.py "${CMD_ARGS[@]}"
