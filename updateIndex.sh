#!/usr/bin/env bash
# Walks the assets directory and writes a structured index.json describing
# each top-level pack (name, served path, file count, total size in bytes).
# Run at container startup; rerun whenever the asset volume changes.

set -euo pipefail

ASSETS_DIR="${ASSETS_DIR:-assets}"
OUTPUT="${OUTPUT:-./index.json}"

if [[ ! -d "$ASSETS_DIR" ]]; then
    echo "updateIndex: assets dir not found: $ASSETS_DIR" >&2
    # write an empty index so nginx has something to serve at /
    jq -n '{generated_at: now | todateiso8601, pack_count: 0, packs: []}' > "$OUTPUT"
    exit 0
fi

cd "$ASSETS_DIR"

pack_json=$(
    for dir in */; do
        [[ -d "$dir" ]] || continue
        pack="${dir%/}"
        file_count=$(find "$pack" -type f | wc -l | tr -d ' ')
        total_size=$(find "$pack" -type f -exec stat -c%s {} + 2>/dev/null \
            | awk '{s+=$1} END {print s+0}')
        jq -n \
            --arg name "$pack" \
            --arg path "assets/$pack/" \
            --argjson file_count "$file_count" \
            --argjson total_size "$total_size" \
            '{name: $name, path: $path, file_count: $file_count, total_size_bytes: $total_size}'
    done | jq -s '.'
)

jq -n \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson packs "$pack_json" \
    '{generated_at: $generated_at, pack_count: ($packs | length), packs: $packs}' > "$OUTPUT"

echo "updateIndex: wrote $OUTPUT ($(jq '.pack_count' "$OUTPUT") packs)"
