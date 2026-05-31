#!/usr/bin/env bash
# pick.sh — bir still koşusunda her sahne için "kullanılacak" varyantı seçer.
# Seçim <koşu>/selection.json'a yazılır; to_video.sh bunu okuyup yalnızca
# seçilen varyantı klibe çevirir (seçim yoksa tüm varyantları işler).
#
# Kullanım:
#   ./pick.sh out/latest 2 3        # sahne 2 için varyant 3'ü seç
#   ./pick.sh out/latest 2          # tek varyantlı sahne 2'yi seç
#   ./pick.sh out/latest --show     # mevcut seçimleri göster
#   ./pick.sh out/latest --clear    # seçimleri temizle

set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh
need_cmd jq

RUN_DIR="${1:?Kullanım: ./pick.sh <koşu_dizini> <sahne> [varyant] | --show | --clear}"
[ -d "$RUN_DIR" ] || die "Dizin yok: $RUN_DIR"
SEL="$RUN_DIR/selection.json"
[ -f "$SEL" ] || echo '{}' > "$SEL"

case "${2:-}" in
  --show)
    log "Seçimler ($SEL):"
    jq -r 'to_entries[] | "  \(.key) -> \(.value)"' "$SEL"
    exit 0 ;;
  --clear)
    echo '{}' | atomic_write "$SEL"; log "Seçimler temizlendi."; exit 0 ;;
  "") die "sahne numarası gerekli (veya --show/--clear)" ;;
esac

SCENE="$2"; VARIANT="${3:-}"
# Eşleşen prompt dosyasını bul
match=""
if [ -n "$VARIANT" ]; then
  for f in "$RUN_DIR"/M*_s"${SCENE}"_v"${VARIANT}".prompt.txt; do [ -f "$f" ] && match="$f" && break; done
else
  for f in "$RUN_DIR"/M*_s"${SCENE}".prompt.txt "$RUN_DIR"/M*_s"${SCENE}"_v*.prompt.txt; do [ -f "$f" ] && match="$f" && break; done
fi
[ -n "$match" ] || die "Eşleşen kare yok: sahne=$SCENE varyant=${VARIANT:-?} ($RUN_DIR)"

base="$(basename "$match" .prompt.txt)"
key="$(sed -E 's/_v[0-9]+$//' <<<"$base")"   # M01_s2_v3 -> M01_s2

jq --arg k "$key" --arg v "$base" '.[$k]=$v' "$SEL" | atomic_write "$SEL"
log "Seçildi: $key -> $base"
info "Videoya çevir: ./to_video.sh $RUN_DIR   (yalnızca seçilenler işlenir)"
