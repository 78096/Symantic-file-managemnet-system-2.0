#!/usr/local/bin/bash
#
# SEMSH

if [ -f .env ]; then
  set -o allexport
  source .env
  set +o allexport
fi

SANDBOX_DIR="/Users/Shared/semsh_sandbox"

USER_TMP="/Users/Shared/semsh_tmp/$(whoami)"
USER_LOG="/Users/Shared/semsh_tmp/$(whoami).log"
mkdir -p "$USER_TMP"

OPENAI_API_KEY="${OPENAI_API_KEY:-}"
OPENAI_MODEL="gpt-4-0613"

if [[ -z "$OPENAI_API_KEY" ]]; then
  echo "❌ ERROR: OPENAI_API_KEY missing in .env"
  exit 1
fi

CURRENT_USER=$(whoami)
LAST_ITEM=""

echo "=============================================="
echo " Welcome to SEMSH"
echo " Running as: $CURRENT_USER"
echo " Sandbox: $SANDBOX_DIR"
echo " Temp & logs: /Users/Shared/semsh_tmp"
echo " Type: 'switch user <name>' to change user"
echo "=============================================="

log_event() {
  local action="$1"
  local details="$2"
  echo "$(date +"%Y-%m-%d %H:%M:%S") | user=$CURRENT_USER | action=$action | $details" >> "$USER_LOG"
}

refresh_index() {
  ./mcp_indexer.sh > /dev/null 2>&1
}

AI_SYSTEM_PROMPT=$(cat <<'EOF'
You are a semantic file assistant.

ALWAYS return valid JSON only.

{
  "intent": "search_files | create_file | delete_files | move_files | rename_item | read_file | explain_file | summarize_files | file_info",
  "parameters": {
    "filename": "optional",
    "source": "optional",
    "destination": "optional",
    "type": "file | folder",
    "new_name": "for renaming",
    "date_range": {
      "from": "YYYY-MM-DD or today/yesterday/last_week",
      "to": "YYYY-MM-DD or today/yesterday/last_week"
    },
    "contains": "optional text"
  }
}
EOF
)

