#!/bin/bash
# SCRIPT V10 - Added network activity monitoring to prevent shutdowns during downloads.

# --- Configuration ---
IDLE_TIMEOUT=${IDLE_TIMEOUT_SECONDS:-1800}
CHECK_INTERVAL=10
GPU_UTILIZATION_THRESHOLD=20
# --- NEW: Network activity threshold in Kilobytes per second ---
# If network traffic is above this, the pod is considered active.
NET_ACTIVITY_THRESHOLD_KBPS=${NET_ACTIVITY_THRESHOLD_KBPS:-100}

echo "--- GPU/Network Idle Shutdown Script Started (v10) ---"
echo "Timeout is set to ${IDLE_TIMEOUT} seconds."
echo "Monitoring GPU utilization > ${GPU_UTILIZATION_THRESHOLD}%"
echo "Monitoring Network traffic > ${NET_ACTIVITY_THRESHOLD_KBPS} KB/s"

# --- Sanity Checks ---
if [ -z "$RUNPOD_POD_ID" ]; then
    echo "--- FATAL: RUNPOD_POD_ID environment variable not found."
    exit 0
fi
if ! command -v nvidia-smi &> /dev/null || ! command -v ip &> /dev/null; then
    echo "--- FATAL: nvidia-smi or ip command not found. Cannot monitor activity."
    exit 0
fi
if ! command -v runpodctl &> /dev/null; then
    echo "--- FATAL: runpodctl command not found. Cannot self-terminate."
    exit 0
fi

# --- NEW: Get the primary network interface (usually eth0) ---
INTERFACE=$(ip route | grep default | awk '{print $5}')
if [ -z "$INTERFACE" ]; then
    echo "--- WARNING: Could not determine default network interface. Network monitoring disabled. ---"
    MONITOR_NETWORK=false
else
    echo "--- Monitoring network activity on interface: $INTERFACE ---"
    MONITOR_NETWORK=true
fi

# --- Main Loop ---
LAST_ACTIVE=$(date +%s)

while true; do
    IS_ACTIVE=false
    
    # 1. Check GPU Utilization
    UTIL_OUT=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | sort -nr | head -n1)
    CURRENT_GPU_UTILIZATION=0
    if [[ "$UTIL_OUT" =~ ^[0-9]+$ ]]; then
        CURRENT_GPU_UTILIZATION=$UTIL_OUT
        if [ "$CURRENT_GPU_UTILIZATION" -gt "$GPU_UTILIZATION_THRESHOLD" ]; then
            echo "INFO: $(date): GPU is ACTIVE (Util: ${CURRENT_GPU_UTILIZATION}%). Resetting idle timer."
            IS_ACTIVE=true
        fi
    fi

    # 2. Check Network Activity
    SPEED_KBPS=0
    if [ "$MONITOR_NETWORK" = true ]; then
        RX_BEFORE=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
        TX_BEFORE=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
        sleep ${CHECK_INTERVAL}
        RX_AFTER=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
        TX_AFTER=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
        
        BYTES_TRANSFERRED=$(( (RX_AFTER - RX_BEFORE) + (TX_AFTER - TX_BEFORE) ))
        SPEED_KBPS=$(( BYTES_TRANSFERRED / CHECK_INTERVAL / 1024 ))
        
        if [ "$SPEED_KBPS" -gt "$NET_ACTIVITY_THRESHOLD_KBPS" ]; then
            if [ "$IS_ACTIVE" = false ]; then # Only print network message if GPU wasn't already active
                 echo "INFO: $(date): Network is ACTIVE (Speed: ${SPEED_KBPS} KB/s). Resetting idle timer."
            fi
            IS_ACTIVE=true
        fi
    else
        # If network monitoring is disabled, just sleep for the interval
        sleep ${CHECK_INTERVAL}
    fi

    # 3. Update Timer or Shutdown
    if [ "$IS_ACTIVE" = true ]; then
        LAST_ACTIVE=$(date +%s)
    else
        CURRENT_TIME=$(date +%s)
        IDLE_TIME=$((CURRENT_TIME - LAST_ACTIVE))
        echo "INFO: $(date): Pod is IDLE (GPU Util: ${CURRENT_GPU_UTILIZATION}%, Net Speed: ${SPEED_KBPS} KB/s). Time since last activity: ${IDLE_TIME}s."

        if [ ${IDLE_TIME} -ge ${IDLE_TIMEOUT} ]; then
            echo "SHUTDOWN: Pod has been idle for ${IDLE_TIME} seconds. Terminating pod ${RUNPOD_POD_ID}..."
            runpodctl remove pod $RUNPOD_POD_ID
            echo "Termination command sent. Script will now exit."
            exit 0
        fi
    fi
done
