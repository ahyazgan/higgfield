#!/usr/bin/env bash
# costs.sh — koşu manifest'lerinden tahmini maliyet raporu.
#
# Kullanım:
#   ./costs.sh                       # tüm out*/**/manifest.csv toplamı
#   ./costs.sh out/latest            # tek koşu
#   ./costs.sh out_video/latest/manifest.csv

set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh
CUR="$(currency)"

# Argümandan manifest dosyalarını topla
files=()
if [ $# -eq 0 ]; then
  while IFS= read -r m; do files+=("$m"); done < <(find out out_dashboard out_video -name manifest.csv 2>/dev/null)
else
  for a in "$@"; do
    if [ -d "$a" ]; then files+=("$a/manifest.csv"); else files+=("$a"); fi
  done
fi
[ "${#files[@]}" -gt 0 ] || die "Manifest bulunamadı (önce bir üretim/dry-run çalıştır)."

printf '%-28s %8s %8s %10s\n' "KOŞU" "satır" "ok" "maliyet($CUR)"
printf -- '---------------------------------------------------------------\n'
grand=0
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  # est_cost = son kolon; status = 9. kolon
  read -r rows ok sum < <(awk -F, 'NR>1{rows++; if($9=="ok"){ok++}; c=$NF+0; s+=c} END{printf "%d %d %.4f\n", rows+0, ok+0, s+0}' "$f")
  printf '%-28s %8s %8s %10s\n' "$(basename "$(dirname "$f")")" "$rows" "$ok" "$sum"
  grand="$(fadd "$grand" "$sum")"
done
printf -- '---------------------------------------------------------------\n'
printf '%-28s %8s %8s %10s\n' "TOPLAM" "" "" "$grand"

if fgt "0.0001" "$grand"; then
  warn "Toplam 0 — pricing.json'daki model maliyetlerini doldurmadıysan rapor sıfır çıkar."
fi
