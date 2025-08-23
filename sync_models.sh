#!/bin/bash
# SCRIPT V2.1 - Uses new, cleaner directory structure.

# Give the Ollama server time to start up properly.
sleep 45

# --- Configuration ---
MODEL_TO_PULL=${OLLAMA_DEFAULT_MODEL:-"hf.co/mlabonne/gemma-3-27b-it-abliterated-GGUF:Q6_K"}
SYMLINK_DIR=${TEXTGEN_MODELS_DIR}
BLOBS_DIR="${OLLAMA_MODELS}/blobs"

echo "====================================================================="
echo "--- Starting Model Sync Script (v2.1) ---"
echo "====================================================================="

# --- 1. PULL DEFAULT OLLAMA MODEL ---
if ! ollama list | grep -q "${MODEL_TO_PULL%%:*}"; then
  echo "--- Pulling default model: $MODEL_TO_PULL ---"
  ollama pull "$MODEL_TO_PULL"
else
  echo "--- Default model ${MODEL_TO_PULL%%:*} already exists ---"
fi
echo "--- Model pull check complete. ---"
echo

# --- 2. CREATE SYMLINKS FOR TEXT-GENERATION-WEBUI ---
echo "--- Starting Text-Gen-WebUI Symlink Sync ---"
mkdir -p "$SYMLINK_DIR"

if ! command -v ollama &> /dev/null; then
    echo "[ERROR] Ollama command not found. Cannot create symlinks."
    exit 1
fi

ollama list | awk '{print $1}' | tail -n +2 | while read -r MODEL_NAME_TAG; do
    echo "[INFO] Processing model: $MODEL_NAME_TAG"
    SYMLINK_FILENAME=$(echo "$MODEL_NAME_TAG" | sed 's/[:\/]/-/g').gguf
    SYMLINK_PATH="$SYMLINK_DIR/$SYMLINK_FILENAME"

    if [ -L "$SYMLINK_PATH" ] && [ ! -e "$SYMLINK_PATH" ]; then
        echo "       > Removing broken symlink: $SYMLINK_FILENAME"
        rm "$SYMLINK_PATH"
    fi

    if [ -e "$SYMLINK_PATH" ]; then
        echo "       > Skipping: Link or file '$SYMLINK_FILENAME' already exists."
        continue
    fi

    BLOB_HASH=$(ollama show --json "$MODEL_NAME_TAG" | grep -A 1 '"mediaType": "application/vnd.ollama.image.model"' | tail -n 1 | grep -o 'sha256:[a-f0-9]*' | sed 's/sha256:/sha256-/g')

    if [ -z "$BLOB_HASH" ]; then
        echo "[ERROR] Could not determine blob hash for '$MODEL_NAME_TAG'. Skipping."
        continue
    fi
    
    BLOB_FILE_PATH="$BLOBS_DIR/$BLOB_HASH"

    if [ -f "$BLOB_FILE_PATH" ]; then
        echo "       > Found blob: $BLOB_HASH"
        echo "       > Creating symlink: $SYMLINK_FILENAME -> (blob)"
        ln -s "$BLOB_FILE_PATH" "$SYMLINK_PATH"
    else
        echo "[ERROR] Blob file not found at '$BLOB_FILE_PATH'. Cannot create symlink."
    fi
done
echo "--- Symlink Sync Complete ---"
