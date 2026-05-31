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
#   ./to_video.sh --platform cinema out/latest # platform profili (reels=9:16 / cinema=16:9)
#
# Model esnek: VIDEO_MODEL env veya missions.json .defaults.video.model (vars. seedance).
# Model flag'leri presets/video_models.json adaptöründen kurulur (modele göre değişir).

set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib.sh
source ./lib.sh
need_cmd jq

PRESETS_CAM="presets/cameras.json"
PRESETS_VID="presets/video_models.json"
MISSIONS="missions.json"
OUT_ROOT="out_video"

DRY_RUN=0; ONLY_SCENE=""; STILLS_DIR=""; CHAIN=0; PLATFORM="${PLATFORM:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --chain) CHAIN=1 ;;
    --platform) PLATFORM="${2:?--platform bir isim ister (reels|cinema)}"; shift ;;
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
STILLS_DIR="$(resolve_run_dir "$STILLS_DIR")"   # 'latest' -> gerçek koşu dizini (race/junction güvenli)
[ -d "$STILLS_DIR" ] || die "Dizin yok: $STILLS_DIR"
SEL_FILE="$STILLS_DIR/selection.json"

jqm() { jq -r "$1" "$MISSIONS"; }
# Platform profili: --platform > PLATFORM env > missions defaults.platform > "cinema".
PLATFORM="${PLATFORM:-$(jqm '.defaults.platform // empty')}"
PLATFORM="${PLATFORM:-cinema}"
[ -f "$PLATFORMS_FILE" ] && { jq empty "$PLATFORMS_FILE" 2>/dev/null || die "Geçersiz JSON: $PLATFORMS_FILE"; }
PLAT_ASPECT="$(platform_field "$PLATFORM" aspect_ratio "$(jqm '.defaults.aspect_ratio')")"
PLAT_MAXDUR="$(platform_field "$PLATFORM" max_duration "")"

VMODEL="${VIDEO_MODEL:-$(jqm '.defaults.video.model')}"
DURATION="$(jqm '.defaults.video.duration')"
ASPECT="${ASPECT:-$PLAT_ASPECT}"                      # platform en/boy oranı (video 9:16/16:9 destekler)
# NOT: video çözünürlüğü modele özgüdür (480p/720p/1080p); platformun '2k' (görsel)
# değeri video CLI'ına gönderilmez — VRES adaptörden/missions'tan gelir.
VRES="$(jqm '.defaults.video.resolution')"            # 480p/720p/1080p (modele göre)
COMMON_MOTION="$(jqm '.defaults.video.common_motion')"
MAX_RETRY="${MAX_RETRY:-3}"
UCOST="$(model_cost "$VMODEL")"; CUR="$(currency)"
ARCHIVE=1; if [ "${NO_ARCHIVE:-}" = 1 ]; then ARCHIVE=0; fi

# ---- Adaptör: seçili video modelinin gerçek flag'leri ----------------------
[ -f "$PRESETS_VID" ] || die "Video adaptör config'i yok: $PRESETS_VID"
jq empty "$PRESETS_VID" 2>/dev/null || die "Geçersiz JSON: $PRESETS_VID"
START_FLAG="$(jq -r --arg m "$VMODEL" '.models[$m].start_flag // empty' "$PRESETS_VID")"
if [ -z "$START_FLAG" ]; then
  warn "'$VMODEL' için adaptör yok ($PRESETS_VID) — varsayılan flag'lerle deniyorum (--start-image/--duration/--aspect_ratio). Doğrula: higgsfield model get $VMODEL"
  START_FLAG="--start-image"
  VVALID=0
else
  VVALID=1
  # Model geçerli bir süre bildiriyorsa onu kullan (örn. veo3_1 5 değil 8 ister).
  VDUR="$(jq -r --arg m "$VMODEL" '.models[$m].duration // empty' "$PRESETS_VID")"
  if [ -n "$VDUR" ] && [ "$VDUR" != "$DURATION" ]; then
    info "süre $DURATION -> $VDUR ($VMODEL için geçerli süre)"
    DURATION="$VDUR"
  fi
fi

# Platform süre tavanı: klip süresi profil max_duration'ı aşmasın.
if [ -n "$PLAT_MAXDUR" ] && [ "$PLAT_MAXDUR" != "null" ] && [ "${DURATION:-0}" -gt "$PLAT_MAXDUR" ] 2>/dev/null; then
  info "süre $DURATION -> $PLAT_MAXDUR (platform '$PLATFORM' tavanı)"
  DURATION="$PLAT_MAXDUR"
fi

RUN_DIR="$(new_run_dir "$OUT_ROOT" "clips")"
MANIFEST="$RUN_DIR/manifest.csv"
manifest_init "$MANIFEST"
log "Platform: $PLATFORM (aspect ${ASPECT}, video süre ${DURATION}s)"
log "Video modeli: $VMODEL | süre ${DURATION}s | kaynak: $STILLS_DIR"
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

