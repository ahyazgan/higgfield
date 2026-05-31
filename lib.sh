#!/usr/bin/env bash
# lib.sh — NORTH / Higgsfield ortak çekirdek fonksiyonları.
# Durum tutmaz, saf yardımcılardır; hem generate.sh hem generate_dashboard.sh source eder.
# shellcheck shell=bash

# ---- Loglama ---------------------------------------------------------------
_c_red=$'\033[31m'; _c_yel=$'\033[33m'; _c_grn=$'\033[32m'; _c_dim=$'\033[2m'; _c_rst=$'\033[0m'
log()  { printf '%s==>%s %s\n'   "$_c_grn" "$_c_rst" "$*" >&2; }
info() { printf '%s    %s%s\n'   "$_c_dim" "$*" "$_c_rst" >&2; }
warn() { printf '%sUYARI:%s %s\n' "$_c_yel" "$_c_rst" "$*" >&2; }
die()  { printf '%sHATA:%s %s\n'  "$_c_red" "$_c_rst" "$*" >&2; exit 1; }

# ---- Önkoşullar ------------------------------------------------------------
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Gerekli komut bulunamadı: $1"; }

# ---- jq sarmalayıcı (Windows CRLF düzeltmesi) ------------------------------
# Windows jq derlemesi stdout'u METIN modunda yazıp her satıra \r ekler. Bu \r,
# $(jq ...) ile yakalanan değerlere (sahne id, base, vb.) sızıp dosya adlarını
# bozar (örn. "M01_s1\r.png" → curl onu "M01_s1_.png" yapar, mv eşleşmez).
# Tüm jq çıktısından \r'yi tek noktada süpür. set -o pipefail açık olduğundan
# jq'nun çıkış kodu korunur (tr daima 0 dönse de pipeline jq'nunkini yansıtır).
jq() { command jq "$@" | tr -d '\r'; }

# ---- Platform profilleri (presets/platforms.json) --------------------------
# Yayın hedefine göre aspect_ratio/resolution/süre tavanını tek yerden çözer.
PLATFORMS_FILE="${PLATFORMS_FILE:-presets/platforms.json}"
platform_field() {  # platform_field <profil> <alan> <fallback> -> değer (profil/dosya yoksa fallback)
  local name=$1 field=$2 fallback=$3 v=""
  if [ -f "$PLATFORMS_FILE" ]; then
    v="$(jq -r --arg p "$name" --arg f "$field" '.profiles[$p][$f] // empty' "$PLATFORMS_FILE" 2>/dev/null)"
  fi
  printf '%s' "${v:-$fallback}"
}

# ---- Atomik yazma ----------------------------------------------------------
# stdin'i hedef dosyaya atomik olarak yazar (yarım/bozuk dosya bırakmaz).
atomic_write() {
  local dest=$1 tmp
  tmp="$(mktemp "${dest}.tmp.XXXXXX")" || die "mktemp başarısız: $dest"
  cat > "$tmp"
  mv -f "$tmp" "$dest"
}

# ---- Retry / exponential backoff -------------------------------------------
# with_retry <max_deneme> <komut...>  — 2s,4s,8s,... backoff ile tekrar dener.
with_retry() {
  local max=$1; shift
  local n=1 delay=2
  until "$@"; do
    if [ "$n" -ge "$max" ]; then
      warn "komut $max denemede de başarısız: $*"
      return 1
    fi
    warn "deneme $n/$max başarısız, ${delay}s sonra tekrar..."
    sleep "$delay"
    n=$((n + 1)); delay=$((delay * 2))
  done
  return 0
}

# ---- Run (koşu) izolasyonu -------------------------------------------------
# new_run_dir <kök> <etiket>  -> "kök/<zaman>_<etiket>" yolunu üretir, 'latest' linkini günceller.
new_run_dir() {
  local root=$1 label=$2 stamp dir
  stamp="$(date +%Y%m%d-%H%M%S)"
  dir="${root}/${stamp}_${label}"
  # Aynı saniyede başlayan iki koşu aynı dizini paylaşmasın
  if [ -e "$dir" ]; then
    dir="${root}/${stamp}-$$-${RANDOM}_${label}"
  fi
  mkdir -p "$dir"
  update_latest "$root" "$dir"
  printf '%s\n' "$dir"
}

# 'latest' kısayolunu en güncel koşuya çevirir. Windows'ta msys `ln -s` sahte/bozuk
# symlink üretir (içeriğe erişilemez) — bu yüzden Windows'ta PowerShell ile gerçek
# dizin junction'ı (admin gerektirmez) kurulur. POSIX'te (Linux CI / macOS) normal
# symlink. Her hâlükârda makine-okur 'latest.path' işaretçisi de yazılır.
update_latest() {
  local root=$1 dir=$2 link="${root}/latest" base
  base="$(basename "$dir")"
  rm -rf "$link" 2>/dev/null || true
  if command -v powershell.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
    local wlink wdir
    wlink="$(cygpath -w "$link")"; wdir="$(cygpath -w "$dir")"
    MSYS2_ARG_CONV_EXCL='*' powershell.exe -NoProfile -Command \
      "if (Test-Path -LiteralPath '$wlink') { Remove-Item -LiteralPath '$wlink' -Recurse -Force }; New-Item -ItemType Junction -Path '$wlink' -Target '$wdir' | Out-Null" \
      >/dev/null 2>&1 || true
  else
    ln -sfn "$base" "$link" 2>/dev/null || true
  fi
  printf '%s\n' "$base" > "${root}/latest.path" 2>/dev/null || true
}

