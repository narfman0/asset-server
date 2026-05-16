#!/usr/bin/env bash
# Walks both the cooked and raw asset directories and writes a combined index.json:
#   { generated_at, cooked: { pack_count, file_count, total_size_bytes, packs: [...] },
#                    raw:    { pack_count, file_count, total_size_bytes, packs: [...] } }
#
# Override env vars to invoke from a host shell:
#   COOKED_DIR   cooked assets tree (GLBs etc.) — served at URL_PREFIX_COOKED
#   RAW_DIR      raw source tree (FBX etc.)      — served at URL_PREFIX_RAW
#   OUTPUT       destination JSON file
#   URL_PREFIX_COOKED  default: assets
#   URL_PREFIX_RAW     default: raw

set -euo pipefail

COOKED_DIR="${COOKED_DIR:-/usr/share/nginx/html/assets}"
RAW_DIR="${RAW_DIR:-/raw}"
OUTPUT="${OUTPUT:-/usr/share/nginx/html/index.json}"
URL_PREFIX_COOKED="${URL_PREFIX_COOKED:-assets}"
URL_PREFIX_RAW="${URL_PREFIX_RAW:-raw}"

generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Emit per-pack JSON for one tree. Args: <dir> <url_prefix>
index_tree() {
    local dir="$1"
    local prefix="$2"

    if [[ ! -d "$dir" ]]; then
        echo '{"pack_count":0,"file_count":0,"total_size_bytes":0,"packs":[]}'
        return
    fi

    ( cd "$dir" && find . -mindepth 1 -type f -printf '%P\t%s\t%T@\n' ) \
    | jq -R -s \
        --arg url_prefix "$prefix" '
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
        | { pack_count: length,
            file_count: (map(.file_count) | add // 0),
            total_size_bytes: (map(.total_size_bytes) | add // 0),
            packs: .
          }
        '
}

cooked_tmp=$(mktemp)
raw_tmp=$(mktemp)
trap 'rm -f "$cooked_tmp" "$raw_tmp"' EXIT

index_tree "$COOKED_DIR" "$URL_PREFIX_COOKED" > "$cooked_tmp"
index_tree "$RAW_DIR"    "$URL_PREFIX_RAW"    > "$raw_tmp"

jq -n \
    --arg generated_at "$generated_at" \
    --slurpfile cooked "$cooked_tmp" \
    --slurpfile raw    "$raw_tmp" \
    '{ generated_at: $generated_at, cooked: $cooked[0], raw: $raw[0] }' \
    > "$OUTPUT"

cooked_packs=$(jq '.pack_count' "$cooked_tmp")
cooked_files=$(jq '.file_count' "$cooked_tmp")
raw_packs=$(jq '.pack_count' "$raw_tmp")
raw_files=$(jq '.file_count' "$raw_tmp")
echo "updateIndex: wrote $OUTPUT (cooked: $cooked_packs packs / $cooked_files files; raw: $raw_packs packs / $raw_files files)"
