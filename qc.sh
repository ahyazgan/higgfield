#!/usr/bin/env bash
# qc.sh — üretilen görseller için kalite kapısı.
#
# Otomatik (bağımlılıksız): geçerli görsel mi, boyut, en-boy oranı talep edilenle
# uyuşuyor mu, bozuk/boş indirme. (qc_core.py)
#
# Opsiyonel derin-QC: QC_VISION_CMD ayarlıysa her görsel için çalıştırılır ve
#   stdout'tan JSON beklenir:  {"face_forward": bool, "location_score": 0..1|null}
#   - face_forward=true  -> FAIL (GTA "arkadan" kuralı ihlali)
#   - location_score < QC_LOC_MIN (vars. 0.5) -> FAIL (mekan master'a benzemiyor)
# Referans uygulama: ./qc_vision.py (opencv gerektirir).
#
# Kullanım:
#   ./qc.sh out/latest
#   QC_VISION_CMD=./qc_vision.py ./qc.sh out/latest

set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh
need_cmd jq

RUN_DIR="${1:?Kullanım: ./qc.sh <koşu_dizini>}"
[ -d "$RUN_DIR" ] || die "Dizin yok: $RUN_DIR"
QC_LOC_MIN="${QC_LOC_MIN:-0.5}"
MISSIONS="missions.json"; LOCS="presets/locations.json"

resolve_master() {  # base -> lokasyon master ref yolu (bulunamazsa boş)
  local base=$1
  [[ "$base" =~ ^M([0-9]+)_s([0-9]+) ]] || return 0
  local m="${BASH_REMATCH[1]}" s="${BASH_REMATCH[2]}" loc
  loc="$(jq -r ".missions.\"$m\".scenes[]|select(.id==$s)|.location" "$MISSIONS" 2>/dev/null)" || return 0
  [ -n "$loc" ] && [ "$loc" != "null" ] && jq -r --arg l "$loc" '.[$l].ref // empty' "$LOCS" 2>/dev/null
}

QC_DIR="$RUN_DIR/qc"; mkdir -p "$QC_DIR"
QCCSV="$RUN_DIR/qc.csv"
printf 'base,status,format,width,height,aspect_ok,bytes,face_forward,location_score,note\n' > "$QCCSV"

have_curl=1; command -v curl >/dev/null 2>&1 || have_curl=0
pass=0; fail=0; skip=0

shopt -s nullglob
for rfile in $(ls "$RUN_DIR"/*.result.txt 2>/dev/null | sort -V); do
  base="$(basename "$rfile" .result.txt)"
  url="$(extract_url "$rfile" || true)"
  pfile="$RUN_DIR/$base.prompt.txt"
  aspect=""; [ -f "$pfile" ] && aspect="$(grep -oE 'aspect=[^ ]+' "$pfile" | head -1 | cut -d= -f2 || true)"

  if [ -z "$url" ]; then
    printf '%s,SKIP,,,,,,,,no-url\n' "$base" >> "$QCCSV"; skip=$((skip+1)); warn "$base: URL yok, atlanıyor"; continue
  fi
  if [ "$have_curl" = 0 ]; then
    printf '%s,SKIP,,,,,,,,no-curl\n' "$base" >> "$QCCSV"; skip=$((skip+1)); continue
  fi

  img="$QC_DIR/$base.img"
  if ! with_retry 3 curl -fsSL "$url" -o "$img"; then
    printf '%s,SKIP,,,,,,,,download-failed\n' "$base" >> "$QCCSV"; skip=$((skip+1)); warn "$base: indirilemedi"; continue
  fi

  core="$(python3 qc_core.py "$img" "$aspect" || true)"
  ok="$(jq -r '.ok'        <<<"$core" 2>/dev/null || echo false)"
  fmt="$(jq -r '.format//""' <<<"$core" 2>/dev/null)"
  w="$(jq -r '.width//0'   <<<"$core" 2>/dev/null)"
  h="$(jq -r '.height//0'  <<<"$core" 2>/dev/null)"
  ar="$(jq -r '.aspect_ok' <<<"$core" 2>/dev/null)"
  by="$(jq -r '.bytes//0'  <<<"$core" 2>/dev/null)"
  note="$(jq -r '.note//""' <<<"$core" 2>/dev/null)"

  ff=""; ls=""
  if [ -n "${QC_VISION_CMD:-}" ]; then
    master="$(resolve_master "$base" || true)"
    vj="$("$QC_VISION_CMD" "$img" "$master" 2>/dev/null || true)"
    if [ -n "$vj" ]; then
      ff="$(jq -r '.face_forward'    <<<"$vj" 2>/dev/null || echo "")"
      ls="$(jq -r '.location_score'  <<<"$vj" 2>/dev/null || echo "")"
      if [ "$ff" = "true" ]; then ok=false; note="${note}; yüz karşıya dönük (GTA ihlali)"; fi
      if [ -n "$ls" ] && [ "$ls" != "null" ] && fgt "$QC_LOC_MIN" "$ls"; then
        ok=false; note="${note}; mekan benzerliği düşük ($ls < $QC_LOC_MIN)"
      fi
    fi
  fi

  if [ "$ok" = "true" ]; then status="PASS"; pass=$((pass+1)); else status="FAIL"; fail=$((fail+1)); fi
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$base" "$status" "$fmt" "$w" "$h" "$ar" "$by" "$ff" "$ls" "${note//,/;}" >> "$QCCSV"
  if [ "$status" = PASS ]; then info "$base: PASS (${fmt} ${w}x${h})"; else warn "$base: FAIL — $note"; fi
done

log "QC bitti — PASS:$pass FAIL:$fail SKIP:$skip → $QCCSV"
if [ -z "${QC_VISION_CMD:-}" ]; then
  info "Derin-QC kapalı (yüz/mekan otomatik kontrolü yok). Açmak için: QC_VISION_CMD=./qc_vision.py ./qc.sh $RUN_DIR"
fi
[ "$fail" -eq 0 ]
