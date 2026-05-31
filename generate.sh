#!/usr/bin/env bash
# NORTH - Higgsfield CLI uretim scripti (nano_banana_2 + Jay face ref + lokasyon master)
# Kullanim:
#   ./generate.sh                  -> Mission 01, tum 6 sahne
#   ./generate.sh 3                -> Mission 01, sahne 3
#   ./generate.sh 02               -> Mission 02, tum 6 sahne
#   ./generate.sh 02 3             -> Mission 02, sahne 3
#
# ON KOSULLAR:
#   refs/JAY_FACE.jpg, refs/NORTH_MASTER.jpg, refs/INTERIOR_MASTER.jpg

set -euo pipefail
cd "$(dirname "$0")"

# ---- AYARLAR ---------------------------------------------------------------
MODEL="nano_banana_2"
ASPECT="16:9"
RESOLUTION="2k"
JAY_FACE="./refs/JAY_FACE.jpg"
MASTER_EXT="./refs/NORTH_MASTER.jpg"
MASTER_INT="./refs/INTERIOR_MASTER.jpg"
OUTDIR="./out"
# ----------------------------------------------------------------------------

mkdir -p "$OUTDIR"

CHAR="Mediterranean Turkish man, mid-twenties around 26 years old, dark brown almost black hair short faded on sides with textured volume on top slightly messy, thick dark eyebrows, full thick dark mustache (chevron style covering upper lip) with connected short chin beard goatee, clean cheeks no sideburn beard, light olive skin, medium solid build with broad shoulders not lean not heavy, oval face with strong jawline, dark brown eyes, wearing fitted white cotton crew-neck t-shirt, black canvas chef apron tied at waist (straps crossing on back), dark navy slim-fit jeans, black low-top sneakers, silver watch on left wrist"
CAM="GTA V THIRD PERSON GAMEPLAY CAMERA, camera positioned directly behind character, camera angled slightly downward following character, character seen from BEHIND back visible, wide angle lens showing environment ahead, video game third person perspective like GTA V gameplay, NOT selfie, NOT portrait, NOT front-facing, character's face NOT toward camera"
# Lite cam block: keeps GTA third-person feel but does NOT force "directly behind", so scene-specific CAMX (side/top-down/wide/etc) can dominate.
CAM_LITE="GTA V third person gameplay perspective, video game cinematic camera framing, character not facing camera, NOT a selfie, NOT a front portrait, character's face not toward camera, real-time game engine look"
LOCK_EXT="NORTH restaurant: weathered red brick facade, black wooden 6-panel door with brass handle, white serif NORTH sign mounted above door, large glass window with warm interior light, two terracotta plant pots flanking entrance, cobblestone sidewalk in front — same building appearance across every scene"
LOCK_INT="NORTH restaurant interior: weathered red brick walls, high ceiling with exposed dark wooden beams, original hardwood floor, large window on one side with golden light, vintage industrial pendant lights, sense of restored heritage space — same interior appearance across every scene"
STYLE="shot on iPhone 15 Pro Max, natural light, slight grain, candid documentary style, no filters, NOT cinematic grade, NOT studio, NOT illustration, NOT cartoon, NOT render, hyperrealistic, real phone snapshot, authentic moment"

ANCHOR="The first reference image is the EXACT location for this scene — match the building, walls, door, signage, brickwork, windows, lighting, layout and every visible detail to that image. Do not invent or alter the location. The second reference image is the character's face and hair — preserve identity exactly. CRITICAL HAIR DETAIL even when seen from behind: dark brown almost black hair, short tight skin fade on sides and back of head with sharp clean fade line above the ears, textured volume only on top with slight messy styling, no long hair, no buzz cut on top, no curls — the back of the head must show the fade pattern clearly. Body build: medium solid frame with broad shoulders, NOT skinny, NOT lean."

