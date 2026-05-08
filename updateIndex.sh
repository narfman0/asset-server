#!/usr/bin/env bash
# Recursively walks the assets directory and writes a complete index.json:
# top-level totals plus per-pack metadata with the full file listing
# (relative path, size in bytes, mtime).
#
# Run on the host (or in a container with env vars set):
#   ASSETS_DIR  source dir whose immediate subdirs are "packs" (default: assets)
#   OUTPUT      destination JSON file (default: ./index.json)
#   URL_PREFIX  served path prefix written into file paths (default: assets)

set -euo pipefail

ASSETS_DIR="${ASSETS_DIR:-assets}"
OUTPUT="${OUTPUT:-./index.json}"
URL_PREFIX="${URL_PREFIX:-assets}"

generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [[ ! -d "$ASSETS_DIR" ]]; then
    echo "updateIndex: assets dir not found: $ASSETS_DIR" >&2
    jq -n --arg g "$generated_at" \
        '{generated_at: $g, pack_count: 0, file_count: 0, total_size_bytes: 0, packs: []}' > "$OUTPUT"
    exit 0
fi

# Recursive walk: TSV with relpath\tsize_bytes\tmtime_epoch.
# Requires GNU find (-printf). Piped straight into jq to avoid
# materializing the file list in shell memory.
( cd "$ASSETS_DIR" && find . -mindepth 1 -type f -printf '%P\t%s\t%T@\n' ) \
| jq -R -s \
    --arg generated_at "$generated_at" \
    --arg url_prefix "$URL_PREFIX" '
    [ split("\n")[]
      | select(length > 0)
      | split("\t")
      | { relpath: .[0],
          size:    (.[1] | tonumber),
          mtime:   (.[2] | tonumber | floor | todate),
          pack:    (if (.[0] | contains("/")) then (.[0] | split("/")[0]) else "_root" end),
          path:    ($url_prefix + "/" + .[0])
        }
    ]
    | group_by(.pack)
    | map({
          name: .[0].pack,
          path: ($url_prefix + "/" + (if .[0].pack == "_root" then "" else (.[0].pack + "/") end)),
          file_count: length,
          total_size_bytes: (map(.size) | add),
          files: map({path, size, mtime})
        })
    | { generated_at: $generated_at,
        pack_count: length,
        file_count: (map(.file_count) | add // 0),
        total_size_bytes: (map(.total_size_bytes) | add // 0),
        packs: .
      }
    ' > "$OUTPUT"

pack_count=$(jq '.pack_count' "$OUTPUT")
file_count=$(jq '.file_count' "$OUTPUT")
total_bytes=$(jq '.total_size_bytes' "$OUTPUT")
echo "updateIndex: wrote $OUTPUT ($pack_count packs, $file_count files, $total_bytes bytes)"
