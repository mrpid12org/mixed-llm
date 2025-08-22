#!/bin/bash

# --- Configuration ---
IDLE_TIMEOUT=${IDLE_TIMEOUT_SECONDS:-1800}

# Checks every 10 seconds to avoid missing short tasks.
CHECK_INTERVAL=10

# --- FIX: Increased threshold to avoid flagging momentary lulls as idle ---
GPU_UTILIZATION_THRESHOLD=20

echo "--- GPU Idle Shutdown Script Started (v9 - Tuned Threshold) ---"
echo "Timeout is set to ${IDLE_TIMEOUT} seconds."
echo "Check interval is set to ${CHECK_INTERVAL} seconds."
echo "Monitoring GPU utilization. Threshold for activity: ${GPU_UTILIZATION_THRESHOLD}%"

# --- Sanity Checks ---
if [ -z "$RUNPOD_POD_ID" ]; then
    echo "--- FATAL: RUNPOD_POD_ID environment variable not found."
    exit 0
fi
if ! command -v nvidia-smi &> /dev/null; then
    echo "--- FATAL: nvidia-smi command not found. Cannot monitor GPU."
    exit 0
fi
if ! command -v runpodctl &> /dev/null; then
    echo "--- FATAL: runpodctl command not found. Cannot self-terminate."
    exit 0
fi

# --- Main Loop ---
LAST_ACTIVE=$(date +%s)

while true; do
  # Get the highest GPU utilization across all cards.
  UTIL_OUT=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | sort -nr | head -n1)

  if [[ "$UTIL_OUT" =~ ^[0-9]+$ ]]; then
    CURRENT_UTILIZATION=$UTIL_OUT
    
    if [ "$CURRENT_UTILIZATION" -gt "$GPU_UTILIZATION_THRESHOLD" ]; then
      echo "INFO: $(date): GPU is ACTIVE (Util: ${CURRENT_UTILIZATION}%). Resetting idle timer."
      LAST_ACTIVE=$(date +%s)
    else
      CURRENT_TIME=$(date +%s)
      IDLE_TIME=$((CURRENT_TIME - LAST_ACTIVE))
      echo "INFO: $(date): GPU is IDLE (Util: ${CURRENT_UTILIZATION}%). Time since last activity: ${IDLE_TIME} seconds."

      if [ ${IDLE_TIME} -ge ${IDLE_TIMEOUT} ]; then
        echo "SHUTDOWN: GPU has been idle for ${IDLE_TIME} seconds (threshold is ${IDLE_TIMEOUT}s). Terminating pod ${RUNPOD_POD_ID}..."
        runpodctl remove pod $RUNPOD_POD_ID
        echo "Termination command sent. Script will now exit."
        exit 0
      fi
    fi
  else
    echo "Warning: Could not read GPU utilization. Output was: '${UTIL_OUT}'"
  fi
  
  sleep ${CHECK_INTERVAL}
done
