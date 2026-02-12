#!/usr/local/bin/bash
# INDEXER

INDEX_DIR=".mcp"
INDEX_FILE="$INDEX_DIR/file_index.json"
SANDBOX_DIR="/Users/Shared/semsh_sandbox"

mkdir -p "$INDEX_DIR"
mkdir -p "$SANDBOX_DIR"

echo '{"files":{}}' > "$INDEX_FILE"

detect_type() {
  local file="$1"
  if [ -d "$file" ]; then
    echo "directory"
    return
  fi
  case "$file" in
    *.txt|*.log|*.md|*.json|*.csv|*.sh|*.py|*.c|*.cpp|*.java) echo "text" ;;
    *.jpg|*.png|*.jpeg|*.gif) echo "image" ;;
    *.pdf) echo "pdf" ;;
    *.zip|*.tar|*.gz) echo "archive" ;;
    *) echo "binary" ;;
  esac
}

file_preview() {
  local file="$1"
  if [ -d "$file" ]; then
    echo '""'
  elif file "$file" | grep -q "text"; then
    head -n 5 "$file" 2>/dev/null | tr '\n' ' ' | jq -R .
  else
    echo '""'
  fi
}

find "$SANDBOX_DIR" \( -type f -o -type d \) | while read -r file; do
  relpath="${file#$SANDBOX_DIR/}"
  name=$(basename "$file")

  size=0
  if [ -f "$file" ]; then
    size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file")
  fi

  created=$(date -r "$file" +"%Y-%m-%d" 2>/dev/null || echo "unknown")
  modified=$(date -r "$file" +"%Y-%m-%d" 2>/dev/null || echo "unknown")

  ftype=$(detect_type "$file")
  preview=$(file_preview "$file")

  jq --arg name "$name" \
     --arg path "$relpath" \
     --arg created "$created" \
     --arg modified "$modified" \
     --arg type "$ftype" \
     --argjson size "$size" \
     --argjson preview "$preview" \
  '
  .files[$name] = {
     "path": $path,
     "size": $size,
     "created": $created,
     "modified": $modified,
     "type": $type,
     "preview": $preview
  }
  ' "$INDEX_FILE" > "$INDEX_FILE.tmp" && mv "$INDEX_FILE.tmp" "$INDEX_FILE"
done

echo "Index rebuilt."
