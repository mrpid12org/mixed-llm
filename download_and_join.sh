#!/bin/bash
# SCRIPT V5.3 - Works in the /workspace/temp_gguf directory.
set -e

# --- Configuration ---
WORK_DIR="/workspace/temp_gguf"

# --- 1. Argument Check ---
if [ -z "$1" ]; then
    echo "--- ERROR: No URL provided. ---"
    echo "Usage: ./download_and_join.sh \"<URL for part 1>\""
    exit 1
fi

URL_PART1="$1"
URL_PART2=""
FINAL_MODEL_NAME=""

# Create the working directory if it doesn't exist
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# --- 2. Intelligently Determine URL and Final Filename ---
FILENAME_PART1="part1.gguf.tmp"
FILENAME_PART2="part2.gguf.tmp"
URL_PATH=$(echo "$URL_PART1" | cut -d'?' -f1)
BASE_FILENAME=$(basename "$URL_PATH")

if [[ "$URL_PART1" == *"-00001-of-00002.gguf"* ]]; then
    echo "--- Detected '-00001-of-00002' naming convention. ---"
    URL_PART2=$(echo "$URL_PART1" | sed 's/-00001-of-00002/-00002-of-00002/')
    FINAL_MODEL_NAME=$(echo "$BASE_FILENAME" | sed 's/-00001-of-00002.gguf//').gguf
elif [[ "$URL_PART1" == *".gguf.part1of2"* ]]; then
    echo "--- Detected '.part1of2' naming convention. ---"
    URL_PART2=$(echo "$URL_PART1" | sed 's/\.part1of2$/.part2of2/')
    FINAL_MODEL_NAME=$(echo "$BASE_FILENAME" | sed 's/\.part1of2$//')
else
    echo "--- ERROR: Unsupported part naming convention in URL. ---"
    echo "This script only supports URLs ending in:"
    echo "  1) ...-00001-of-00002.gguf"
    echo "  2) ....gguf.part1of2"
    exit 1
fi

echo "====================================================================="
echo "--- Model Download & Join Script (v5.3) ---"
echo "  > Working Directory: $WORK_DIR"
echo "  > Final Model Name: $FINAL_MODEL_NAME"
echo "====================================================================="

# --- 3. Sanity Check ---
if [ -f "$FINAL_MODEL_NAME" ]; then
    echo "--- INFO: Final model '$FINAL_MODEL_NAME' already exists. Nothing to do. ---"
    exit 0
fi

# --- 4. Download Files ---
echo "--- Starting Download ---"
echo "Downloading Part 1 from: $URL_PART1"
aria2c -c -x 16 -s 16 -k 1M -o "$FILENAME_PART1" "$URL_PART1"

echo "Downloading Part 2 from: $URL_PART2"
aria2c -c -x 16 -s 16 -k 1M -o "$FILENAME_PART2" "$URL_PART2"

# --- Verification ---
if [ ! -f "$FILENAME_PART1" ] || [ ! -f "$FILENAME_PART2" ]; then
    echo "--- ERROR: Download failed. One or both parts are missing. ---"
    exit 1
fi

echo "--- Download Complete ---"
echo "File sizes:"
ls -lh "$FILENAME_PART1" "$FILENAME_PART2"

# --- 5. Join Files ---
echo "--- Joining files... This may take some time. ---"
cat "$FILENAME_PART2" >> "$FILENAME_PART1"
echo "--- Join complete. ---"

# --- 6. Clean Up ---
echo "--- Cleaning up temporary files... ---"
rm "$FILENAME_PART2"
echo "--- Renaming final model... ---"
mv "$FILENAME_PART1" "$FINAL_MODEL_NAME"

# --- 7. Final Verification ---
echo "--- All Done! ---"
echo "Final model created at: $WORK_DIR/$FINAL_MODEL_NAME"
echo "Final file size:"
ls -lh "$FINAL_MODEL_NAME"
