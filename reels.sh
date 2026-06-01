#!/usr/bin/env bash
# reels.sh — uçtan uca Reels üretim hattı (generate → qc → video → thumbnail → assemble → caption → REELS_READY).
#
# Kullanım:
#   ./reels.sh 01            # Mission 01
#   ./reels.sh --all         # tüm mission'lar
#   ./reels.sh --dry-run 01  # tüm adımları simüle et, hiç üretim yapma
#
# İdempotent: tamamlanmış adımların çıktısı varsa o adım ATLANIR.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh
need_cmd jq

DRY_RUN=0; ALL=0; ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --all)     ALL=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    --*)       die "Bilinmeyen seçenek: $1" ;;
    *)         ARGS+=("$1") ;;
  esac
  shift
done

MISSIONS_LIST=()
if [ "$ALL" = 1 ]; then
  while IFS= read -r m; do MISSIONS_LIST+=("$m"); done < <(jq -r '.missions|keys[]' missions.json)
elif [ "${#ARGS[@]}" -gt 0 ]; then
  MISSIONS_LIST=("${ARGS[@]}")
else
  MISSIONS_LIST=("01")
fi

# Komut çalıştırıcı: dry-run'da sadece yazar; gerçek koşuda başarısızsa durdurur.
DRY="[dry-run] "
runc() {  # runc <numara/etiket> <komut...>
  local label=$1; shift
  if [ "$DRY_RUN" = 1 ]; then info "${DRY}${label}: $*"; return 0; fi
  log "$label"
  "$@" || die "ADIM BAŞARISIZ — $label. Hat durduruldu."
}

# En yeni TAM still seti (tüm sahnelerin png'si) — idempotency için.
latest_complete_still() {  # <mission> -> dizin yolu (yoksa boş)
  local m=$1 want d png
  want="$(jq "[.missions[\"$m\"].scenes[]]|length" missions.json)"
  for d in $(ls -dt out/*_M${m}/ 2>/dev/null); do
    d="${d%/}"
    png="$(ls "$d"/M${m}_s*.png 2>/dev/null | wc -l)"
    if [ "$png" -ge "$want" ]; then printf '%s' "$d"; return 0; fi
  done
}

for M in "${MISSIONS_LIST[@]}"; do
  log "════════ REELS hattı — Mission $M ════════"

  # ---- 1) generate (still) -------------------------------------------------
  STILL_DIR="$(latest_complete_still "$M" || true)"
  if [ -n "$STILL_DIR" ]; then
    info "1/7 generate: ATLA (tam set zaten var → $STILL_DIR)"
  elif [ "$DRY_RUN" = 1 ]; then
    info "${DRY}1/7 generate: ./generate.sh --platform reels --jobs 4 $M"
    STILL_DIR="out/<koşu sonrası latest>"
  else
    runc "1/7 generate" ./generate.sh --platform reels --jobs 4 "$M"
    STILL_DIR="out/$(cat out/latest.path)"
    info "Still dizini: $STILL_DIR"
  fi

  # ---- 2) qc ---------------------------------------------------------------
  if [ "$DRY_RUN" != 1 ] && [ -f "$STILL_DIR/qc.csv" ]; then
    info "2/7 qc: ATLA (qc.csv var)"
  else
    runc "2/7 qc" ./qc.sh "$STILL_DIR"
  fi

  # ---- 3) to_video ---------------------------------------------------------
  VIDEO_DIR=""
  if [ "$DRY_RUN" != 1 ]; then
    for d in $(ls -dt out_video/*_clips/ 2>/dev/null); do
      d="${d%/}"; ls "$d"/*.clip.txt >/dev/null 2>&1 && { VIDEO_DIR="$d"; break; }
    done
  fi
  if [ -n "$VIDEO_DIR" ]; then
    info "3/7 to_video: ATLA (klipler var → $VIDEO_DIR)"
  elif [ "$DRY_RUN" = 1 ]; then
    info "${DRY}3/7 to_video: ./to_video.sh --platform reels $STILL_DIR"
    VIDEO_DIR="out_video/<koşu sonrası latest>"
  else
    runc "3/7 to_video" ./to_video.sh --platform reels "$STILL_DIR"
    VIDEO_DIR="out_video/$(cat out_video/latest.path)"
  fi

  # ---- 4) thumbnail --------------------------------------------------------
  if [ "$DRY_RUN" != 1 ] && [ -d "$STILL_DIR/thumbnails" ] && ls "$STILL_DIR"/thumbnails/*.jpg >/dev/null 2>&1; then
    info "4/7 thumbnail: ATLA (thumbnails/ var)"
  else
    runc "4/7 thumbnail" ./thumbnail.sh "$STILL_DIR"
  fi

  # ---- 5) assemble ---------------------------------------------------------
  if [ "$DRY_RUN" != 1 ] && [ -f "$VIDEO_DIR/final.mp4" ]; then
    info "5/7 assemble: ATLA (final.mp4 var)"
  else
    runc "5/7 assemble" ./assemble.sh "$VIDEO_DIR" --hud --audio --transition --loop --cover
  fi

  # ---- 6) caption ----------------------------------------------------------
  if [ "$DRY_RUN" != 1 ] && [ -f "$STILL_DIR/caption_reels.txt" ]; then
    info "6/7 caption: ATLA (caption_reels.txt var)"
  else
    PY=python3; command -v python3 >/dev/null 2>&1 || PY=python
    runc "6/7 caption" "$PY" caption.py --mission "$M" --platform both --output "$STILL_DIR/caption"
  fi

  # ---- 7) REELS_READY.txt --------------------------------------------------
  READY="$STILL_DIR/REELS_READY.txt"
  if [ "$DRY_RUN" = 1 ]; then
    info "${DRY}7/7 REELS_READY.txt yazılacak ($STILL_DIR/REELS_READY.txt)"
  else
    # toplam kredi (still manifest + video manifest est_cost sütunu)
    credits="$(awk -F, 'NR>1{s+=$12} END{printf "%.2f", s+0}' "$STILL_DIR/manifest.csv" 2>/dev/null || echo 0)"
    vcredits="$(awk -F, 'NR>1{s+=$12} END{printf "%.2f", s+0}' "$VIDEO_DIR/manifest.csv" 2>/dev/null || echo 0)"
    total="$(awk -v a="$credits" -v b="$vcredits" 'BEGIN{printf "%.2f", a+b}')"
    {
      echo "NORTH — Mission $M — REELS HAZIR"
      echo "================================"
      echo "Üretim tarihi : $(date '+%Y-%m-%d %H:%M:%S')"
      echo "Final video   : $VIDEO_DIR/final.mp4"
      echo "Cover         : $VIDEO_DIR/cover.jpg"
      echo "Caption (IG)  : $STILL_DIR/caption_reels.txt"
      echo "Caption (TT)  : $STILL_DIR/caption_tiktok.txt"
      echo "Toplam kredi  : $total  (still $credits + video $vcredits)"
      echo "Still dizini  : $STILL_DIR"
      echo "Video dizini  : $VIDEO_DIR"
    } > "$READY"
    log "REELS_READY: $READY"
    cat "$READY" | sed 's/^/    /'
  fi

  log "════════ Mission $M tamam ════════"
done

[ "$DRY_RUN" = 1 ] && log "[dry-run] hiçbir üretim yapılmadı — plan yukarıda." || true
