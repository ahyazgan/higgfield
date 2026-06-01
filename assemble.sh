#!/usr/bin/env bash
# assemble.sh — video koşusundaki klipleri sahne sırasında tek mp4'e birleştirir,
# ardından Reels için son-işleme uygular (HUD / transition / ses / loop / cover).
#
# Kullanım:
#   ./assemble.sh out_video/latest                         # düz birleştirme (mevcut davranış)
#   ./assemble.sh out_video/latest --music track.mp3       # eski müzik bayrağı
#   ./assemble.sh out_video/latest --transition --dry-run  # geçiş planını listele (üretmeden)
#   ./assemble.sh out_video/latest --hud --audio --transition --loop --cover
#
# Bayraklar: --hud --transition --audio --music-only --music <f> --loop --cover --dry-run
# Bayrak verilmezse mevcut davranış (düz concat) korunur.

set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

MISSIONS="missions.json"
PRESETS_TR="presets/transitions.json"
PRESETS_AU="presets/audio.json"
HUD_OVERLAY="hud/overlay.png"

RUN_DIR="${1:?Kullanım: ./assemble.sh <video_koşu_dizini> [bayraklar]}"
RUN_DIR="$(resolve_run_dir "$RUN_DIR")"
[ -d "$RUN_DIR" ] || die "Dizin yok: $RUN_DIR"
shift || true

MUSIC=""; HUD=0; TRANSITION=0; AUDIO=0; MUSIC_ONLY=0; LOOP=0; COVER=0; DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --music)      MUSIC="${2:?--music bir dosya ister}"; shift ;;
    --hud)        HUD=1 ;;
    --transition) TRANSITION=1 ;;
    --audio)      AUDIO=1 ;;
    --music-only) MUSIC_ONLY=1 ;;
    --loop)       LOOP=1 ;;
    --cover)      COVER=1 ;;
    --dry-run)    DRY_RUN=1 ;;
    -h|--help)    sed -n '2,13p' "$0"; exit 0 ;;
    --*)          die "Bilinmeyen seçenek: $1" ;;
    *)            die "Beklenmeyen argüman: $1" ;;
  esac
  shift
done

have_ffmpeg=1; command -v ffmpeg >/dev/null 2>&1 || have_ffmpeg=0
have_curl=1;   command -v curl   >/dev/null 2>&1 || have_curl=0
have_probe=1;  command -v ffprobe >/dev/null 2>&1 || have_probe=0

