#!/bin/bash

# Check for the input directory argument
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <directory_path>"
    exit 1
fi

DIRECTORY=$1

# Check if the directory exists
if [ ! -d "$DIRECTORY" ]; then
    echo "Error: Directory $DIRECTORY does not exist."
    exit 1
fi

OUTPUT_FILE="dimensions.csv"

# Create or overwrite the CSV header
echo "sheet;width;height" > "$OUTPUT_FILE"

# Iterate over images and extract dimensions
find "$DIRECTORY" -type f \( -name "*.jpg" -o -name "*.png" \) | sort | while read -r IMAGE; do
    FILENAME=$(basename "$IMAGE")
    DIMENSIONS=$(identify -format "%w;%h" "$IMAGE")
    echo "$FILENAME;$DIMENSIONS" >> "$OUTPUT_FILE"
done

echo "Dimensions have been saved to $OUTPUT_FILE"
