#!/usr/bin/env bash
# generate.sh — NORTH sahne üreticisi (TEK kaynak: missions.json + presets/).
#
# Kullanım:
#   ./generate.sh                      M01, tüm sahneler
#   ./generate.sh 01 3                 M01, sahne 3
#   ./generate.sh 02                   M02, tüm sahneler
#   ./generate.sh --all                TÜM mission'lar tek koşuda + birleşik manifest
#   ./generate.sh --platform reels 01  Platform profili (reels=9:16, cinema=16:9)
#   ./generate.sh --jobs 6 01          Sahneleri PARALEL üret (en çok 6 eşzamanlı)
#   ./generate.sh --check [--all]      Üretmeden doğrula: config + ref + mutex + CLI flag uyumu
#   ./generate.sh --dry-run 01 2       Prompt'u kur ve göster, CLI çağırma, kredi harcama
#   ./generate.sh --variants 4 01 1    Sahne için 4 varyant üret (seed kayar)
#
# Ortam değişkeni ile override: MODEL, ASPECT, RESOLUTION, SEED, MAX_RETRY, JOBS
#
# Önkoşul: refs/JAY_FACE.jpg + ilgili lokasyon master görseli (refs/*.jpg)

set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib.sh
source ./lib.sh

need_cmd jq

PRESETS_CHAR="presets/characters.json"
PRESETS_LOC="presets/locations.json"
PRESETS_CAM="presets/cameras.json"
MISSIONS="missions.json"
OUT_ROOT="out"

# ---- Argüman ayrıştırma ----------------------------------------------------
DRY_RUN=0; CHECK=0; VARIANTS=1; BUDGET="${BUDGET:-}"; ALL=0; JOBS="${JOBS:-1}"; PLATFORM="${PLATFORM:-}"
ARCHIVE=1; if [ "${NO_ARCHIVE:-}" = 1 ]; then ARCHIVE=0; fi
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --check)   CHECK=1 ;;
    --all)     ALL=1 ;;
    --platform) PLATFORM="${2:?--platform bir isim ister (reels|cinema)}"; shift ;;
    --jobs)    JOBS="${2:?--jobs bir sayı ister}"; shift ;;
    --variants) VARIANTS="${2:?--variants bir sayı ister}"; shift ;;
    --budget)  BUDGET="${2:?--budget bir sayı ister}"; shift ;;
    --no-archive) ARCHIVE=0 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    --*) die "Bilinmeyen seçenek: $1" ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done

MISSION="01"; SCENE=""
if [ "${#ARGS[@]}" -ge 1 ]; then
  if [[ "${ARGS[0]}" =~ ^0[0-9]$ ]]; then
    MISSION="${ARGS[0]}"
    if [ "${#ARGS[@]}" -ge 2 ]; then SCENE="${ARGS[1]}"; fi
  else
    SCENE="${ARGS[0]}"
  fi
fi

# ---- Config yükleme (defaults + override) ----------------------------------
for f in "$PRESETS_CHAR" "$PRESETS_LOC" "$PRESETS_CAM" "$MISSIONS"; do
  [ -f "$f" ] || die "Config dosyası yok: $f"
  jq empty "$f" 2>/dev/null || die "Geçersiz JSON: $f"
done

jqm() { jq -r "$1" "$MISSIONS"; }

# Platform profili: --platform > PLATFORM env > missions defaults.platform > "cinema".
# Profilden aspect_ratio/resolution gelir; ASPECT/RESOLUTION env'leri yine de üst tutar.
PLATFORM="${PLATFORM:-$(jqm '.defaults.platform // empty')}"
PLATFORM="${PLATFORM:-cinema}"
[ -f "$PLATFORMS_FILE" ] && { jq empty "$PLATFORMS_FILE" 2>/dev/null || die "Geçersiz JSON: $PLATFORMS_FILE"; }
PLAT_ASPECT="$(platform_field "$PLATFORM" aspect_ratio "$(jqm '.defaults.aspect_ratio')")"
PLAT_RES="$(platform_field "$PLATFORM" resolution "$(jqm '.defaults.resolution')")"

