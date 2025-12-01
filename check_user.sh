#!/usr/bin/env bash
# check_user.sh - verify username + password and print role on success
# Usage: ./check_user.sh --username alice
set -euo pipefail
IFS=$'\n\t'

command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 1; }
command -v shasum >/dev/null 2>&1 || { echo "shasum required"; exit 1; }

USERNAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --username) USERNAME="$2"; shift 2;;
    -h|--help) echo "Usage: $0 --username <name>"; exit 0;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

if [[ -z "$USERNAME" ]]; then
  echo "username required"
  exit 1
fi

USERS_FILE=".mcp/users.json"
if [[ ! -f "$USERS_FILE" ]]; then
  echo "Users file missing: $USERS_FILE"
  exit 1
fi

# prompt for password
printf "Password for %s: " "$USERNAME"
read -s PASSWORD
echo

# fetch salt and stored hash for user
user_entry=$(jq -r --arg u "$USERNAME" '.users[] | select(.username==$u) | @json' "$USERS_FILE" || true)
if [[ -z "$user_entry" ]]; then
  echo "User not found"
  exit 2
fi

SALT=$(echo "$user_entry" | jq -r '.salt')
STORED_HASH=$(echo "$user_entry" | jq -r '.hash')

# compute hash with salt
COMPUTED=$(printf "%s%s" "$SALT" "$PASSWORD" | shasum -a 256 | awk '{print $1}')

if [[ "$COMPUTED" == "$STORED_HASH" ]]; then
  ROLE=$(echo "$user_entry" | jq -r '.role')
  echo "$ROLE"
  exit 0
else
  echo "Authentication failed"
  exit 3
fi
