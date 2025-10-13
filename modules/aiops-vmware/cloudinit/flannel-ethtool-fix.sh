#!/bin/bash
# Script to persistently disable generic transmit checksum offload on flannel.1

FLANNEL_INTERFACE="flannel.1"
MAX_RETRIES=10
RETRY_COUNT=0

echo "Starting ethtool fix for ${FLANNEL_INTERFACE}..."

# Wait up to 10 seconds for the flannel.1 interface to appear
while ! ip link show "$FLANNEL_INTERFACE" > /dev/null 2>&1; do
    if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
        echo "Error: ${FLANNEL_INTERFACE} did not appear after ${MAX_RETRIES} attempts. Aborting."
        exit 1
    fi
    echo "Waiting for ${FLANNEL_INTERFACE}..."
    sleep 1
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

# Apply the persistent setting
echo "Applying ethtool setting: tx-checksum-ip-generic off"
/usr/sbin/ethtool -K "$FLANNEL_INTERFACE" tx-checksum-ip-generic off

if [ $? -eq 0 ]; then
    echo "SUCCESS: Ethtool setting applied to ${FLANNEL_INTERFACE}."
else
    echo "FAILURE: Could not apply ethtool setting."
    exit 1
fi