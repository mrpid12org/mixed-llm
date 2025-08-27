#!/bin/bash
# SCRIPT V4 - Automatically handles models starting from part 0 or 1.
# Usage: ./download_multi_part.sh "URL_TO_FIRST_PART"

set -e

# --- 1. Argument and Sanity Checks ---
if [ -z "$1" ]; then
    echo "--- ERROR: No URL provided. ---"
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

# --- NEW: Detect the starting number (0 or 1) ---
START_NUM=$((10#$FIRST_PART_STR))
END_NUM=$((START_NUM + TOTAL_PARTS - 1))

echo "====================================================================="
echo "--- Multi-Part Model Downloader (v4) ---"
echo "  > Final Model Name: $FINAL_MODEL_NAME"
echo "  > Total Parts:      $TOTAL_PARTS"
echo "  > Part Numbers:     $START_NUM to $END_NUM"
echo "  > Working Directory: $WORK_DIR"
echo "====================================================================="

# --- 3. Setup Working Directory and Perform Safety Checks ---
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

if [ -f "$FINAL_MODEL_NAME" ] && ! ls part_*.tmp 1>/dev/null 2>&1; then
    echo "--- INFO: Final model '$FINAL_MODEL_NAME' already exists and appears complete. Nothing to do. ---"
    exit 0
fi

if [ -f "$FINAL_MODEL_NAME" ]; then
    echo "--- WARNING: Found an incomplete final model. Deleting it to re-attempt the join. ---"
    rm -f "$FINAL_MODEL_NAME"
fi

# --- 4. Loop and Download Missing Parts ---
DOWNLOADED_PARTS=()
# --- FIX: The loop now uses the detected start and end numbers ---
for i in $(seq $START_NUM $END_NUM); do
    CURRENT_PART_NUM=$(printf "%0${PART_NUM_LEN}d" "$i")
    TEMP_FILENAME="part_${CURRENT_PART_NUM}.tmp"
    
    CURRENT_URL=$(echo "$BASE_URL" | sed "s/-${FIRST_PART_STR}-of-/-${CURRENT_PART_NUM}-of-/")
    
    echo
    echo "--- Verifying Part $i / $END_NUM ---"
    aria2c -c -x 16 -s 16 -k 1M -o "$TEMP_FILENAME" "$CURRENT_URL"
    
    DOWNLOADED_PARTS+=("$TEMP_FILENAME")
done

# --- 5. Join All Parts ---
# Sort the parts numerically to ensure correct order before joining
IFS=$'\n' mapfile -t SORTED_PARTS < <(
  printf '%s\n' "${DOWNLOADED_PARTS[@]}" | sort -t '_' -k2,2n
)
unset IFS

echo
echo "--- All parts are present. Joining files into '$FINAL_MODEL_NAME'... ---"
cat "${SORTED_PARTS[@]}" > "$FINAL_MODEL_NAME"
echo "--- Join complete. ---"

# --- 6. Clean Up Temporary Files ---
echo "--- Cleaning up temporary part files... ---"
rm "${SORTED_PARTS[@]}"

# --- 7. Final Verification ---
echo "--- All Done! ---"
echo "Final model created at: $WORK_DIR/$FINAL_MODEL_NAME"
echo "Final file size:"
ls -lh "$FINAL_MODEL_NAME"
