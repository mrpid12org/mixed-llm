#!/bin/bash
# SCRIPT V2 - Uses a robust bash array for command arguments, inspired by the original run.sh.
# This script reads environment variables and uses them to launch text-generation-webui with the correct flags.

cd /opt/text-generation-webui

# --- 1. Build Argument Array ---
# This is a safer way to build commands, especially if variables contain spaces.
CMD_ARGS=()

# --- 2. Networking and Base Flags ---
CMD_ARGS+=(--listen --listen-host 0.0.0.0 --listen-port 7860 --api --now-ui)

# --- 3. Model and LoRA Configuration ---
CMD_ARGS+=(--models-dir "${TEXTGEN_MODELS_DIR}" --lora-dir "${TEXTGEN_MODELS_DIR}/loras")

if [ -n "$MODEL_NAME" ]; then
    CMD_ARGS+=(--model "$MODEL_NAME")
fi

if [ -n "$LORA_NAMES" ]; then
    # Handles comma-separated LoRA names
    IFS=',' read -ra loras <<< "$LORA_NAMES"
    for lora in "${loras[@]}"; do
        CMD_ARGS+=(--lora "$lora")
    done
fi

# --- 4. Optional MoE config ---
if [ -n "$NUM_EXPERTS_PER_TOKEN" ]; then
    CMD_ARGS+=(--num-experts-per-token "$NUM_EXPERTS_PER_TOKEN")
fi

# --- 5. Feature Flags ---
if [[ "$ENABLE_MULTIMODAL" == "true" || "$ENABLE_MULTIMODAL" == "TRUE" ]]; then
    CMD_ARGS+=(--multimodal)
fi

# The HUGGING_FACE_HUB_TOKEN is automatically read from the environment by the Hugging Face library.

echo "--- Starting Text-Generation-WebUI with arguments: ---"
printf " %q" "${CMD_ARGS[@]}"
echo "\n----------------------------------------------------"

# --- 6. Launch Server ---
# Using "${CMD_ARGS[@]}" ensures each argument is passed as a separate, correctly-quoted string.
exec python3 server.py "${CMD_ARGS[@]}"
