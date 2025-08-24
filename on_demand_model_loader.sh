#!/bin/bash
# SCRIPT V1.2 - Added cleanup step for temporary files
set -e

# --- Configuration ---
MODEL_NAME_TO_CHECK="Huihui-gpt-oss-120b-BF16-abliterated.i1-Q4_K_S"
MODEL_DOWNLOAD_URL="https://huggingface.co/mradermacher/Huihui-gpt-oss-120b-BF16-abliterated-i1-GGUF/resolve/main/Huihui-gpt-oss-120b-BF16-abliterated.i1-Q4_K_S.gguf.part1of2"
WORK_DIR="/workspace/temp_gguf"

echo "====================================================================="
echo "--- On-Demand Model Loader (v1.2) ---"
echo "====================================================================="

# Give the Ollama server time to start up properly.
sleep 45

# --- 1. Check if the final model already exists in Ollama ---
echo "[INFO] Checking for existence of model containing '${MODEL_NAME_TO_CHECK}'..."
if ollama list | grep -q "${MODEL_NAME_TO_CHECK}"; then
  echo "--- Model already exists. Skipping download and creation. ---"
else
  echo "--- Model not found. Starting download and creation process... ---"
  
  # --- 2. Download and Join the Model Parts ---
  echo "[INFO] Calling download_and_join.sh script..."
  /download_and_join.sh "${MODEL_DOWNLOAD_URL}"
  
  # --- 3. Create the Modelfile ---
  echo "[INFO] Calling create_modelfile.sh script..."
  /create_modelfile.sh
  
  # --- 4. Create the model in Ollama ---
  MODELFILE_TO_CREATE=$(ls -t "$WORK_DIR"/*.Modelfile 2>/dev/null | head -n 1)
  if [ -z "$MODELFILE_TO_CREATE" ]; then
      echo "--- ERROR: No .Modelfile found in $WORK_DIR after script execution. ---"
      exit 1
  fi
  
  echo "[INFO] Creating model in Ollama from ${MODELFILE_TO_CREATE}..."
  cd "$WORK_DIR"
  ollama create "${MODEL_NAME_TO_CHECK}" -f "${MODELFILE_TO_CREATE}"
  echo "--- Ollama model creation complete. ---"

  # --- 5. Clean up temporary files ---
  echo "[INFO] Cleaning up temporary GGUF and Modelfile from ${WORK_DIR}..."
  rm -f "${WORK_DIR}"/*
  echo "--- Cleanup complete. ---"
fi

# --- 6. Run the main sync_models.sh script ---
echo "[INFO] All checks complete. Proceeding with sync_models.sh... ---"
exec /sync_models.sh
