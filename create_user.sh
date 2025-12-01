#!/usr/bin/env bash
# create_user.sh - create a user in .mcp/users.json
# Usage: ./create_user.sh --username alice --role editor
set -euo pipefail
IFS=$'\n\t'

# ensure jq & openssl/shasum exist
command -v jq >/dev/null 2>&1 || { echo "jq is required. Install with brew install jq"; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "openssl is required."; exit 1; }
command -v shasum >/dev/null 2>&1 || { echo "shasum is required."; exit 1; }

# parse args
USERNAME=""
ROLE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --username) USERNAME="$2"; shift 2;;
    --role) ROLE="$2"; shift 2;;
    -h|--help) echo "Usage: $0 --username <name> --role <admin|editor|viewer>"; exit 0;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

if [[ -z "$USERNAME" || -z "$ROLE" ]]; then
  echo "ERROR: username and role required. Example: $0 --username alice --role editor"
  exit 1
fi

if [[ "$ROLE" != "admin" && "$ROLE" != "editor" && "$ROLE" != "viewer" ]]; then
  echo "ERROR: role must be one of: admin, editor, viewer"
  exit 1
fi

# prepare .mcp folder and users file
MCP_DIR=".mcp"
USERS_FILE="$MCP_DIR/users.json"
mkdir -p "$MCP_DIR"
if [[ ! -f "$USERS_FILE" ]]; then
  echo '{"users": []}' > "$USERS_FILE"
fi

# prompt for password (hidden)
printf "Enter password for user '%s': " "$USERNAME"
read -s PASSWORD
echo
printf "Confirm password: "
read -s PASSWORD2
echo
if [[ "$PASSWORD" != "$PASSWORD2" ]]; then
  echo "Passwords do not match."
  exit 1
fi

# create salt and hash (salted sha256)
SALT=$(openssl rand -hex 12)
# combine salt + password and compute sha256
HASH=$(printf "%s%s" "$SALT" "$PASSWORD" | shasum -a 256 | awk '{print $1}')

# check if user already exists
exists=$(jq --arg u "$USERNAME" '.users[] | select(.username==$u) | .username' "$USERS_FILE" || true)
if [[ -n "$exists" ]]; then
  echo "ERROR: user '$USERNAME' already exists."
  exit 1
fi

# add user object
jq --arg u "$USERNAME" --arg r "$ROLE" --arg s "$SALT" --arg h "$HASH" \
  '.users += [{username:$u, role:$r, salt:$s, hash:$h}]' \
  "$USERS_FILE" > "$USERS_FILE.tmp" && mv "$USERS_FILE.tmp" "$USERS_FILE"

echo "User '$USERNAME' created with role '$ROLE'."
echo "Stored in $USERS_FILE"
