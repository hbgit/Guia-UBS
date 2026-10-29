#!/usr/bin/env bash
#
# Confere o objeto do modelo PELO EDGE, como o aparelho vai recebe-lo
# (P1-1, #3). O `ResumableDownloader` do app depende de HEAD e de Range
# corretos; este script prova cada um, com o mesmo `Accept-Encoding: gzip` que
# o `HttpClient` do dart:io manda por padrao — se o .gguf saisse comprimido, o
# Content-Length sumiria e o Range deixaria de fazer sentido.
#
# Uso: check-model-endpoint.sh <url-do-.gguf> <sha256> <bytes> [--manifest <url>]
# Sai 0 so se todas as conferencias passarem.

set -uo pipefail

URL="${1:-}"; SHA="${2:-}"; BYTES="${3:-}"
MANIFEST=""
[ "${4:-}" = "--manifest" ] && MANIFEST="${5:-}"
if [ -z "$URL" ] || [ -z "$SHA" ] || [ -z "$BYTES" ]; then
  echo "uso: check-model-endpoint.sh <url> <sha256> <bytes> [--manifest <url>]" >&2
  exit 64
fi
BASE="${URL%/models/*}"
GZ=(-H 'Accept-Encoding: gzip')
falhas=0

ok() { echo "ok      $1"; }
nok() { echo "FALHOU  $1: $2" >&2; falhas=$((falhas + 1)); }
header() { printf '%s\n' "$1" | tr -d '\r' | sed -n "s/^$2: *//Ip" | head -1; }
status() { printf '%s\n' "$1" | tr -d '\r' | sed -n 's/^HTTP\/[0-9.]* \([0-9]*\).*/\1/p' | tail -1; }

h="$(curl -sS -I "${GZ[@]}" "$URL")"
[ "$(status "$h")" = 200 ] && ok "HEAD 200" || nok "HEAD" "status $(status "$h")"
[ "$(header "$h" content-length)" = "$BYTES" ] && ok "HEAD Content-Length $BYTES" \
  || nok "HEAD Content-Length" "$(header "$h" content-length)"
[ "$(header "$h" accept-ranges)" = bytes ] && ok "HEAD Accept-Ranges: bytes" \
  || nok "HEAD Accept-Ranges" "'$(header "$h" accept-ranges)'"
[ -z "$(header "$h" content-encoding)" ] && ok "sem Content-Encoding com Accept-Encoding: gzip" \
  || nok "Content-Encoding" "$(header "$h" content-encoding)"

h="$(curl -sS -o /dev/null -D - "${GZ[@]}" -H 'Range: bytes=100-199' "$URL")"
[ "$(status "$h")" = 206 ] && ok "Range 100-199 → 206" || nok "Range 100-199" "status $(status "$h")"
[ "$(header "$h" content-range)" = "bytes 100-199/$BYTES" ] && ok "Content-Range bytes 100-199/$BYTES" \
  || nok "Content-Range" "'$(header "$h" content-range)'"
[ "$(header "$h" content-length)" = 100 ] && ok "Range Content-Length 100" \
  || nok "Range Content-Length" "$(header "$h" content-length)"

h="$(curl -sS -o /dev/null -D - "${GZ[@]}" -H "Range: bytes=$((BYTES - 1))-" "$URL")"
[ "$(status "$h")" = 206 ] && [ "$(header "$h" content-length)" = 1 ] && ok "Range do ultimo byte → 206, 1 B" \
  || nok "Range do ultimo byte" "status $(status "$h"), $(header "$h" content-length) B"

c="$(curl -sS -o /dev/null -w '%{http_code}' -H "Range: bytes=$BYTES-" "$URL")"
[ "$c" = 416 ] && ok "Range alem do fim → 416" || nok "Range alem do fim" "status $c"

c="$(curl -sS -o /dev/null -w '%{http_code}' -X PUT --data-binary x "$URL")"
case "$c" in 403|405) ok "escrita anonima recusada ($c)" ;; *) nok "escrita anonima" "status $c" ;; esac

c="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE?list-type=2&prefix=models")"
[ "$c" = 403 ] && ok "listagem anonima de models/ recusada" || nok "listagem anonima" "status $c"

# Com a politica certa (models/*), chave vizinha e 403; com `models*`, seria 404.
c="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/models-x/nao-existe")"
[ "$c" = 403 ] && ok "chave vizinha (models-x/) fechada" || nok "chave vizinha models-x/" "status $c"

if [ -n "$MANIFEST" ]; then
  c="$(curl -sS -o /dev/null -w '%{http_code}' "$MANIFEST")"
  [ "$c" = 200 ] && ok "manifest dos packs continua servido" || nok "manifest dos packs" "status $c em $MANIFEST"
fi

got="$(curl -sS "${GZ[@]}" "$URL" | sha256sum | cut -d' ' -f1)"
[ "$got" = "$SHA" ] && ok "download completo pelo edge: sha256 $SHA" || nok "sha256 do download" "$got"

[ "$falhas" -eq 0 ] || { echo "$falhas conferencia(s) falharam" >&2; exit 1; }
