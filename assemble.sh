#!/usr/bin/env bash
# assemble.sh — video koşusundaki klipleri sahne sırasında tek mp4'e birleştirir.
# ffmpeg + curl varsa: klipleri indirir ve birleştirir.
# Yoksa: sıralı playlist.txt yazar (klipleri elle indirip birleştirmek için).
#
# Kullanım:
#   ./assemble.sh out_video/latest
#   ./assemble.sh out_video/latest --music track.mp3

set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

RUN_DIR="${1:?Kullanım: ./assemble.sh <video_koşu_dizini> [--music dosya]}"
[ -d "$RUN_DIR" ] || die "Dizin yok: $RUN_DIR"
shift || true
MUSIC=""
if [ "${1:-}" = "--music" ]; then MUSIC="${2:?--music bir dosya ister}"; fi

# Klip URL'lerini sahne sırasında topla
PLAYLIST="$RUN_DIR/playlist.txt"
: > "$PLAYLIST"
n=0
for rfile in $(ls "$RUN_DIR"/*.clip.txt 2>/dev/null | sort -V); do
  url="$(extract_url "$rfile" || true)"
  [ -n "$url" ] || { warn "URL yok: $(basename "$rfile")"; continue; }
  printf '%s\n' "$url" >> "$PLAYLIST"
  n=$((n+1))
done
[ "$n" -gt 0 ] || die "Birleştirilecek klip URL'si yok ($RUN_DIR). Önce ./to_video.sh çalıştır."
log "$n klip sahne sırasında: $PLAYLIST"

if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  warn "ffmpeg ve/veya curl yok — otomatik birleştirme atlandı."
  info "Sıralı klip listesi hazır: $PLAYLIST"
  info "Kurunca:  ./assemble.sh $RUN_DIR  tekrar çalıştır."
  exit 0
fi

# İndir + concat
DL="$RUN_DIR/clips"; mkdir -p "$DL"
CONCAT="$RUN_DIR/concat.txt"; : > "$CONCAT"
i=0
while IFS= read -r url; do
  i=$((i+1))
  f="$DL/$(printf '%03d' "$i").mp4"
  log "indiriliyor ($i/$n): $url"
  with_retry 3 curl -fsSL "$url" -o "$f" || die "indirilemedi: $url"
  printf "file '%s'\n" "$(cd "$DL" && pwd)/$(basename "$f")" >> "$CONCAT"
done < "$PLAYLIST"

OUT="$RUN_DIR/final.mp4"
log "ffmpeg ile birleştiriliyor → $OUT"
if [ -n "$MUSIC" ]; then
  ffmpeg -y -f concat -safe 0 -i "$CONCAT" -i "$MUSIC" \
    -map 0:v -map 1:a -c:v libx264 -pix_fmt yuv420p -shortest "$OUT" >/dev/null 2>&1
else
  ffmpeg -y -f concat -safe 0 -i "$CONCAT" -c:v libx264 -pix_fmt yuv420p "$OUT" >/dev/null 2>&1
fi
log "Bitti: $OUT"
