#!/bin/bash

# Script to kill any stuck Cue to Cue processes
echo "Looking for Cue to Cue processes..."

# Find and kill Cue to Cue processes
PIDS=$(ps aux | grep "Cue to Cue" | grep -v grep | awk '{print $2}')

if [ -z "$PIDS" ]; then
    echo "No Cue to Cue processes found."
else
    echo "Found Cue to Cue processes: $PIDS"
    echo "Killing processes..."
    echo $PIDS | xargs kill -9
    echo "Processes killed."
fi

# Check if port 8080 is free
echo "Checking port 8080..."
if lsof -i :8080 > /dev/null 2>&1; then
    echo "Port 8080 is still in use. You may need to restart your system or find the process manually."
else
    echo "Port 8080 is now free."
fi

echo "Done!"