MODEL="${MODEL:-$(jqm '.defaults.model')}"
ASPECT="${ASPECT:-$PLAT_ASPECT}"
RESOLUTION="${RESOLUTION:-$PLAT_RES}"
STYLE="$(jqm '.defaults.style')"
NEGATIVE="$(jqm '.defaults.negative')"
COMPOSITION="$(jqm '.defaults.composition // empty')"   # dikey 9:16 kompozisyon yönergesi
HUD="$(jqm '.defaults.hud // empty')"                   # GTA minimap/HUD bindirmesi
SEED_DEFAULT="$(jqm '.defaults.seed')"
SEED="${SEED:-$SEED_DEFAULT}"        # "null" => seed kullanılmaz
MAX_RETRY="${MAX_RETRY:-3}"
# nano_banana_2 seed desteklemez; seed destekleyen bir modele geçersen 1 yap.
MODEL_SUPPORTS_SEED="${MODEL_SUPPORTS_SEED:-0}"
UCOST="$(model_cost "$MODEL")"       # birim üretim maliyeti
CUR="$(currency)"
SPENT=0; PROJECTED=0; STOP_BUDGET=0

# --jobs güvenlik kapıları: dry-run paralel anlamsız (hızlı + projeksiyon parent-global);
# bütçe kapısı sıralı muhasebe ister, paralelle birlikte güvenilir değil.
[[ "$JOBS" =~ ^[0-9]+$ ]] || die "--jobs sayı olmalı: $JOBS"
[ "$DRY_RUN" = 1 ] && JOBS=1
if [ "$JOBS" -gt 1 ] && [ -n "$BUDGET" ]; then
  die "--jobs ve --budget birlikte kullanılamaz (bütçe sıralı muhasebe gerektirir). Birini bırak."
fi

# Mission'a özgü karakter preset'ini global'lere yükler.
# --all modunda her mission için ayrı çağrılır (mission'lar farklı karakter kullanabilir).
load_mission() {
  local m=$1
  [ "$(jqm ".missions.\"$m\" // empty")" != "" ] || die "Mission bulunamadı: $m"
  CHAR_ID="$(jqm ".missions.\"$m\".character")"
  CHAR_DESC="$(jq -r --arg c "$CHAR_ID" '.[$c].description'      "$PRESETS_CHAR")"
  CHAR_ANCHOR="$(jq -r --arg c "$CHAR_ID" '.[$c].identity_anchor' "$PRESETS_CHAR")"
  FACE_REF="$(jq -r --arg c "$CHAR_ID" '.[$c].face_ref'          "$PRESETS_CHAR")"
  [ "$CHAR_DESC" != "null" ] || die "Karakter preset'i yok: $CHAR_ID"
}

# ---- Prompt kurucu ---------------------------------------------------------
# Sahne alanlarını okur, blokları çakışmayacak tek bir sırayla birleştirir.
# Sonuçları global'e değil, isimli değişkenlere yazar; her sahne için baştan kurulur.
build_scene() {
  local mission=$1 scene=$2
  local q=".missions.\"$mission\".scenes[] | select(.id==$scene)"
  local s; s="$(jqm "$q")"
  [ -n "$s" ] || die "M$mission sahne $scene bulunamadı"

  S_TITLE="$(jq -r '.title'       <<<"$s")"
  local loc_id cam_id framing action env
  loc_id="$(jq -r '.location'  <<<"$s")"
  cam_id="$(jq -r '.camera'    <<<"$s")"
  framing="$(jq -r '.framing'  <<<"$s")"
  action="$(jq -r '.action'    <<<"$s")"
  env="$(jq -r '.environment' <<<"$s")"

  LOC_LOCK="$(jq -r --arg l "$loc_id" '.[$l].lock'   "$PRESETS_LOC")"
  LOC_ANCHOR="$(jq -r --arg l "$loc_id" '.[$l].anchor' "$PRESETS_LOC")"
  LOC_REF="$(jq -r --arg l "$loc_id" '.[$l].ref'     "$PRESETS_LOC")"
  [ "$LOC_LOCK" != "null" ] || die "Lokasyon preset'i yok: $loc_id"

  local cam_base
  cam_base="$(jq -r --arg m "$cam_id" '.modes[$m] // empty' "$PRESETS_CAM")"
  [ -n "$cam_base" ] || die "Kamera modu yok: '$cam_id' (geçerli: $(jq -r '.modes|keys|join(", ")' "$PRESETS_CAM"))"

  # Sıra: lokasyon ankor + kimlik ankor -> lokasyon kilidi -> karakter -> KAMERA(tek mod)
  #       -> framing -> aksiyon -> ortam -> DIKEY KOMPOZISYON -> stil -> GTA HUD
  PROMPT="$LOC_ANCHOR $CHAR_ANCHOR $LOC_LOCK, $CHAR_DESC, ${action}, ${cam_base}, ${framing}, ${env}"
  [ -n "$COMPOSITION" ] && PROMPT="$PROMPT, ${COMPOSITION}"
  PROMPT="$PROMPT, ${STYLE}"
  [ -n "$HUD" ] && PROMPT="$PROMPT, ${HUD}"
}

