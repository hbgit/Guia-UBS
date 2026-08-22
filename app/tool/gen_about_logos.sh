#!/usr/bin/env bash
#
# Rasteriza os logotipos institucionais da tela "Sobre".
#
# PNG e nao SVG dentro do app: renderizar vetor em tempo de execucao custaria
# uma dependencia nova (`flutter_svg`) para duas imagens que aparecem numa tela
# so, sempre no mesmo tamanho. O SVG fica versionado aqui, ao lado da receita.
#
# Mesmo padrao de tool/gen_launcher_icon.sh: o PNG e versionado porque o build
# do Flutter o consome direto, mas quem precisar mexer nao fica adivinhando de
# onde ele saiu.
#
# Uso:
#   tool/gen_about_logos.sh          # escreve em assets/branding/
#   tool/gen_about_logos.sh --check  # confere que o disco bate com os SVG
#
# ------------------------------------------------------------------ TAMANHOS
#
# Os dois logos tem proporcoes muito diferentes — um e uma faixa horizontal
# (350x92), o outro e quase quadrado (777x757). Rasterizar os dois na mesma
# LARGURA deixaria um deles gigante ao lado do outro. Por isso a medida
# normalizada e a ALTURA: e ela que alinha logos numa fila de creditos.
#
# 3x a altura de exibicao (96 dp) cobre xxhdpi sem ficar borrado; acima disso o
# ganho e invisivel e o peso no APK, nao.
#
set -euo pipefail

readonly ALTURA=288    # 96 dp @ 3x

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly RAIZ
readonly ORIGEM="$RAIZ/tool/icon"
readonly DESTINO="$RAIZ/assets/branding"

readonly LOGOS=(
  "about_logo_prism"
  "about_telessaude_ufrr"
)

modo_check=0
[[ "${1:-}" == "--check" ]] && modo_check=1

for ferramenta in rsvg-convert magick; do
  if ! command -v "$ferramenta" >/dev/null 2>&1; then
    echo "erro: '$ferramenta' nao encontrado." >&2
    echo "      Fedora: sudo dnf install librsvg2-tools ImageMagick" >&2
    echo "      Debian: sudo apt install librsvg2-bin imagemagick" >&2
    exit 1
  fi
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

saida="$DESTINO"
(( modo_check )) && saida="$tmp/branding"
mkdir -p "$saida"

for nome in "${LOGOS[@]}"; do
  svg="$ORIGEM/$nome.svg"
  [[ -f "$svg" ]] || { echo "erro: fonte ausente: $svg" >&2; exit 1; }

  # ARMADILHA: `-b none` NAO basta. O SVG do Telessaude pinta o proprio fundo
  # com um path branco que cobre a tela inteira — o mesmo padrao do SVG do
  # icone do app. O resultado e um retangulo branco no lugar do logo: passa
  # despercebido no tema claro e vira uma mancha acesa no tema escuro.
  #
  # Removemos o PRIMEIRO path quando ele e quase branco: e o fundo. Os demais
  # paths claros sao detalhes desenhados por cima do verde e precisam ficar.
  python3 - "$svg" "$tmp/$nome-src.svg" <<'PY'
import re, sys
origem, destino = sys.argv[1], sys.argv[2]
svg = open(origem).read()

primeiro = re.search(r'<path[^>]*/>', svg)
if primeiro:
    fill = re.search(r'fill:\s*(#[0-9a-fA-F]{6})', primeiro.group(0))
    if fill:
        r, g, b = (int(fill.group(1)[i:i + 2], 16) for i in (1, 3, 5))
        # "Quase branco" com folga: branco de arte raramente e #ffffff.
        if r > 240 and g > 240 and b > 240:
            svg = svg[:primeiro.start()] + svg[primeiro.end():]

open(destino, 'w').write(svg)
PY
  svg="$tmp/$nome-src.svg"

  # Fundo TRANSPARENTE: a tela "Sobre" tem tema claro e escuro, e um fundo
  # branco assado no PNG viraria um retangulo aceso no tema escuro.
  #
  # `-depth 8 -strip` pelo mesmo motivo do gerador de icone: o ImageMagick
  # promove para 16 bits e carimba data, e nenhum dos dois sobrevive util
  # dentro do APK.
  # RECORTAR antes de dimensionar, e nao depois. A tela do SVG nao e a arte:
  # o logo do PRISM vem numa tela QUADRADA de 378x378 com o wordmark ocupando
  # uma faixa de 350x92 no meio. Escalar por altura sem recortar daria 288 px
  # de altura com o desenho ocupando 70 deles — o logo apareceria minusculo ao
  # lado do outro, e a diferenca seria pura sobra transparente.
  #
  # Por isso: rasteriza grande, apara a borda transparente, e SO ENTAO
  # normaliza a altura.
  rsvg-convert -h "$((ALTURA * 4))" -b none "$svg" -o "$tmp/$nome-cru.png"
  magick "$tmp/$nome-cru.png" \
    -trim +repage \
    -resize "x$ALTURA" \
    -depth 8 -strip "$saida/$nome.png"
done

if (( modo_check )); then
  divergiu=0
  for nome in "${LOGOS[@]}"; do
    if ! cmp -s "$saida/$nome.png" "$DESTINO/$nome.png"; then
      echo "divergente: assets/branding/$nome.png"
      divergiu=1
    fi
  done
  (( divergiu )) && { echo "PNGs fora de sincronia com os SVG." >&2; exit 1; }
  echo "ok: os logos batem com tool/icon/about_*.svg"
else
  echo "ok: ${#LOGOS[@]} logos escritos em assets/branding/"
fi
