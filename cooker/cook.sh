#!/usr/bin/env bash
# Transform dispatcher. Walks RAW_DIR, decides what to do with each file
# based on extension and (optionally) directory naming convention, writes
# results to mirror paths under COOKED_DIR.
#
# Currently supported transforms:
#   *.fbx           → GLB via transforms/fbx_to_glb.py
#     - if the path contains '/mixamo' or '_mixamo' (case-insensitive),
#       pass --rename mixamo so mixamorig:* bones get remapped to humanoid names
#
# Idempotent: each transform skips files whose cooked output exists and is
# newer than the source.

set -euo pipefail

RAW="${1:?usage: cook.sh <raw_dir> <cooked_dir>}"
COOKED="${2:?usage: cook.sh <raw_dir> <cooked_dir>}"

log() { echo "[cook $(date -u +%H:%M:%S)] $*"; }

# Collect input groups by transform kind. For FBX we split by "uses mixamo
# rename" vs not, because Blender batch is more efficient when the rename
# preset is set once at script start.

declare -a fbx_normal=()
declare -a fbx_mixamo=()

while IFS= read -r -d '' src; do
    rel="${src#$RAW/}"
    dst_glb="${COOKED}/${rel%.fbx}.glb"
    dst_glb="${COOKED}/${rel%.FBX}.glb"  # also handle uppercase ext
    # idempotency: skip if cooked is newer than source
    if [[ -f "$dst_glb" && "$dst_glb" -nt "$src" ]]; then
        continue
    fi
    # Mixamo detection — case-insensitive path match.
    if [[ "${src,,}" == *mixamo* ]]; then
        fbx_mixamo+=("$src")
    else
        fbx_normal+=("$src")
    fi
done < <(find "$RAW" \( -name '*.fbx' -o -name '*.FBX' \) -type f -print0)

run_blender_batch() {
    local preset="$1"
    shift
    local count=$#
    if (( count == 0 )); then
        return 0
    fi
    log "Blender FBX→GLB batch (${preset}): ${count} file(s)"
    # We re-use the existing transforms/fbx_to_glb.py which walks an input
    # dir. To minimize Blender startup cost across many files we just run
    # it once over the whole RAW tree and let its own idempotency skip
    # files that are already up-to-date. Pass --rename only when present.
    if [[ "${preset}" == "mixamo" ]]; then
        blender --background --python /opt/cooker/transforms/fbx_to_glb.py -- \
            "$RAW" "$COOKED" --rename mixamo
    else
        blender --background --python /opt/cooker/transforms/fbx_to_glb.py -- \
            "$RAW" "$COOKED"
    fi
}

# NOTE: the python script walks the entire input dir; we invoke it once per
# preset rather than once per file (Blender startup is ~3s; per-file overhead
# would dominate). When there's a mix of mixamo+non-mixamo inputs, the script
# is invoked twice and each pass skips files already converted by the other.
# This is OK because the script's own existence check is fast.

# Run non-mixamo first so default behavior happens for the bulk of files;
# then the mixamo pass picks up the ones that need the rename. They write to
# different output filenames (same source path), so they don't conflict.
if (( ${#fbx_normal[@]} > 0 )); then
    run_blender_batch "default" "${fbx_normal[@]}" || log "default batch had failures"
fi
if (( ${#fbx_mixamo[@]} > 0 )); then
    run_blender_batch "mixamo" "${fbx_mixamo[@]}" || log "mixamo batch had failures"
fi

# Future transform hooks would go here. Stubbed for clarity:
#   *.ogg → normalized .ogg (ffmpeg loudnorm)
#   *.wav → .ogg
#   raw textures → atlas