# ---- Üretim (tek sahne) ----------------------------------------------------
generate_one() {
  local mission=$1 scene=$2 outdir=$3 manifest=$4
  build_scene "$mission" "$scene"

  # Çelişki kapısı
  if ! mutex_check "$PROMPT"; then
    die "M$mission sahne $scene prompt'unda çelişki var — üretim iptal (yukarıdaki uyarılara bak)."
  fi

  # Ref kontrolü — dry-run önizlemesi ref görseli gerektirmez (CLI çağrılmaz).
  # Gerçek üretimde ref zorunlu.
  local ref="$LOC_REF"
  for img in "$FACE_REF" "$ref"; do
    if [ ! -f "$img" ]; then
      if [ "$DRY_RUN" = 1 ]; then
        warn "(dry-run) ref görseli yok: $img — gerçek üretimde gerekli"
      else
        die "Referans görseli yok: $img"
      fi
    fi
  done

  local base="M${mission}_s${scene}"
  local v
  for (( v=1; v<=VARIANTS; v++ )); do
    local tag="$base"; if [ "$VARIANTS" -gt 1 ]; then tag="${base}_v${v}"; fi
    local pfile="$outdir/${tag}.prompt.txt"
    local rfile="$outdir/${tag}.result.txt"

    # Prompt'u her zaman kaydet (dry-run dahil) — tam tekrar-üretilebilirlik
    {
      printf 'mission=%s scene=%s variant=%s\n' "$mission" "$scene" "$v"
      printf 'model=%s aspect=%s resolution=%s seed=%s\n' "$MODEL" "$ASPECT" "$RESOLUTION" "$(scene_seed "$mission" "$scene" "$v")"
      printf 'refs=%s + %s\n\n' "$ref" "$FACE_REF"
      printf 'POSITIVE:\n%s\n\nNEGATIVE:\n%s\n' "$PROMPT" "$NEGATIVE"
    } | atomic_write "$pfile"

    if [ "$DRY_RUN" = 1 ]; then
      PROJECTED="$(fadd "$PROJECTED" "$UCOST")"
      log "[dry-run] M$mission $S_TITLE (s$scene v$v) — prompt: $pfile"
      info "$PROMPT"
      manifest_append "$manifest" "M$mission" "s$scene" "$v" "$MODEL" "$ASPECT" "$RESOLUTION" \
        "$(scene_seed "$mission" "$scene" "$v")" "dry-run" "-" "$(basename "$pfile")" "$UCOST"
      continue
    fi

    # Bütçe kapısı: bu üretim limiti aşacaksa dur
    if [ -n "$BUDGET" ] && fgt "$(fadd "$SPENT" "$UCOST")" "$BUDGET"; then
      warn "Bütçe limitine ulaşıldı ($CUR $BUDGET). Harcanan: $CUR $SPENT. Kalan sahneler atlanıyor."
      STOP_BUDGET=1; return 0
    fi

    log "M$mission $S_TITLE (s$scene v$v) üretiliyor → $(basename "$rfile")"
    local status="ok" cost="$UCOST"
    if with_retry "$MAX_RETRY" run_cli "$ref" "$rfile" "$(scene_seed "$mission" "$scene" "$v")"; then
      info "URL: $(extract_url "$rfile" || echo '?')"
      SPENT="$(fadd "$SPENT" "$UCOST")"
      if [ "$ARCHIVE" = 1 ]; then
        local u saved
        u="$(extract_url "$rfile" || true)"
        if [ -n "$u" ]; then
          saved="$(archive_result "$u" "$outdir/$tag" || true)"
          if [ -n "$saved" ]; then info "arşivlendi: $(basename "$saved")"; else warn "$tag: arşivlenemedi (curl yok / indirme hatası) — URL süreli olabilir"; fi
        fi
      fi
    else
      status="FAILED"; cost=0; warn "M$mission s$scene v$v üretilemedi."
    fi
    manifest_append "$manifest" "M$mission" "s$scene" "$v" "$MODEL" "$ASPECT" "$RESOLUTION" \
      "$(scene_seed "$mission" "$scene" "$v")" "$status" "$(basename "$rfile")" "$(basename "$pfile")" "$cost"
  done
}

# Deterministik seed: SEED set ise SEED + (scene*10 + variant), değilse boş.
scene_seed() {
  local mission=$1 scene=$2 v=$3
  if [ "$SEED" = "null" ] || [ -z "$SEED" ]; then printf ''; return; fi
  printf '%s' "$(( SEED + scene*10 + v ))"
}

