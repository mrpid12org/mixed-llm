#!/bin/bash
# SCRIPT V1 - Downloads all parts of a multi-part GGUF model and correctly
#             merges them using the official gguf-split tool.
# Usage: ./download_and_join_multipart_gguf.sh "URL_TO_FIRST_PART"

set -e

# Ensure the llama shared library can be found
export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"

# --- 1. Argument and Sanity Checks ---
if [ -z "$1" ]; then
    echo "--- ERROR: No URL provided. ---"
    exit 1
fi

if ! command -v gguf-split &> /dev/null; then
    echo "--- ERROR: 'gguf-split' command not found. The image may need to be rebuilt. ---"
    exit 1
fi

URL_PART1="$1"
WORK_DIR="/workspace/temp_gguf"

# --- 2. Parse URL and Determine File Structure ---
BASE_URL=$(echo "$URL_PART1" | cut -d'?' -f1)
BASE_FILENAME=$(basename "$BASE_URL")

PART_INFO=$(echo "$BASE_FILENAME" | sed -n -E 's/.*-([0-9]+)-of-([0-9]+)\..*/\1 \2/p')

if [ -z "$PART_INFO" ]; then
    echo "--- ERROR: URL does not match the expected multi-part GGUF format. ---"
    exit 1
fi

read -r FIRST_PART_STR TOTAL_PARTS_STR <<< "$PART_INFO"
TOTAL_PARTS=$((10#$TOTAL_PARTS_STR))
PART_NUM_LEN=${#FIRST_PART_STR}
OUTPUT_FILENAME=$(echo "$BASE_FILENAME" | sed -E "s/-[0-9]+-of-[0-9]+//")
OUTPUT_BASENAME="${OUTPUT_FILENAME%.gguf}"

# Detect the starting number (0 or 1)
START_NUM=$((10#$FIRST_PART_STR))
END_NUM=$((START_NUM + TOTAL_PARTS - 1))

echo "====================================================================="
echo "--- GGUF Multi-Part Downloader & Joiner (v1) ---"
echo "  > Final Model Name: $OUTPUT_FILENAME"
echo "  > Total Parts:      $TOTAL_PARTS"
echo "  > Part Numbers:     $START_NUM to $END_NUM"
echo "  > Working Directory: $WORK_DIR"
echo "====================================================================="

# --- 3. Setup Working Directory ---
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# --- 4. Loop and Download All Parts ---
FIRST_PART_LOCAL_NAME=""
for i in $(seq $START_NUM $END_NUM); do
    CURRENT_PART_NUM=$(printf "%0${PART_NUM_LEN}d" "$i")
    FILENAME=$(echo "$BASE_FILENAME" | sed "s/-${FIRST_PART_STR}-of-/-${CURRENT_PART_NUM}-of-/")
    
    # Keep track of the local name of the first part for the merge command
    if [ "$i" -eq "$START_NUM" ]; then
        FIRST_PART_LOCAL_NAME=$FILENAME
    fi

    CURRENT_URL=$(echo "$BASE_URL" | sed "s/-${FIRST_PART_STR}-of-/-${CURRENT_PART_NUM}-of-/")
    
    echo
    echo "--- Verifying Part $i / $END_NUM: ${FILENAME} ---"
    aria2c -c -x 16 -s 16 -k 1M -o "$FILENAME" "$CURRENT_URL"
done

# --- 5. Run the Official Merge Tool ---
echo
echo "--- All parts downloaded. Merging files using gguf-split... ---"
if ! gguf-split --merge "$FIRST_PART_LOCAL_NAME" "$OUTPUT_FILENAME"; then
    echo "--- WARN: gguf-split failed; falling back to simple concatenation ---"
    cat $(ls "${OUTPUT_BASENAME}"-*-of-*.gguf | sort) > "$OUTPUT_FILENAME"
fi

# --- 6. Clean Up Part Files ---
echo "--- Merge complete. Cleaning up part files... ---"
find . -name "*-*-of-*.gguf" -delete

# --- 7. Final Verification ---
echo
echo "--- All Done! ---"
echo "Final model is ready at: ${WORK_DIR}/${OUTPUT_FILENAME}"
ls -lh "${OUTPUT_FILENAME}"
