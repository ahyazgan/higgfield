#!/usr/bin/env bash
# Soccer Manager dashboard - Higgsfield nano_banana_2 ile gercek foto/asset uretimi
# Kullanim: ./generate_dashboard.sh [asset_id]   (bos = hepsi)
#
# Asset id listesi:
#   1  atm_crest         - Atletico Madrid crest (1:1)
#   2  racing_crest      - Real Racing Club crest (1:1)
#   3  laliga_logo       - La Liga logo (1:1)
#   4  stadium_wanda     - Wanda Metropolitano aerial (16:9)
#   5  manager_portrait  - Menajer Malavida portresi (1:1)
#   6  dembele_portrait  - Dembele spotlight portresi (1:1)
#   7  transfer_atangana - V. Atangana headshot (1:1)
#   8  transfer_learburn - M. Learburn headshot (1:1)
#   9  transfer_parsons  - C. Parsons headshot (1:1)
#   10 afcon_news        - AFCON haber foto (16:9)
#   11 ultimate_pack     - Ultimate Edition gold pack art (1:1)
#   12 scout_illust      - Scout assignment illustration (1:1)

set -euo pipefail
cd "$(dirname "$0")"

MODEL="nano_banana_2"
OUTDIR="./out_dashboard"
mkdir -p "$OUTDIR"

generate_asset() {
  local id=$1 name aspect prompt

  case $id in
    1)  name="atm_crest"; aspect="1:1"
        prompt="Atletico Madrid football club official crest, red and white vertical stripes shield, blue lower section with bear and strawberry tree, yellow star and crown details, crisp vector style logo, centered on flat dark navy background, high resolution clean rendering, professional sports branding" ;;
    2)  name="racing_crest"; aspect="1:1"
        prompt="Real Racing Club de Santander football crest, vertical green and white striped shield, yellow crown above, classic spanish football club logo design, vector art, clean rendering, centered on flat dark navy background, professional crest" ;;
    3)  name="laliga_logo"; aspect="1:1"
        prompt="La Liga official logo, modern stylized red and dark navy mark with abstract footballer silhouette, sleek minimalist sports league branding, vector art, centered on flat white background, ultra crisp rendering" ;;
    4)  name="stadium_wanda"; aspect="16:9"
        prompt="Wanda Metropolitano stadium aerial photograph at golden hour, modern white curved roof structure, full stadium illuminated, red Atletico Madrid colors visible in the seating bowl, surrounding Madrid suburban skyline, shot from helicopter, professional sports photography, sharp realistic detail, dramatic warm sunset light, photo-realistic" ;;
    5)  name="manager_portrait"; aspect="1:1"
        prompt="Professional press photo of a football team manager in his late thirties, short dark hair, clean shaven, wearing a sharp black suit jacket and white shirt, standing on the touchline of a football stadium, slight smile, looking confidently toward camera, shallow depth of field with blurred stadium crowd in background, natural daylight, sports photojournalism style, hyper realistic" ;;
    6)  name="dembele_portrait"; aspect="1:1"
        prompt="Professional football player portrait, athletic young man in his mid twenties wearing Paris Saint-Germain dark navy and red home jersey, short curly hair, focused intense expression, mid-action close-up during a match, shallow depth of field stadium lights bokeh background, sports press photography, hyper realistic detail, dramatic stadium lighting" ;;
    7)  name="transfer_atangana"; aspect="1:1"
        prompt="Football player headshot, young African footballer mid twenties wearing red and white RB Leipzig training jersey, neutral confident expression looking at camera, plain dark grey studio background, official club portrait style, sharp clean lighting, hyper realistic" ;;
    8)  name="transfer_learburn"; aspect="1:1"
        prompt="Football player headshot, young white British footballer early twenties wearing navy blue and white striped West Bromwich Albion home jersey, neutral expression looking at camera, plain dark grey studio background, official club portrait style, sharp clean lighting, hyper realistic" ;;
    9)  name="transfer_parsons"; aspect="1:1"
        prompt="Football player headshot, young footballer late teens wearing claret and blue Doncaster Rovers home jersey, neutral focused expression looking at camera, plain dark grey studio background, official club portrait style, sharp clean lighting, hyper realistic" ;;
    10) name="afcon_news"; aspect="16:9"
        prompt="Africa Cup of Nations football match action photograph, two African national team players competing for the ball, dramatic stadium floodlights, packed crowd of fans in colorful jerseys in background, motion blur on legs, sports photojournalism, golden trophy hint in foreground bokeh, hyper realistic press photo, vibrant warm colors" ;;
    11) name="ultimate_pack"; aspect="1:1"
        prompt="Premium gold collector card pack for a football manager mobile game, glossy gold metallic packaging with embossed crown and trophy emblem, glowing edges, scattered virtual coins and a shimmering football around the pack, premium loot box product render, dark navy gradient background, dramatic studio lighting, ultra high quality 3D render" ;;
    12) name="scout_illust"; aspect="1:1"
        prompt="Stylized illustration of a football scout with binoculars and a notebook, watching a player from the stands of a stadium, modern flat illustration style with subtle gradients, blue and orange color palette, friendly approachable mobile game UI art, clean composition centered on character, no text" ;;
    *)  echo "Gecersiz asset id: $id" >&2; return 1 ;;
  esac

  echo "==> [$id] $name uretiliyor ($aspect)"
  higgsfield generate create "$MODEL" \
    --prompt "$prompt" \
    --aspect_ratio "$aspect" \
    --wait \
    > "$OUTDIR/${name}.txt"
  echo "    -> $OUTDIR/${name}.txt"
}

if [ $# -ge 1 ]; then
  generate_asset "$1"
else
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    generate_asset "$i"
  done
fi

echo ""
echo "Bitti. Sonuc URL'leri $OUTDIR/*.txt icinde."
