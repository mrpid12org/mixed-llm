#!/bin/bash
# SCRIPT V5.2 - Corrected MMProj symlink path to 'mmproj' directory.

# Give the Ollama server time to start up properly.
sleep 45

# --- Configuration ---
MODEL_TO_PULL=${OLLAMA_DEFAULT_MODEL:-"phi3:latest"}
MODELS_SYMLINK_DIR=${TEXTGEN_DATA_DIR}/models
# --- FIX: Use the correct 'mmproj' directory ---
MMPROJ_SYMLINK_DIR=${TEXTGEN_DATA_DIR}/mmproj
BLOBS_DIR="${OLLAMA_MODELS}/blobs"

echo "====================================================================="
echo "--- Starting Model Sync Script (v5.2) ---"
echo "====================================================================="

# --- 1. PULL DEFAULT OLLAMA MODEL ---
echo "[INFO] Checking for default model..."
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
mkdir -p "$MODELS_SYMLINK_DIR"
mkdir -p "$MMPROJ_SYMLINK_DIR"

if ! command -v ollama &> /dev/null; then
    echo "[ERROR] Ollama command not found. Cannot create symlinks."
    exit 1
fi

ollama list | awk '{print $1}' | tail -n +2 | while read -r MODEL_NAME_TAG; do
    echo "[INFO] Processing model: $MODEL_NAME_TAG"
    BASE_SYMLINK_NAME=$(echo "$MODEL_NAME_TAG" | sed 's/[:\/]/-/g')
    GGUF_SYMLINK_PATH="$MODELS_SYMLINK_DIR/$BASE_SYMLINK_NAME.gguf"

    if [ -e "$GGUF_SYMLINK_PATH" ]; then
        echo "       > Skipping: Link for '$BASE_SYMLINK_NAME' already exists."
        continue
    fi

    # Use the robust fallback method for all models to handle both types consistently
    MODElFILE_CONTENT=$(ollama show --modelfile "$MODEL_NAME_TAG")
    FROM_LINES=$(echo "$MODElFILE_CONTENT" | grep '^FROM ')
    NUM_FROM_LINES=$(echo "$FROM_LINES" | wc -l)

    if [ "$NUM_FROM_LINES" -eq 1 ]; then
        BLOB_FILE_PATH=$(echo "$FROM_LINES" | cut -d' ' -f2-)
        echo "       > Found single file path (standard or HF model): $BLOB_FILE_PATH"
        if [ -f "$BLOB_FILE_PATH" ]; then
            echo "       > Creating symlink: $BASE_SYMLINK_NAME.gguf"
            ln -s "$BLOB_FILE_PATH" "$GGUF_SYMLINK_PATH"
        else
            echo "[ERROR] Blob file not found at '$BLOB_FILE_PATH'."
        fi
    elif [ "$NUM_FROM_LINES" -eq 2 ]; then
        echo "       > Found 2 file paths; assuming vision model (GGUF + MMProj)."
        PATH1=$(echo "$FROM_LINES" | sed -n '1p' | cut -d' ' -f2-)
        PATH2=$(echo "$FROM_LINES" | sed -n '2p' | cut -d' ' -f2-)

        if [ ! -f "$PATH1" ] || [ ! -f "$PATH2" ]; then
            echo "[ERROR] One or both blob files not found ($PATH1, $PATH2). Skipping."
            continue
        fi
        
        SIZE1=$(stat -c%s "$PATH1")
        SIZE2=$(stat -c%s "$PATH2")

        if [ "$SIZE1" -gt "$SIZE2" ]; then
            GGUF_PATH=$PATH1
            MMPROJ_PATH=$PATH2
        else
            GGUF_PATH=$PATH2
            MMPROJ_PATH=$PATH1
        fi

        echo "       > GGUF identified: $GGUF_PATH"
        echo "       > MMProj identified: $MMPROJ_PATH"
        
        MMPROJ_SYMLINK_PATH="$MMPROJ_SYMLINK_DIR/$BASE_SYMLINK_NAME.mmproj"

        echo "       > Creating GGUF symlink in models/: $BASE_SYMLINK_NAME.gguf"
        ln -s "$GGUF_PATH" "$GGUF_SYMLINK_PATH"
        echo "       > Creating MMProj symlink in mmproj/: $BASE_SYMLINK_NAME.mmproj"
        ln -s "$MMPROJ_PATH" "$MMPROJ_SYMLINK_PATH"
    else
         echo "[ERROR] Model '$MODEL_NAME_TAG' has $NUM_FROM_LINES parts, which is unsupported. Skipping."
    fi
done
echo "--- Symlink Sync Complete ---"