# ---- 'latest' kısayolunu sabitle (race + Windows junction güvenli) ---------
# resolve_run_dir <yol> -> verilen yol "<kök>/latest" ise latest.path'i okuyup
# gerçek koşu dizinini döndürür; böylece paralel bir üretim 'latest'i değiştirse
# bile (ya da Windows junction bozuksa) doğru dizine sabitlenir. Aksi halde yolu
# olduğu gibi döndürür.
resolve_run_dir() {
  local p=${1%/} root base
  if [ "$(basename "$p")" = "latest" ]; then
    root="$(dirname "$p")"
    if [ -f "$root/latest.path" ]; then
      base="$(tr -d '\r\n' < "$root/latest.path")"
      if [ -n "$base" ] && [ -d "$root/$base" ]; then printf '%s\n' "$root/$base"; return 0; fi
    fi
  fi
  printf '%s\n' "$p"
}

# ---- Manifest --------------------------------------------------------------
manifest_init() {
  local f=$1
  [ -f "$f" ] && return 0
  printf 'timestamp,project,unit,variant,model,aspect,resolution,seed,status,result_file,prompt_file,est_cost\n' > "$f"
}
manifest_append() {
  # manifest_append <dosya> <project> <unit> <variant> <model> <aspect> <res> <seed> <status> <result_file> <prompt_file> <est_cost>
  local f=$1; shift
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$@" >> "$f"
}

# ---- Maliyet / bütçe (pricing.json) ----------------------------------------
PRICING_FILE="${PRICING_FILE:-pricing.json}"
model_cost() {  # model_cost <model> -> birim maliyet (yoksa 0)
  local m=$1
  [ -f "$PRICING_FILE" ] || { printf '0'; return; }
  jq -r --arg m "$m" '.models[$m] // 0' "$PRICING_FILE"
}
currency() {
  [ -f "$PRICING_FILE" ] && jq -r '.currency // "USD"' "$PRICING_FILE" || printf 'USD'
}
# Kayan nokta toplama/karşılaştırma (bc olmadan, awk ile)
fadd() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.4f", a+b}'; }
fgt()  { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>b)}'; }    # a>b ise 0 (true)

