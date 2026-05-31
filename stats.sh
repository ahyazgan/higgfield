#!/usr/bin/env bash
# stats.sh — tüm koşuların üretim sağlık özeti (başarı/başarısızlık trendi + QC).
# out/, out_video/, out_dashboard/ altındaki manifest.csv'leri tarar ve koşu-bazlı
# + genel başarısızlık oranını gösterir. Koşular zaman damgalı olduğu için liste
# kronolojiktir = trend (fail% zamanla yükseliyor mu düşüyor mu görünür).
#
# Kullanım: ./stats.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

ROOTS=("out" "out_video" "out_dashboard")
printf '%-28s %7s %5s %7s %6s  %s\n' "KOŞU" "ÜRETİM" "OK" "FAILED" "FAIL%" "QC(P/F)"
printf '%s\n' "--------------------------------------------------------------------------"

g_total=0; g_ok=0; g_fail=0; g_qp=0; g_qf=0; runs=0
shopt -s nullglob
for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || continue
  for mf in "$root"/*/manifest.csv; do
    run="$(basename "$(dirname "$mf")")"
    [ "$run" = "latest" ] && continue   # junction — işaret ettiği gerçek koşu zaten sayılıyor
    stats="$(awk -F, '
      function clean(s){ gsub(/\r/,"",s); return s }
      NR>1{
        n++; s=clean($9);
        if(s=="ok") ok++;
        else if(s=="FAILED") fail++;
        else if(s=="dry-run") dry++;
        q=clean($13);
        if(q=="PASS") qp++; else if(q=="FAIL") qf++;
      }
      END{printf "%d %d %d %d %d %d", n+0, ok+0, fail+0, dry+0, qp+0, qf+0}
    ' "$mf")"
    read -r tot ok fail dry qp qf <<<"$stats"
    real=$((tot - dry))                 # dry-run koşuları üretim sayılmaz
    [ "$real" -le 0 ] && continue
    pct="$(awk -v f="$fail" -v t="$real" 'BEGIN{printf "%.0f", t ? f*100/t : 0}')"
    printf '%-28s %7d %5d %7d %5s%%  %d/%d\n' "$run" "$real" "$ok" "$fail" "$pct" "$qp" "$qf"
    g_total=$((g_total+real)); g_ok=$((g_ok+ok)); g_fail=$((g_fail+fail))
    g_qp=$((g_qp+qp)); g_qf=$((g_qf+qf)); runs=$((runs+1))
  done
done

printf '%s\n' "--------------------------------------------------------------------------"
if [ "$g_total" -le 0 ]; then
  log "Henüz gerçek üretim koşusu yok (sadece dry-run veya boş)."
  exit 0
fi
gpct="$(awk -v f="$g_fail" -v t="$g_total" 'BEGIN{printf "%.1f", f*100/t}')"
qcrate="$(awk -v p="$g_qp" -v f="$g_qf" 'BEGIN{t=p+f; printf "%s", t ? sprintf("%.1f%%", p*100/t) : "-"}')"
log "GENEL: $runs koşu · $g_total üretim · $g_ok ok · $g_fail başarısız → FAIL %$gpct"
info "QC geçme oranı: $qcrate  (PASS $g_qp / FAIL $g_qf)"
[ "$g_fail" -gt 0 ] && warn "Başarısız üretimler var — son koşuların manifest'lerine bak (status=FAILED)."
exit 0
