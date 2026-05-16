#!/usr/bin/env bash
# Cooker entry point. On startup:
#   1. Initial pass — cook any raw files whose cooked output is missing.
#   2. Refresh the index.
# Then loop:
#   inotifywait blocks until a raw/ event fires, debounce window collects
#   subsequent events, then we cook the changed files and refresh the index.
#
# Idempotent: cook.sh skips files whose cooked output is newer than the source.

set -euo pipefail

: "${RAW_DIR:=/raw}"
: "${COOKED_DIR:=/cooked}"
: "${LOGS_DIR:=/logs}"
: "${DEBOUNCE_SECS:=5}"
: "${INDEX_OUTPUT:=/cooked/index.json}"
: "${URL_PREFIX:=assets}"

mkdir -p "$LOGS_DIR"

COOKER_LOG="${LOGS_DIR}/cooker.log"

# Tee all output (stdout+stderr) to the persistent cooker log.
exec > >(tee -a "$COOKER_LOG") 2>&1

log() { echo "[cooker $(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

regenerate_index() {
    log "regenerating index → ${INDEX_OUTPUT}"
    COOKED_DIR="${COOKED_DIR}" \
    RAW_DIR="${RAW_DIR}" \
    OUTPUT="${INDEX_OUTPUT}" \
    URL_PREFIX_COOKED="${URL_PREFIX}" \
        /usr/local/bin/updateIndex.sh
}

cook_all() {
    local run_log="${LOGS_DIR}/cook-$(date -u +%Y%m%dT%H%M%SZ).log"
    log "cooking raw → cooked (incremental); run log → ${run_log}"
    /opt/cooker/cook.sh "${RAW_DIR}" "${COOKED_DIR}" 2>&1 | tee "$run_log"
}

# Initial pass on startup so a fresh container picks up any pre-existing files
# in the raw mount.
log "cooker starting; RAW=${RAW_DIR} COOKED=${COOKED_DIR} LOGS=${LOGS_DIR} DEBOUNCE=${DEBOUNCE_SECS}s"
cook_all
regenerate_index

# Main watch loop. inotifywait blocks until something changes; the debounce
# trick reads subsequent events with a short timeout to coalesce bursts.
while true; do
    log "watching ${RAW_DIR} for changes…"

    # Block until the first event arrives.
    inotifywait -q -r -e create,modify,delete,move "${RAW_DIR}" >/dev/null

    # Debounce: drain further events within the window.
    while inotifywait -q -r -e create,modify,delete,move \
            -t "${DEBOUNCE_SECS}" "${RAW_DIR}" >/dev/null 2>&1; do
        :  # event consumed, restart the timer
    done

    log "fs settled; running cook + index"
    cook_all || log "cook returned non-zero (continuing)"
    regenerate_index || log "index regen returned non-zero (continuing)"
done
