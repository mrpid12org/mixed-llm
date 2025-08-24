#!/bin/bash
# SCRIPT V1.1 - Updated with correct abliterated model URL
set -e

# --- Configuration ---
# --- FIX: Updated to the correct model name and URL ---
MODEL_NAME_TO_CHECK="Huihui-gpt-oss-120b-BF16-abliterated.i1-Q4_K_S"
MODEL_DOWNLOAD_URL="https://huggingface.co/mradermacher/Huihui-gpt-oss-120b-BF16-abliterated-i1-GGUF/resolve/main/Huihui-gpt-oss-120b-BF16-abliterated.i1-Q4_K_S.gguf.part1of2"
WORK_DIR="/workspace/temp_gguf"

echo "====================================================================="
echo "--- On-Demand Model Loader (v1.1) ---"
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
  # Find the generated Modelfile to use with the create command
  MODELFILE_TO_CREATE=$(ls -t "$WORK_DIR"/*.Modelfile 2>/dev/null | head -n 1)
  if [ -z "$MODELFILE_TO_CREATE" ]; then
      echo "--- ERROR: No .Modelfile found in $WORK_DIR after script execution. ---"
      exit 1
  fi
  
  echo "[INFO] Creating model in Ollama from ${MODELFILE_TO_CREATE}..."
  # We must be in the directory with the GGUF file for the 'FROM' command to work
  cd "$WORK_DIR"
  ollama create "${MODEL_NAME_TO_CHECK}" -f "${MODELFILE_TO_CREATE}"
  echo "--- Ollama model creation complete. ---"
fi

# --- 5. Run the main sync_models.sh script ---
echo "[INFO] All checks complete. Proceeding with sync_models.sh... ---"
exec /sync_models.sh
