#!/usr/bin/env bash
# to_video.sh — image-to-video: still kareleri video kliplerine çevirir.
# Mevcut still hattının çıktısını (out/<koşu>/) girdi alır; her karenin sonuç
# URL'sini video modeline --start-image olarak verir.
#
# Kullanım:
#   ./to_video.sh out/latest                 # koşudaki tüm kareleri klibe çevir
#   ./to_video.sh --dry-run out/latest        # motion prompt'ları göster, CLI çağırma
#   ./to_video.sh --scene 3 out/latest        # sadece sahne 3
#   ./to_video.sh --chain out/latest          # last-frame chaining (akıcı tek-çekim)
#
# Model esnek: VIDEO_MODEL env veya missions.json .defaults.video.model (vars. seedance).
# Flag adları (--start-image/--duration/--fps) sürümle değişebilir; --help ile doğrula.

set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib.sh
source ./lib.sh
need_cmd jq

PRESETS_CAM="presets/cameras.json"
MISSIONS="missions.json"
OUT_ROOT="out_video"

DRY_RUN=0; ONLY_SCENE=""; STILLS_DIR=""; CHAIN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --chain) CHAIN=1 ;;
    --scene) ONLY_SCENE="${2:?--scene bir sayı ister}"; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    --*) die "Bilinmeyen seçenek: $1" ;;
    *) STILLS_DIR="$1" ;;
  esac
  shift
done
if [ "$CHAIN" = 1 ] && [ -n "$ONLY_SCENE" ]; then
  die "--chain ve --scene birlikte kullanılamaz (zincir tüm sahneleri sırayla ister)."
fi
[ -n "$STILLS_DIR" ] || die "Still koşu dizini gerekli. Örn: ./to_video.sh out/latest"
[ -d "$STILLS_DIR" ] || die "Dizin yok: $STILLS_DIR"

jqm() { jq -r "$1" "$MISSIONS"; }
VMODEL="${VIDEO_MODEL:-$(jqm '.defaults.video.model')}"
DURATION="$(jqm '.defaults.video.duration')"
FPS="$(jqm '.defaults.video.fps')"
ASPECT="${ASPECT:-$(jqm '.defaults.aspect_ratio')}"
COMMON_MOTION="$(jqm '.defaults.video.common_motion')"
VNEG="$(jqm '.defaults.video.negative')"
MAX_RETRY="${MAX_RETRY:-3}"

RUN_DIR="$(new_run_dir "$OUT_ROOT" "clips")"
MANIFEST="$RUN_DIR/manifest.csv"
manifest_init "$MANIFEST"
log "Video modeli: $VMODEL | süre ${DURATION}s @ ${FPS}fps | kaynak: $STILLS_DIR"
log "Koşu dizini: $RUN_DIR"

# Sahne için motion prompt'u kurar (tek kaynak: missions.json + cameras.json)
build_motion() {
  local mission=$1 scene=$2
  local s; s="$(jqm ".missions.\"$mission\".scenes[] | select(.id==$scene)")"
  [ -n "$s" ] || die "M$mission sahne $scene missions.json'da yok"
  local action cam scene_motion cam_motion
  action="$(jq -r '.action' <<<"$s")"
  cam="$(jq -r '.camera' <<<"$s")"
  scene_motion="$(jq -r '.motion // empty' <<<"$s")"
  cam_motion="$(jq -r --arg m "$cam" '.motion[$m] // empty' "$PRESETS_CAM")"
  local move="${scene_motion:-$cam_motion}"
  MOTION_PROMPT="${action}, ${move}, ${COMMON_MOTION}"
}

run_cli() {
  local start=$1 rfile=$2
  higgsfield generate create "$VMODEL" \
    --prompt "$MOTION_PROMPT" \
    --negative-prompt "$VNEG" \
    --start-image "$start" \
    --duration "$DURATION" \
    --fps "$FPS" \
    --aspect_ratio "$ASPECT" \
    --wait > "${rfile}.tmp" 2>&1 && mv -f "${rfile}.tmp" "$rfile"
}

