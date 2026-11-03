#!/usr/bin/env bash
#
# Build do APK com MODEL_URL e PACK_MANIFEST_URL conferidos ANTES de compilar
# (P1-1/ADR-004 e #45).
#
# O catalogo do modelo nao tem host padrao: sem --dart-define, o app compila e
# sai sem assistente. Este script e o caminho de build que nao deixa isso
# acontecer por engano.
#
# Uso (de dentro de app/):
#   tool/build_apk.sh <debug|profile|release> [config] [arm64|arm]
#
# `abi` padrao: arm64. Um build por ABI, nunca --split-per-abi: com o split, o
# plugin gradle do Flutter sobrescreve o versionCode com abi*1000 + codigo, e
# os artefatos da mesma tag sairiam com numeros diferentes (ADR-009, item 5).
# `arm` (armeabi-v7a) sai SEM o shim nativo: so o RuleOnlyEngine.
#
# `config` padrao: config/defines.<modo>.json (modelo em
# config/defines.example.json; os reais nao sao versionados). Para rodar sem
# build: flutter run --dart-define-from-file=config/defines.debug.json

set -euo pipefail

# Substituivel nos testes (test/tool/build_apk_test.dart), como o DOCKER do
# infra/scripts/publish-model.sh.
FLUTTER="${FLUTTER:-flutter}"

MODE="${1:-}"
case "$MODE" in
  debug|profile|release) ;;
  *) echo "uso: tool/build_apk.sh <debug|profile|release> [config]" >&2; exit 64 ;;
esac
CONFIG="${2:-config/defines.$MODE.json}"
ABI="${3:-arm64}"
case "$ABI" in
  arm64|arm) ;;
  *) echo "abi invalida: $ABI (use arm64 ou arm)" >&2; exit 64 ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ ! -f "$CONFIG" ]; then
  echo "FALHOU  $CONFIG nao existe (copie config/defines.example.json)" >&2
  exit 1
fi

dart run tool/model_url_check.dart --config "$CONFIG" --mode "$MODE"
"$FLUTTER" build apk "--$MODE" "--target-platform=android-$ABI" \
  "--dart-define-from-file=$CONFIG"
