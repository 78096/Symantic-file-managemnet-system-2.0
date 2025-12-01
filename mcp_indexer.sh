#!/usr/bin/env bash

# Load .env file from the same directory as this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -o allexport
    source "$SCRIPT_DIR/.env"
    set +o allexport
else
    echo "ERROR: .env file not found in $SCRIPT_DIR"
    exit 1
fi

# Validate SANDBOX_DIR environment variable
if [[ -z "$SANDBOX_DIR" ]]; then
    echo "ERROR: SANDBOX_DIR is not set in .env"
    exit 1
fi

mkdir -p ".mcp"
INDEX_FILE=".mcp/index.json"

echo "{"
echo "  \"files\": {"

FIRST=1
for file in "$SANDBOX_DIR"/*; do
    [[ -f "$file" ]] || continue
    fname=$(basename "$file")
    size=$(stat -f "%z" "$file")
    modified=$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%S" "$file")

    if [[ $FIRST -eq 0 ]]; then echo ","; fi
    FIRST=0

    echo "    \"$fname\": {\"path\": \"$file\", \"size\": $size, \"modified\": \"$modified\"}"
done

echo "  }"
echo "}" > "$INDEX_FILE"

echo "Index written to $INDEX_FILE"
