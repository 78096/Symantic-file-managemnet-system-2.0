#!/usr/local/bin/bash

# Load .env if present
if [ -f .env ]; then
  set -o allexport
  source .env
  set +o allexport
fi

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

# Authenticate user, returns 0 if success, 1 if fail
authenticate_user() {
  local username=$1
  local password=$2

  # Use jq to extract user JSON object
  local user_json
  user_json=$(jq -r --arg u "$username" '.users[] | select(.username == $u)' "$USERS_FILE")

  if [[ -z "$user_json" ]]; then
    return 1
  fi

  local stored_pass role
  stored_pass=$(echo "$user_json" | jq -r '.password')
  role=$(echo "$user_json" | jq -r '.role')

  # Hash input password with SHA256
  local input_hash
  input_hash=$(echo -n "$password" | shasum -a 256 | awk '{print $1}')

  if [[ "$input_hash" == "$stored_pass" ]]; then
    USER_ROLE=$role
    return 0
  else
    return 1
  fi
}

# Add new user function
add_new_user() {
  echo "Creating new user: $NEW_USERNAME"
  # Ask new password for user
  echo "Set password for $NEW_USERNAME:"
  prompt_password
  local new_user_pass
  new_user_pass=$(echo -n "$PASSWORD" | shasum -a 256 | awk '{print $1}')

  # Ask for admin credentials to authorize
  echo "Admin authorization required to create new user."
  read -p "Admin username: " ADMIN_USER
  prompt_password
  local admin_pass=$PASSWORD

  if ! authenticate_user "$ADMIN_USER" "$admin_pass"; then
    echo "❌ Admin authentication failed. Cannot create new user."
    return 1
  fi

  if [[ "$USER_ROLE" != "admin" ]]; then
    echo "❌ User $ADMIN_USER is not authorized to create users."
    return 1
  fi

  # Ask for new user role
  echo "Set role for $NEW_USERNAME (admin/manager/employee): "
  read -r NEW_ROLE

  if [[ "$NEW_ROLE" != "admin" && "$NEW_ROLE" != "manager" && "$NEW_ROLE" != "employee" ]]; then
    echo "Invalid role. Aborting user creation."
    return 1
  fi

  # Append new user JSON to .users.json file
  # Read current users array
  users_array=$(jq '.users' "$USERS_FILE")

  # Create new user JSON object
  new_user_json="{\"username\":\"$NEW_USERNAME\",\"password\":\"$new_user_pass\",\"role\":\"$NEW_ROLE\"}"

  # Append new user and save back to file
  jq --argjson newUser "$new_user_json" '.users += [$newUser]' "$USERS_FILE" > "${USERS_FILE}.tmp" && mv "${USERS_FILE}.tmp" "$USERS_FILE"

  echo "✅ User $NEW_USERNAME created with role $NEW_ROLE."

  return 0
}

# ==== LOGIN / CREATE LOOP ====
while true; do
  read -p "Enter username: " INPUT_USERNAME

  # Check if user exists
  if jq -e --arg u "$INPUT_USERNAME" '.users[] | select(.username == $u)' "$USERS_FILE" > /dev/null 2>&1; then
    # User exists, ask password to login
    prompt_password

    if authenticate_user "$INPUT_USERNAME" "$PASSWORD"; then
      echo "🔐 Active user role: $USER_ROLE"
      break
    else
      echo "❌ Invalid password. Try again."
    fi
  else
    # User doesn't exist - trigger creation flow
    NEW_USERNAME=$INPUT_USERNAME
    echo "User $NEW_USERNAME not found."
    read -p "Create new user? (yes/no): " create_choice
    if [[ "$create_choice" == "yes" ]]; then
      if add_new_user; then
        echo "You can now login with new credentials."
      fi
    fi
  fi
done

# ==== SET PERMISSIONS ====
declare -A PERMISSIONS
case "$USER_ROLE" in
  admin)
    PERMISSIONS=( ["list_files"]=1 ["create_file"]=1 ["delete_file"]=1 ["move_file"]=1 ["read_file"]=1 )
    ;;
  manager)
    PERMISSIONS=( ["list_files"]=1 ["create_file"]=1 ["move_file"]=1 ["read_file"]=1 )
    ;;
  employee)
    PERMISSIONS=( ["list_files"]=1 ["read_file"]=1 )
    ;;
  *)
    echo "Unknown role, no permissions granted."
    exit 1
    ;;
