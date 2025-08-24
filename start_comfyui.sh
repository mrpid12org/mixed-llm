#!/bin/bash
# SCRIPT V1 - Toggles FlashAttention based on an environment variable.

# 1. Start with the base command as an array for safety
CMD_ARGS=("/opt/venv-comfyui/bin/python3" "main.py" "--listen" "0.0.0.0" "--port" "8188" "--preview-method" "auto" "--extra-model-paths-config" "/etc/comfyui_model_paths.yaml")

# 2. Check the environment variable. Default to 'true' if not set.
if [[ "${COMFYUI_USE_FLASH_ATTENTION:-true}" == "true" ]]; then
  echo "--- FlashAttention is ENABLED for ComfyUI ---"
  CMD_ARGS+=("--use-flash-attention")
else
  echo "--- FlashAttention is DISABLED for ComfyUI ---"
fi

# 3. Execute the final command
echo "--- Launching ComfyUI with arguments: ${CMD_ARGS[*]} ---"
exec "${CMD_ARGS[@]}"
