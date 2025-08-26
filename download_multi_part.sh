#!/bin/bash
# SCRIPT V3 - Improved safety and restart logic.
# Usage: ./download_multi_part.sh "URL_TO_FIRST_PART"

set -e

# --- 1. Argument and Sanity Checks ---
if [ -z "$1" ]; then
    echo "--- ERROR: No URL provided. ---"
    echo "Usage: $0 \"<URL for the first part, e.g., ...-00000-of-00014.safetensors>\""
    exit 1
fi

URL_PART1="$1"
WORK_DIR="/workspace/temp_gguf"

# --- 2. Parse URL and Determine File Structure ---
BASE_URL=$(echo "$URL_PART1" | cut -d'?' -f1)
BASE_FILENAME=$(basename "$BASE_URL")

PART_INFO=$(echo "$BASE_FILENAME" | sed -n -E 's/.*-([0-9]+)-of-([0-9]+)\..*/\1 \2/p')

if [ -z "$PART_INFO" ]; then
    echo "--- ERROR: URL does not match the expected multi-part format. ---"
    exit 1
fi

read -r FIRST_PART_STR TOTAL_PARTS_STR <<< "$PART_INFO"
TOTAL_PARTS=$((10#$TOTAL_PARTS_STR))
PART_NUM_LEN=${#FIRST_PART_STR}
FINAL_MODEL_NAME=$(echo "$BASE_FILENAME" | sed -E "s/-[0-9]+-of-[0-9]+//")

echo "====================================================================="
echo "--- Multi-Part Model Downloader (v3) ---"
echo "  > Final Model Name: $FINAL_MODEL_NAME"
echo "  > Total Parts:      $TOTAL_PARTS"
echo "  > Working Directory: $WORK_DIR"
echo "====================================================================="

# --- 3. Setup Working Directory and Perform Safety Checks ---
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# If final file exists AND no temp parts exist, the job is already done.
if [ -f "$FINAL_MODEL_NAME" ] && ! ls part_*.tmp 1>/dev/null 2>&1; then
    echo "--- INFO: Final model '$FINAL_MODEL_NAME' already exists and appears complete. Nothing to do. ---"
    exit 0
fi

# If final file exists AND temp parts also exist, the join failed. Clean up the bad file.
if [ -f "$FINAL_MODEL_NAME" ]; then
    echo "--- WARNING: Found an incomplete final model from a previous failed run. Deleting it to re-attempt the join. ---"
    rm -f "$FINAL_MODEL_NAME"
fi


# --- 4. Loop and Download Missing Parts ---
DOWNLOADED_PARTS=()
for i in $(seq 0 $((TOTAL_PARTS - 1))); do
    CURRENT_PART_NUM=$(printf "%0${PART_NUM_LEN}d" "$i")
    TEMP_FILENAME="part_${CURRENT_PART_NUM}.tmp"
    
    # Let aria2c handle resuming/skipping completed parts
    CURRENT_URL=$(echo "$BASE_URL" | sed "s/-${FIRST_PART_STR}-of-/-${CURRENT_PART_NUM}-of-/")
    echo
    echo "--- Verifying Part $((i + 1)) / $TOTAL_PARTS ---"
    aria2c -c -x 16 -s 16 -k 1M -o "$TEMP_FILENAME" "$CURRENT_URL"
    
    DOWNLOADED_PARTS+=("$TEMP_FILENAME")
done

# --- 5. Join All Parts ---
echo
echo "--- All parts are present. Joining files into '$FINAL_MODEL_NAME'... ---"
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
