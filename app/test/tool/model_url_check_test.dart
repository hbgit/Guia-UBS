/// Guarda de build do `MODEL_URL` (P1-1, ADR-004).
///
/// O app não tem host padrão para o modelo. Isso só é seguro se o build que
/// esqueceu o `--dart-define`, ou que aponta para o lugar errado, falhar ANTES
/// de compilar — e não no aparelho de alguém.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/model_catalog.dart';

import '../../tool/model_url_check.dart';

void main() {
  final sha = activeModel.sha256;
  String problem(String? url, {bool release = true}) =>
      modelUrlProblem(url, release: release, expectedSha256: sha) ?? 'ok';

  test('ausente reprova', () {
    expect(problem(null, release: false), contains('MODEL_URL'));
    expect(problem('', release: false), contains('MODEL_URL'));
  });

  test('relativa reprova', () {
    expect(problem('models/x.gguf', release: false), contains('absoluta'));
  });

  test('http reprova no release', () {
    expect(
      problem('http://10.0.2.2:8081/content-packs/models/gemma-3-1b-it-Q4_K_M-$sha.gguf'),
      contains('https'),
    );
  });

  test('huggingface reprova: o modelo vem do storage proprio', () {
    expect(
      problem('https://huggingface.co/ggml-org/x/gemma-3-1b-it-Q4_K_M-$sha.gguf'),
      contains('storage proprio'),
    );
  });

  test('URL de outro modelo reprova e cita o hash esperado', () {
    expect(
      problem('https://c.exemplo.invalid/content-packs/models/'
          'gemma-3-1b-it-Q4_K_M-${'0' * 64}.gguf'),
      contains(sha),
    );
  });

  test('https no storage proprio, com o hash do catalogo, passa', () {
    expect(
      problem('https://c.exemplo.invalid/content-packs/models/'
          'gemma-3-1b-it-Q4_K_M-$sha.gguf'),
      'ok',
    );
  });

  test('http passa fora do release (emulador em dev)', () {
    expect(
      problem('http://10.0.2.2:8081/content-packs/models/gemma-3-1b-it-Q4_K_M-$sha.gguf',
          release: false),
      'ok',
    );
  });
}
