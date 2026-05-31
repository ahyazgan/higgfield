#!/usr/bin/env python3
"""qc_core.py — bağımlılıksız (saf stdlib) görsel doğrulayıcı.

Bir görsel dosyasının formatını ve boyutlarını başlıktan okur; bozuk/boş/yanlış
en-boy oranlı üretimleri yakalar. ML gerektirmez.

Kullanım:
  qc_core.py <image> [beklenen_aspect örn 16:9]
Çıktı: tek satır JSON  {ok, format, width, height, bytes, aspect_ok, note}
"""
import json
import os
import struct
import sys


def png_size(f):
    f.seek(0)
    sig = f.read(8)
    if sig != b"\x89PNG\r\n\x1a\n":
        return None
    # İlk chunk IHDR olmalı
    f.read(4)  # length
    if f.read(4) != b"IHDR":
        return None
    w, h = struct.unpack(">II", f.read(8))
    return w, h


def jpeg_size(f):
    f.seek(0)
    if f.read(2) != b"\xff\xd8":
        return None
    while True:
        b = f.read(1)
        if not b:
            return None
        if b != b"\xff":
            continue
        # marker baytlarını atla (ardışık 0xFF olabilir)
        marker = f.read(1)
        while marker == b"\xff":
            marker = f.read(1)
        if not marker:
            return None
        m = marker[0]
        # SOF0..SOF15 (C4/C8/CC hariç) -> boyut burada
        if 0xC0 <= m <= 0xCF and m not in (0xC4, 0xC8, 0xCC):
            f.read(3)  # length(2) + precision(1)
            h, w = struct.unpack(">HH", f.read(4))
            return w, h
        # diğer segmentleri uzunluğa göre atla
        seg = f.read(2)
        if len(seg) < 2:
            return None
        (length,) = struct.unpack(">H", seg)
        f.seek(length - 2, os.SEEK_CUR)


def gif_size(f):
    f.seek(0)
    if f.read(6) not in (b"GIF87a", b"GIF89a"):
        return None
    w, h = struct.unpack("<HH", f.read(4))
    return w, h


def detect(path):
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        for name, fn in (("png", png_size), ("jpeg", jpeg_size), ("gif", gif_size)):
            try:
                f.seek(0)
                wh = fn(f)
            except Exception:
                wh = None
            if wh:
                return name, wh[0], wh[1], size
    return None, 0, 0, size


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "note": "kullanım: qc_core.py <image> [aspect]"}))
        return 2
    path = sys.argv[1]
    expected = sys.argv[2] if len(sys.argv) > 2 else None

    if not os.path.exists(path):
        print(json.dumps({"ok": False, "note": "dosya yok"}))
        return 1

    fmt, w, h, size = detect(path)
    res = {"ok": True, "format": fmt, "width": w, "height": h, "bytes": size,
           "aspect_ok": None, "note": ""}

    if size < 1024:
        res["ok"] = False
        res["note"] = "dosya çok küçük (<1KB) — hata sayfası/boş üretim olabilir"
    elif fmt is None or w == 0 or h == 0:
        res["ok"] = False
        res["note"] = "görsel başlığı çözümlenemedi — bozuk/desteklenmeyen format"
    elif expected and ":" in expected:
        try:
            aw, ah = (float(x) for x in expected.split(":"))
            want = aw / ah
            got = w / h
            res["aspect_ok"] = abs(got - want) / want <= 0.03  # %3 tolerans
            if not res["aspect_ok"]:
                res["ok"] = False
                res["note"] = f"en-boy oranı uyuşmuyor: beklenen {expected} (~{want:.3f}), gelen {w}x{h} (~{got:.3f})"
        except Exception:
            res["note"] = "aspect karşılaştırılamadı"

    print(json.dumps(res, ensure_ascii=False))
    return 0 if res["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
