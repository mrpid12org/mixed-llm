#!/bin/bash
# SCRIPT V1.4 - Uses curl and a robust Python JSON parser.

# Give other services, especially Ollama, time to finish.
sleep 60

MODELS_DIR="/workspace/webui-data/user_data/models"
BLOBS_DIR="$MODELS_DIR/blobs"

echo "====================================================================="
echo "--- Starting TextgenUI Symlink Sync (v1.4) ---"
echo "====================================================================="

if ! command -v ollama &> /dev/null; then
    echo "[ERROR] Ollama command not found. Exiting."
    exit 1
fi

# Get a list of all model names from Ollama.
ollama list | awk '{print $1}' | tail -n +2 | while read -r MODEL_NAME_TAG; do
    echo
    echo "[INFO] Processing model: $MODEL_NAME_TAG"
    
    # Sanitize the model name for use as a filename (replace ':' and slashes with '-')
    SYMLINK_FILENAME=$(echo "$MODEL_NAME_TAG" | sed 's/[:\/]/-/g').gguf
    SYMLINK_PATH="$MODELS_DIR/$SYMLINK_FILENAME"

    if [ -L "$SYMLINK_PATH" ]; then
        if [ -e "$SYMLINK_PATH" ]; then
            echo "[SKIPPING] Valid symlink for '$SYMLINK_FILENAME' already exists."
            continue
        else
            echo "[CLEANUP] Removing broken symlink: $SYMLINK_FILENAME"
            rm "$SYMLINK_PATH"
        fi
    elif [ -f "$SYMLINK_PATH" ]; then
        echo "[WARNING] A real file exists at '$SYMLINK_PATH' and is not a symlink. Skipping."
        continue
    fi

    echo "       > Querying Ollama API for blob path..."
    # Use curl to get the JSON data directly from the API
    JSON_OUTPUT=$(curl -s http://127.0.0.1:11434/api/show -d "{\"name\": \"$MODEL_NAME_TAG\"}")

    # Use Python to robustly parse the JSON and extract the FROM line
    BLOB_FULL_PATH=$(echo "$JSON_OUTPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    modelfile_content = data.get('modelfile', '')
    for line in modelfile_content.split('\n'):
        if line.startswith('FROM '):
            print(line.split(' ', 1)[1])
            break
except (json.JSONDecodeError, IndexError):
    pass
")
    
    if [ -z "$BLOB_FULL_PATH" ]; then
        echo "[ERROR] Could not determine blob path for model '$MODEL_NAME_TAG'. Skipping."
        continue
    fi
    
    BLOB_HASH_FILENAME=$(basename "$BLOB_FULL_PATH")

    if [ -f "$BLOB_FULL_PATH" ]; then
        echo "       > Found blob file: $BLOB_HASH_FILENAME"
        echo "       > Creating symlink: $SYMLINK_FILENAME -> $BLOB_HASH_FILENAME"
        ln -s "$BLOB_FULL_PATH" "$SYMLINK_PATH"
    else
        echo "[ERROR] Blob file not found at '$BLOB_FULL_PATH'. Cannot create symlink."
    fi
done

echo
echo "--- TextgenUI Symlink Sync Complete ---"
