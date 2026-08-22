#!/usr/bin/env bash
#
# Gera os PNGs do icone do launcher a partir de tool/icon/icone_app.svg.
#
# Os PNGs SAO versionados (o build do Android os consome direto), mas a receita
# que os produz fica aqui do lado. Sem ela, mexer no icone daqui a um ano
# significa adivinhar em que escala e em que posicao a arte foi colada — e
# enquadramento de icone adaptativo nao e coisa que se acerta no olho.
#
# Uso:
#   tool/gen_launcher_icon.sh          # escreve em android/app/src/main/res/
#   tool/gen_launcher_icon.sh --check  # so confere que o que esta no disco bate
#
# ------------------------------------------------------------------ ENQUADRAMENTO
#
# A arte de origem NAO foi desenhada para virar icone: a tela e 1015x955 (nao
# quadrada) e a estrada com as moitas sangra pelas bordas esquerda, direita e
# inferior. Duas medidas, tiradas do proprio SVG e nao estimadas:
#
#   tinta total (paths 2-4)   1012 x 922  a partir de (3, 33)
#   pino + cruz                595 x 802  a partir de (211, 33)
#
# O icone adaptativo tem tela de 108 dp, dos quais so a janela central de 72 dp
# e visivel e so o CIRCULO central de 66 dp e territorio garantido — a mascara
# do launcher (circulo, squircle, quadrado...) come o resto.
#
# Regra: a ALTURA DO PINO ocupa 62 dp. Nao 66: a ponta do pino e afilada e e a
# primeira coisa que uma mascara circular decepa; 62 dp deixa a folga.
#
# E a arte e centrada NO CENTRO DO PINO (508.5, 434), nao no centro da tela: a
# composicao e assimetrica no eixo vertical, e centrar pela tela empurraria a
# ponta do pino para fora da zona segura.
#
# Com isso a arte inteira fica com ~78 dp de largura — mais que os 72 dp
# visiveis. Ou seja: a estrada segue sangrando pela borda mascarada, que e
# exatamente o que ela faz na arte original. A sangria e de proposito.
#
# ------------------------------------------------------------------ INVERSAO
#
# tool/icon/icone_app.svg guarda a arte COMO ENTREGUE: pino verde sobre fundo
# quase branco. O icone publicado inverte as duas cores — campo verde solido,
# pino e estrada em branco. Um disco verde cheio se acha de relance numa grade
# de icones claros, e "verde = UBS" e a semantica fixa do projeto
# (CLAUDE.md / design.html).
#
# A inversao mora AQUI, e nao no SVG, para que a fonte continue sendo o arquivo
# que o autor entregou e a transformacao continue reversivel numa linha.
#
set -euo pipefail

readonly VERDE='#248b54'      # fill dos paths 2 e 4 no SVG de origem
readonly CLARO='#f3fbf1'      # fill dos paths 1 e 3 (fundo e cruz)

# Densidades: nome do diretorio mipmap : lado da tela adaptativa (108 dp) em px
readonly DENSIDADES=(
  "mdpi:108"
  "hdpi:162"
  "xhdpi:216"
  "xxhdpi:324"
  "xxxhdpi:432"
)

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly RAIZ
readonly SVG="$RAIZ/tool/icon/icone_app.svg"
readonly RES="$RAIZ/android/app/src/main/res"

modo_check=0
[[ "${1:-}" == "--check" ]] && modo_check=1

for ferramenta in rsvg-convert magick python3; do
  if ! command -v "$ferramenta" >/dev/null 2>&1; then
    echo "erro: '$ferramenta' nao encontrado." >&2
    echo "      Fedora: sudo dnf install librsvg2-tools ImageMagick python3" >&2
    echo "      Debian: sudo apt install librsvg2-bin imagemagick python3" >&2
    exit 1
  fi
done

