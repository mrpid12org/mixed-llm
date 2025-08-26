#!/bin/bash
# SCRIPT V1 - Merges split GGUF files using the official gguf-split tool.

set -e

# --- 1. Sanity Checks ---
if ! command -v gguf-split &> /dev/null; then
    echo "--- ERROR: 'gguf-split' command not found. The image may need to be rebuilt. ---"
    exit 1
fi

WORK_DIR="/workspace/temp_gguf"
cd "$WORK_DIR"

# --- 2. Find the first part of the model ---
# It will look for a file like '...-00001-of-....gguf'
FIRST_PART=$(find . -name "*-00001-of-*.gguf" | head -n 1)

if [ -z "$FIRST_PART" ]; then
    echo "--- ERROR: Could not find the first part of a GGUF model in ${WORK_DIR} ---"
    echo "           (Looking for a file like '...-00001-of-....gguf')"
    exit 1
fi

# --- 3. Determine the output filename ---
# Removes the '-00001-of-...' part to get the base name
OUTPUT_FILENAME=$(echo "$FIRST_PART" | sed -E "s/-[0-9]+-of-[0-9]+//")

echo "====================================================================="
echo "--- GGUF Model Joiner (v1) ---"
echo "  > Found first part: $FIRST_PART"
echo "  > Output file will be: $OUTPUT_FILENAME"
echo "====================================================================="

# --- 4. Run the official merge tool ---
echo "--- Merging files... This may take a while. ---"
gguf-split --merge "$FIRST_PART" "$OUTPUT_FILENAME"

# --- 5. Clean up the now-unnecessary part files ---
echo "--- Merge complete. Cleaning up part files... ---"
# Find all files matching the pattern and delete them
find . -name "*-*-of-*.gguf" -delete

echo "--- All Done! ---"
echo "Final model is ready at: ${WORK_DIR}/${OUTPUT_FILENAME}"
ls -lh "${OUTPUT_FILENAME}"
