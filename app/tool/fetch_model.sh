#!/usr/bin/env bash
#
# Baixa o modelo GGUF para app/assets/models/ e VERIFICA o SHA-256.
#
# O modelo nao vai para o git (.gitignore): sao centenas de MB que mudariam o
# tamanho do repositorio sem mudar o codigo. Em troca, o checksum fica aqui
# versionado — e o que impede que um espelho comprometido, ou um download
# truncado, vire um modelo diferente rodando triagem no aparelho de alguem.
#
# Uso:
#   tool/fetch_model.sh [gemma-3-1b | gemma-3-270m]
#
# Sem argumento, baixa o modelo padrao do projeto.

set -euo pipefail

# ---------------------------------------------------------------------------
# Catalogo. Formato: <nome>|<url>|<sha256>|<bytes>
#
# Orcamento do RNF-03 (ADR-003): APK + modelo + pack <= 1,2 GB, com o modelo
# entre 700 MB e 1,2 GB. O Gemma 3 1B Q4_K_M (768 MB) cabe; medicoes e
# comparacao entre modelos em arquitetura.md 5.1.
# ---------------------------------------------------------------------------
CATALOG=(
  "gemma-3-1b|https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf|8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135|806058240"
  "gemma-3-270m|https://huggingface.co/unsloth/gemma-3-270m-it-GGUF/resolve/main/gemma-3-270m-it-Q4_K_M.gguf|b1baabd6b729e4041822220d3e648e00d99cac5df86b10dffb77bcccf0688e39|253115424"
)

DEFAULT_MODEL="gemma-3-1b"
WANTED="${1:-$DEFAULT_MODEL}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$SCRIPT_DIR/../assets/models"

for entry in "${CATALOG[@]}"; do
  IFS='|' read -r name url sha bytes <<<"$entry"
  [ "$name" = "$WANTED" ] || continue

  mkdir -p "$DEST_DIR"
  dest="$DEST_DIR/$name.gguf"

  # Ja presente e integro: nao rebaixa. Downloads de ~800 MB nao devem
  # acontecer de novo so porque alguem rodou o script duas vezes.
  if [ -f "$dest" ] && echo "$sha  $dest" | sha256sum --check --status; then
    echo "ok: $dest ja presente e com checksum conferido"
    exit 0
  fi

  echo "baixando $name ($(( bytes / 1048576 )) MB)..."
  # Arquivo temporario: um Ctrl-C no meio nao pode deixar um .gguf truncado
  # com o nome definitivo, que passaria despercebido ate o app tentar carregar.
  tmp="$dest.parcial"
  curl -fL --retry 3 --retry-delay 2 -o "$tmp" "$url"

  echo "conferindo SHA-256..."
  obtido="$(sha256sum "$tmp" | cut -d' ' -f1)"
  if [ "$obtido" != "$sha" ]; then
    rm -f "$tmp"
    {
      echo "FALHOU: checksum nao confere. Arquivo descartado."
      echo "  esperado: $sha"
      echo "  obtido:   $obtido"
    } >&2
    exit 1
  fi

  mv "$tmp" "$dest"
  echo "ok: $dest"
  exit 0
done

{
  echo "modelo desconhecido: $WANTED"
  echo "disponiveis:"
  for entry in "${CATALOG[@]}"; do echo "  ${entry%%|*}"; done
} >&2
exit 2