# ---- Mutex / çelişki doğrulama ---------------------------------------------
# Üretilmiş POZITIF prompt'ta çelişen talimat var mı denetler.
# 0 = temiz, 1 = çelişki bulundu (sebepler stderr'e yazılır).
CAMERA_SIGNATURES=(
  "GAMEPLAY CAMERA"
  "CUTSCENE CAMERA"
  "HIGH ESTABLISHING CAMERA"
  "LOW INTIMATE CAMERA"
  "LOW SIDE ACTION CAMERA"
  "OVER-SHOULDER TOP-DOWN CAMERA"
  "SIDE TRACKING DOLLY CAMERA"
  "ULTRA-WIDE CUTSCENE PULL-BACK CAMERA"
  "CUTSCENE HERO CAMERA"
  "CUTSCENE PUSH-IN CAMERA"
  "CUTSCENE ORBIT CAMERA"
  "CUTSCENE LEAD TRACKING CAMERA"
)
# Bunlar SADECE negatif prompt'ta olmalı; pozitifte görünürse çelişki.
FORBIDDEN_IN_POSITIVE=(
  "selfie"
  "front-facing"
  "facing the camera"
  "looking at the camera"
  "front portrait"
)
# Karşıt yön ipuçları: ikisi de aynı prompt'ta geçerse kamera-modu ile framing/env
# çelişiyordur (örn. eski CAM 'directly behind' + CAMX 'to the side' hatası).
# Muhafazakar tutuldu — mevcut 12 sahnenin hiçbirinde ikisi birlikte geçmez.
OPPOSING_PAIRS=(
  "directly behind|to the side"
  "directly behind|in front of"
)
# Saf-bash string yardımcıları (grep'siz — msys2/Windows'ta `grep -i` here-string
# ile SIGABRT atıp sessizce "no-match" döndüğü için kapı çökmesin diye).
_count_substr() {  # _count_substr <metin> <parça> -> tam-eşleşme sayısı (büyük/küçük duyarlı)
  local rest=$1 needle=$2 c=0
  [ -n "$needle" ] || { printf 0; return; }
  while [ "${rest#*"$needle"}" != "$rest" ]; do c=$((c+1)); rest=${rest#*"$needle"}; done
  printf '%s' "$c"
}
_contains_ci() {  # _contains_ci <metin> <parça> -> 0 (true) eğer içeriyorsa (duyarsız)
  local hay=${1,,} needle=${2,,}
  [ -n "$needle" ] || return 1
  [ "${hay#*"$needle"}" != "$hay" ]
}
mutex_check() {
  local prompt=$1 conflicts=0 sig n hit
  # 1) Tam olarak BİR kamera modu imzası olmalı.
  local cam_hits=0
  for sig in "${CAMERA_SIGNATURES[@]}"; do
    n=$(_count_substr "$prompt" "$sig")
    cam_hits=$((cam_hits + n))
  done
  if [ "$cam_hits" -gt 1 ]; then
    warn "Çelişki: $cam_hits adet kamera-modu imzası var (tam 1 bekleniyor) — çakışan kamera talimatları."
    conflicts=$((conflicts + 1))
  elif [ "$cam_hits" -eq 0 ]; then
    warn "Çelişki: hiç kamera-modu imzası yok — kamera bloğu enjekte edilmemiş."
    conflicts=$((conflicts + 1))
  fi
  # 2) Negatife ait terimler pozitifte olmamalı.
  for hit in "${FORBIDDEN_IN_POSITIVE[@]}"; do
    if _contains_ci "$prompt" "$hit"; then
      warn "Çelişki: pozitif prompt'ta negatife ait terim var: '$hit'"
      conflicts=$((conflicts + 1))
    fi
  done
  # 3) Karşıt yön ipuçları aynı anda olmamalı (kamera modu ↔ framing/env çelişkisi).
  local pair a b
  for pair in "${OPPOSING_PAIRS[@]}"; do
    a="${pair%%|*}"; b="${pair##*|}"
    if _contains_ci "$prompt" "$a" && _contains_ci "$prompt" "$b"; then
      warn "Çelişki: karşıt yön ipuçları birlikte: '$a' + '$b' (kamera modu ile framing/ortam uyumsuz)"
      conflicts=$((conflicts + 1))
    fi
  done
  [ "$conflicts" -eq 0 ]
}

# ---- URL çıkarma (sonuç dosyasından) ---------------------------------------
extract_url() { grep -oE 'https?://[^[:space:]"]+' "$1" 2>/dev/null | head -n1; }

# ---- Sonuç arşivleme (süreli URL -> kalıcı dosya) --------------------------
# archive_result <url> <dest_no_ext>  -> indirilen dosya yolunu stdout'a yazar.
# curl yoksa veya indirme başarısızsa rc!=0 ve boş çıktı (çağıran uyarır).
archive_result() {
  local url=$1 dest=$2 ext out
  command -v curl >/dev/null 2>&1 || return 1
  # uzantıyı URL'den çıkar (sorgu parametrelerini at)
  ext="$(printf '%s' "$url" | sed -E 's/[?#].*$//; s/.*\.//')"
  case "$ext" in
    png|jpg|jpeg|webp|gif|mp4|mov|webm|m4v) : ;;
    *) ext="bin" ;;
  esac
  out="${dest}.${ext}"
  if with_retry 3 curl -fsSL "$url" -o "${out}.part"; then
    mv -f "${out}.part" "$out"; printf '%s' "$out"; return 0
  fi
  rm -f "${out}.part" 2>/dev/null || true
  return 1
}

# ---- Son kare çıkarma (last-frame chaining) --------------------------------
# chain_lastframe <klip_url> <çıktı_jpg>  — klibi indirir, SON karesini görsele yazar.
# ffmpeg + curl yoksa 1 döner (zincir kırılır, çağıran kendi still'ine düşer).
# Son kare KAYNAK en-boy oranını korur (9:16 dikeyde kompozisyon kaymasın); kaydedilen
# JPEG boyutu kaynaktan farklıysa (ffprobe varsa) uyarır.
chain_lastframe() {
  local url=$1 out=$2 tmp
  command -v curl   >/dev/null 2>&1 || return 1
  command -v ffmpeg >/dev/null 2>&1 || return 1
  tmp="$(mktemp --suffix=.mp4)" || return 1
  if ! with_retry 3 curl -fsSL "$url" -o "$tmp"; then rm -f "$tmp"; return 1; fi
  # -sseof -0.1: sondan ~0.1s; -vf scale=iw:ih:...disable -> kaynak en-boy oranını birebir koru
  if ! ffmpeg -y -sseof -0.1 -i "$tmp" -frames:v 1 -q:v 2 \
       -vf "scale=iw:ih:force_original_aspect_ratio=disable" "$out" >/dev/null 2>&1; then
    rm -f "$tmp"; return 1
  fi
  # Boyut doğrulama: çıkan JPEG kaynak videoyla aynı en-boy oranında mı?
  if command -v ffprobe >/dev/null 2>&1 && [ -f "$out" ]; then
    local sd od
    sd="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$tmp" 2>/dev/null)"
    od="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$out" 2>/dev/null)"
    if [ -n "$sd" ] && [ -n "$od" ] && [ "$sd" != "$od" ]; then
      warn "chain: son kare boyutu kaynaktan farklı ($sd -> $od) — kompozisyon/aspect kaymış olabilir"
    fi
  fi
  rm -f "$tmp"
  [ -f "$out" ]
}