# Adaptörden CLI argümanlarını kurar (yalnızca modelin desteklediği parametreler).
# Değer kaynakları: duration<-DURATION, aspect_ratio<-ASPECT, resolution<-VRES.
build_video_args() {
  local start=$1
  VARGS=(generate create "$VMODEL" --prompt "$MOTION_PROMPT" "$START_FLAG" "$start")
  if [ "$VVALID" = 1 ]; then
    local pk flag val
    while IFS=$'\t' read -r pk flag; do
      [ -z "$pk" ] && continue
      case "$pk" in
        duration)     val="$DURATION" ;;
        aspect_ratio) val="$ASPECT" ;;
        resolution)   val="$VRES" ;;
        *)            val="" ;;
      esac
      [ -n "$val" ] && [ "$val" != "null" ] && VARGS+=("$flag" "$val")
    done < <(jq -r --arg m "$VMODEL" '.models[$m].params // {} | to_entries[] | "\(.key)\t\(.value)"' "$PRESETS_VID")
  else
    # adaptörsüz güvenli varsayılan
    VARGS+=(--duration "$DURATION" --aspect_ratio "$ASPECT")
  fi
  VARGS+=(--wait)
}

run_cli() {
  local start=$1 rfile=$2
  build_video_args "$start"
  higgsfield "${VARGS[@]}" > "${rfile}.tmp" 2>&1 && mv -f "${rfile}.tmp" "$rfile"
}

clip_one() {
  local pfile=$1
  local base; base="$(basename "$pfile" .prompt.txt)"   # örn M01_s3 veya M01_s3_v1
  [[ "$base" =~ ^M([0-9]+)_s([0-9]+) ]] || { warn "ad çözümlenemedi, atlanıyor: $base"; return 0; }
  local mission="${BASH_REMATCH[1]}" scene="${BASH_REMATCH[2]}"
  if [ -n "$ONLY_SCENE" ] && [ "$scene" != "$ONLY_SCENE" ]; then return 0; fi

  # Seçim varsa: bu sahne için yalnızca seçilen varyantı işle
  if [ -f "$SEL_FILE" ]; then
    local key chosen
    key="$(sed -E 's/_v[0-9]+$//' <<<"$base")"
    chosen="$(jq -r --arg k "$key" '.[$k] // empty' "$SEL_FILE")"
    if [ -n "$chosen" ] && [ "$chosen" != "$base" ]; then
      info "$base: seçilmedi (seçili: $chosen) — atlanıyor"
      return 0
    fi
  fi

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
  build_video_args "${start:-<START>}"   # kayıt için adaptör-çözümlenmiş gerçek flag'ler
  {
    printf 'source_still=%s\nstart_image=%s (%s)\nvideo_model=%s duration=%s aspect=%s res=%s\n' \
      "$base" "${start:-<yok>}" "$start_label" "$VMODEL" "$DURATION" "$ASPECT" "$VRES"
    printf 'cli=higgsfield %s\n\nMOTION:\n%s\n' "${VARGS[*]}" "$MOTION_PROMPT"
  } | atomic_write "$mfile"

  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] $base → klip motion: $mfile  [başlangıç: $start_label]"
    info "$MOTION_PROMPT"
    manifest_append "$MANIFEST" "video" "$base" "1" "$VMODEL" "$ASPECT" "${DURATION}s" "" "dry-run" "-" "$(basename "$mfile")" "$UCOST"
    return 0
  fi

  if [ -z "$start" ]; then
    warn "$base: başlangıç görseli (still URL) yok — önce ./generate.sh ile üret. Atlanıyor."
    manifest_append "$MANIFEST" "video" "$base" "1" "$VMODEL" "$ASPECT" "${DURATION}s" "" "SKIP_no_start" "-" "$(basename "$mfile")" "0"
    return 0
  fi

  log "$base → video klibi üretiliyor ($VMODEL) [başlangıç: $start_label]"
  local status="ok"
  if with_retry "$MAX_RETRY" run_cli "$start" "$rfile"; then
    info "Klip URL: $(extract_url "$rfile" || echo '?')"
    if [ "$ARCHIVE" = 1 ]; then
      local cu2 saved2; cu2="$(extract_url "$rfile" || true)"
      if [ -n "$cu2" ]; then
        saved2="$(archive_result "$cu2" "$RUN_DIR/$base.clip" || true)"
        if [ -n "$saved2" ]; then info "arşivlendi: $(basename "$saved2")"; else warn "$base: klip arşivlenemedi (curl yok / indirme hatası)"; fi
      fi
    fi
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
  local cost="$UCOST"; [ "$status" = "ok" ] || cost=0
  manifest_append "$MANIFEST" "video" "$base" "1" "$VMODEL" "$ASPECT" "${DURATION}s" "" "$status" "$(basename "$rfile")" "$(basename "$mfile")" "$cost"
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
