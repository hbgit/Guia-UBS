#!/usr/bin/env bash
#
# Build do APK com o MODEL_URL conferido ANTES de compilar (P1-1, ADR-004).
#
# O catalogo do modelo nao tem host padrao: sem --dart-define, o app compila e
# sai sem assistente. Este script e o caminho de build que nao deixa isso
# acontecer por engano.
#
# Uso (de dentro de app/):
#   tool/build_apk.sh <debug|profile|release> [config]
#
# `config` padrao: config/defines.<modo>.json (modelo em
# config/defines.example.json; os reais nao sao versionados). Para rodar sem
# build: flutter run --dart-define-from-file=config/defines.debug.json

set -euo pipefail

MODE="${1:-}"
case "$MODE" in
  debug|profile|release) ;;
  *) echo "uso: tool/build_apk.sh <debug|profile|release> [config]" >&2; exit 64 ;;
esac
CONFIG="${2:-config/defines.$MODE.json}"

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ ! -f "$CONFIG" ]; then
  echo "FALHOU  $CONFIG nao existe (copie config/defines.example.json)" >&2
  exit 1
fi

dart run tool/model_url_check.dart --config "$CONFIG" --mode "$MODE"
flutter build apk "--$MODE" --target-platform=android-arm64 \
  "--dart-define-from-file=$CONFIG"