# CLI çağrısı — sonucu atomik olarak rfile'a yazar.
# Not: nano_banana_2 yalnızca prompt/input_images/aspect_ratio/resolution kabul eder.
# negative-prompt ve seed bu modelde YOK (negatif yine de prompt.txt'ye kayıt için tutulur).
# Modeli değiştirirsen `higgsfield model get <model>` ile geçerli paramları doğrula.
run_cli() {
  local ref=$1 rfile=$2 seed=$3
  local extra=()
  if [ -n "$seed" ] && [ "$MODEL_SUPPORTS_SEED" = 1 ]; then extra+=(--seed "$seed"); fi
  higgsfield generate create "$MODEL" \
    --prompt "$PROMPT" \
    --image "$ref" \
    --image "$FACE_REF" \
    --aspect_ratio "$ASPECT" \
    --resolution "$RESOLUTION" \
    "${extra[@]}" \
    --wait > "${rfile}.tmp" 2>&1 && mv -f "${rfile}.tmp" "$rfile"
}

# ---- CLI sürüm + model parametre uyumu -------------------------------------
# Üretimden önce modelin GERÇEK parametre listesini (higgsfield model get) okur ve
# generate.sh'in göndereceği flag'lerle karşılaştırır — CLI sürümü değişip bir flag
# kaybolduysa (örn. --negative-prompt) krediyi yakmadan ÖNCE uyarır.
check_cli_params() {
  command -v higgsfield >/dev/null 2>&1 || return 0
  local ver; ver="$(higgsfield version 2>/dev/null | head -1 | tr -d '\r' || true)"
  [ -n "$ver" ] && info "higgsfield: $ver"
  local spec; spec="$(higgsfield model get "$MODEL" 2>/dev/null | tr -d '\r' || true)"
  if [ -z "$spec" ]; then
    warn "model parametreleri okunamadı ($MODEL) — flag uyumu doğrulanamadı"; return 0
  fi
  # Modelin kabul ettiği param adları: "PARAM" başlık satırından sonraki ilk sütun.
  local params; params="$(awk 'f && $1 ~ /^[a-z_]+$/{print $1} /^PARAM/{f=1}' <<<"$spec")"
  local need="prompt input_images aspect_ratio resolution"
  [ "$MODEL_SUPPORTS_SEED" = 1 ] && need="$need seed"
  local p miss=0
  for p in $need; do
    if ! grep -qx "$p" <<<"$params"; then
      warn "model '$MODEL' '$p' parametresini listelemiyor ama generate.sh gönderiyor — CLI sürümü değişmiş olabilir. 'higgsfield model get $MODEL' ile run_cli flag'lerini doğrula."
      miss=$((miss+1))
    fi
  done
  if [ "$miss" -eq 0 ]; then info "CLI flag uyumu OK ($MODEL: $(tr '\n' ' ' <<<"$params"))"; fi
}

# ---- --check (preflight) ---------------------------------------------------
# Tek mission'ın ref+mutex kontrolü; bulunan sorunları global CK_FAIL/CK_MISSING'e ekler.
run_check_one() {
  local m=$1 sc scenes
  load_mission "$m"
  scenes="$(jqm ".missions.\"$m\".scenes[].id")"
  for sc in $scenes; do
    build_scene "$m" "$sc"
    # ref kontrolü — eksik ref config hatası DEĞİL, asset hazırlık uyarısıdır
    # (gerçek üretim yine de ref'i şart koşar). Bu yüzden preflight'ı düşürmez.
    for img in "$FACE_REF" "$LOC_REF"; do
      if [ ! -f "$img" ]; then warn "M$m s$sc: ref görseli yok (üretim için gerekli): $img"; CK_MISSING=$((CK_MISSING+1)); fi
    done
    if mutex_check "$PROMPT" 2>/tmp/mx.$$; then
      info "M$m s$sc ($S_TITLE): prompt OK ($(wc -w <<<"$PROMPT") kelime)"
    else
      cat /tmp/mx.$$ >&2; CK_FAIL=$((CK_FAIL+1))
    fi
    rm -f /tmp/mx.$$
  done
}

