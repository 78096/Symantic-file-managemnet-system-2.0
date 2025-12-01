#!/bin/bash

# Load environment variables
if [ ! -f .env ]; then
  echo ".env file not found!"
  exit 1
fi
source .env

# Check required env vars
if [ -z "$SANDBOX_DIR" ]; then
  echo "Set SANDBOX_DIR in .env (e.g. SANDBOX_DIR=/Users/a1989/Desktop/sandbox)"
  exit 1
fi

# Usage function
usage() {
  echo "Usage: $0 --q <query> [--days <days>] [--top <n>]"
  echo "Example: $0 --q \"error 104\" --days 7 --top 5"
  exit 1
}

# Default values
DAYS=0
TOP=10

# Parse arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --q)
      QUERY="$2"
      shift 2
      ;;
    --days)
      DAYS="$2"
      shift 2
      ;;
    --top)
      TOP="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

if [ -z "$QUERY" ]; then
  echo "Query string (--q) is required."
  usage
fi

# Function to convert days to seconds for comparison
days_to_seconds() {
  echo $(( $1 * 86400 ))
}

SECONDS_LIMIT=0
if [[ "$DAYS" =~ ^[0-9]+$ ]] && [ "$DAYS" -gt 0 ]; then
  SECONDS_LIMIT=$(days_to_seconds $DAYS)
fi

echo "Searching for \"$QUERY\" in files under $SANDBOX_DIR..."

# Find files modified within DAYS if DAYS>0, else all files
if [ "$SECONDS_LIMIT" -gt 0 ]; then
  # Find files modified within last DAYS days
  FILES=$(find "$SANDBOX_DIR" -type f -mtime -"$DAYS")
else
  FILES=$(find "$SANDBOX_DIR" -type f)
fi

# Search the query inside files and print matching lines with filename and line number
RESULTS=()
for f in $FILES; do
  # Grep query in file (case insensitive)
  matches=$(grep -i -H -n -- "$QUERY" "$f")
  if [ -n "$matches" ]; then
    RESULTS+=("$matches")
  fi
done

# If no results
if [ ${#RESULTS[@]} -eq 0 ]; then
  echo "No matches found."
  exit 0
fi

# Print top N results (if more than TOP lines)
echo "Top $TOP results:"
count=0
for res in "${RESULTS[@]}"; do
  echo "$res"
  count=$((count+$(echo "$res" | wc -l)))
  if [ "$count" -ge "$TOP" ]; then
    break
  fi
done
