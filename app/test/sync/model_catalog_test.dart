/// O catálogo do modelo: identidade versionada no código, origem no build.
///
/// O host saiu do código na P1-1 (#3, ADR-004): o modelo vem do storage do
/// próprio projeto, e a URL entra por `--dart-define=MODEL_URL`. O que fica
/// versionado é o que autentica o arquivo — hash, tamanho e nome.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/model_catalog.dart';

void main() {
  test('o catalogo nao carrega host nenhum', () {
    final fonte = File('lib/sync/model_catalog.dart').readAsStringSync();

    expect(fonte, isNot(contains('huggingface.co')));
    expect(RegExp(r'https?://').hasMatch(fonte), isFalse,
        reason: 'host no catalogo vira padrao escondido: o build que esqueceu '
            'o --dart-define sairia baixando de um lugar que ninguem escolheu');
  });

  test('sem --dart-define, o artefato se declara nao configurado', () {
    // `flutter test` roda sem MODEL_URL: este e o build "esquecido".
    expect(modelUrl, isEmpty);
    expect(activeModel.isConfigured, isFalse);
  });

  test('a identidade do modelo e o SHA-256 e o nome, nao a URL', () {
    expect(activeModel.sha256,
        '8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135');
    expect(activeModel.sizeBytes, 806058240);
    expect(activeModel.fileName, 'gemma-3-1b-q4.gguf');
  });
}
