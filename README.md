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
presets/cameras.json     # kamera MODLARI (mutex) + i2v motion + reveal_modes
presets/video_models.json # video modeli ADAPTÖRLERİ (seedance/kling/veo flag haritası)
pricing.json             # model başına maliyet (bütçe/rapor için)
dashboard_assets.json    # Soccer Manager asset tanımları
lib.sh                   # ortak: retry, atomik yazma, manifest, mutex, maliyet, run-izolasyonu
generate.sh              # NORTH sahne üreticisi (still kareler) — --check/--dry-run/--variants/--budget
to_video.sh              # image-to-video: kareleri kliplere çevirir (--chain)
assemble.sh              # klipleri tek mp4'e birleştirir (ffmpeg)
pick.sh                  # varyant seçimi (selection.json)
qc.sh + qc_core.py       # görsel kalite kapısı (geçerlilik/aspect) + opsiyonel
qc_vision.py             #   derin-QC (cv2: yüz-yönü + mekan benzerliği)
costs.sh                 # koşulardan tahmini maliyet raporu
stats.sh                 # üretim sağlık/başarısızlık trendi (tüm koşular + QC)
requirements.txt         # opsiyonel derin-QC (cv2+numpy) bağımlılıkları
contact_sheet.sh         # koşu dizininden HTML galeri (QC rozeti + manuel inceleme)
serve.py                 # yerel web paneli (bağımlılıksız, http://127.0.0.1:8000)
generate_dashboard.sh    # dashboard asset üreticisi
.claude/hooks/           # web SessionStart hook (jq + config doğrulama)
.github/workflows/       # CI: JSON/syntax/mutex/dry-run doğrulama
refs/                    # JAY_FACE.jpg + NORTH_MASTER.jpg + INTERIOR_MASTER.jpg
                         #   (+ KITCHEN_MASTER.jpg — M02 mutfak sahneleri için, sen ekle)
```

## İki aşamalı boru hattı: still → video
Sistem önce **sabit kare** üretir, sonra istersen o kareleri **image-to-video**
ile klibe çevirir (Seedance/Kling/Veo). Karakter+mekan zaten karede kilitli
olduğu için video tutarlılığı yüksek olur.

**Last-frame chaining (`--chain`):** ilk sahne kendi still'inden başlar; sonraki
her sahne **bir önceki klibin son karesinden** başlar — böylece sahneler arası
sıçrama azalır, akıcı tek-çekim hissi oluşur. (ffmpeg + curl gerektirir; yoksa
zincir o sahnede kırılıp kendi still'ine düşer ve seni uyarır.)

```
                 ./generate.sh 01        ./to_video.sh out/latest      ./assemble.sh out_video/latest
  missions.json ───────────────►  6 still ──────────────────────►  6 klip ───────────────────────►  final.mp4
  + presets/        (kareler)        (start-image)     (Seedance i2v)        (ffmpeg + müzik)
```

## Kurulum
```bash
npm install -g @higgsfield/cli@latest      # veya resmi install scripti
higgsfield auth login
# Bu sistem ayrıca `jq` gerektirir (config okuma).
```

## Kullanım
```bash
./generate.sh --check                 # ÜRETMEDEN doğrula: config + ref + çelişki + CLI flag uyumu
./generate.sh --check --all           # TÜM mission'ları doğrula
./generate.sh --dry-run 01 1          # prompt'u kur ve göster, kredi harcama
./generate.sh 01                      # Mission 01, tüm sahneler
./generate.sh 02 3                    # Mission 02, sahne 3
./generate.sh --all                   # TÜM mission'lar tek koşuda + tek birleşik manifest
./generate.sh --jobs 6 01             # 6 sahneyi PARALEL üret (~3-5x hızlı; --budget ile kullanılamaz)
./generate.sh --variants 4 01 2       # sahne 2 için 4 varyant (seed kayar)
./contact_sheet.sh out/latest         # son koşunun HTML galerisi (QC rozetli)

./to_video.sh --dry-run out/latest    # motion prompt'ları göster (üretmeden)
./to_video.sh out/latest              # her kareyi klibe çevir (Seedance i2v)
./to_video.sh --scene 3 out/latest    # sadece sahne 3'ün klibi
./to_video.sh --chain out/latest      # last-frame chaining (akıcı tek-çekim)
./assemble.sh out_video/latest        # klipleri tek mp4'e birleştir
./assemble.sh out_video/latest --music track.mp3   # müzikli

