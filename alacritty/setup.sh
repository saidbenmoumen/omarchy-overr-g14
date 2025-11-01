#!/bin/bash

# Source file (current directory)
SOURCE_FILE="./screensaver.toml"

# Target file to replace
TARGET_FILE="$HOME/.local/share/omarchy/default/alacritty/screensaver.toml"

# Check if source file exists
if [ ! -f "$SOURCE_FILE" ]; then
    echo "Error: Source file '$SOURCE_FILE' does not exist"
    exit 1
fi

# Check if target file exists (optional - will create if it doesn't)
if [ ! -f "$TARGET_FILE" ]; then
    echo "Warning: Target file '$TARGET_FILE' does not exist. It will be created."
    # Create parent directories if they don't exist
    mkdir -p "$(dirname "$TARGET_FILE")"
fi

# Copy the source file to the target location, replacing its content
cp "$SOURCE_FILE" "$TARGET_FILE"

# Check if the operation was successful
if [ $? -eq 0 ]; then
    echo "Successfully replaced content in '$TARGET_FILE'"
else
    echo "Error: Failed to replace file content"
    exit 1
fi
