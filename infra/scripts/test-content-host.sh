#!/usr/bin/env bash
#
# Teste do host so de conteudo (plano B): sobe o compose.content.yaml com
# CONTENT_DOMAIN=localhost (o Caddy emite certificado interno), publica uma
# arvore SINTETICA assinada com a chave de dev pelo publish-content.sh (alvo
# local) e confere, pela borda, o que o aparelho vai ver.
#
#   npm run content:test
#
# Projeto compose proprio (gubs-content-test) e portas proprias: nao toca no
# infra/.env nem num edge que esteja rodando.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCKER="${DOCKER:-docker}"
HTTPS_PORT="${CONTENT_TEST_HTTPS_PORT:-18443}"
HTTP_PORT="${CONTENT_TEST_HTTP_PORT:-18080}"
PROJECT=gubs-content-test
DEV_PUB=bbfd5b2b69d27c539a4d29a4167319508bbf36130590d22289676a0e7e237dfa

WORK="$(mktemp -d)"
ENVF="$WORK/env"
SITE="$WORK/site"
mkdir -p "$SITE"
cat > "$ENVF" <<EOT
CONTENT_DOMAIN=localhost
ACME_EMAIL=ops@exemplo.invalid
CONTENT_ROOT=$SITE
CONTENT_HTTP_PORT=$HTTP_PORT
CONTENT_HTTPS_PORT=$HTTPS_PORT
EOT
compose() { "$DOCKER" compose -p "$PROJECT" --env-file "$ENVF" -f "$ROOT/infra/compose.content.yaml" "$@"; }
cleanup() { compose down -v >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

FAILS=0
ok() { echo "ok    $*"; }
nok() { echo "FALHA $*" >&2; FAILS=$((FAILS + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else nok "$1 (esperado $3, obtido $2)"; fi; }

# Arvores sinteticas: v1 e uma v2 com o MESMO pack (nome igual).
arvore() {
  SOURCE_DATE_EPOCH=1787097600 node --import tsx "$ROOT/packer/test/support/manifest-interop.ts" \
    --key "$ROOT/contract/keys/dev-k1.pem" --out "$1" --arvore --pack-version "$2" >/dev/null 2>&1
}
arvore "$WORK/v1" 1
arvore "$WORK/v2" 2

compose up -d >/dev/null 2>&1
BASE="https://localhost:$HTTPS_PORT/content-packs/0000000"
for _ in $(seq 1 60); do
  curl -sk -o /dev/null "https://localhost:$HTTPS_PORT/" && break
  sleep 1
done

export CONTENT_TARGET="$SITE" PACK_PUBKEY_HEX="$DEV_PUB"
bash "$ROOT/infra/scripts/publish-content.sh" "$WORK/v1" 0000000 >/dev/null

PACK="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1])).pack.url)' "$WORK/v1/manifest.json")"
code() { curl -sk -o /dev/null -w '%{http_code}' "$@"; }
hdr() { curl -sk -D - -o /dev/null "$@" | tr -d '\r' | grep -i "^$1:" | head -1 | cut -d' ' -f2-; }

check "PUT recusado" "$(code -X PUT "$BASE/x")" 405
check "DELETE recusado" "$(code -X DELETE "$BASE/manifest.json")" 405
check "diretorio nao lista (#46)" "$(code "$BASE/")" 404
check "diretorio de packs nao lista" "$(code "$BASE/packs/")" 404
echo '{}' > "$SITE/content-packs/0000000/.manifest.json.tmp"
check "temporario oculto do rsync nao e servido" "$(code "$BASE/.manifest.json.tmp")" 404

MCC="$(curl -sk -D - -o /dev/null "$BASE/manifest.json" | tr -d '\r' | grep -i '^cache-control:' | cut -d' ' -f2-)"
check "manifest com cache curto" "$MCC" "public, max-age=60, must-revalidate"
ETAG="$(curl -sk -D - -o /dev/null "$BASE/manifest.json" | tr -d '\r' | grep -i '^etag:' | cut -d' ' -f2-)"
[ -n "$ETAG" ] && ok "manifest com ETag" || nok "manifest sem ETag"
check "If-None-Match devolve 304" "$(code -H "If-None-Match: $ETAG" "$BASE/manifest.json")" 304
PCC="$(curl -sk -D - -o /dev/null "$BASE/$PACK" | tr -d '\r' | grep -i '^cache-control:' | cut -d' ' -f2-)"
check "pack immutable" "$PCC" "public, max-age=31536000, immutable"
check "Range no pack devolve 206" "$(code -H 'Range: bytes=0-9' "$BASE/$PACK")" 206

# Segunda publicacao da mesma arvore: nada e reenviado, e passa.
if bash "$ROOT/infra/scripts/publish-content.sh" "$WORK/v1" 0000000 >/dev/null 2>&1; then
  ok "republicar a mesma arvore passa"
else
  nok "republicar a mesma arvore falhou"
fi

# Pack com o mesmo nome e bytes diferentes no destino: aborta SEM manifest.
printf 'adulterado' > "$SITE/content-packs/0000000/$PACK"
if bash "$ROOT/infra/scripts/publish-content.sh" "$WORK/v2" 0000000 >/dev/null 2>&1; then
  nok "publicar pack divergente aborta sem manifest (publicou)"
else
  VER="$(curl -sk "$BASE/manifest.json" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).packVersion))')"
  check "publicar pack divergente aborta sem manifest" "$VER" 1
fi

# rsync que falha NA CONFERENCIA (queda de SSH, rrsync recusando uma opcao):
# a conferencia nao pode falhar aberta e deixar o manifest sair.
FAKE="$WORK/rsync-falha-no-dry-run"
cat > "$FAKE" <<'EOT'
#!/bin/sh
for a in "$@"; do [ "$a" = --dry-run ] && { echo "conexao perdida" >&2; exit 255; }; done
exec rsync "$@"
EOT
chmod +x "$FAKE"
if RSYNC_BIN="$FAKE" bash "$ROOT/infra/scripts/publish-content.sh" "$WORK/v2" falha-na-conferencia >/dev/null 2>&1; then
  nok "rsync falhando na conferencia nao aborta (publicou)"
else
  [ -e "$SITE/content-packs/falha-na-conferencia/manifest.json" ] \
    && nok "rsync falhando na conferencia deixou o manifest sair" \
    || ok "rsync falhando na conferencia: manifest nao enviado"
fi

# Manifest que nao verifica: nada sai.
if PACK_PUBKEY_HEX="$(printf 'a%.0s' $(seq 64))" bash "$ROOT/infra/scripts/publish-content.sh" "$WORK/v2" outra >/dev/null 2>&1; then
  nok "manifest com chave errada foi publicado"
else
  [ -e "$SITE/content-packs/outra" ] && nok "chave errada deixou arquivos no destino" || ok "chave errada: nada enviado"
fi

[ "$FAILS" -eq 0 ] || { echo "$FAILS falha(s)" >&2; exit 1; }
echo "content:test verde"