build_prompt_01() {
  local id=$1
  case $id in
    1) ACTION="character walking forward down the street, relaxed confident stride, arms natural at sides"
       CAMX="camera floating 3 meters behind at 1.7m height, character in lower-center of frame"
       ENV="narrow Miami Little Havana street, old red brick and pastel buildings on both sides, cobblestone sidewalk, NORTH restaurant visible ahead in distance, vintage 1960s American cars parked along curb, palm trees, overhead cables, golden late afternoon sunlight"
       LOCK="$LOCK_EXT"; REF="$MASTER_EXT" ;;
    2) ACTION="character walking toward NORTH restaurant entrance, approaching the building"
       CAMX="camera floating 3 meters behind at 1.7m height, character in lower-left third of frame"
       ENV="NORTH restaurant red brick facade directly ahead, black wooden 6-panel door, NORTH sign above door in white serif letters, large glass window with warm light inside, two terracotta plant pots flanking door, cobblestone sidewalk, golden afternoon light"
       LOCK="$LOCK_EXT"; REF="$MASTER_EXT" ;;
    3) ACTION="character standing at NORTH door, right hand reaching out to push door open, door beginning to swing inward"
       CAMX="camera floating 2.5 meters behind at 1.7m height, character in center-left of frame"
       ENV="NORTH black wooden door directly ahead, brass handle, red brick facade around door, NORTH sign above, terracotta plant pots on sides, warm amber light spilling from opening door, cobblestone under feet, golden afternoon light"
       LOCK="$LOCK_EXT"; REF="$MASTER_EXT" ;;
    4) ACTION="character walking into the empty restaurant, stepping forward into the space"
       CAMX="camera floating 2.5 meters behind at 1.7m height, camera following character into the building, character in center of frame"
       ENV="abandoned empty restaurant interior, exposed weathered red brick walls, high ceiling with old wooden beams, overturned wooden tables and scattered chairs, dust particles floating in afternoon light, large window on right with golden light streaming in, empty bar counter at back"
       LOCK="$LOCK_INT"; REF="$MASTER_INT" ;;
    5) ACTION="character standing still in center of empty restaurant, looking around the abandoned space, arms relaxed at sides"
       CAMX="camera floating 4 meters behind at 2m height, camera angled downward, ultra wide angle showing entire room, character in lower-center small in vast space"
       ENV="vast abandoned restaurant interior surrounding character, high ceiling with exposed dark wooden beams, weathered red brick walls all around, overturned tables and scattered chairs, dramatic golden light beams through right window, dust particles, old framed photographs on walls, empty bar counter at back, sense of scale and emptiness"
       LOCK="$LOCK_INT"; REF="$MASTER_INT" ;;
    6) ACTION="character standing still in center of empty space, looking ahead at the room before him, slight head movement, contemplative still posture"
       CAMX="GTA V THIRD PERSON CUTSCENE CAMERA, camera behind character slightly to the right, floating 2 meters behind at 1.6m height, slowly drifting to three-quarter back view, back of head and slight side of jaw visible, NOT full face NOT front-facing NOT selfie"
       ENV="abandoned restaurant interior ahead and around, red brick walls, wooden beams, golden light beams through window, dust in air, empty space full of potential"
       LOCK="$LOCK_INT"; REF="$MASTER_INT" ;;
    *) echo "M01 gecersiz sahne: $id" >&2; return 1 ;;
  esac
}

build_prompt_02() {
  local id=$1
  case $id in
    1) ACTION="character pushing through double swing kitchen doors from dining room into the kitchen, both arms raised pushing the doors outward, stepping forward into the kitchen, dynamic stride"
       CAMX="GTA V third person HIGH ESTABLISHING CAMERA, camera elevated at 3 meters height looking down at 30 degree angle, character framed in lower portion of wide frame, deep perspective revealing the whole kitchen ahead, doors swinging open in foreground"
       ENV="restaurant kitchen entrance from dining side, double wooden swing doors with round porthole windows in foreground opening into a bright stainless-steel commercial kitchen seen from above, polished steel countertops stretching back, long row of hanging copper pots and pans, gas range and grill far back, ceramic checkerboard floor tiles, early morning sunlight from high side windows casting long shadows, dust in light beams, sense of quiet morning before service"
       LOCK="$LOCK_INT"; REF="$MASTER_INT" ;;
    2) ACTION="character standing at stainless steel prep counter facing away, both arms bent sharply backward, hands behind his back tying the chef apron strap into a tight knot at the small of his back, apron straps crossing visibly on his back muscles"
       CAMX="GTA V third person LOW INTIMATE CAMERA, camera positioned very close 1.2 meters behind at waist height 1.0m, slight dutch tilt 5 degrees, tight cropped frame focused on the upper back and hands tying the knot, narrow depth of field, almost handheld feel"
       ENV="extreme closeup of commercial kitchen prep zone, focus on the rough black canvas apron straps and the knot being tied at the small of the back, white cotton t-shirt fabric and silver watch visible, blurred background of stainless steel counter and hanging copper pots, warm side window light raking across the back, intimate quiet moment"
       LOCK="$LOCK_INT"; REF="$MASTER_INT" ;;
    3) ACTION="character crouched in front of large industrial gas grill, right hand on the gas valve knob, head turned slightly toward the grill, blue and orange flames just igniting and licking up under the cast iron grates, his face lit by the fire glow"
       CAMX="GTA V third person LOW SIDE ACTION CAMERA, camera at ground level 0.6m height positioned to the LEFT SIDE of the character at 1.5 meters distance, side profile angle three-quarter back, character silhouetted against the bright grill flames, slight dutch tilt, cinematic action-cam framing like a heist mission ignition shot"
       ENV="kitchen grill station seen from low side angle, massive stainless industrial gas grill dominating the frame, blue and orange ignition flames bursting along the burner row, smoke just starting, suspended exhaust hood overhead, dark exposed brick wall behind the grill, rack of copper saucepans on the side wall, dim warm tungsten kitchen light contrasting with the bright flame"
       LOCK="$LOCK_INT"; REF="$MASTER_INT" ;;
    4) ACTION="character standing at the wooden prep board, chef knife gripped in right hand in mid downstroke, slicing through a red bell pepper, left hand curled fingers holding the pepper in place, focused downward gaze, motion blur on the knife edge"
       CAMX="GTA V third person TIGHT OVER-SHOULDER TOP-DOWN CAMERA, camera positioned just above and behind the right shoulder at 1.9m height angled steeply downward 50 degrees to look at the cutting board, knife and hands fill the lower foreground, character's head visible at top of frame from behind"
       ENV="prep station seen from top-down over-shoulder, large worn wooden cutting board centered, vivid fresh ingredients laid out — red and yellow bell peppers half-sliced, whole tomatoes, white onion, garlic cloves, sprigs of parsley and thyme, the sharp German chef knife mid-cut, stainless counter edge visible at top, neat mise en place feeling"
       LOCK="$LOCK_INT"; REF="$MASTER_INT" ;;
    5) ACTION="character walking slowly through the restored empty dining room down the center aisle between tables, mid stride, left hand brushing the back of a wooden chair as he passes, head turned slightly inspecting place settings"
       CAMX="GTA V third person SIDE TRACKING DOLLY CAMERA, camera positioned 2.5 meters to the side of the character moving parallel to his walk, character in profile mid-frame walking left to right, long row of tables and chairs receding behind him into deep perspective, lateral tracking motion feel"
       ENV="NORTH restaurant dining room restored and dressed for service, two long rows of wooden tables with crisp white linen tablecloths and place settings stretching into background, vintage industrial pendant lights glowing warm amber overhead, exposed weathered red brick walls on both sides, polished hardwood floor reflecting light, large windows on the right wall pouring golden morning light at low angle, dust motes in the beams, calm anticipation"
       LOCK="$LOCK_INT"; REF="$MASTER_INT" ;;
    6) ACTION="character standing absolutely still in front of the large NORTH restaurant front window, looking out at the street, both thumbs hooked into the front pockets of the apron, shoulders relaxed, head slightly tilted, contemplative posture before opening"
       CAMX="GTA V third person ULTRA-WIDE CUTSCENE PULL-BACK CAMERA, camera positioned far back 8 meters at high height 2.5m, slowly drifting backward and upward, character very small in lower-third of frame standing against the bright window, the entire vast restored dining room sprawling around him with empty tables pendant lights brick walls visible, cinematic mission-start framing"
       ENV="vast NORTH restaurant dining room interior seen in ultra wide composition, character a small silhouette far across the room against the bright morning window with cobblestone street visible outside and the backwards NORTH sign on the glass, two rows of dressed tables flanking him receding from camera, warm pendant lights, exposed red brick walls left and right, hardwood floor with parallel light streaks from the window, drifting dust particles, profound stillness of a space waiting to be opened"
       LOCK="$LOCK_INT"; REF="$MASTER_INT" ;;
    *) echo "M02 gecersiz sahne: $id" >&2; return 1 ;;
  esac
}

