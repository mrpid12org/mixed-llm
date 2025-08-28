#!/bin/bash
# SCRIPT V2 - Added explicit directory flags to ensure correct paths.

# --- 1. Base command with new directory arguments ---
# These flags force ComfyUI to use the correct symlinked paths for user data.
CMD_ARGS=(
    "/opt/venv-comfyui/bin/python3" "main.py" \
    "--listen" "0.0.0.0" \
    "--port" "8188" \
    "--preview-method" "auto" \
    "--extra-model-paths-config" "/opt/ComfyUI/extra_model_paths.yaml" \
    "--input-directory" "/opt/ComfyUI/input" \
    "--output-directory" "/opt/ComfyUI/output"
)

# --- 2. Check the environment variable for FlashAttention ---
if [[ "${COMFYUI_USE_FLASH_ATTENTION:-true}" == "true" ]]; then
  echo "--- FlashAttention is ENABLED for ComfyUI ---"
  CMD_ARGS+=("--use-flash-attention")
else
  echo "--- FlashAttention is DISABLED for ComfyUI ---"
fi

# --- 3. Execute the final command ---
echo "--- Launching ComfyUI with arguments: ${CMD_ARGS[*]} ---"
exec "${CMD_ARGS[@]}"
