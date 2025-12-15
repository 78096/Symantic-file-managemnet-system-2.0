#!/usr/local/bin/bash

# Load .env if present
if [ -f .env ]; then
  set -o allexport
  source .env
  set +o allexport
fi

#  LOGGING MODULE 
LOG_FILE="semsh.log"

log_event() {
  local status="$1"
  local action="$2"
  local details="$3"
  local timestamp
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")

  echo "$timestamp | user=$INPUT_USERNAME | role=$USER_ROLE | action=$action | status=$status | $details" >> "$LOG_FILE"
}
# ==================================================

# Path to user credentials and roles
USERS_FILE=".users.json"
SANDBOX_DIR="${SANDBOX_DIR:-/Users/a1989/Desktop/sandbox}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-4-0613}"

# Check required env vars
if [[ -z "$SANDBOX_DIR" ]]; then
  echo "SANDBOX_DIR not set in environment."
  exit 1
fi
if [[ -z "$OPENAI_API_KEY" ]]; then
  echo "OPENAI_API_KEY not set in environment."
  exit 1
fi

# Function to prompt for password silently
prompt_password() {
  stty -echo
  printf "Enter password: "
  read -r PASSWORD
  stty echo
  echo
}

# Authenticate user
authenticate_user() {
  local username=$1
  local password=$2

  local user_json
  user_json=$(jq -r --arg u "$username" '.users[] | select(.username == $u)' "$USERS_FILE")

  [[ -z "$user_json" ]] && return 1

  local stored_pass role
  stored_pass=$(echo "$user_json" | jq -r '.password')
  role=$(echo "$user_json" | jq -r '.role')

  local input_hash
  input_hash=$(echo -n "$password" | shasum -a 256 | awk '{print $1}')

  if [[ "$input_hash" == "$stored_pass" ]]; then
    USER_ROLE=$role
    return 0
  else
    return 1
  fi
}

# ==== LOGIN LOOP ====
while true; do
  read -p "Enter username: " INPUT_USERNAME

  if jq -e --arg u "$INPUT_USERNAME" '.users[] | select(.username == $u)' "$USERS_FILE" > /dev/null 2>&1; then
    prompt_password

    if authenticate_user "$INPUT_USERNAME" "$PASSWORD"; then
      echo "🔐 Active user role: $USER_ROLE"
      log_event "SUCCESS" "login" "user logged in"
      break
    else
      echo "❌ Invalid password."
      log_event "FAIL" "login" "invalid password"
    fi
  else
    echo "❌ User not found."
  fi
done

# ==== PERMISSIONS ====
declare -A PERMISSIONS
case "$USER_ROLE" in
  admin) PERMISSIONS=( ["list_files"]=1 ["create_file"]=1 ["delete_file"]=1 ["move_file"]=1 ["read_file"]=1 ) ;;
  manager) PERMISSIONS=( ["list_files"]=1 ["create_file"]=1 ["move_file"]=1 ["read_file"]=1 ) ;;
  employee) PERMISSIONS=( ["list_files"]=1 ["read_file"]=1 ) ;;
  *) echo "Unknown role"; exit 1 ;;
esac

echo "Allowed actions: ${!PERMISSIONS[@]}"
echo "------------------------------------------------------"
echo "🔧 SEMSH interactive mode started."
echo "Type English commands. Type 'exit' to quit."
echo "------------------------------------------------------"

# ==== MAIN LOOP ====
while true; do
  echo -n "semsh> "
  read -r USER_INPUT
  [[ "$USER_INPUT" == "exit" ]] && log_event "INFO" "logout" "user exited shell" && break
  [[ -z "$USER_INPUT" ]] && continue

AI_RESPONSE=$(curl -s https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d @- <<EOF
{
  "model": "$OPENAI_MODEL",
  "messages": [
    {
      "role": "system",
      "content": "You MUST reply ONLY with pure JSON: {\"action\":\"list_files|create_file|delete_file|move_file|read_file\",\"parameters\":{}}"
    },
    {
      "role": "user",
      "content": $(printf '%s' "$USER_INPUT" | jq -R .)
    }
  ],
  "temperature": 0
}
EOF
)

RAW_CONTENT=$(echo "$AI_RESPONSE" | jq -r '.choices[0].message.content // empty')

ACTION=$(echo "$RAW_CONTENT" | jq -r '.action // empty')
PARAMETERS=$(echo "$RAW_CONTENT" | jq -c '.parameters // {}')

[[ -z "$ACTION" ]] && echo "❌ No action found." && log_event "FAIL" "ai_parse" "no action" && continue
[[ -z "${PERMISSIONS[$ACTION]}" ]] && echo "❌ No permission." && log_event "FAIL" "$ACTION" "permission denied" && continue

case "$ACTION" in
  list_files)
    DIR=$(echo "$PARAMETERS" | jq -r '.directory // "."')
    TARGET="$SANDBOX_DIR/$DIR"
    if [[ ! -d "$TARGET" ]]; then
      echo "Directory does not exist."
      log_event "FAIL" "list_files" "dir=$DIR"
    else
      ls -1 "$TARGET"
      log_event "SUCCESS" "list_files" "dir=$DIR"
    fi
    ;;

  create_file)
    FILE=$(echo "$PARAMETERS" | jq -r '.name // .filename // empty')
    if [[ -z "$FILE" ]]; then
      echo "File name missing."
      log_event "FAIL" "create_file" "missing filename"
    else
      touch "$SANDBOX_DIR/$FILE"
      echo "File created."
      log_event "SUCCESS" "create_file" "file=$FILE"
    fi
    ;;

  delete_file)
    FILE=$(echo "$PARAMETERS" | jq -r '.name // .filename // empty')
    if [[ -z "$FILE" ]]; then
      echo "File name missing."
      log_event "FAIL" "delete_file" "missing filename"
    else
      rm -i "$SANDBOX_DIR/$FILE"
      log_event "SUCCESS" "delete_file" "file=$FILE"
    fi
    ;;

  move_file)
    SRC=$(echo "$PARAMETERS" | jq -r '.source // empty')
    DEST=$(echo "$PARAMETERS" | jq -r '.destination // empty')
    if [[ -z "$SRC" || -z "$DEST" ]]; then
      echo "Missing source/destination."
      log_event "FAIL" "move_file" "src=$SRC dest=$DEST"
    else
      mv "$SANDBOX_DIR/$SRC" "$SANDBOX_DIR/$DEST"
      echo "Moved."
      log_event "SUCCESS" "move_file" "from=$SRC to=$DEST"
    fi
    ;;

  read_file)
    FILE=$(echo "$PARAMETERS" | jq -r '.name // .filename // empty')
    if [[ ! -f "$SANDBOX_DIR/$FILE" ]]; then
      echo "Missing file."
      log_event "FAIL" "read_file" "file=$FILE"
    else
      cat "$SANDBOX_DIR/$FILE"
      log_event "SUCCESS" "read_file" "file=$FILE"
    fi
    ;;
esac

done

echo "Bye!"
