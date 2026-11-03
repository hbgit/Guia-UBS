/// `shimSupported`: a pergunta "este aparelho roda o modelo?" que o
/// provisionamento e o worker fazem antes de qualquer download (ADR-009).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/triage/engine/llama_bindings.dart';

void main() {
  test('sem nenhum candidato carregavel, o aparelho nao suporta o shim', () {
    expect(
      shimSupported(candidates: const ['libgubs_llama_inexistente.so']),
      isFalse,
    );
  });
}
