#!/usr/bin/env python3
"""qc_vision.py — opsiyonel derin-QC (opencv gerektirir).

qc.sh için QC_VISION_CMD referans uygulaması. cv2 kuruluysa:
  - face_forward: kareye dönük (frontal) bir yüz tespit edilirse true
    (GTA "hep arkadan" kuralının ihlali — karakter kameraya bakmamalı).
  - location_score: master görselle algısal benzerlik (aHash), 0..1.

Kurulum (deps geldiğinde):  pip install opencv-python numpy
cv2 yoksa: her iki alan da null döner ve qc.sh bu kontrolleri atlar.

Kullanım: qc_vision.py <image> [master]
Çıktı: tek satır JSON {"face_forward": bool|null, "location_score": float|null, "note": str}
"""
import json
import sys


def ahash(img, cv2, np, size=16):
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    g = cv2.resize(g, (size, size), interpolation=cv2.INTER_AREA)
    return (g > g.mean()).flatten()


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"face_forward": None, "location_score": None, "note": "kullanım: qc_vision.py <image> [master]"}))
        return 2
    image = sys.argv[1]
    master = sys.argv[2] if len(sys.argv) > 2 else ""

    try:
        import cv2  # type: ignore
        import numpy as np  # type: ignore
    except Exception:
        print(json.dumps({"face_forward": None, "location_score": None, "note": "cv2 yok — derin-QC atlandı"}))
        return 0

    img = cv2.imread(image)
    if img is None:
        print(json.dumps({"face_forward": None, "location_score": None, "note": "görsel okunamadı"}))
        return 0

    # 1) Frontal yüz tespiti (cv2 ile gelen hazır cascade — ek model indirmeye gerek yok)
    face_forward = False
    try:
        cascade = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        faces = cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=6, minSize=(60, 60))
        face_forward = len(faces) > 0
    except Exception:
        face_forward = None

    # 2) Mekan benzerliği (master verildiyse)
    location_score = None
    if master:
        m = cv2.imread(master)
        if m is not None:
            try:
                a = ahash(img, cv2, np)
                b = ahash(m, cv2, np)
                location_score = round(float((a == b).mean()), 4)
            except Exception:
                location_score = None

    print(json.dumps({"face_forward": face_forward, "location_score": location_score, "note": ""}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
