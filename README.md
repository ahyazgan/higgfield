# NORTH Mission 01 — Cursor + Claude Code + Higgsfield CLI Rehberi

Bu klasörde 3 dosya var:
- `SENARYO.md` — Okunaklı senaryo (kopyala-yapıştır için). Sabit bloklar + 6 sahne.
- `scenes.json` — Programatik veri (script bunu okur, sen de düzenleyebilirsin).
- `generate.sh` — Higgsfield CLI ile 6 sahneyi üreten script.

---

## 1) Higgsfield CLI kurulumu
```bash
npm install -g @higgsfield/cli@latest
# veya
curl -fsSL https://raw.githubusercontent.com/higgsfield-ai/cli/main/install.sh | sh

higgsfield auth login        # giriş yap
higgsfield model list        # mevcut modelleri gör (Nano Banana, Soul, Kling, Veo...)
```

## 2) Cursor + Claude Code ile çalışma
1. Bu klasörü Cursor'da aç.
2. Claude Code'a şu işleri yaptırabilirsin:
   - "scenes.json'daki Sahne 2'nin mekan açıklamasını şöyle değiştir..."
   - "generate.sh'a Soul ID flag'ini ekle"
   - "her sahne için ayrı .txt prompt dosyası üret"
3. CLI'ı Claude Code terminalinden çalıştır.

## 3) Referans görseller (kritik — bina tutarlılığı)
`refs/` klasörü oluştur ve iki master görseli koy:
- `refs/NORTH_MASTER.png` — seçtiğin TEK dış cephe binası
- `refs/INTERIOR_MASTER.png` — seçtiğin TEK iç mekan

> Önceki sorunun (her sahnede bina farklı) tek çözümü buydu: binayı kelimeyle
> değil, **referans görselle** sabitlemek. Script bunu `--start-image` ile yapıyor.

## 4) Çalıştırma
```bash
chmod +x generate.sh
./generate.sh        # 6 sahnenin hepsi
./generate.sh 2      # sadece Sahne 2
```

## 5) generate.sh içinde doldurman gerekenler
- `MODEL` — `higgsfield model list` çıktısından seç.
- `SOUL_ID` — Jay karakterinin Soul id'si (`higgsfield soul list` benzeri bir komutla).
- `MASTER_EXT` / `MASTER_INT` — referans görsel yolları.
- Flag adları sürüme göre değişebilir — `higgsfield generate create <model> --help`
  ile doğrula (özellikle start-image, soul, aspect ratio).

---

## ⚠️ Dürüst notlar
- **CLI flag'leri:** Yukarıdaki flag adları (`--start-image`, `--aspect_ratio`, `--wait`)
  CLI dokümanındaki örneklerden alındı ama sürümle değişebilir. İlk çalıştırmadan önce
  `--help` ile mutlaka kontrol et.
- **Soul karakter bağlama:** CLI'da Soul karakterini prompt'a bağlama yöntemi (ayrı flag
  mı, prompt içi mi) sürüme bağlı; `model list` ve `--help` sana net söyler.
- **MCP alternatifi:** Resmî MCP yok ama topluluk yapımı `geopopos/higgsfield_ai_mcp`
  var. Claude Desktop/Code'a MCP olarak bağlamak istersen onu kurabilirsin; mantık aynı
  (prompt + referans görsel). CLI çoğu iş için daha basit.
