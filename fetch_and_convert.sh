#!/bin/bash
# Downloads selected Synty packs from asset server and converts FBX -> GLB
# Usage: ./fetch_and_convert.sh [pack_name]
#
# Available Cindertide-relevant packs (use exact names):
#   POLYGON_SciFi_Horror_SourceFiles_v2
#   POLYGON_Prototype_SourceFiles_v4
#   POLYGON_Western_Pack_Source_Files_v4
#   POLYGON_CyberCity_SourceFiles_v3
#
# Example: ./fetch_and_convert.sh POLYGON_SciFi_Horror_SourceFiles_v2

set -e

ASSET_SERVER="http://srv:49200"
DOWNLOAD_DIR="${HOME}/.cindertide/assets/raw"
CONVERTED_DIR="${HOME}/.cindertide/assets/converted"
BLENDER=$(which blender 2>/dev/null || echo "flatpak run org.blender.Blender")
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PACK="${1:-POLYGON_SciFi_Horror_SourceFiles_v2}"

echo "=== Downloading pack: $PACK ==="
mkdir -p "$DOWNLOAD_DIR/$PACK"

# Fetch index and filter FBX files for this pack (files are under assets/<pack_name>/...)
curl -s "$ASSET_SERVER/index.json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
pack = '$PACK'
# Find the matching pack entry by name
matched = None
for p in data.get('packs', []):
    if p['name'] == pack:
        matched = p
        break
if matched is None:
    print(f'ERROR: pack \"{pack}\" not found', file=sys.stderr)
    print('Available packs:', file=sys.stderr)
    for p in data.get('packs', []):
        print(f'  {p[\"name\"]}', file=sys.stderr)
    sys.exit(1)
for f in matched.get('files', []):
    fpath = f['path']
    if fpath.lower().endswith('.fbx'):
        print(fpath)
" | while read -r filepath; do
    outfile="$DOWNLOAD_DIR/$filepath"
    mkdir -p "$(dirname "$outfile")"
    if [ ! -f "$outfile" ]; then
        echo "  Downloading: $filepath"
        curl -s -o "$outfile" "$ASSET_SERVER/$filepath"
    else
        echo "  Skip (exists): $filepath"
    fi
done

echo "=== Converting FBX -> GLB ==="
"$BLENDER" --background --python "$SCRIPT_DIR/convert_fbx_to_gltf.py" -- \
    "$DOWNLOAD_DIR/$PACK" \
    "$CONVERTED_DIR/$PACK"

echo "=== Done! GLB files in: $CONVERTED_DIR/$PACK ==="
