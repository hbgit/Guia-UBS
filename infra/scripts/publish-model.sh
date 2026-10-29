#!/usr/bin/env bash
#
# Publica o modelo SLM no storage do projeto (P1-1, #3 — ADR-004).
#
# Uso (da raiz do repositorio):
#   npm run model:publish -- <arquivo.gguf>                 # publica e confere
#   npm run model:publish -- <arquivo.gguf> --check-only    # so confere o arquivo
#   npm run model:publish -- --policy-only                  # so aplica a politica de models/
#
# O que ele garante, em ordem:
#   1. O arquivo e o que o app aceita: SHA-256 e tamanho batem com
#      app/lib/sync/model_catalog.dart. Sem isso nao ha rede nem docker.
#   2. O Gemma nunca sai sem o Notice e a copia dos termos ao lado (§3.1(2) e
#      §3.1(4) dos Gemma Terms of Use). A fonte unica e app/assets/legal/.
#   3. A politica anonima ganha SO `s3:GetObject` em models/*, e nenhuma
#      permissao anterior some (a dos packs foi configurada fora do repo, #46).
#      Falhou a conferencia: reaplica o backup e sai 1.
#   4. O objeto e conferido PELO EDGE, como o aparelho vai recebe-lo
#      (check-model-endpoint.sh): HEAD, Range, listagem fechada, manifest dos
#      packs ainda servido, e SHA-256 do download completo.
#
# Credenciais: o `mc` roda dentro do servico `storage` do compose, que ja tem
# MINIO_ROOT_USER/MINIO_ROOT_PASSWORD de infra/.env no ambiente. Nada de
# segredo na linha de comando do host.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCKER="${DOCKER:-docker}"
CATALOG="$ROOT/app/lib/sync/model_catalog.dart"
LEGAL="$ROOT/app/assets/legal"
# Nome do arquivo na origem (ggml-org): e o nome que o Notice cita.
OBJECT_NAME="gemma-3-1b-it-Q4_K_M"

fail() { echo "FALHOU  $*" >&2; exit 1; }

SHA="$(sed -n "s/.*sha256: '\([0-9a-f]\{64\}\)'.*/\1/p" "$CATALOG" | head -1)"
BYTES="$(sed -n 's/.*sizeBytes: \([0-9]\+\).*/\1/p' "$CATALOG" | head -1)"
[ -n "$SHA" ] && [ -n "$BYTES" ] || fail "nao achei sha256/sizeBytes em $CATALOG"

MODE=publish
FILE=""
for arg in "$@"; do
  case "$arg" in
    --check-only) MODE=check ;;
    --policy-only) MODE=policy ;;
    *) FILE="$arg" ;;
  esac
done

if [ "$MODE" != policy ]; then
  [ -n "$FILE" ] || fail "uso: publish-model.sh <arquivo.gguf> [--check-only] | --policy-only"
  [ -f "$FILE" ] || fail "$FILE nao existe"
  got_bytes="$(stat -c %s "$FILE")"
  [ "$got_bytes" = "$BYTES" ] || fail "SHA-256 nao confere: tamanho $got_bytes B, o catalogo espera $BYTES B (sha256 $SHA)"
  got_sha="$(sha256sum "$FILE" | cut -d' ' -f1)"
  [ "$got_sha" = "$SHA" ] || fail "SHA-256 nao confere: esperado $SHA, obtido $got_sha"
  echo "ok  arquivo confere com o catalogo ($SHA, $BYTES B)"
  [ "$MODE" = check ] && exit 0
fi

# INFRA_ENV_FILE troca o .env (verificacao num projeto compose descartavel,
# com COMPOSE_PROJECT_NAME proprio). Padrao: infra/.env.
ENV_FILE="${INFRA_ENV_FILE:-$ROOT/infra/.env}"
[ -f "$ENV_FILE" ] || fail "$ENV_FILE nao existe (copie infra/.env.example)"
env_get() { sed -n "s/^$1=//p" "$ENV_FILE" | tail -1; }
BUCKET="$(env_get S3_BUCKET)"; BUCKET="${BUCKET:-content-packs}"
PUBLIC_BASE="$(env_get MODEL_PUBLIC_BASE_URL)"
MANIFEST="$(env_get MODEL_CHECK_MANIFEST_URL)"

mc_run() {
  # `run` de um servico ja definido: mesma imagem e mesmo .env, sem porta
  # publicada (sem --service-ports) e sem subir dependencias.
  "$DOCKER" compose --env-file "$ENV_FILE" -f "$ROOT/infra/compose.yaml" run --rm --no-deps -T \
    "$@" --entrypoint sh storage -c \
    'mc alias set local http://storage:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && '"$MC_SCRIPT"
}

