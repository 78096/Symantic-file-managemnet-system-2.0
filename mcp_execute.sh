#!/usr/bin/env bash
# mcp_execute.sh — safe execution wrapper for admin actions inside SANDBOX_DIR
# Usage examples:
#  ./mcp_execute.sh --action grep --file "logs/app.log" --pattern "Error 104"
#  ./mcp_execute.sh --action cp --file "a.txt" --dest "backup/a.txt"
#  ./mcp_execute.sh --action sed_replace --file "logs/app.log" --pattern "OLD" --replace "NEW" --dry-run

set -euo pipefail
IFS=$'\n\t'

# Load .env
if [[ -f .env ]]; then
  export $(grep -v '^\s*#' .env | xargs)
fi

: "${SANDBOX_DIR:?Set SANDBOX_DIR in .env}"
LOGFILE=".mcp/actions.log"
PASSFILE=".admin_pass"  # created by semsh if using admin flow
DRY_RUN=0

# Simple arg parsing
ACTION=""
FILE=""
FILE2=""
PATTERN=""
REPLACE=""
DEST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action) ACTION="$2"; shift 2;;
    --file) FILE="$2"; shift 2;;
    --file2) FILE2="$2"; shift 2;;
    --pattern) PATTERN="$2"; shift 2;;
    --replace) REPLACE="$2"; shift 2;;
    --dest) DEST="$2"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    -h|--help) echo "Usage: --action <grep|sed_replace|cp|mv|diff|cat> --file <path> ..."; exit 0;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

log() {
  mkdir -p "$(dirname "$LOGFILE")"
  echo "$(date '+%Y-%m-%d %H:%M:%S') ACTION=$ACTION FILE=${FILE:-} FILE2=${FILE2:-} PATTERN=${PATTERN:-} DEST=${DEST:-} DRY_RUN=$DRY_RUN" >> "$LOGFILE"
}

in_sandbox() {
  # Accept relative paths that resolve inside SANDBOX_DIR
  local p="$1"
  # Avoid absolute paths; convert relative to sandbox
  if [[ "$p" == /* ]]; then
    # absolute: check realpath prefix
    rp=$(realpath "$p" 2>/dev/null || echo "")
  else
    rp=$(realpath "$SANDBOX_DIR/$p" 2>/dev/null || echo "")
  fi
  [[ -n "$rp" ]] || return 1
  case "$rp" in
    "$SANDBOX_DIR"/*|"$SANDBOX_DIR") return 0;;
    *) return 1;;
  esac
}

# Verify admin password (either via PASSFILE or manual confirmation)
verify_admin() {
  if [[ -f "$PASSFILE" ]]; then
    printf "Admin password: "
    read -s attempt; echo
    stored=$(cat "$PASSFILE")
    if [[ "$attempt" != "$stored" ]]; then
      echo "Auth failed."
      exit 1
    fi
  else
    read -p "Type 'I AM ADMIN' to confirm: " ans
    if [[ "$ans" != "I AM ADMIN" ]]; then
      echo "Confirmation failed."
      exit 1
    fi
  fi
}

# Dispatcher
case "$ACTION" in
  grep)
    if [[ -z "$FILE" || -z "$PATTERN" ]]; then echo "missing args"; exit 1; fi
    if ! in_sandbox "$FILE"; then echo "file outside sandbox"; exit 1; fi
    verify_admin
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[DRY] grep -n --color=always -- \"$PATTERN\" \"$SANDBOX_DIR/$FILE\""
      log; exit 0
    fi
    grep -n --color=always -- "$PATTERN" "$SANDBOX_DIR/$FILE" || true
    log
    ;;

  sed_replace)
    if [[ -z "$FILE" || -z "$PATTERN" || -z "$REPLACE" ]]; then echo "missing args"; exit 1; fi
    if ! in_sandbox "$FILE"; then echo "file outside sandbox"; exit 1; fi
    verify_admin
    echo "About to replace pattern in $FILE"
    read -p "Confirm replacement? (y/N): " c
    if [[ "$c" != "y" && "$c" != "Y" ]]; then echo "Cancelled"; exit 0; fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[DRY] sed -i.bak -e 's/${PATTERN}/${REPLACE}/g' \"$SANDBOX_DIR/$FILE\""
      log; exit 0
    fi
    sed -i.bak -e "s/${PATTERN}/${REPLACE}/g" "$SANDBOX_DIR/$FILE" && echo "Replacements done. Backup saved to ${SANDBOX_DIR}/${FILE}.bak"
    log
    ;;

  cp)
    if [[ -z "$FILE" || -z "$DEST" ]]; then echo "missing args"; exit 1; fi
    if ! in_sandbox "$FILE" || ! in_sandbox "$DEST"; then echo "paths must be in sandbox"; exit 1; fi
    verify_admin
    if [[ "$DRY_RUN" -eq 1 ]]; then echo "[DRY] cp \"$SANDBOX_DIR/$FILE\" \"$SANDBOX_DIR/$DEST\""; log; exit 0; fi
    cp -r "$SANDBOX_DIR/$FILE" "$SANDBOX_DIR/$DEST" && echo "Copied."; log
    ;;

  mv)
    if [[ -z "$FILE" || -z "$DEST" ]]; then echo "missing args"; exit 1; fi
    if ! in_sandbox "$FILE" || ! in_sandbox "$DEST"; then echo "paths must be in sandbox"; exit 1; fi
    verify_admin
    if [[ "$DRY_RUN" -eq 1 ]]; then echo "[DRY] mv \"$SANDBOX_DIR/$FILE\" \"$SANDBOX_DIR/$DEST\""; log; exit 0; fi
    mv "$SANDBOX_DIR/$FILE" "$SANDBOX_DIR/$DEST" && echo "Moved."; log
    ;;

  diff)
    if [[ -z "$FILE" || -z "$FILE2" ]]; then echo "missing args"; exit 1; fi
    if ! in_sandbox "$FILE" || ! in_sandbox "$FILE2"; then echo "paths must be inside sandbox"; exit 1; fi
    verify_admin
    diff -u "$SANDBOX_DIR/$FILE" "$SANDBOX_DIR/$FILE2" || true
    log
    ;;

  cat)
    if [[ -z "$FILE" ]]; then echo "missing args"; exit 1; fi
    if ! in_sandbox "$FILE"; then echo "file outside sandbox"; exit 1; fi
    # cat is non-destructive; still log and require minimal confirmation
    read -p "View file $FILE? (y/N): " c
    if [[ "$c" != "y" && "$c" != "Y" ]]; then echo "Cancelled"; exit 0; fi
    cat "$SANDBOX_DIR/$FILE"
    log
    ;;

  *)
    echo "Unknown action: ${ACTION:-}"
    exit 1
    ;;
esac
