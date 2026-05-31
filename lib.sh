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
  mkdir -p "$dir"
  ln -sfn "$(basename "$dir")" "${root}/latest"
  printf '%s\n' "$dir"
}

# ---- Manifest --------------------------------------------------------------
manifest_init() {
  local f=$1
  [ -f "$f" ] && return 0
  printf 'timestamp,project,unit,variant,model,aspect,resolution,seed,status,result_file,prompt_file\n' > "$f"
}
manifest_append() {
  # manifest_append <dosya> <project> <unit> <variant> <model> <aspect> <res> <seed> <status> <result_file> <prompt_file>
  local f=$1; shift
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$@" >> "$f"
}

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
)
# Bunlar SADECE negatif prompt'ta olmalı; pozitifte görünürse çelişki.
FORBIDDEN_IN_POSITIVE=(
  "selfie"
  "front-facing"
  "facing the camera"
  "looking at the camera"
  "front portrait"
)
mutex_check() {
  local prompt=$1 conflicts=0 sig n hit
  # 1) Tam olarak BİR kamera modu imzası olmalı.
  local cam_hits=0
  for sig in "${CAMERA_SIGNATURES[@]}"; do
    n=$(grep -o -F "$sig" <<<"$prompt" | wc -l)
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
    if grep -qi -F "$hit" <<<"$prompt"; then
      warn "Çelişki: pozitif prompt'ta negatife ait terim var: '$hit'"
      conflicts=$((conflicts + 1))
    fi
  done
  [ "$conflicts" -eq 0 ]
}

# ---- URL çıkarma (sonuç dosyasından) ---------------------------------------
extract_url() { grep -oE 'https?://[^[:space:]"]+' "$1" 2>/dev/null | head -n1; }

# ---- Son kare çıkarma (last-frame chaining) --------------------------------
# chain_lastframe <klip_url> <çıktı_jpg>  — klibi indirir, SON karesini görsele yazar.
# ffmpeg + curl yoksa 1 döner (zincir kırılır, çağıran kendi still'ine düşer).
chain_lastframe() {
  local url=$1 out=$2 tmp
  command -v curl   >/dev/null 2>&1 || return 1
  command -v ffmpeg >/dev/null 2>&1 || return 1
  tmp="$(mktemp --suffix=.mp4)" || return 1
  if ! with_retry 3 curl -fsSL "$url" -o "$tmp"; then rm -f "$tmp"; return 1; fi
  # -sseof -0.1: sondan ~0.1s, son kareyi yakala
  ffmpeg -y -sseof -0.1 -i "$tmp" -frames:v 1 -q:v 2 "$out" >/dev/null 2>&1 || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
  [ -f "$out" ]
}
