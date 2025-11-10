#!/bin/bash

# Configuration
TARGET_PERCENT=90
MOUNT_POINT="/"
SAFETY_BUFFER_MB=10 # Add 10MB buffer to ensure we pass the threshold
TARGET_FILE="/tmp/ROOT_FILL_FILE.bin"

echo "--- Disk Usage Alert Trigger ---"

# 1. Get disk statistics for the root filesystem in Kilobytes (KB)
# Uses df -k to get output in KB for precise calculation
if ! STATS=$(df -k "${MOUNT_POINT}" 2>/dev/null | awk 'NR==2{print $2, $3}'); then
    echo "Error: Failed to get disk statistics for ${MOUNT_POINT}. Exiting."
    exit 1
fi

TOTAL_KB=$(echo "$STATS" | awk '{print $1}')
USED_KB=$(echo "$STATS" | awk '{print $2}')
# AVAILABLE_KB is not strictly needed for the calculation, but useful for debugging

# Calculate percentages using integer arithmetic (multiplying by 100 first for precision)
CURRENT_PERCENT=$(( (USED_KB * 100) / TOTAL_KB ))

# Convert KB to MB for display purposes only
TOTAL_MB=$(( TOTAL_KB / 1024 ))
USED_MB=$(( USED_KB / 1024 ))

echo "Filesystem: ${MOUNT_POINT}"
echo "Total Size: ${TOTAL_MB} MB"
echo "Used Size:  ${USED_MB} MB (${CURRENT_PERCENT}%)"
echo "Target:     ${TARGET_PERCENT}% usage"

# 2. Check if the disk is already above the target
# Integer check: If (Current Used KB * 100) is >= (Total KB * Target Percent)
if [ $(( USED_KB * 100 )) -ge $(( TOTAL_KB * TARGET_PERCENT )) ]; then
    echo "Current usage (${CURRENT_PERCENT}%) is already above the target (${TARGET_PERCENT}%). No file created."
    exit 0
fi

# 3. Calculate the required KB to reach the target percentage
# T_target_KB = (TOTAL_KB * TARGET_PERCENT) / 100
TARGET_USAGE_KB=$(( (TOTAL_KB * TARGET_PERCENT) / 100 ))

# Calculate buffer size in KB
SAFETY_BUFFER_KB=$(( SAFETY_BUFFER_MB * 1024 ))

# Required KB = (Target KB - Current Used KB) + Safety Buffer KB
REQUIRED_KB=$(( TARGET_USAGE_KB - USED_KB + SAFETY_BUFFER_KB ))


# 4. Convert required KB to MB (dd count uses 1MB blocks) and round up
# Use shell arithmetic for simple rounding up: (KB + 1023) / 1024
REQUIRED_MB_COUNT=$(( (REQUIRED_KB + 1023) / 1024 ))

# 5. Execute dd command
echo "--------------------------------------"
echo "Creating file of size: ${REQUIRED_MB_COUNT} MB at ${TARGET_FILE}"
echo "This will push usage over ${TARGET_PERCENT}%..."

# Execute the dd command using the calculated count
# Note: Requires sudo access to write to the filesystem
sudo dd if=/dev/zero of="${TARGET_FILE}" bs=1M count="${REQUIRED_MB_COUNT}" 2>/dev/null

# 6. Final verification (Use awk to extract the percentage from df -h)
NEW_PERCENT=$(df -h "${MOUNT_POINT}" | awk 'NR==2{print $5}')
echo "Creation complete."
echo "New usage: ${NEW_PERCENT}"
echo "--------------------------------------"

exit 0