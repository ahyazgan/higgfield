#!/usr/bin/env bash
# thumbnail.sh — her video klibinden 5 aday kapak karesi (%10/25/50/75/90) çıkarır.
#
# Kullanım:
#   ./thumbnail.sh out/latest          # tüm sahneler
#   ./thumbnail.sh out/latest 3        # sadece sahne 3
#
# Klipler verilen dizinde *.clip.txt olarak yoksa otomatik out_video/latest'e bakar.
# Kareler: <dizin>/thumbnails/M01_s1_t10.jpg ... _t90.jpg
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

RUN_DIR="$(resolve_run_dir "${1:?Kullanım: ./thumbnail.sh <koşu_dizini> [sahne]}")"
[ -d "$RUN_DIR" ] || die "Dizin yok: $RUN_DIR"
ONLY_SCENE="${2:-}"

# Klip kaynağı: verilen dizinde *.clip.txt varsa orada; yoksa out_video/latest.
CLIP_DIR="$RUN_DIR"
if ! ls "$CLIP_DIR"/*.clip.txt >/dev/null 2>&1; then
  alt="out_video/latest"
  [ -f out_video/latest.path ] && alt="out_video/$(tr -d '\r\n' < out_video/latest.path)"
  if ls "$alt"/*.clip.txt >/dev/null 2>&1; then CLIP_DIR="$(resolve_run_dir "$alt")"; info "klip kaynağı: $CLIP_DIR"; fi
fi
ls "$CLIP_DIR"/*.clip.txt >/dev/null 2>&1 || die "Klip (*.clip.txt) bulunamadı — önce ./to_video.sh çalıştır."

command -v ffmpeg >/dev/null 2>&1 || die "thumbnail için ffmpeg gerekli (kurulu değil)."
command -v curl   >/dev/null 2>&1 || die "thumbnail için curl gerekli."

THUMB="$RUN_DIR/thumbnails"; mkdir -p "$THUMB"
PCTS=(10 25 50 75 90)
n=0
shopt -s nullglob
for cf in $(ls "$CLIP_DIR"/*.clip.txt 2>/dev/null | sort -V); do
  base="$(basename "$cf" .clip.txt)"
  [[ "$base" =~ _s([0-9]+) ]] || continue
  if [ -n "$ONLY_SCENE" ] && [ "${BASH_REMATCH[1]}" != "$ONLY_SCENE" ]; then continue; fi
  url="$(extract_url "$cf" || true)"
  [ -n "$url" ] || { warn "$base: URL yok, atlanıyor"; continue; }
  tmp="$(mktemp --suffix=.mp4)" || continue
  if ! with_retry 3 curl -fsSL "$url" -o "$tmp"; then warn "$base: indirilemedi"; rm -f "$tmp"; continue; fi
  dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$tmp" 2>/dev/null || echo 5)"
  for p in "${PCTS[@]}"; do
    t="$(awk -v d="$dur" -v p="$p" 'BEGIN{printf "%.3f", d*p/100}')"
    out="$THUMB/${base}_t${p}.jpg"
    if ffmpeg -y -ss "$t" -i "$tmp" -frames:v 1 -q:v 2 "$out" >/dev/null 2>&1; then n=$((n+1)); fi
  done
  info "$base: 5 aday kare"
  rm -f "$tmp"
done
log "Thumbnail bitti — $n kare → $THUMB"
[ "$n" -gt 0 ] && info "Seç: ./thumbnail_pick.sh $RUN_DIR <sahne> t25"