if [ "$MODE" = publish ]; then
  for f in gemma_notice.txt gemma_terms_en.md gemma_prohibited_use_en.md; do
    [ -f "$LEGAL/$f" ] || fail "falta $LEGAL/$f: o Gemma nao sai sem o Notice e a copia dos termos ao lado (ADR-004, §3.1)"
  done
  KEY="models/$OBJECT_NAME-$SHA"
  # Notice e termos ANTES do modelo: em nenhum instante o .gguf fica servido sem eles.
  MC_SCRIPT="set -e
    mc cp -q --attr 'Content-Type=text/plain; charset=utf-8' /in/legal/gemma_notice.txt local/$BUCKET/$KEY.NOTICE.txt
    mc cp -q --attr 'Content-Type=text/markdown; charset=utf-8' /in/legal/gemma_terms_en.md local/$BUCKET/models/gemma-terms-of-use.md
    mc cp -q --attr 'Content-Type=text/markdown; charset=utf-8' /in/legal/gemma_prohibited_use_en.md local/$BUCKET/models/gemma-prohibited-use-policy.md
    mc cp -q --attr 'Content-Type=application/octet-stream' /in/model.gguf local/$BUCKET/$KEY.gguf
    test \"\$(mc stat --json local/$BUCKET/$KEY.gguf | sed -n 's/.*\"size\":\([0-9]*\).*/\1/p')\" = $BYTES" \
    mc_run -v "$(realpath "$FILE"):/in/model.gguf:ro" -v "$LEGAL:/in/legal:ro"
  echo "ok  enviado $BUCKET/$KEY.gguf (+ NOTICE e termos)"
fi

# --- Politica: so GetObject em models/*, sem perder nada do que ja existia ---
BACKUP_DIR="$ROOT/infra/scripts/.policy-backup"
mkdir -p "$BACKUP_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BEFORE="$BACKUP_DIR/$STAMP-antes.json"
NEW="$BACKUP_DIR/$STAMP-nova.json"
AFTER="$BACKUP_DIR/$STAMP-depois.json"

# Ler o "antes" PRECISA dar certo. Bucket sem política é `{}` com saída 0
# (medido no mc da imagem do compose); qualquer outra coisa — MinIO
# reiniciando, credencial errada — antes virava "sem política" e o `set-json`
# gravava só o statement de models/, apagando o acesso anônimo aos packs.
if ! MC_SCRIPT="mc anonymous get-json local/$BUCKET" mc_run > "$BEFORE"; then
  fail "nao consegui ler a politica atual de $BUCKET; nada foi alterado"
fi
grep -q '^{' "$BEFORE" || fail "a politica atual de $BUCKET nao e JSON ($BEFORE); nada foi alterado"
node --import tsx "$ROOT/packer/src/models-policy.ts" merge "$BEFORE" --bucket "$BUCKET" > "$NEW"

# Do `set-json` em diante, qualquer saída sem conferência completa reaplica o
# "antes" — inclusive quando o `set -e` derruba o script no meio.
rollback() {
  if grep -q '"Statement"' "$BEFORE"; then
    MC_SCRIPT="mc anonymous set-json /in/policy.json local/$BUCKET >/dev/null" \
      mc_run -v "$BEFORE:/in/policy.json:ro" || true
  else
    MC_SCRIPT="mc anonymous set private local/$BUCKET >/dev/null" mc_run || true
  fi
  echo "FALHOU  politica reaplicada a partir do backup ($BEFORE)" >&2
}
POLICY_VERIFIED=0
trap '[ "$POLICY_VERIFIED" = 1 ] || rollback' EXIT

MC_SCRIPT="mc anonymous set-json /in/policy.json local/$BUCKET >/dev/null" \
  mc_run -v "$NEW:/in/policy.json:ro"
MC_SCRIPT="mc anonymous get-json local/$BUCKET" mc_run > "$AFTER"
node --import tsx "$ROOT/packer/src/models-policy.ts" verify "$BEFORE" "$AFTER" \
  || fail "a politica nova perdeu permissoes anteriores"
POLICY_VERIFIED=1
trap - EXIT
echo "ok  politica: GetObject em $BUCKET/models/*, nada anterior perdido (backup $BEFORE)"

if [ "$MODE" = publish ]; then
  [ -n "$PUBLIC_BASE" ] || fail "MODEL_PUBLIC_BASE_URL nao definida em infra/.env"
  args=("$PUBLIC_BASE/$KEY.gguf" "$SHA" "$BYTES")
  if [ -n "$MANIFEST" ]; then
    args+=(--manifest "$MANIFEST")
  else
    echo "aviso  MODEL_CHECK_MANIFEST_URL vazia: sem manifest publicado nao ha pack a preservar" >&2
  fi
  bash "$ROOT/infra/scripts/check-model-endpoint.sh" "${args[@]}"
  echo "ok  MODEL_URL=$PUBLIC_BASE/$KEY.gguf"
fi