esac

echo "Allowed actions: ${!PERMISSIONS[@]}"
echo "------------------------------------------------------"
echo "🔧 SEMSH interactive mode started."
echo "Type English commands. Type 'exit' to quit."
echo "------------------------------------------------------"

# ==== MAIN REPL LOOP ====

while true; do
  echo -n "semsh> "
  read -r USER_INPUT
  [[ "$USER_INPUT" == "exit" ]] && break
  [[ -z "$USER_INPUT" ]] && continue

  # Call AI API to get action and parameters JSON
  AI_RESPONSE=$(curl -s https://api.openai.com/v1/chat/completions \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d @- <<EOF
{
  "model": "$OPENAI_MODEL",
  "messages": [
    {"role": "system", "content": "You are an assistant that ONLY replies with a JSON object with exactly two keys: 'action' and 'parameters'. Allowed actions are: list_files, create_file, delete_file, move_file, read_file. The 'parameters' value should be an object with needed keys for the action, or empty object if none."},
    {"role": "user", "content": "$USER_INPUT"}
  ],
  "temperature": 0
}
EOF
)

  # Extract raw content from AI response
  RAW_CONTENT=$(echo "$AI_RESPONSE" | jq -r '.choices[0].message.content')

 # Use RAW_CONTENT directly since it's valid JSON
ACTION=$(echo "$RAW_CONTENT" | jq -r '.action // empty')
PARAMETERS=$(echo "$RAW_CONTENT" | jq -c '.parameters // {}')

  if [[ -z "$ACTION" ]]; then
    echo "❌ No action found in AI response."
    continue
  fi

  # Check permission for action
  if [[ -z "${PERMISSIONS[$ACTION]}" ]]; then
    echo "❌ You do not have permission to perform '$ACTION'."
    continue
  fi

  # Process actions
  case "$ACTION" in
    list_files)
      DIR_PARAM=$(echo "$PARAMETERS" | jq -r '.directory // "."')
      TARGET_DIR="$SANDBOX_DIR/$DIR_PARAM"
      if [[ ! -d "$TARGET_DIR" ]]; then
        echo "Directory does not exist: $TARGET_DIR"
      else
        echo "Listing files in $TARGET_DIR:"
        ls -1 "$TARGET_DIR"
      fi
      ;;

    create_file)
      FILE_NAME=$(echo "$PARAMETERS" | jq -r '.name // empty')
      if [[ -z "$FILE_NAME" ]]; then
        echo "File name missing."
      else
        touch "$SANDBOX_DIR/$FILE_NAME" && echo "File created: $SANDBOX_DIR/$FILE_NAME"
      fi
      ;;

    delete_file)
      FILE_NAME=$(echo "$PARAMETERS" | jq -r '.name // empty')
      if [[ -z "$FILE_NAME" ]]; then
        echo "File name missing."
      else
        rm -i "$SANDBOX_DIR/$FILE_NAME" && echo "File deleted: $SANDBOX_DIR/$FILE_NAME"
      fi
      ;;

    move_file)
      SRC=$(echo "$PARAMETERS" | jq -r '.source // empty')
      DEST=$(echo "$PARAMETERS" | jq -r '.destination // empty')
      if [[ -z "$SRC" || -z "$DEST" ]]; then
        echo "Source or destination missing."
      else
        mv "$SANDBOX_DIR/$SRC" "$SANDBOX_DIR/$DEST" && echo "Moved $SRC to $DEST"
      fi
      ;;

    read_file)
      FILE_NAME=$(echo "$PARAMETERS" | jq -r '.name // empty')
      if [[ -z "$FILE_NAME" ]]; then
        echo "File name missing."
      else
        if [[ -f "$SANDBOX_DIR/$FILE_NAME" ]]; then
          echo "Contents of $FILE_NAME:"
          cat "$SANDBOX_DIR/$FILE_NAME"
        else
          echo "File does not exist: $SANDBOX_DIR/$FILE_NAME"
        fi
      fi
      ;;

    *)
      echo "Unknown action: $ACTION"
      ;;
  esac

done

echo "Bye!"
