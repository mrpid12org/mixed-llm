#!/bin/bash
# SCRIPT V1 - Downloads and joins a multi-part model with a variable number of parts.
# Usage: ./download_multi_part.sh "URL_TO_FIRST_PART"

set -e

# --- 1. Argument and Sanity Checks ---
if [ -z "$1" ]; then
    echo "--- ERROR: No URL provided. ---"
    echo "Usage: $0 \"<URL for the first part, e.g., ...-00000-of-00014.safetensors>\""
    exit 1
fi

URL_PART1="$1"
WORK_DIR="/workspace/temp_gguf" # Using the same temp dir for consistency

# --- 2. Parse URL and Determine File Structure ---
BASE_URL=$(echo "$URL_PART1" | cut -d'?' -f1)
BASE_FILENAME=$(basename "$BASE_URL")

# Use sed with a regex to extract the numbers. This is the core logic.
PART_INFO=$(echo "$BASE_FILENAME" | sed -n -E 's/.*-([0-9]+)-of-([0-9]+)\..*/\1 \2/p')

if [ -z "$PART_INFO" ]; then
    echo "--- ERROR: URL does not match the expected multi-part format. ---"
    echo "Expected format: '...-XXXXX-of-YYYYY.ext'"
    echo "Example: '.../model-00000-of-00014.safetensors'"
    exit 1
fi

read -r FIRST_PART_STR TOTAL_PARTS_STR <<< "$PART_INFO"

TOTAL_PARTS=$((10#$TOTAL_PARTS_STR)) # Convert to number
PART_NUM_LEN=${#FIRST_PART_STR}      # Get the padding length (e.g., 5 for '00000')

# Derive the final model name by removing the part info, e.g., "model.safetensors"
FINAL_MODEL_NAME=$(echo "$BASE_FILENAME" | sed -E "s/-[0-9]+-of-[0-9]+//")

echo "====================================================================="
echo "--- Multi-Part Model Downloader (v1) ---"
echo "  > Final Model Name: $FINAL_MODEL_NAME"
echo "  > Total Parts:      $TOTAL_PARTS"
echo "  > Working Directory: $WORK_DIR"
echo "====================================================================="

# --- 3. Setup Working Directory ---
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

if [ -f "$FINAL_MODEL_NAME" ]; then
    echo "--- INFO: Final model '$FINAL_MODEL_NAME' already exists. Nothing to do. ---"
    exit 0
fi

# --- 4. Loop, Download, and Collect Part Filenames ---
DOWNLOADED_PARTS=()
for i in $(seq 0 $((TOTAL_PARTS - 1))); do
    CURRENT_PART_NUM=$(printf "%0${PART_NUM_LEN}d" "$i")
    
    # Replace the first part number in the original URL with the current one
    CURRENT_URL=$(echo "$BASE_URL" | sed "s/-${FIRST_PART_STR}-of-/-${CURRENT_PART_NUM}-of-/")
    
    TEMP_FILENAME="part_${CURRENT_PART_NUM}.tmp"
    
    echo
    echo "--- Downloading Part $((i + 1)) / $TOTAL_PARTS ---"
    echo "URL: $CURRENT_URL"
    
    aria2c -c -x 16 -s 16 -k 1M -o "$TEMP_FILENAME" "$CURRENT_URL"
    
    DOWNLOADED_PARTS+=("$TEMP_FILENAME")
done

# --- 5. Join All Parts ---
echo
echo "--- All parts downloaded. Joining files into '$FINAL_MODEL_NAME'... ---"
# 'cat' will read the files in the correct order due to the zero-padded names
cat "${DOWNLOADED_PARTS[@]}" > "$FINAL_MODEL_NAME"
echo "--- Join complete. ---"

# --- 6. Clean Up Temporary Files ---
echo "--- Cleaning up temporary part files... ---"
rm "${DOWNLOADED_PARTS[@]}"

# --- 7. Final Verification ---
echo "--- All Done! ---"
echo "Final model created at: $WORK_DIR/$FINAL_MODEL_NAME"
echo "Final file size:"
ls -lh "$FINAL_MODEL_NAME"
