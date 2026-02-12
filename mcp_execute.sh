#!/usr/local/bin/bash
# EXECUTE

SANDBOX_DIR="/Users/Shared/semsh_sandbox"
TRASH_DIR="$SANDBOX_DIR/.trash"

mkdir -p "$TRASH_DIR"

ACTION=""
FILE=""
DEST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action) ACTION="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    --dest) DEST="$2"; shift 2 ;;
    *) echo "Bad arguments"; exit 1 ;;
  esac
done

find_item() {
  local name="$1"
  match=$(find "$SANDBOX_DIR" \( -type f -o -type d \) -name "$name" 2>/dev/null | head -n 1)
  if [[ -z "$match" && "$name" != *.txt ]]; then
    match=$(find "$SANDBOX_DIR" \( -type f -o -type d \) -name "$name.txt" 2>/dev/null | head -n 1)
  fi
  echo "$match"
}

REAL_PATH=$(find_item "$FILE")

if [[ "$ACTION" != "create" ]]; then
  if [[ -z "$REAL_PATH" ]]; then
    echo "❌ No file or folder found named '$FILE'"
    exit 1
  fi
fi

[[ -n "$REAL_PATH" ]] && FILE="$REAL_PATH"

case "$ACTION" in

  create)
    touch "$SANDBOX_DIR/$FILE"
    echo "Created file: $SANDBOX_DIR/$FILE"
    ;;

  read)
    echo "----- BEGIN ITEM: $FILE -----"
    cat "$FILE" 2>/dev/null || echo "Cannot read."
    echo "----- END ITEM -----"
    ;;

  delete)
    BASENAME=$(basename "$FILE")
    mv "$FILE" "$TRASH_DIR/$BASENAME"
    echo "Moved to trash: $FILE"
    ;;

  move)
    DEST_DIR="$SANDBOX_DIR/$DEST"
    mkdir -p "$DEST_DIR"
    BASENAME=$(basename "$FILE")
    mv "$FILE" "$DEST_DIR/$BASENAME"
    echo "Moved: $FILE → $DEST_DIR/$BASENAME"
    ;;

  rename)
    DIRNAME=$(dirname "$FILE")
    mv "$FILE" "$DIRNAME/$DEST"
    echo "Renamed to: $DIRNAME/$DEST"
    ;;

  summarize)
    if [ -d "$FILE" ]; then
      echo "❌ Cannot summarize a folder."
      exit 1
    fi
    CONTENT=$(cat "$FILE")
    curl -s https://api.openai.com/v1/chat/completions \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -H "Content-Type: application/json" \
      -d @- <<EOF | jq -r '.choices[0].message.content'
{
  "model": "gpt-4o-mini",
  "messages": [
    {"role":"system","content":"Summarize this file in 3 bullet points."},
    {"role":"user","content":"$CONTENT"}
  ]
}
EOF
    ;;

  explain)
    cat "$FILE"
    ;;
esac
