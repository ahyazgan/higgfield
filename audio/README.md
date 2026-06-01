# audio/ — ses dosyaları

`assemble.sh --audio` / `--music-only` bu klasördeki sesleri videoya ekler.
Yollar `presets/audio.json`'dan okunur. Dosyalar repoya dahil DEĞİL (`.gitignore`),
büyük/telifli oldukları için — buraya kendin koyarsın.

## Nereye ne konur
```
audio/
  music.mp3            # arka plan müziği (background_music)
  sfx/
    whoosh.mp3         # sahne başı efekti (sfx.scene_start)
    impact.mp3         # sahne sonu efekti (sfx.scene_end)
```

## Ayarlar (presets/audio.json)
- `background_music` — müzik dosya yolu
- `music_volume` — 0..1 (varsayılan 0.7)
- `music_start_offset` — müziğe kaçıncı saniyeden başlanacağı
- `sfx_volume` — efekt sesi seviyesi
- `sfx.scene_start` / `sfx.scene_end` — efekt dosya yolları

## Davranış
- Müzik videodan **kısaysa** otomatik **loop** edilir (`-stream_loop -1`),
  **uzunsa** video uzunluğuna **trim** edilir (`-shortest`).
- Dosya yoksa `assemble.sh` **uyarır ama çökmez** — ses adımını sessizce atlar.
- `--music-only` sadece müzik ekler (sfx yok); `--audio` müzik + sfx ekler.

## Ücretsiz/telifsiz kaynak önerisi
YouTube Audio Library, Pixabay Music, Freesound (sfx) — Reels/TikTok için
telifsiz veya platform-içi ses kullanmak en güvenlisi.