get_intent_from_ai() {
  local user_text="$1"

  ESCAPED_PROMPT=$(printf "%s" "$AI_SYSTEM_PROMPT" | jq -Rs .)
  ESCAPED_USER=$(printf "%s" "$user_text" | jq -Rs .)

  cat > "$USER_TMP/openai_request.json" <<EOF
{
  "model": "$OPENAI_MODEL",
  "messages": [
    {"role":"system","content": $ESCAPED_PROMPT},
    {"role":"user","content": $ESCAPED_USER}
  ],
  "temperature": 0
}
EOF

  RAW_RESPONSE=$(curl -s https://api.openai.com/v1/chat/completions \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d @"$USER_TMP/openai_request.json")

  echo "$RAW_RESPONSE" > "$USER_TMP/last_openai_response.json"
  echo "$RAW_RESPONSE" | jq -r '.choices[0].message.content // empty'
}

handle_intent() {
  local intent="$1"
  local params="$2"

  FILE=$(echo "$params" | jq -r '.filename // empty')

  if [[ -z "$FILE" && "$USER_INPUT" =~ \bit\b && -n "$LAST_ITEM" ]]; then
    FILE="$LAST_ITEM"
  fi

  if [[ "$FILE" == "it" && -n "$LAST_ITEM" ]]; then
    FILE="$LAST_ITEM"
  fi

  if echo "$USER_INPUT" | grep -qi "^switch user "; then
    NEWUSER=$(echo "$USER_INPUT" | awk '{print $3}')
    echo "🔄 Switching user to $NEWUSER..."
    exec su "$NEWUSER"
  fi

  if [[ "$USER_INPUT" =~ ^move\ all\ ([a-zA-Z0-9]+)\ files\ to\ ([a-zA-Z0-9_\/-]+)$ ]]; then
    FILETYPE="${BASH_REMATCH[1]}"
    DEST="${BASH_REMATCH[2]}"

    refresh_index

    DEST_DIR="$SANDBOX_DIR/$DEST"
    mkdir -p "$DEST_DIR"

    find "$SANDBOX_DIR" -type f -name "*.$FILETYPE" | while read -r f; do
      mv "$f" "$DEST_DIR/"
      echo "Moved: $f → $DEST_DIR/"
    done

    refresh_index
    log_event "bulk_move" "all .$FILETYPE files → $DEST"
    return
  fi

  if [[ "$USER_INPUT" =~ ^delete\ all\ ([a-zA-Z0-9]+)\ files$ ]]; then
    FILETYPE="${BASH_REMATCH[1]}"

    refresh_index

    find "$SANDBOX_DIR" -type f -name "*.$FILETYPE" | while read -r f; do
      ./mcp_execute.sh --action delete --file "$(basename "$f")"
      echo "Deleted: $f"
    done

    refresh_index
    log_event "bulk_delete" "all .$FILETYPE files"
    return
  fi

  case "$intent" in

  search_files)
    refresh_index
    echo "🔍 Searching semantic index..."
    echo "$params" > "$USER_TMP/semsh_last_query.json"
    ./mcp_query.sh --json "$USER_TMP/semsh_last_query.json"
    log_event "search_files" "$params"
    ;;

  create_file)
    if echo "$USER_INPUT" | grep -qi "folder"; then
      mkdir -p "$SANDBOX_DIR/$FILE"
      echo "Created folder: $SANDBOX_DIR/$FILE"
      LAST_ITEM="$FILE"
      log_event "create_folder" "$FILE"
    else
      ./mcp_execute.sh --action create --file "$FILE"
      LAST_ITEM="$FILE"
      log_event "create_file" "$FILE"
    fi
    refresh_index
    ;;

    delete_files)
    echo "⚠️  WARNING: You are about to delete '$FILE'."
    echo -n "Type 'yes' to confirm: "
    read -r CONFIRM

    if [[ "$CONFIRM" != "yes" ]]; then
      echo "❌ Delete cancelled."
      return
    fi

    ./mcp_execute.sh --action delete --file "$FILE"
    LAST_ITEM="$FILE"
    refresh_index
    log_event "delete_files" "$FILE"
    ;;


  move_files)
    SRC=$(echo "$params" | jq -r '.source // empty')
    DEST=$(echo "$params" | jq -r '.destination // empty')
    [[ -z "$SRC" ]] && SRC="$FILE"

    if [[ "$SRC" == "it" && -n "$LAST_ITEM" ]]; then
      SRC="$LAST_ITEM"
    fi

    if [[ -z "$SRC" || -z "$DEST" ]]; then
      echo "❌ ERROR: Missing source or destination."
      return
    fi

    refresh_index

    DEST_DIR="$SANDBOX_DIR/$DEST"
    mkdir -p "$DEST_DIR"

    REAL_SRC=$(find "$SANDBOX_DIR" \( -type f -o -type d \) -name "$SRC" 2>/dev/null | head -n 1)

    if [[ -z "$REAL_SRC" ]]; then
      echo "❌ ERROR: Could not find '$SRC'"
      return
    fi

    BASENAME=$(basename "$REAL_SRC")
    mv "$REAL_SRC" "$DEST_DIR/$BASENAME"

    echo "Moved: $REAL_SRC → $DEST_DIR/$BASENAME"

    LAST_ITEM="$BASENAME"
    refresh_index
    log_event "move_files" "$SRC → $DEST"
    ;;

  rename_item)
    NEW_NAME=$(echo "$params" | jq -r '.new_name // empty')

    if [[ -z "$FILE" ]]; then
      echo "❌ No file specified to rename."
      return
    fi

    if [[ -z "$NEW_NAME" ]]; then
      echo "❌ Missing new name."
      return
    fi

    ./mcp_execute.sh --action rename --file "$FILE" --dest "$NEW_NAME"

    LAST_ITEM="$NEW_NAME"
    refresh_index
    log_event "rename_item" "$FILE → $NEW_NAME"
    ;;

    file_info)
    refresh_index

    if [[ -z "$FILE" ]]; then
      echo "❌ ERROR: Please specify a file or folder."
      return
    fi

    REAL_PATH=$(find "$SANDBOX_DIR" \( -type f -o -type d \) -name "$FILE" 2>/dev/null | head -n 1)

    if [[ -z "$REAL_PATH" ]]; then
      echo "❌ ERROR: No file or folder found named '$FILE'"
      return
    fi

    OWNER=$(stat -f "%Su" "$REAL_PATH")
    GROUP=$(stat -f "%Sg" "$REAL_PATH")
    SIZE=$(stat -f "%z" "$REAL_PATH")
    PERM=$(stat -f "%Sp" "$REAL_PATH")
    MODIFIED=$(stat -f "%Sm" -t "%b %d %Y %H:%M" "$REAL_PATH")

    TYPE="File"
    if [[ -d "$REAL_PATH" ]]; then
      TYPE="Folder"
    fi

    # Parse permissions
    OWNER_PERM=""
    GROUP_PERM=""
    OTHER_PERM=""

    [[ "${PERM:1:1}" == "r" ]] && OWNER_PERM+="read "
    [[ "${PERM:2:1}" == "w" ]] && OWNER_PERM+="write "
    [[ "${PERM:3:1}" == "x" ]] && OWNER_PERM+="execute "

    [[ "${PERM:4:1}" == "r" ]] && GROUP_PERM+="read "
    [[ "${PERM:5:1}" == "w" ]] && GROUP_PERM+="write "
    [[ "${PERM:6:1}" == "x" ]] && GROUP_PERM+="execute "

    [[ "${PERM:7:1}" == "r" ]] && OTHER_PERM+="read "
    [[ "${PERM:8:1}" == "w" ]] && OTHER_PERM+="write "
    [[ "${PERM:9:1}" == "x" ]] && OTHER_PERM+="execute "

    echo ""
    echo "📄 $TYPE Information"
    echo "----------------------------------"
    echo "Name: $(basename "$REAL_PATH")"
    echo "Owner: $OWNER"
    echo "Group: $GROUP"
    echo "Size: $SIZE bytes"
    echo ""
    echo "Permissions:"
    echo "  Owner  → $OWNER_PERM"
    echo "  Group  → $GROUP_PERM"
    echo "  Others → $OTHER_PERM"
    echo ""
    echo "Last Modified: $MODIFIED"
    echo "Full Path: $REAL_PATH"
    echo "----------------------------------"
    echo ""

    LAST_ITEM="$FILE"
    log_event "file_info" "$FILE"
    ;;


  read_file)
    refresh_index
    ./mcp_execute.sh --action read --file "$FILE"
    LAST_ITEM="$FILE"
    log_event "read_file" "$FILE"
    ;;

  explain_file)
    refresh_index
    ./mcp_execute.sh --action explain --file "$FILE"
    LAST_ITEM="$FILE"
    log_event "explain_file" "$FILE"
    ;;

  summarize_files)
    refresh_index
    if [[ -z "$FILE" ]]; then
      echo "❌ ERROR: I need a filename to summarize."
      return
    fi
    echo "🧠 Summarizing: $FILE"
    ./mcp_execute.sh --action summarize --file "$FILE"
    LAST_ITEM="$FILE"
    log_event "summarize_file" "$FILE"
    ;;
  esac
}

while true; do
  echo -n "semsh> "
  read -r USER_INPUT
  [[ -z "$USER_INPUT" ]] && continue
  [[ "$USER_INPUT" == "exit" ]] && exit 0

  echo "🤖 Thinking..."
  RAW_JSON=$(get_intent_from_ai "$USER_INPUT")

  INTENT=$(echo "$RAW_JSON" | jq -r '.intent // empty' 2>/dev/null)
  PARAMS=$(echo "$RAW_JSON" | jq -c '.parameters // {}' 2>/dev/null)

  if [[ -z "$INTENT" ]]; then
    echo "❌ AI returned invalid or empty JSON."
    continue
  fi

  echo "➡️ Detected intent: $INTENT"
  handle_intent "$INTENT" "$PARAMS"
done