run_check() {
  CK_FAIL=0; CK_MISSING=0
  if command -v higgsfield >/dev/null 2>&1; then
    info "higgsfield: $(command -v higgsfield)"
    check_cli_params
  else
    warn "higgsfield CLI kurulu değil — gerçek üretim yapılamaz, --dry-run çalışır (config kontrolü sürüyor)"
  fi

  if [ "$ALL" = 1 ]; then
    log "Preflight kontrolü (TÜM mission'lar)"
    for m in $(jqm '.missions|keys[]'); do run_check_one "$m"; done
  else
    log "Preflight kontrolü (M$MISSION)"
    run_check_one "$MISSION"
  fi

  if [ "$CK_FAIL" -ne 0 ]; then
    die "Preflight $CK_FAIL config/çelişki sorunu buldu (yukarı bak)."
  fi
  if [ "$CK_MISSING" -ne 0 ]; then
    warn "Config TEMIZ ✔ ama $CK_MISSING ref görseli eksik — o sahneler üretilemeden önce ilgili görseli ekle."
  else
    log "Preflight TEMIZ ✔  (üretime hazır)"
  fi
}

# ---- Akış ------------------------------------------------------------------
if [ "$CHECK" = 1 ]; then
  run_check
  exit 0
fi

RUN_LABEL="M${MISSION}"; [ "$ALL" = 1 ] && RUN_LABEL="ALL"
RUN_DIR="$(new_run_dir "$OUT_ROOT" "$RUN_LABEL")"
MANIFEST="$RUN_DIR/manifest.csv"
manifest_init "$MANIFEST"
log "Platform: $PLATFORM (aspect ${ASPECT}, res ${RESOLUTION})"
log "Koşu dizini: $RUN_DIR"

# Bir mission'ı üretir (scene verilirse sadece onu). Tüm sahneler tek RUN_DIR/MANIFEST'e yazılır.
# JOBS>1 ise sahneler izole subshell'lerde paralel üretilir (her biri kendi manifest
# parçasına yazar; sonda sahne sırasıyla birleştirilir — satır karışması olmaz).
gen_mission() {
  local m=$1 only=${2:-} s scenes
  load_mission "$m"
  if [ -n "$only" ]; then scenes="$only"; else scenes="$(jqm ".missions.\"$m\".scenes[].id")"; fi

  if [ "$JOBS" -le 1 ]; then
    for s in $scenes; do
      generate_one "$m" "$s" "$RUN_DIR" "$MANIFEST"
      if [ "$STOP_BUDGET" = 1 ]; then break; fi
    done
    return 0
  fi

  # Paralel: en çok JOBS eşzamanlı arka plan işi.
  local running=0
  for s in $scenes; do
    ( generate_one "$m" "$s" "$RUN_DIR" "$RUN_DIR/.mf.${m}_${s}" ) &
    running=$((running+1))
    if [ "$running" -ge "$JOBS" ]; then wait -n 2>/dev/null || true; running=$((running-1)); fi
  done
  wait 2>/dev/null || true
  # Parçaları sahne sırasıyla ana manifest'e ekle, sonra temizle.
  cat "$RUN_DIR"/.mf.${m}_* 2>/dev/null | sort -t, -k3 -V >> "$MANIFEST" || true
  rm -f "$RUN_DIR"/.mf.${m}_* 2>/dev/null || true
}

[ "$JOBS" -gt 1 ] && log "Paralel üretim: en çok $JOBS eşzamanlı iş"
if [ "$ALL" = 1 ]; then
  log "Multi-mission akış: tüm mission'lar tek koşuda → $RUN_DIR"
  for m in $(jqm '.missions|keys[]'); do
    gen_mission "$m"
    if [ "$STOP_BUDGET" = 1 ]; then break; fi
  done
else
  gen_mission "$MISSION" "$SCENE"
fi

# Paralel modda harcama parent'ta birikmez (subshell'ler) — manifest'ten topla.
if [ "$DRY_RUN" != 1 ] && [ "$JOBS" -gt 1 ]; then
  SPENT="$(awk -F, 'NR>1 && $9=="ok"{s+=$12} END{printf "%.4f", s+0}' "$MANIFEST" 2>/dev/null || echo 0)"
fi

# Maliyet özeti
if [ "$DRY_RUN" = 1 ]; then
  log "Tahmini maliyet (dry-run projeksiyonu): $CUR $PROJECTED"
else
  log "Harcanan (tahmini): $CUR $SPENT"
fi
if fgt "0.0001" "$UCOST"; then
  warn "pricing.json'da '$MODEL' için maliyet 0 — gerçek rakamı girersen bütçe/özet anlamlı olur."
fi

log "Bitti. Manifest: $MANIFEST"
[ "$DRY_RUN" = 1 ] || info "Galeri için: ./contact_sheet.sh $RUN_DIR"
