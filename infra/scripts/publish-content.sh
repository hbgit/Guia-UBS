#!/usr/bin/env bash
#
# Publica no host SO de conteudo (plano B; compose.content.yaml) por rsync.
#
# Uso (da raiz do repositorio):
#   npm run content:publish -- <out-dir> <edicao>     # pack: out/ do pack:build
#   npm run content:publish -- --model <arquivo.gguf> # modelo SLM
#
# Ambiente:
#   CONTENT_TARGET   destino rsync: `publisher@<host>:` (rrsync fixa a raiz) ou
#                    um diretorio local (testes). Obrigatorio.
#   PACK_PUBKEY_HEX  publica Ed25519 (hex) que confere o manifest antes de
#                    enviar. Obrigatoria para pack.
#
# O que ele garante, em ordem (pack):
#   1. Antes de qualquer rede: o manifest verifica com a publica, pelo MESMO
#      codigo do app (tool/verify_manifest.dart), e cada arquivo que ele cita
#      existe em <out-dir> com o sha256 declarado.
#   2. packs/ e assets/ vao com --ignore-existing: nome ja publicado nunca e
#      sobrescrito (`Cache-Control: immutable`; os nomes carregam o sha).
#   3. Conferencia remota: um arquivo com o MESMO nome e bytes DIFERENTES no
#      destino aborta tudo SEM enviar o manifest.
#   4. manifest.json por ultimo (o rsync grava num temporario oculto e renomeia).
#
# O `publisher` escreve e nao apaga (`rrsync -no-del`). Apagar e do
# administrador da VPS, pela conta dele.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail() { echo "FALHOU  $*" >&2; exit 1; }
uso() { echo "uso: publish-content.sh <out-dir> <edicao> | --model <arquivo.gguf>" >&2; exit 64; }

[ -n "${CONTENT_TARGET:-}" ] || fail "CONTENT_TARGET nao definido (publisher@<host>: ou diretorio)"
command -v rsync >/dev/null || fail "rsync nao instalado"

# `publisher@host:` -> caminho relativo a raiz do rrsync; diretorio -> absoluto.
destino() {
  case "$CONTENT_TARGET" in
    *:) printf '%s%s/' "$CONTENT_TARGET" "$1" ;;
    *) printf '%s/%s/' "${CONTENT_TARGET%/}" "$1" ;;
  esac
}

RSYNC=(rsync --recursive --links --times --chmod=D755,F644 --mkpath)

if [ "${1:-}" = "--model" ]; then
  [ $# -eq 2 ] || uso
  FILE="$2"
  # Mesmas conferencias do model:publish: sha e tamanho do catalogo, e o Gemma
  # nunca sai sem o Notice e os termos ao lado (ADR-004, §3.1).
  bash "$ROOT/infra/scripts/publish-model.sh" "$FILE" --check-only
  LEGAL="$ROOT/app/assets/legal"
  for f in gemma_notice.txt gemma_terms_en.md gemma_prohibited_use_en.md; do
    [ -f "$LEGAL/$f" ] || fail "falta $LEGAL/$f"
  done
  SHA="$(sed -n "s/.*sha256: '\([0-9a-f]\{64\}\)'.*/\1/p" "$ROOT/app/lib/sync/model_catalog.dart" | head -1)"
  KEY="gemma-3-1b-it-Q4_K_M-$SHA"
  STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
  cp "$LEGAL/gemma_notice.txt" "$STAGE/$KEY.NOTICE.txt"
  cp "$LEGAL/gemma_terms_en.md" "$STAGE/gemma-terms-of-use.md"
  cp "$LEGAL/gemma_prohibited_use_en.md" "$STAGE/gemma-prohibited-use-policy.md"
  DEST="$(destino content-packs/models)"
  # Notice e termos ANTES do modelo: o .gguf nunca fica servido sem eles. Os
  # termos tem nome fixo e podem ser atualizados; o NOTICE e o .gguf, nao.
  "${RSYNC[@]}" --checksum "$STAGE/gemma-terms-of-use.md" "$STAGE/gemma-prohibited-use-policy.md" "$DEST"
  "${RSYNC[@]}" --ignore-existing "$STAGE/$KEY.NOTICE.txt" "$DEST"
  "${RSYNC[@]}" --ignore-existing "$FILE" "$DEST$KEY.gguf"
  echo "ok  modelo em content-packs/models/$KEY.gguf (+ NOTICE e termos)"
  echo "    manifest: --model-url ../models/$KEY.gguf --model-sha256 $SHA"
  exit 0
fi

[ $# -eq 2 ] || uso
OUT="$(cd "$1" && pwd)"; ED="$2"
[[ "$ED" =~ ^[A-Za-z0-9._-]+$ ]] || fail "edicao invalida: $ED"
[ -f "$OUT/manifest.json" ] || fail "$OUT/manifest.json nao existe"
[ -n "${PACK_PUBKEY_HEX:-}" ] || fail "PACK_PUBKEY_HEX nao definido"

# 1. Antes de qualquer rede
(cd "$ROOT/app" && dart run tool/verify_manifest.dart "$OUT/manifest.json" "$PACK_PUBKEY_HEX") \
  || fail "manifest nao verifica com PACK_PUBKEY_HEX; nada foi enviado"
node -e '
  const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  for (const a of [m.pack, ...m.assets]) console.log(`${a.sha256}  ${a.url}`);
' "$OUT/manifest.json" | (cd "$OUT" && sha256sum --check --quiet --strict) \
  || fail "arquivo citado pelo manifest ausente ou com sha divergente em $OUT; nada foi enviado"
echo "ok  manifest e arquivos conferidos em $OUT"

SRCS=()
for d in packs assets; do [ -d "$OUT/$d" ] && SRCS+=("$OUT/$d"); done
DEST="$(destino "content-packs/$ED")"

# 2. Artefatos por hash, sem sobrescrever
"${RSYNC[@]}" --ignore-existing "${SRCS[@]}" "$DEST"

# 3. Mesmo nome, bytes diferentes no destino? Entao NAO publica o manifest.
DIVERGE="$("${RSYNC[@]}" --checksum --dry-run --itemize-changes "${SRCS[@]}" "$DEST" | grep -E '^[<>]f' || true)"
if [ -n "$DIVERGE" ]; then
  echo "$DIVERGE" >&2
  fail "o destino tem arquivo com o mesmo nome e bytes diferentes; manifest NAO enviado"
fi

# 4. Manifest por ultimo
"${RSYNC[@]}" "$OUT/manifest.json" "$DEST"
echo "ok  publicado em content-packs/$ED (packs e assets antes, manifest por ultimo)"