# ---- Klipleri sahne sırasında topla (url + base) ---------------------------
URLS=(); BASES=()
shopt -s nullglob
for rfile in $(ls "$RUN_DIR"/*.clip.txt 2>/dev/null | sort -V); do
  url="$(extract_url "$rfile" || true)"
  base="$(basename "$rfile" .clip.txt)"
  [ -n "$url" ] || { warn "URL yok: $base"; continue; }
  URLS+=("$url"); BASES+=("$base")
done
N="${#URLS[@]}"
[ "$N" -gt 0 ] || die "Birleştirilecek klip URL'si yok ($RUN_DIR). Önce ./to_video.sh çalıştır."
log "$N klip sahne sırasında bulundu."

# ---- base -> sahnenin transition_out'u (transitions.json yoksa default) ----
scene_transition() {  # base -> transition adı
  local base=$1 m s t
  [[ "$base" =~ ^M([0-9]+)_s([0-9]+) ]] || { printf 'smash_cut'; return; }
  m="${BASH_REMATCH[1]}"; s="${BASH_REMATCH[2]}"
  t="$(jq -r --arg m "$m" --arg s "$s" '.missions[$m].scenes[]|select(.id==($s|tonumber))|.transition_out // empty' "$MISSIONS" 2>/dev/null)"
  [ -n "$t" ] && [ "$t" != "null" ] || t="$(jq -r '.default // "smash_cut"' "$PRESETS_TR" 2>/dev/null || echo smash_cut)"
  printf '%s' "$t"
}
# transition adı -> "xfade_tipi süre"  (xfade zinciri için; hepsi xfade'e eşlenir)
transition_xfade() {  # name -> "type dur"
  local name=$1 dur type
  dur="$(jq -r --arg n "$name" '.transitions[$n].duration // 0.2' "$PRESETS_TR" 2>/dev/null || echo 0.2)"
  case "$name" in
    smash_cut) type="fade"; dur="0.05" ;;   # ≈ sert kesme
    flash)     type="fadewhite" ;;
    whip_pan)  type="slideleft" ;;
    fade_black) type="fade" ;;
    zoom_punch) type="fade" ;;               # zoompan zincirlenemez -> fade ikamesi
    *)         type="fade" ;;
  esac
  printf '%s %s' "$type" "$dur"
}

# ---- --dry-run: planı yaz, ÜRETME -----------------------------------------
if [ "$DRY_RUN" = 1 ]; then
  log "[dry-run] assemble planı — $RUN_DIR"
  info "Aktif bayraklar: $( [ $HUD = 1 ] && printf 'hud ' )$( [ $TRANSITION = 1 ] && printf 'transition ' )$( [ $AUDIO = 1 ] && printf 'audio ' )$( [ $MUSIC_ONLY = 1 ] && printf 'music-only ' )$( [ $LOOP = 1 ] && printf 'loop ' )$( [ $COVER = 1 ] && printf 'cover ' )"
  local_i=0
  for ((i=0; i<N; i++)); do
    b="${BASES[$i]}"
    if [ "$i" -lt $((N-1)) ]; then
      t="$(scene_transition "$b")"
      if [ "$TRANSITION" = 1 ]; then read -r xt xd <<<"$(transition_xfade "$t")"; info "$b → sonraki: geçiş '$t' (xfade=$xt, ${xd}s)"
      else info "$b → sonraki: '$t' (transition bayrağı kapalı, düz kesme)"; fi
    else
      info "$b → son klip (transition yok)"
    fi
  done
  [ "$HUD" = 1 ] && info "HUD: $HUD_OVERLAY bindirilecek (overlay=0:0)"
  [ "$LOOP" = 1 ] && info "LOOP: son kare ilk kareye 0.5s xfade ile bağlanacak"
  if [ "$AUDIO" = 1 ] || [ "$MUSIC_ONLY" = 1 ]; then info "SES: $([ "$MUSIC_ONLY" = 1 ] && echo 'sadece müzik' || echo 'müzik + sfx') (presets/audio.json)"; fi
  [ "$COVER" = 1 ] && info "COVER: thumbnail_selection.json'dan cover.jpg kopyalanacak"
  log "[dry-run] üretim yapılmadı."
  exit 0
fi

# ---- ffmpeg/curl yoksa: playlist yaz, çık ----------------------------------
PLAYLIST="$RUN_DIR/playlist.txt"; : > "$PLAYLIST"
for u in "${URLS[@]}"; do printf '%s\n' "$u" >> "$PLAYLIST"; done
if [ "$have_ffmpeg" = 0 ] || [ "$have_curl" = 0 ]; then
  warn "ffmpeg ve/veya curl yok — otomatik birleştirme atlandı."
  info "Sıralı klip listesi hazır: $PLAYLIST"
  exit 0
fi

# ---- Klipleri indir --------------------------------------------------------
DL="$RUN_DIR/clips"; mkdir -p "$DL"
INPUTS=()
for ((i=0; i<N; i++)); do
  f="$DL/$(printf '%03d' "$((i+1))").mp4"
  log "indiriliyor ($((i+1))/$N): ${BASES[$i]}"
  with_retry 3 curl -fsSL "${URLS[$i]}" -o "$f" || die "indirilemedi: ${URLS[$i]}"
  INPUTS+=("$f")
done

# klip süresi (ffprobe varsa)
clip_dur() { local f=$1; [ "$have_probe" = 1 ] && ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null || echo 5; }

BASEVID="$RUN_DIR/_base.mp4"

# ---- Birleştirme: transition'lı (xfade zinciri) veya düz concat ------------
if [ "$TRANSITION" = 1 ] && [ "$N" -gt 1 ]; then
  log "Birleştirme: xfade geçiş zinciri ($N klip)"
  DUR=(); for f in "${INPUTS[@]}"; do DUR+=("$(clip_dur "$f")"); done
  ff_in=(); for f in "${INPUTS[@]}"; do ff_in+=(-i "$f"); done
  fc=""; cur="[0:v]"; acc="${DUR[0]}"
  for ((i=1; i<N; i++)); do
    read -r xt xd <<<"$(transition_xfade "$(scene_transition "${BASES[$((i-1))]}")")"
    off="$(awk -v a="$acc" -v d="$xd" 'BEGIN{printf "%.3f", (a-d>0)?a-d:0}')"
    out="[x$i]"
    fc+="${cur}[$i:v]xfade=transition=$xt:duration=$xd:offset=$off$out;"
    cur="$out"
    acc="$(awk -v a="$acc" -v n="${DUR[$i]}" -v d="$xd" 'BEGIN{printf "%.3f", a+n-d}')"
  done
  fc="${fc%;}"
  ffmpeg -y "${ff_in[@]}" -filter_complex "$fc" -map "$cur" -c:v libx264 -pix_fmt yuv420p "$BASEVID" >/dev/null 2>&1 \
    || die "xfade birleştirme başarısız (ffmpeg)."
else
  log "Birleştirme: düz concat ($N klip)"
  CONCAT="$RUN_DIR/concat.txt"; : > "$CONCAT"
  for f in "${INPUTS[@]}"; do printf "file '%s'\n" "$(cd "$DL" && pwd)/$(basename "$f")" >> "$CONCAT"; done
  ffmpeg -y -f concat -safe 0 -i "$CONCAT" -c:v libx264 -pix_fmt yuv420p "$BASEVID" >/dev/null 2>&1 \
    || die "concat birleştirme başarısız (ffmpeg)."
fi

CUR="$BASEVID"   # son-işleme zinciri için güncel video

# ---- LOOP: son kareyi ilk kareye 0.5s xfade ile bağla (seamless loop) ------
if [ "$LOOP" = 1 ]; then
  dur="$(clip_dur "$CUR")"
  off="$(awk -v a="$dur" 'BEGIN{printf "%.3f", (a-0.5>0)?a-0.5:0}')"
  tmp="$RUN_DIR/_loop.mp4"
  # videonun başını sonuna 0.5s xfade=fade ile karıştır (döngü hissi)
  if ffmpeg -y -i "$CUR" -i "$CUR" -filter_complex \
       "[0:v][1:v]xfade=transition=fade:duration=0.5:offset=$off,format=yuv420p[v]" \
       -map "[v]" -c:v libx264 -pix_fmt yuv420p "$tmp" >/dev/null 2>&1; then
    CUR="$tmp"; info "loop: son→ilk 0.5s xfade uygulandı"
  else warn "loop uygulanamadı (ffmpeg) — atlanıyor"; fi
fi

# ---- HUD: şeffaf overlay'i bindir ------------------------------------------
if [ "$HUD" = 1 ]; then
  if [ -f "$HUD_OVERLAY" ]; then
    tmp="$RUN_DIR/_hud.mp4"
    if ffmpeg -y -i "$CUR" -i "$HUD_OVERLAY" \
         -filter_complex "[0:v][1:v]overlay=0:0:format=auto,format=yuv420p" \
         -c:a copy "$tmp" >/dev/null 2>&1; then
      CUR="$tmp"; info "hud: $HUD_OVERLAY bindirildi"
    else warn "hud bindirme başarısız (ffmpeg) — atlanıyor"; fi
  else
    warn "HUD overlay yok ($HUD_OVERLAY) — önce: python3 hud/hud_generator.py ... Atlanıyor."
  fi
fi

# ---- SES: müzik (+ sfx) ekle -----------------------------------------------
add_audio() {
  local want_sfx=$1 music vol off smix
  music="$MUSIC"
  if [ -z "$music" ] && [ -f "$PRESETS_AU" ]; then music="$(jq -r '.background_music // empty' "$PRESETS_AU" 2>/dev/null)"; fi
  vol="$(jq -r '.music_volume // 0.7' "$PRESETS_AU" 2>/dev/null || echo 0.7)"
  off="$(jq -r '.music_start_offset // 0' "$PRESETS_AU" 2>/dev/null || echo 0)"
  if [ -z "$music" ] || [ ! -f "$music" ]; then
    warn "ses: müzik dosyası yok (${music:-tanımsız}) — ses adımı sessizce atlandı"; return 0
  fi
  local tmp="$RUN_DIR/_audio.mp4"
  # müzik videodan kısaysa loop, uzunsa -shortest ile trim; volume uygula
  if ffmpeg -y -i "$CUR" -stream_loop -1 -ss "$off" -i "$music" \
       -filter:a "volume=$vol" -map 0:v -map 1:a -c:v copy -shortest "$tmp" >/dev/null 2>&1; then
    CUR="$tmp"; info "ses: müzik eklendi (volume=$vol)"
  else warn "ses eklenemedi (ffmpeg) — atlanıyor"; return 0; fi
  # sfx (opsiyonel): başta whoosh, sonda impact — mevcutsa karıştır
  if [ "$want_sfx" = 1 ] && [ -f "$PRESETS_AU" ]; then
    local sfx_start sfx_end svol
    sfx_start="$(jq -r '.sfx.scene_start // empty' "$PRESETS_AU" 2>/dev/null)"
    sfx_end="$(jq -r '.sfx.scene_end // empty' "$PRESETS_AU" 2>/dev/null)"
    svol="$(jq -r '.sfx_volume // 1.0' "$PRESETS_AU" 2>/dev/null || echo 1.0)"
    if [ -n "$sfx_start" ] && [ -f "$sfx_start" ]; then
      local tmp2="$RUN_DIR/_sfx.mp4"
      if ffmpeg -y -i "$CUR" -i "$sfx_start" -filter_complex \
           "[1:a]volume=$svol[s];[0:a][s]amix=inputs=2:duration=first[a]" \
           -map 0:v -map "[a]" -c:v copy "$tmp2" >/dev/null 2>&1; then
        CUR="$tmp2"; info "ses: scene_start sfx karıştırıldı"
      else warn "sfx karıştırılamadı — atlanıyor"; fi
    fi
  fi
}
if [ "$MUSIC_ONLY" = 1 ]; then add_audio 0
elif [ "$AUDIO" = 1 ] || [ -n "$MUSIC" ]; then add_audio 1; fi

# ---- COVER: seçili thumbnail'ı cover.jpg yap -------------------------------
# selection bu video koşusunda veya still koşusunda (out/latest) olabilir.
if [ "$COVER" = 1 ]; then
  seldir=""
  outlatest=""; [ -f out/latest.path ] && outlatest="out/$(tr -d '\r\n' < out/latest.path)"
  for d in "$RUN_DIR" "out/latest" "$outlatest"; do
    [ -n "$d" ] && [ -f "$d/thumbnail_selection.json" ] && { seldir="$d"; break; }
  done
  if [ -n "$seldir" ]; then
    cov="$(jq -r '.cover // empty' "$seldir/thumbnail_selection.json" 2>/dev/null)"
    if [ -n "$cov" ] && [ -f "$seldir/$cov" ]; then
      cp -f "$seldir/$cov" "$RUN_DIR/cover.jpg" && info "cover: $seldir/$cov → cover.jpg"
    else warn "cover: seçili thumbnail dosyası yok ($cov) — atlanıyor"; fi
  else
    warn "cover: thumbnail_selection.json yok — önce ./thumbnail_pick.sh çalıştır. Atlanıyor."
  fi
fi

# ---- Sonuç -----------------------------------------------------------------
OUT="$RUN_DIR/final.mp4"
mv -f "$CUR" "$OUT"
# ara dosyaları temizle
rm -f "$RUN_DIR/_base.mp4" "$RUN_DIR/_loop.mp4" "$RUN_DIR/_hud.mp4" "$RUN_DIR/_audio.mp4" "$RUN_DIR/_sfx.mp4" 2>/dev/null || true
log "Bitti: $OUT"

# ---- Caption + hashtag otomatik üret (mission'ı klip adından çıkar) --------
if [[ "${BASES[0]}" =~ ^M([0-9]+)_s ]]; then
  PY=python3; command -v python3 >/dev/null 2>&1 || PY=python
  if command -v "$PY" >/dev/null 2>&1; then
    log "Caption üretiliyor (mission ${BASH_REMATCH[1]})"
    "$PY" caption.py --mission "${BASH_REMATCH[1]}" --platform both --output "$RUN_DIR/caption" 2>&1 | sed 's/^/    /' || warn "caption üretilemedi"
  fi
fi
