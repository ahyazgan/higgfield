# NORTH — Higgsfield CLI Üretim Sistemi

GTA üçüncü-şahıs tarzında tutarlı bir görsel sekansı (NORTH restoran hikayesi)
ve ayrı bir Soccer Manager dashboard asset seti üreten, **config-güdümlü** bir
bash sistemi.

## Tasarım ilkeleri
- **Tek doğru kaynak (single source of truth):** karakter/lokasyon/kamera ve
  sahneler veri dosyalarında yaşar; scriptler sadece okur ve birleştirir.
  İkinci bir nüsha olmadığı için kayma (drift) olmaz.
- **Çakışma yapısal olarak imkânsız:** her sahne **tek** bir kamera *modu*
  seçer (modlar birbirini dışlar), negatifler pozitiften ayrıdır ve üretimden
  önce bir **mutex kapısı** çelişkileri yakalar.
- **Her koşu izole:** çıktı `out/<zaman>_<etiket>/` altına yazılır, atomik
  kaydedilir, `manifest.csv`'ye loglanır — paralel koşular birbirini ezmez.

## Dosya yapısı
```
missions.json            # M01+M02 tüm sahneler (TEK kaynak)
presets/characters.json  # karakter (jay)
presets/locations.json   # lokasyon (north_ext / north_int)
presets/cameras.json     # kamera MODLARI (mutex)
dashboard_assets.json    # Soccer Manager asset tanımları
lib.sh                   # ortak: retry, atomik yazma, manifest, mutex, run-izolasyonu
generate.sh              # NORTH sahne üreticisi
generate_dashboard.sh    # dashboard asset üreticisi
contact_sheet.sh         # koşu dizininden HTML galeri
refs/                    # JAY_FACE.jpg + NORTH_MASTER.jpg + INTERIOR_MASTER.jpg
```

## Kurulum
```bash
npm install -g @higgsfield/cli@latest      # veya resmi install scripti
higgsfield auth login
# Bu sistem ayrıca `jq` gerektirir (config okuma).
```

## Kullanım
```bash
./generate.sh --check                 # ÜRETMEDEN doğrula: config + ref + çelişki kapısı
./generate.sh --dry-run 01 1          # prompt'u kur ve göster, kredi harcama
./generate.sh 01                      # Mission 01, tüm sahneler
./generate.sh 02 3                    # Mission 02, sahne 3
./generate.sh --variants 4 01 2       # sahne 2 için 4 varyant (seed kayar)
./contact_sheet.sh out/latest         # son koşunun HTML galerisi

./generate_dashboard.sh --list        # dashboard asset listesi
./generate_dashboard.sh --dry-run     # tüm dashboard prompt'ları (üretmeden)
./generate_dashboard.sh 5             # sadece asset 5
```

Ortam değişkeniyle override: `MODEL`, `ASPECT`, `RESOLUTION`, `SEED`, `MAX_RETRY`.
Örn. ucuz taslak: `RESOLUTION=1k ./generate.sh 01`.

## Yeni içerik eklemek (kod yazmadan)
- **Yeni sahne / Mission:** `missions.json`'a ekle. `camera` alanı
  `presets/cameras.json`'daki modlardan biri olmalı (yoksa `--check` reddeder).
- **Yeni karakter / lokasyon:** ilgili preset dosyasına bir kayıt ekle, sahnede
  `character` / `location` ile referansla.

## Tutarlılık yöntemi
İki referans görsel her sahnede sabit kalır:
1. **Lokasyon master** (`NORTH_MASTER.jpg` / `INTERIOR_MASTER.jpg`) → mekan/bina.
2. **Yüz referansı** (`JAY_FACE.jpg`) → karakter kimliği + saç deseni (arkadan bile).

Bina/iç mekanı kelimeyle değil **referans görselle** sabitlemek tutarlılığın
anahtarıdır; prompt yalnızca "match the reference exactly" der.

## Dürüst notlar
- **CLI flag'leri** sürümle değişebilir (`--negative-prompt`, `--resolution`,
  `--seed`, `--aspect_ratio`). İlk gerçek üretimden önce
  `higgsfield generate create <model> --help` ile doğrula; `generate.sh`'ın
  `run_cli` fonksiyonundaki flag adlarını gerekirse güncelle.
- `--check` ve `--dry-run` higgsfield kurulu olmadan da çalışır (config + prompt
  testi için).
