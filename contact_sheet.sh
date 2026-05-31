#!/usr/bin/env bash
# contact_sheet.sh — bir koşu dizinindeki sonuçlardan tek HTML galeri üretir.
# Sonuç dosyasında http(s) URL varsa <img> gömer, yoksa prompt metnini gösterir.
#
# Kullanım:
#   ./contact_sheet.sh out/latest
#   ./contact_sheet.sh out_dashboard/20260531-xxxxx_assets

set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

RUN_DIR="$(resolve_run_dir "${1:?Kullanım: ./contact_sheet.sh <koşu_dizini>}")"
[ -d "$RUN_DIR" ] || die "Dizin yok: $RUN_DIR"
OUT="$RUN_DIR/index.html"

esc() { sed -e 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

{
  cat <<'HTML'
<!doctype html><html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>NORTH — Contact Sheet</title>
<style>
  body{background:#111;color:#eee;font:14px/1.5 system-ui,sans-serif;margin:0;padding:24px}
  h1{font-size:18px;margin:0 0 16px}
  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:16px}
  .card{background:#1b1b1b;border:1px solid #2a2a2a;border-radius:10px;overflow:hidden}
  .card img{width:100%;display:block;background:#000}
  .card .body{padding:10px 12px}
  .card h2{font-size:13px;margin:0 0 6px;color:#7ec8ff}
  .card pre{white-space:pre-wrap;word-break:break-word;font-size:11px;color:#aaa;margin:0;max-height:160px;overflow:auto}
  .missing{padding:40px 12px;text-align:center;color:#666;background:#161616}
  .tag{display:inline-block;font-size:10px;color:#999;border:1px solid #333;border-radius:4px;padding:1px 6px;margin-bottom:6px}
  .qc{display:inline-block;font-size:10px;border-radius:4px;padding:1px 6px;margin:0 0 6px 4px;font-weight:600}
  .qc.PASS{background:#173d1f;color:#7ee787;border:1px solid #2a6}
  .qc.FAIL{background:#3d1717;color:#ff7b72;border:1px solid #a33}
  .qc.SKIP{background:#222;color:#999;border:1px solid #444}
  .review{font-size:11px;color:#bbb;margin-top:8px;border-top:1px solid #2a2a2a;padding-top:6px}
  .review label{display:block;cursor:pointer}
</style></head><body>
HTML
  printf '<h1>Contact Sheet — %s</h1><div class="grid">\n' "$(basename "$RUN_DIR" | esc)"

  QCCSV="$RUN_DIR/qc.csv"
  qc_status() {  # base -> PASS/FAIL/SKIP (qc.csv yoksa boş)
    [ -f "$QCCSV" ] || return 0
    awk -F, -v b="$1" 'NR>1 && $1==b{print $2; exit}' "$QCCSV"
  }

  shopt -s nullglob
  for pfile in "$RUN_DIR"/*.prompt.txt; do
    base="$(basename "$pfile" .prompt.txt)"
    rfile="$RUN_DIR/$base.result.txt"
    url=""
    [ -f "$rfile" ] && url="$(extract_url "$rfile" || true)"
    qc="$(qc_status "$base")"

    # Arşivlenmiş yerel dosya varsa onu kullan (URL süreli olabilir); yoksa URL
    local_img=""
    for e in png jpg jpeg webp gif; do
      if [ -f "$RUN_DIR/$base.$e" ]; then local_img="$base.$e"; break; fi
    done

    printf '<div class="card">'
    if [ -n "$local_img" ]; then
      printf '<img src="%s" alt="%s" loading="lazy"><div class="tag">arşiv: %s</div>' "$(esc <<<"$local_img")" "$(esc <<<"$base")" "$(esc <<<"$local_img")"
    elif [ -n "$url" ]; then
      printf '<img src="%s" alt="%s" loading="lazy">' "$(esc <<<"$url")" "$(esc <<<"$base")"
    else
      printf '<div class="missing">görsel yok / üretilmedi</div>'
    fi
    printf '<div class="body"><h2>%s</h2><span class="tag">%s</span>' \
      "$(esc <<<"$base")" \
      "$( [ -n "$url" ] && echo "URL var" || echo "dry-run / sonuç yok" )"
    if [ -n "$qc" ]; then printf '<span class="qc %s">QC: %s</span>' "$qc" "$qc"; fi
    # Manuel inceleme: otomatik QC yakalayamadığı kuralları insanın onaylaması için
    printf '<div class="review"><label><input type="checkbox"> Karakter ARKADAN (yüz kameraya dönük değil)</label><label><input type="checkbox"> Bina/iç mekan master ile aynı</label><label><input type="checkbox"> Kıyafet/kimlik tutarlı</label></div>'
    printf '<pre>%s</pre></div></div>\n' "$(esc < "$pfile")"
  done

  printf '</div></body></html>\n'
} | atomic_write "$OUT"

log "Galeri yazıldı: $OUT"
info "Tarayıcıda aç: file://$(pwd)/$OUT"
