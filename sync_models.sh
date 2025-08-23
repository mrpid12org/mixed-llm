#!/bin/bash
# SCRIPT V3.0 - Uses the proven curl/python method from the parent build.

# Give the Ollama server time to start up properly.
sleep 45

# --- Configuration ---
# Use a standard, valid Ollama library model name.
MODEL_TO_PULL=${OLLAMA_DEFAULT_MODEL:-"phi3:latest"}
SYMLINK_DIR=${TEXTGEN_MODELS_DIR}
BLOBS_DIR="${OLLAMA_MODELS}/blobs"

echo "====================================================================="
echo "--- Starting Model Sync Script (v3.0) ---"
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

    # --- FIX: Using the proven curl and python method to get blob info ---
    JSON_OUTPUT=$(curl -s http://127.0.0.1:11434/api/show -d "{\"name\": \"$MODEL_NAME_TAG\"}")
    BLOB_HASH=$(echo "$JSON_OUTPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    digest = data.get('details', {}).get('digest', '')
    if digest:
        print(digest.replace('sha256:', 'sha256-'))
except (json.JSONDecodeError, KeyError):
    pass
")

    if [ -z "$BLOB_HASH" ]; then
        echo "[ERROR] Could not determine blob hash for '$MODEL_NAME_TAG' via API. Skipping."
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
