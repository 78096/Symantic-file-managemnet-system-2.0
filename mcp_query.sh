#!/usr/local/bin/bash
# QUERY

INDEX_FILE=".mcp/file_index.json"

QUERY_JSON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) QUERY_JSON="$2"; shift 2 ;;
  esac
done

if [[ -z "$QUERY_JSON" || ! -f "$QUERY_JSON" ]]; then
  echo "Invalid query."
  exit 1
fi

PARAMS=$(cat "$QUERY_JSON")

FROM=$(echo "$PARAMS" | jq -r '.date_range.from // empty')
TO=$(echo "$PARAMS"   | jq -r '.date_range.to // empty')
CONTAINS=$(echo "$PARAMS" | jq -r '.contains // empty')
TYPE=$(echo "$PARAMS" | jq -r '.type // empty')

# -------------------------------
# DATE NORMALIZATION
# -------------------------------

today() { date +"%Y-%m-%d"; }
yesterday() { date -v -1d +"%Y-%m-%d" 2>/dev/null || date -d "yesterday" +"%Y-%m-%d"; }
last_week() { date -v -7d +"%Y-%m-%d" 2>/dev/null || date -d "7 days ago" +"%Y-%m-%d"; }

normalize_date() {
  case "$1" in
    today) today ;;
    yesterday) yesterday ;;
    last_week) last_week ;;
    "") echo "" ;;
    *) echo "$1" ;;
  esac
}

FROM_NORM=$(normalize_date "$FROM")
TO_NORM=$(normalize_date "$TO")

# If only FROM is provided, assume same day range
if [[ -n "$FROM_NORM" && -z "$TO_NORM" ]]; then
  TO_NORM="$FROM_NORM"
fi

# -------------------------------
# QUERY
# -------------------------------

RESULT=$(jq -r \
  --arg from "$FROM_NORM" \
  --arg to "$TO_NORM" \
  --arg contains "$CONTAINS" \
  --arg type "$TYPE" \
'
.files
| to_entries[]
| select(
    ($from == "" and $to == "") or
    (.value.created >= $from and .value.created <= $to)
  )
| select(
    ($contains == "" or
     (.value.preview | ascii_downcase | contains($contains | ascii_downcase)))
  )
| select(
    ($type == "" or
     ($type == "folder" and .value.type == "directory") or
     ($type == "file" and .value.type != "directory"))
  )
| {
   filename: .key,
   path: .value.path,
   size: .value.size,
   created: .value.created,
   modified: .value.modified,
   type: .value.type,
   preview: .value.preview
}
' "$INDEX_FILE")

if [[ -z "$RESULT" ]]; then
  echo "No results."
  exit 0
fi

echo "$RESULT" | jq -s .