build_prompt() {
  local mission=$1 scene=$2
  case "$mission" in
    01) build_prompt_01 "$scene" ;;
    02) build_prompt_02 "$scene" ;;
    *)  echo "Gecersiz mission: $mission" >&2; return 1 ;;
  esac

  # M01: traditional behind-the-back GTA cam everywhere (sahne 6 hariç - cutscene)
  # M02: varied GTA cameras per scene - use CAM_LITE so CAMX (side/top-down/wide) is not contradicted by "directly behind"
  if [ "$mission" = "01" ] && [ "$scene" = "6" ]; then
    PROMPT="$ANCHOR $LOCK, $CHAR, $CAMX, $ENV, $STYLE"
  elif [ "$mission" = "01" ]; then
    PROMPT="$ANCHOR $LOCK, $CHAR, $CAM, $CAMX, $ENV, $STYLE"
  else
    PROMPT="$ANCHOR $LOCK, $CHAR, $CAM_LITE, $CAMX, $ENV, $STYLE"
  fi
}

generate_scene() {
  local mission=$1 scene=$2
  build_prompt "$mission" "$scene"

  for img in "$JAY_FACE" "$REF"; do
    if [ ! -f "$img" ]; then
      echo "HATA: Referans gorseli yok: $img" >&2
      return 1
    fi
  done

  echo "==> M${mission} Sahne ${scene} uretiliyor (refs: $(basename "$REF") + JAY_FACE)"
  higgsfield generate create "$MODEL" \
    --prompt "$PROMPT" \
    --image "$REF" \
    --image "$JAY_FACE" \
    --aspect_ratio "$ASPECT" \
    --resolution "$RESOLUTION" \
    --wait
}

# Arg parse: ./generate.sh [MISSION] [SCENE]
MISSION="01"
SCENE=""
if [ $# -ge 1 ]; then
  if [[ "$1" =~ ^0[0-9]$ ]]; then
    MISSION="$1"
    [ $# -ge 2 ] && SCENE="$2"
  else
    SCENE="$1"
  fi
fi

if [ -n "$SCENE" ]; then
  generate_scene "$MISSION" "$SCENE"
else
  for s in 1 2 3 4 5 6; do
    generate_scene "$MISSION" "$s"
  done
fi

echo "Bitti."
