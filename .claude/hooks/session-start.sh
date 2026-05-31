#!/bin/bash
# NORTH — SessionStart hook (Claude Code on the web).
# jq'nun kurulu olduğundan emin olur ve config'i doğrular (drift/çelişki erken yakalama).
# Senkron çalışır: oturum başlamadan önce ortam hazır olur.
set -euo pipefail

# Yalnızca uzak (web) ortamda çalış
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}"

# jq gerekli (tüm scriptler config'i jq ile okur)
if ! command -v jq >/dev/null 2>&1; then
  echo "jq kuruluyor..."
  if command -v apt-get >/dev/null 2>&1; then
    { sudo apt-get update -y && sudo apt-get install -y jq; } >/dev/null 2>&1 \
      || apt-get install -y jq >/dev/null 2>&1 \
      || echo "UYARI: jq kurulamadı (ağ/izin yok) — scriptler jq gerektirir."
  fi
fi

# Konfig doğrulama — bozuk JSON / prompt çelişkisi sezon başında yakalansın
ok=1
for f in missions.json dashboard_assets.json pricing.json presets/*.json; do
  [ -f "$f" ] || continue
  if ! jq empty "$f" >/dev/null 2>&1; then echo "GEÇERSIZ JSON: $f"; ok=0; fi
done

if command -v jq >/dev/null 2>&1; then
  if ./generate.sh --check 01 >/dev/null 2>&1; then echo "preflight M01 OK"; else echo "preflight M01 BAŞARISIZ"; ok=0; fi
  if ./generate.sh --check 02 >/dev/null 2>&1; then echo "preflight M02 OK"; else echo "preflight M02 BAŞARISIZ"; ok=0; fi
fi

if [ "$ok" = 1 ]; then
  echo "NORTH ortamı hazır (jq + config doğrulandı)."
else
  echo "NORTH: bazı kontroller başarısız (yukarıdaki satırlara bak)."
fi
exit 0
