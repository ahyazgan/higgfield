#!/usr/bin/env bash
# generate.sh — NORTH sahne üreticisi (TEK kaynak: missions.json + presets/).
#
# Kullanım:
#   ./generate.sh                      M01, tüm sahneler
#   ./generate.sh 01 3                 M01, sahne 3
#   ./generate.sh 02                   M02, tüm sahneler
#   ./generate.sh --check              Üretmeden doğrula (preflight): config + ref + mutex
#   ./generate.sh --dry-run 01 2       Prompt'u kur ve göster, CLI çağırma, kredi harcama
#   ./generate.sh --variants 4 01 1    Sahne için 4 varyant üret (seed kayar)
#
# Ortam değişkeni ile override: MODEL, ASPECT, RESOLUTION, SEED, MAX_RETRY
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
DRY_RUN=0; CHECK=0; VARIANTS=1; BUDGET="${BUDGET:-}"
ARCHIVE=1; if [ "${NO_ARCHIVE:-}" = 1 ]; then ARCHIVE=0; fi
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --check)   CHECK=1 ;;
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

MODEL="${MODEL:-$(jqm '.defaults.model')}"
ASPECT="${ASPECT:-$(jqm '.defaults.aspect_ratio')}"
RESOLUTION="${RESOLUTION:-$(jqm '.defaults.resolution')}"
STYLE="$(jqm '.defaults.style')"
NEGATIVE="$(jqm '.defaults.negative')"
SEED_DEFAULT="$(jqm '.defaults.seed')"
SEED="${SEED:-$SEED_DEFAULT}"        # "null" => seed kullanılmaz
MAX_RETRY="${MAX_RETRY:-3}"
UCOST="$(model_cost "$MODEL")"       # birim üretim maliyeti
CUR="$(currency)"
SPENT=0; PROJECTED=0; STOP_BUDGET=0

[ "$(jqm ".missions.\"$MISSION\" // empty")" != "" ] || die "Mission bulunamadı: $MISSION"
CHAR_ID="$(jqm ".missions.\"$MISSION\".character")"

# Karakter preset
CHAR_DESC="$(jq -r --arg c "$CHAR_ID" '.[$c].description'      "$PRESETS_CHAR")"
CHAR_ANCHOR="$(jq -r --arg c "$CHAR_ID" '.[$c].identity_anchor' "$PRESETS_CHAR")"
FACE_REF="$(jq -r --arg c "$CHAR_ID" '.[$c].face_ref'          "$PRESETS_CHAR")"
[ "$CHAR_DESC" != "null" ] || die "Karakter preset'i yok: $CHAR_ID"

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

  # Sıra: lokasyon ankor + kimlik ankor -> lokasyon kilidi -> karakter -> KAMERA(tek mod) -> framing -> aksiyon -> ortam -> stil
  PROMPT="$LOC_ANCHOR $CHAR_ANCHOR $LOC_LOCK, $CHAR_DESC, ${action}, ${cam_base}, ${framing}, ${env}, ${STYLE}"
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
run_cli() {
  local ref=$1 rfile=$2 seed=$3
  local seed_args=()
  if [ -n "$seed" ]; then seed_args=(--seed "$seed"); fi
  higgsfield generate create "$MODEL" \
    --prompt "$PROMPT" \
    --negative-prompt "$NEGATIVE" \
    --image "$ref" \
    --image "$FACE_REF" \
    --aspect_ratio "$ASPECT" \
    --resolution "$RESOLUTION" \
    "${seed_args[@]}" \
    --wait > "${rfile}.tmp" 2>&1 && mv -f "${rfile}.tmp" "$rfile"
}

# ---- --check (preflight) ---------------------------------------------------
run_check() {
  log "Preflight kontrolü (M$MISSION)"
  local fail=0

  if command -v higgsfield >/dev/null 2>&1; then
    info "higgsfield: $(command -v higgsfield)"
  else
    warn "higgsfield CLI kurulu değil — gerçek üretim yapılamaz, --dry-run çalışır (config kontrolü sürüyor)"
  fi

  # Sahne listesi
  local scenes missing=0; scenes="$(jqm ".missions.\"$MISSION\".scenes[].id")"
  for sc in $scenes; do
    build_scene "$MISSION" "$sc"
    # ref kontrolü — eksik ref config hatası DEĞİL, asset hazırlık uyarısıdır
    # (gerçek üretim yine de ref'i şart koşar). Bu yüzden preflight'ı düşürmez.
    for img in "$FACE_REF" "$LOC_REF"; do
      if [ ! -f "$img" ]; then warn "s$sc: ref görseli yok (üretim için gerekli): $img"; missing=$((missing+1)); fi
    done
    # mutex
    if mutex_check "$PROMPT" 2>/tmp/mx.$$; then
      info "s$sc ($S_TITLE): prompt OK ($(wc -w <<<"$PROMPT") kelime)"
    else
      cat /tmp/mx.$$ >&2; fail=$((fail+1))
    fi
    rm -f /tmp/mx.$$
  done

  if [ "$fail" -ne 0 ]; then
    die "Preflight $fail config/çelişki sorunu buldu (yukarı bak)."
  fi
  if [ "$missing" -ne 0 ]; then
    warn "Config TEMIZ ✔ ama $missing ref görseli eksik — o sahneler üretilemeden önce ilgili görseli ekle."
  else
    log "Preflight TEMIZ ✔  (üretime hazır)"
  fi
}

# ---- Akış ------------------------------------------------------------------
if [ "$CHECK" = 1 ]; then
  run_check
  exit 0
fi

RUN_DIR="$(new_run_dir "$OUT_ROOT" "M${MISSION}")"
MANIFEST="$RUN_DIR/manifest.csv"
manifest_init "$MANIFEST"
log "Koşu dizini: $RUN_DIR"

if [ -n "$SCENE" ]; then
  generate_one "$MISSION" "$SCENE" "$RUN_DIR" "$MANIFEST"
else
  for s in $(jqm ".missions.\"$MISSION\".scenes[].id"); do
    generate_one "$MISSION" "$s" "$RUN_DIR" "$MANIFEST"
    if [ "$STOP_BUDGET" = 1 ]; then break; fi
  done
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
