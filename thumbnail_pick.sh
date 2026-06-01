#!/usr/bin/env bash
# thumbnail_pick.sh — bir sahnenin aday karelerinden kapağı (cover) seçer.
#
# Kullanım:
#   ./thumbnail_pick.sh out/latest 1 t25
#   (sahne 1'in %25 karesini kapak yapar; thumbnail_selection.json'a yazar)
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh
need_cmd jq

RUN_DIR="$(resolve_run_dir "${1:?Kullanım: ./thumbnail_pick.sh <dir> <sahne> <frame>}")"
SCENE="${2:?sahne no gerekli}"
FRAME="${3:?frame gerekli (t10|t25|t50|t75|t90)}"
[ -d "$RUN_DIR" ] || die "Dizin yok: $RUN_DIR"

hit="$(ls "$RUN_DIR"/thumbnails/M*_s${SCENE}_${FRAME}.jpg 2>/dev/null | head -1)"
[ -n "$hit" ] || die "Aday kare yok: sahne $SCENE, frame $FRAME (önce ./thumbnail.sh çalıştır)"
fname="$(basename "$hit")"
base="${fname%_${FRAME}.jpg}"        # M01_s1
rel="thumbnails/$fname"

SEL="$RUN_DIR/thumbnail_selection.json"
[ -f "$SEL" ] || printf '%s\n' '{"selections":{}}' > "$SEL"
jq --arg b "$base" --arg r "$rel" '.selections[$b]=$r | .cover=$r | .cover_base=$b' "$SEL" \
  | tr -d '\r' > "$SEL.tmp" && mv -f "$SEL.tmp" "$SEL"
log "Kapak seçildi: $base → $rel"
info "Kayıt: $SEL"
