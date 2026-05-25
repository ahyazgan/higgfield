#!/usr/bin/env bash
# NORTH Mission 01 - Higgsfield CLI uretim scripti (soul_cinematic + Yazgan Soul ID)
# Kullanim: ./generate.sh [scene_id]   (bos birakirsan hepsini uretir)
#
# ON KOSULLAR:
#   1. higgsfield CLI kurulu ve giris yapilmis (higgsfield auth login).
#   2. refs/NORTH_MASTER.png  ve  refs/INTERIOR_MASTER.png  mevcut.
#
# Model: soul_cinematic (image)
#   params: prompt(req), aspect_ratio, quality(1.5k|2k),
#           custom_reference_id (Soul UUID, bare string), medias (--image ile)
#
# Soul: Yazgan (Jay rolunde)  id: efcf33c2-6e4f-4ee3-ad17-89795cdfe894
#
# Maliyet ipucu:
#   higgsfield generate cost soul_cinematic --prompt "..." \
#     --custom_reference_id <SOUL> --image <REF> --aspect_ratio 16:9 --quality 2k

set -euo pipefail
cd "$(dirname "$0")"

# ---- AYARLAR ---------------------------------------------------------------
MODEL="text2image_soul_v2"
ASPECT="16:9"
QUALITY="2k"                                                # 1.5k veya 2k
SOUL_ID="efcf33c2-6e4f-4ee3-ad17-89795cdfe894"              # Yazgan
MASTER_EXT="./refs/NORTH_MASTER.jpg"
MASTER_INT="./refs/INTERIOR_MASTER.jpg"
OUTDIR="./out"
# ----------------------------------------------------------------------------

mkdir -p "$OUTDIR"

# Sabit bloklar
CHAR="young Mediterranean man, 22-24 years old, short black hair clean fade haircut, thick black eyebrows, light 3-day stubble with small mustache, olive-tan skin, lean build, wearing fitted white cotton t-shirt, black canvas chef apron tied at waist (straps crossing on back), dark navy slim-fit jeans, black low-top sneakers, silver watch on left wrist"
CAM="GTA V THIRD PERSON GAMEPLAY CAMERA, camera positioned directly behind character, camera angled slightly downward following character, character seen from BEHIND back visible, wide angle lens showing environment ahead, video game third person perspective like GTA V gameplay, NOT selfie, NOT portrait, NOT front-facing, character's face NOT toward camera"
LOCK="same exact NORTH restaurant building as reference image, identical brick, identical door, identical sign, do not change the building"
STYLE="shot on iPhone 15 Pro Max, natural golden hour light, slight grain, candid documentary style, no filters, NOT cinematic grade, NOT studio, NOT illustration, NOT cartoon, NOT render, hyperrealistic, real phone snapshot, authentic moment"

build_prompt() {
  local id=$1
  case $id in
    1) ACTION="character walking forward down the street, relaxed confident stride, arms natural at sides"
       CAMX="camera floating 3 meters behind at 1.7m height, character in lower-center of frame"
       ENV="narrow Miami Little Havana street, old red brick and pastel buildings on both sides, cobblestone sidewalk, NORTH restaurant visible ahead in distance, vintage 1960s American cars parked along curb, palm trees, overhead cables, golden late afternoon sunlight"
       REF="$MASTER_EXT" ;;
    2) ACTION="character walking toward NORTH restaurant entrance, approaching the building"
       CAMX="camera floating 3 meters behind at 1.7m height, character in lower-left third of frame"
       ENV="NORTH restaurant red brick facade directly ahead, black wooden 6-panel door, NORTH sign above door in white serif letters, large glass window with warm light inside, two terracotta plant pots flanking door, cobblestone sidewalk, golden afternoon light"
       REF="$MASTER_EXT" ;;
    3) ACTION="character standing at NORTH door, right hand reaching out to push door open, door beginning to swing inward"
       CAMX="camera floating 2.5 meters behind at 1.7m height, character in center-left of frame"
       ENV="NORTH black wooden door directly ahead, brass handle, red brick facade around door, NORTH sign above, terracotta plant pots on sides, warm amber light spilling from opening door, cobblestone under feet, golden afternoon light"
       REF="$MASTER_EXT" ;;
    4) ACTION="character walking into the empty restaurant, stepping forward into the space"
       CAMX="camera floating 2.5 meters behind at 1.7m height, camera following character into the building, character in center of frame"
       ENV="abandoned empty restaurant interior, exposed weathered red brick walls, high ceiling with old wooden beams, overturned wooden tables and scattered chairs, dust particles floating in afternoon light, large window on right with golden light streaming in, empty bar counter at back"
       REF="$MASTER_INT" ;;
    5) ACTION="character standing still in center of empty restaurant, looking around the abandoned space, arms relaxed at sides"
       CAMX="camera floating 4 meters behind at 2m height, camera angled downward, ultra wide angle showing entire room, character in lower-center small in vast space"
       ENV="vast abandoned restaurant interior surrounding character, high ceiling with exposed dark wooden beams, weathered red brick walls all around, overturned tables and scattered chairs, dramatic golden light beams through right window, dust particles, old framed photographs on walls, empty bar counter at back, sense of scale and emptiness"
       REF="$MASTER_INT" ;;
    6) ACTION="character standing still in center of empty space, looking ahead at the room before him, slight head movement, contemplative still posture"
       CAMX="GTA V THIRD PERSON CUTSCENE CAMERA, camera behind character slightly to the right, floating 2 meters behind at 1.6m height, slowly drifting to three-quarter back view, back of head and slight side of jaw visible, NOT full face NOT front-facing NOT selfie"
       ENV="abandoned restaurant interior ahead and around, red brick walls, wooden beams, golden light beams through window, dust in air, empty space full of potential"
       REF="$MASTER_INT" ;;
    *) echo "Gecersiz sahne: $id" >&2; return 1 ;;
  esac

  # Sahne 6 cutscene kendi kamera blogunu kullanir
  if [ "$id" = "6" ]; then
    PROMPT="$LOCK, $CHAR, $CAMX, $ENV, $STYLE"
  else
    PROMPT="$LOCK, $CHAR, $CAM, $CAMX, $ENV, $STYLE"
  fi
}

generate_scene() {
  local id=$1
  build_prompt "$id"

  if [ ! -f "$REF" ]; then
    echo "HATA: Referans gorseli yok: $REF" >&2
    echo "       refs/ klasorune NORTH_MASTER.png ve INTERIOR_MASTER.png koy." >&2
    return 1
  fi

  echo "==> Sahne $id uretiliyor (ref: $REF, soul: Yazgan)"
  higgsfield generate create "$MODEL" \
    --prompt "$PROMPT" \
    --custom_reference_id "$SOUL_ID" \
    --image "$REF" \
    --aspect_ratio "$ASPECT" \
    --quality "$QUALITY" \
    --wait
}

if [ $# -ge 1 ]; then
  generate_scene "$1"
else
  for s in 1 2 3 4 5 6; do
    generate_scene "$s"
  done
fi

echo "Bitti."