[[ -f "$SVG" ]] || { echo "erro: fonte ausente: $SVG" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- 1. separa os paths -------------------------------------------------------
#
# path 1 e o retangulo de fundo, que o icone adaptativo substitui pela camada
# <background>. path 3 e a cruz, que o monocromatico precisa isolar.
python3 - "$SVG" "$tmp" <<'PY'
import re, sys
svg, saida = sys.argv[1], sys.argv[2]
paths = re.findall(r'<path[^>]*/>', open(svg).read())
if len(paths) != 4:
    sys.exit(f"erro: esperava 4 paths no SVG, achei {len(paths)}. "
             "A arte mudou — reveja o enquadramento antes de seguir.")
cab = '<svg xmlns="http://www.w3.org/2000/svg" width="1015" height="955">'
# tinta: tudo menos o fundo
open(f'{saida}/tinta.svg', 'w').write(cab + ''.join(paths[1:]) + '</svg>')
# so os paths verdes (pino cheio + estrada), sem a cruz
open(f'{saida}/solido.svg', 'w').write(cab + paths[1] + paths[3] + '</svg>')
# so a cruz
open(f'{saida}/cruz.svg', 'w').write(cab + paths[2] + '</svg>')
PY

# --- 2. inverte as cores ------------------------------------------------------
#
# Em tres tempos, via marcador. Dois `sed` encadeados pintariam tudo de uma cor
# so: o primeiro troca A por B, o segundo troca de volta o que acabou de virar B.
sed -e "s/$VERDE/#SWAP00/gI" -e "s/$CLARO/$VERDE/gI" -e "s/#SWAP00/$CLARO/gI" \
  "$tmp/tinta.svg" > "$tmp/tinta_inv.svg"

# --- 3. gera ------------------------------------------------------------------
#
# Escala e posicao saem da regra de enquadramento acima. Em 108 dp:
#   s            = 62 / 802          (altura do pino -> 62 dp)
#   arte         = 1015 s x 955 s
#   deslocamento = centro da tela - centro do pino, em px
gerar_densidade() {
  local dir="$1" lado="$2" destino="$3"
  local dims largura dx dy visivel legado
  dims=$(python3 -c "
lado = $lado
s = (lado / 108.0) * 62 / 802.0     # px por unidade SVG
print(round(1015 * s),
      round(lado / 2 - 508.5 * s),
      round(lado / 2 - 434.0 * s),
      round(lado * 72 / 108.0),     # janela visivel
      round(lado * 48 / 108.0))     # lado do icone legado
")
  read -r largura dx dy visivel legado <<< "$dims"

  local saida="$destino/mipmap-$dir"
  mkdir -p "$saida"

  # camada <foreground>: arte invertida sobre tela transparente
  #
  # `-depth 8 -strip` em todo PNG que sai daqui: o ImageMagick promove para
  # 16 bits por canal no meio da composicao e carimba metadado de data, e nem
  # um nem outro sobrevive util dentro do APK — so engordam o binario e fazem
  # duas geracoes do mesmo SVG produzirem bytes diferentes.
  rsvg-convert -w "$largura" "$tmp/tinta_inv.svg" -o "$tmp/arte-$dir.png"
  magick -size "${lado}x${lado}" xc:none \
    "$tmp/arte-$dir.png" -geometry "+${dx}+${dy}" -composite \
    -depth 8 -strip "$saida/ic_launcher_foreground.png"

  # icone legado: mesma composicao achatada sobre o campo verde, recortada na
  # janela visivel de 72 dp. Launcher antigo nao mascara nada, entao o que ele
  # recebe ja tem que estar enquadrado.
  magick -size "${lado}x${lado}" "xc:$VERDE" \
    "$saida/ic_launcher_foreground.png" -composite \
    -gravity center -crop "${visivel}x${visivel}+0+0" +repage \
    -resize "${legado}x${legado}" \
    -depth 8 -strip "$saida/ic_launcher.png"

  # <monochrome>: silhueta que o sistema tinge. ARMADILHA: a cruz nao e um furo
  # no pino, e um path desenhado POR CIMA dele. Silhueta ingenua pelo alfa
  # devolve um pino solido, sem cruz nenhuma. Aqui o vazado e construido:
  # alfa dos paths verdes MENOS alfa do path da cruz.
  rsvg-convert -w "$largura" "$tmp/solido.svg" -o "$tmp/solido-$dir.png"
  rsvg-convert -w "$largura" "$tmp/cruz.svg"   -o "$tmp/cruz-$dir.png"
  magick "$tmp/solido-$dir.png" "$tmp/cruz-$dir.png" \
    -compose DstOut -composite \
    -fill black -colorize 100 \
    "$tmp/mono-$dir.png"
  magick -size "${lado}x${lado}" xc:none \
    "$tmp/mono-$dir.png" -geometry "+${dx}+${dy}" -composite \
    -depth 8 -strip "$saida/ic_launcher_monochrome.png"
}

if (( modo_check )); then
  destino="$tmp/res"
else
  destino="$RES"
fi

for entrada in "${DENSIDADES[@]}"; do
  gerar_densidade "${entrada%%:*}" "${entrada##*:}" "$destino"
done

if (( modo_check )); then
  divergiu=0
  for entrada in "${DENSIDADES[@]}"; do
    dir="${entrada%%:*}"
    for png in ic_launcher ic_launcher_foreground ic_launcher_monochrome; do
      if ! cmp -s "$destino/mipmap-$dir/$png.png" "$RES/mipmap-$dir/$png.png"; then
        echo "divergente: mipmap-$dir/$png.png"
        divergiu=1
      fi
    done
  done
  (( divergiu )) && { echo "PNGs fora de sincronia com o SVG. Rode sem --check." >&2; exit 1; }
  echo "ok: os 15 PNGs batem com tool/icon/icone_app.svg"
else
  echo "ok: 15 PNGs escritos em android/app/src/main/res/mipmap-*/"
fi