./generate_dashboard.sh --list        # dashboard asset listesi
./generate_dashboard.sh --dry-run     # tüm dashboard prompt'ları (üretmeden)
./generate_dashboard.sh 5             # sadece asset 5
```

### Kalite, seçim, maliyet, panel
```bash
./generate.sh --variants 4 01 2       # sahne 2 için 4 aday
./pick.sh out/latest 2 3              # sahne 2 -> varyant 3 seç (to_video sadece onu işler)
./pick.sh out/latest --show          # seçimleri göster

./qc.sh out/latest                   # görsel kalite kapısı (geçerlilik + aspect)
QC_VISION_CMD=./qc_vision.py ./qc.sh out/latest   # + derin-QC (cv2 gerekir)

./generate.sh --budget 5 01          # 5 birim maliyeti aşmadan dur
./costs.sh                           # tüm koşuların tahmini maliyeti
./stats.sh                           # üretim sağlık/başarısızlık trendi (tüm koşular + QC oranı)

python3 serve.py                     # yerel web paneli (canlı çıktı + token) -> http://127.0.0.1:8000
```

> Maliyet/bütçe için önce `pricing.json`'a gerçek model fiyatlarını gir
> (varsayılan 0 — rapor sıfır çıkar).

Ortam değişkeniyle override: `MODEL`, `ASPECT`, `RESOLUTION`, `SEED`, `MAX_RETRY`,
`JOBS` (paralel iş sayısı), `VIDEO_MODEL` (vars. `seedance_2_0`). Video modeli
flag'leri `presets/video_models.json` **adaptöründen** kurulur — model değiştirmek
(kling2_6, veo3_1, …) için sadece `VIDEO_MODEL`'i değiştir; her model yalnızca kendi
desteklediği flag'leri alır (örn. seedance `--resolution` alır, kling almaz).

> **Otomatik arşivleme:** Üretilen görsel/video, sonuç URL'sinden hemen diske
> indirilir (`out/<koşu>/<base>.png|mp4`). Higgsfield URL'leri süreli olduğu için
> bu, ürettiğinin link ölünce kaybolmasını önler. Contact-sheet de varsa yerel
> arşivi kullanır. Kapatmak için `--no-archive` veya `NO_ARCHIVE=1`.
Örn. ucuz taslak: `RESOLUTION=1k ./generate.sh 01`.

## Yeni içerik eklemek (kod yazmadan)
- **Yeni sahne / Mission:** `missions.json`'a ekle. `camera` alanı
  `presets/cameras.json`'daki modlardan biri olmalı (yoksa `--check` reddeder).
- **Yeni karakter / lokasyon:** ilgili preset dosyasına bir kayıt ekle, sahnede
  `character` / `location` ile referansla.

## Tutarlılık yöntemi
İki referans görsel her sahnede sabit kalır:
1. **Lokasyon master** (`NORTH_MASTER.jpg` = dış cephe, `INTERIOR_MASTER.jpg` = salon,
   `KITCHEN_MASTER.jpg` = mutfak — M02 s1–4 için eklemen gerekir) → mekan/bina.
2. **Yüz referansı** (`JAY_FACE.jpg`) → karakter kimliği + saç deseni (arkadan bile).

Bina/iç mekanı kelimeyle değil **referans görselle** sabitlemek tutarlılığın
anahtarıdır; prompt yalnızca "match the reference exactly" der.

## Dürüst notlar
- **CLI flag uyumu artık otomatik kontrol ediliyor:** `./generate.sh --check`
  modelin gerçek parametrelerini (`higgsfield model get <model>`) okuyup
  `run_cli`'ın göndereceği flag'lerle karşılaştırır; bir flag kaybolduysa
  **kredi harcamadan önce** uyarır. (nano_banana_2 `--negative-prompt`/`--seed`
  KABUL ETMEZ — bu yüzden gönderilmiyor.) Video tarafında flag'ler
  `presets/video_models.json` adaptöründen gelir; yeni model eklemek kod değil
  config işidir. Hiçbir video modeli `fps`/`negative` almaz.
- **Video modeli kurulumu:** `to_video.sh` still karelerin sonuç URL'sini
  başlangıç görseli yapar; önce `./generate.sh` ile kareleri üretmen gerekir.
- `--check` ve `--dry-run` higgsfield kurulu olmadan da çalışır (config + prompt
  testi için).
