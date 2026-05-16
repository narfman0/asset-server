# asset-server

Two-tier asset pipeline for the openclaw projects. Splits **source** from
**cooked** assets:

```
RAW_PATH (host)         ←  artists / dev upload FBX, raw OGG, etc.
   │
   │  inotifywait + Blender headless + transforms/
   ▼
COOKED_PATH (host)      →  served by nginx at /assets/
   │
   ▼  GLB / normalized OGG / etc. + auto-generated index.json
clients (Bevy etc.)
```

Two containers, one stack:

| Service | Role |
|---|---|
| `assets` (nginx) | Serves `${COOKED_PATH}` at `http://host:49200/assets/` and the auto-generated index at `/index.json`. Read-only. |
| `cooker` (Blender + inotify) | Watches `${RAW_PATH}` for changes; runs transforms in `cooker/transforms/`; writes results to `${COOKED_PATH}`; regenerates the index after every cook cycle. |

Each transform is idempotent — re-running the cooker only touches files whose
output is missing or stale relative to source.

## Quickstart

1. `cp .env.example .env` and edit the two paths.

   * `RAW_PATH` — where you drop FBX / raw audio. Cooker watches this read-only.
   * `COOKED_PATH` — where GLBs land. Nginx serves this. Safe to wipe and let the cooker rebuild from raw.

2. `docker compose up -d --build` — first build pulls Blender 5.0.0 (~700 MB compressed in the cooker image; one-time).

3. Drop an FBX into `${RAW_PATH}/your_pack/`.

4. Within `DEBOUNCE_SECS` (default 5) of the last filesystem event, the cooker
   converts and the index updates. Check `docker logs asset-cooker` to follow.

5. Clients hit `http://host:49200/assets/your_pack/.../foo.glb`.

## Supported transforms today

`*.fbx → *.glb` via `cooker/transforms/fbx_to_glb.py` (Blender Python).

If any path under raw/ contains `mixamo` (case-insensitive), the conversion
runs with `--rename mixamo` so Mixamo's `mixamorig:*` bones get remapped to
standard humanoid names. See the script's `RENAME_PRESETS` dict for the
full mapping including the 4-bone-spine → 3-bone-spine collapse.

## Index behavior

The cooker writes `index.json` directly into the cooked tree
(`${COOKED_PATH}/index.json`). Nginx serves it at:

* `http://host:49200/index.json` (canonical)
* `http://host:49200/` (redirects to the index)
* `http://host:49200/assets/index.json` (direct)

Schema is unchanged from the pre-split server — top-level totals plus
per-pack metadata with full file listings (relative path, size, mtime).

## Adding new transforms

Drop a script under `cooker/transforms/` and add a dispatch rule in
`cooker/cook.sh`. The existing FBX rule batches by Blender invocation to
amortize startup cost. For lighter formats (OGG → loudnorm OGG via ffmpeg),
a per-file loop is fine.

Useful future transforms:

* `*.wav → *.ogg` (codec normalization, smaller payload)
* `*.ogg → loudness-normalized *.ogg` (ffmpeg loudnorm filter)
* Source PNGs → packed sprite atlases
* Mesh decimation / LOD generation

## Why not split into two repos

A "raw asset server" and "asset hub" as separate projects has the appeal of
single-responsibility, but for our scale (one developer, low traffic, single
machine deploy) the operational cost (two docker stacks, two URLs, two repos
to update in lock-step) outweighs the cleanliness. The directory-layout
separation here gets the architectural benefit without those costs. Worth
revisiting if multiple teams own different transforms or if separate scaling
ever matters.

## Legacy: `fetch_and_convert.sh`

The per-developer client-side fetch+convert script. Pre-cooker, every
developer had to run Blender locally. Now obsolete for the team flow — the
cooker does it once on the server. Kept as an escape hatch for offline
development.