clip_one() {
  local pfile=$1
  local base; base="$(basename "$pfile" .prompt.txt)"   # örn M01_s3 veya M01_s3_v1
  [[ "$base" =~ ^M([0-9]+)_s([0-9]+) ]] || { warn "ad çözümlenemedi, atlanıyor: $base"; return 0; }
  local mission="${BASH_REMATCH[1]}" scene="${BASH_REMATCH[2]}"
  if [ -n "$ONLY_SCENE" ] && [ "$scene" != "$ONLY_SCENE" ]; then return 0; fi

  build_motion "$mission" "$scene"
  SEQ=$((SEQ + 1))

  # Başlangıç görseli seçimi:
  #  - zincir modunda ilk-sahne-dışı sahneler önceki klibin SON karesini kullanır
  #  - aksi halde (veya zincir kırıldıysa) bu sahnenin kendi still URL'sini kullanır
  local rfile_src="$STILLS_DIR/$base.result.txt" start="" start_label=""
  if [ "$CHAIN" = 1 ] && [ "$SEQ" -gt 1 ] && [ -n "$PREV_LASTFRAME" ]; then
    start="$PREV_LASTFRAME"; start_label="zincir: önceki klibin son karesi"
  elif [ "$CHAIN" = 1 ] && [ "$SEQ" -gt 1 ] && [ "$DRY_RUN" = 1 ]; then
    start=""; start_label="zincir: önceki klibin son karesi (gerçek koşuda dolar)"
  else
    if [ -f "$rfile_src" ]; then start="$(extract_url "$rfile_src" || true)"; fi
    start_label="still: $base"
  fi

  local mfile="$RUN_DIR/${base}.motion.txt"
  local rfile="$RUN_DIR/${base}.clip.txt"
  {
    printf 'source_still=%s\nstart_image=%s (%s)\nvideo_model=%s duration=%s fps=%s\n\nMOTION:\n%s\n\nNEGATIVE:\n%s\n' \
      "$base" "${start:-<yok>}" "$start_label" "$VMODEL" "$DURATION" "$FPS" "$MOTION_PROMPT" "$VNEG"
  } | atomic_write "$mfile"

  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] $base → klip motion: $mfile  [başlangıç: $start_label]"
    info "$MOTION_PROMPT"
    manifest_append "$MANIFEST" "video" "$base" "1" "$VMODEL" "$ASPECT" "${DURATION}s" "" "dry-run" "-" "$(basename "$mfile")"
    return 0
  fi

  if [ -z "$start" ]; then
    warn "$base: başlangıç görseli (still URL) yok — önce ./generate.sh ile üret. Atlanıyor."
    manifest_append "$MANIFEST" "video" "$base" "1" "$VMODEL" "$ASPECT" "${DURATION}s" "" "SKIP_no_start" "-" "$(basename "$mfile")"
    return 0
  fi

  log "$base → video klibi üretiliyor ($VMODEL) [başlangıç: $start_label]"
  local status="ok"
  if with_retry "$MAX_RETRY" run_cli "$start" "$rfile"; then
    info "Klip URL: $(extract_url "$rfile" || echo '?')"
    if [ "$CHAIN" = 1 ]; then
      local cu lf; cu="$(extract_url "$rfile" || true)"
      lf="$RUN_DIR/${base}.lastframe.jpg"
      if [ -n "$cu" ] && chain_lastframe "$cu" "$lf"; then
        PREV_LASTFRAME="$lf"; info "zincir: son kare → $(basename "$lf")"
      else
        PREV_LASTFRAME=""; warn "zincir kırıldı (ffmpeg/curl yok ya da indirme başarısız) — sonraki sahne kendi still'ini kullanır"
      fi
    fi
  else
    status="FAILED"; warn "$base klip üretilemedi."
  fi
  manifest_append "$MANIFEST" "video" "$base" "1" "$VMODEL" "$ASPECT" "${DURATION}s" "" "$status" "$(basename "$rfile")" "$(basename "$mfile")"
}

if [ "$CHAIN" = 1 ]; then log "Zincir modu (last-frame chaining) açık — sahneler sırayla, her klibin son karesi sonrakine başlangıç."; fi

shopt -s nullglob
SEQ=0; PREV_LASTFRAME=""
found=0
for pfile in $(ls "$STILLS_DIR"/*.prompt.txt 2>/dev/null | sort -V); do
  found=1
  clip_one "$pfile"
done
[ "$found" = 1 ] || die "$STILLS_DIR içinde *.prompt.txt yok — burası bir still koşu dizini mi?"

log "Bitti. Manifest: $MANIFEST"
[ "$DRY_RUN" = 1 ] || info "Birleştirmek için: ./assemble.sh $RUN_DIR"
