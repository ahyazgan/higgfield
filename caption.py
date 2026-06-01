#!/usr/bin/env python3
"""caption.py — bir mission için Instagram Reels ve/veya TikTok caption + hashtag üretir.

missions.json'dan caption_template + hashtags + series okur, {part}/{total}/{series_name}
yer tutucularını doldurur ve platforma göre uzunluk/hashtag kurallarını uygular.

Kullanım:
  python3 caption.py --mission 01 --platform both --output out/latest/caption
    -> caption_reels.txt + caption_tiktok.txt
  python3 caption.py --mission 01 --platform reels --output caption.txt

Kurallar:
  Reels (Instagram): <=2200 char, hashtag SONDA, 3 large + 5 medium + 5 niche
  TikTok: caption <=150 char + hashtagler AYRI satırda, 2 large + 3 medium + 3 niche
"""
import argparse
import json
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
REELS_MAX = 2200
TIKTOK_CAP_MAX = 150


def load_mission(mid):
    with open(os.path.join(ROOT, "missions.json"), encoding="utf-8") as f:
        d = json.load(f)
    missions = d.get("missions", {})
    m = missions.get(mid) or missions.get(str(mid).zfill(2)) or missions.get(str(mid))
    if not m:
        raise SystemExit(f"Mission bulunamadı: {mid} (mevcut: {', '.join(missions)})")
    return m


def fill_template(tmpl, series):
    series = series or {}
    return (tmpl or "").replace("{part}", str(series.get("part", ""))) \
                       .replace("{total}", str(series.get("total", ""))) \
                       .replace("{series_name}", str(series.get("name", "")))


def tags(m, nl, nm, nn):
    h = m.get("hashtags", {}) or {}
    return (h.get("large", [])[:nl] + h.get("medium", [])[:nm] + h.get("niche", [])[:nn])


def build_reels(m):
    body = fill_template(m.get("caption_template", ""), m.get("series"))
    text = body + "\n\n" + " ".join(tags(m, 3, 5, 5))
    return text[:REELS_MAX]


def build_tiktok(m):
    body = " ".join(fill_template(m.get("caption_template", ""), m.get("series")).split())
    if len(body) > TIKTOK_CAP_MAX:
        body = body[:TIKTOK_CAP_MAX].rstrip()
    return body + "\n" + " ".join(tags(m, 2, 3, 3))


def write(path, text):
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text + "\n")
    print(f"yazildi: {path} ({len(text)} char)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mission", required=True)
    ap.add_argument("--platform", choices=["reels", "tiktok", "both"], default="both")
    ap.add_argument("--output", default="caption")
    a = ap.parse_args()

    m = load_mission(a.mission)
    base = a.output[:-4] if a.output.lower().endswith(".txt") else a.output

    if a.platform == "both":
        write(base + "_reels.txt", build_reels(m))
        write(base + "_tiktok.txt", build_tiktok(m))
    else:
        out = a.output if a.output.lower().endswith(".txt") else a.output + ".txt"
        write(out, build_reels(m) if a.platform == "reels" else build_tiktok(m))


if __name__ == "__main__":
    main()
