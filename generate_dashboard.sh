#!/usr/bin/env bash
# generate_dashboard.sh — Soccer Manager dashboard asset üreticisi.
# Asset tanımları TEK kaynak: dashboard_assets.json. Ortak altyapı: lib.sh.
#
# Kullanım:
#   ./generate_dashboard.sh                 tüm asset'ler
#   ./generate_dashboard.sh 5               sadece asset 5
#   ./generate_dashboard.sh --dry-run       prompt'ları göster, CLI çağırma
#   ./generate_dashboard.sh --list          asset listesini yaz

set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib.sh
source ./lib.sh
need_cmd jq

ASSETS="dashboard_assets.json"
OUT_ROOT="out_dashboard"
[ -f "$ASSETS" ] || die "Asset dosyası yok: $ASSETS"
jq empty "$ASSETS" 2>/dev/null || die "Geçersiz JSON: $ASSETS"

MODEL="${MODEL:-$(jq -r '.defaults.model' "$ASSETS")}"
MAX_RETRY="${MAX_RETRY:-3}"

DRY_RUN=0; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --list) jq -r '.assets[] | "  \(.id)\t\(.name)\t(\(.aspect))"' "$ASSETS"; exit 0 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    --*) die "Bilinmeyen seçenek: $1" ;;
    *) ONLY="$1" ;;
  esac
  shift
done

RUN_DIR="$(new_run_dir "$OUT_ROOT" "assets")"
MANIFEST="$RUN_DIR/manifest.csv"
manifest_init "$MANIFEST"
log "Koşu dizini: $RUN_DIR"

run_cli() {
  local prompt=$1 aspect=$2 rfile=$3
  higgsfield generate create "$MODEL" \
    --prompt "$prompt" \
    --aspect_ratio "$aspect" \
    --wait > "${rfile}.tmp" 2>&1 && mv -f "${rfile}.tmp" "$rfile"
}

generate_asset() {
  local id=$1
  local a; a="$(jq -c --argjson id "$id" '.assets[] | select(.id==$id)' "$ASSETS")"
  [ -n "$a" ] || die "Geçersiz asset id: $id"
  local name aspect prompt
  name="$(jq -r '.name'   <<<"$a")"
  aspect="$(jq -r '.aspect' <<<"$a")"
  prompt="$(jq -r '.prompt' <<<"$a")"

  local pfile="$RUN_DIR/${name}.prompt.txt"
  local rfile="$RUN_DIR/${name}.result.txt"
  printf 'aspect=%s model=%s\n\n%s\n' "$aspect" "$MODEL" "$prompt" | atomic_write "$pfile"

  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] [$id] $name ($aspect) — $pfile"
    manifest_append "$MANIFEST" "dashboard" "$name" "1" "$MODEL" "$aspect" "-" "" "dry-run" "-" "$(basename "$pfile")"
    return 0
  fi

  log "[$id] $name ($aspect) üretiliyor"
  local status="ok"
  if with_retry "$MAX_RETRY" run_cli "$prompt" "$aspect" "$rfile"; then
    info "URL: $(extract_url "$rfile" || echo '?')"
  else
    status="FAILED"; warn "[$id] $name üretilemedi."
  fi
  manifest_append "$MANIFEST" "dashboard" "$name" "1" "$MODEL" "$aspect" "-" "" "$status" "$(basename "$rfile")" "$(basename "$pfile")"
}

if [ -n "$ONLY" ]; then
  generate_asset "$ONLY"
else
  for id in $(jq -r '.assets[].id' "$ASSETS"); do
    generate_asset "$id"
  done
fi

log "Bitti. Manifest: $MANIFEST"
[ "$DRY_RUN" = 1 ] || info "Galeri için: ./contact_sheet.sh $RUN_DIR"
