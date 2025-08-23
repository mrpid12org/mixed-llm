#!/bin/bash
# SCRIPT V3 - Activates the correct Conda environment before launch.

# --- 1. Activate Conda Environment ---
# This is the critical missing step. It sets up the correct Python and libraries.
source /opt/conda/etc/profile.d/conda.sh
conda activate /opt/conda/envs/textgen

cd /opt/text-generation-webui

# --- 2. Build Argument Array ---
CMD_ARGS=()

# --- 3. Networking and Base Flags ---
CMD_ARGS+=(--listen --listen-host 0.0.0.0 --listen-port 7860 --api --now-ui)

# --- 4. Model and LoRA Configuration ---
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

# --- 5. Optional MoE config ---
if [ -n "$NUM_EXPERTS_PER_TOKEN" ]; then
    CMD_ARGS+=(--num-experts-per-token "$NUM_EXPERTS_PER_TOKEN")
fi

# --- 6. Feature Flags ---
if [[ "$ENABLE_MULTIMODAL" == "true" || "$ENABLE_MULTIMODAL" == "TRUE" ]]; then
    CMD_ARGS+=(--multimodal)
fi

echo "--- Starting Text-Generation-WebUI with arguments: ---"
printf " %q" "${CMD_ARGS[@]}"
echo -e "\n----------------------------------------------------"

# --- 7. Launch Server ---
exec python server.py "${CMD_ARGS[@]}"
