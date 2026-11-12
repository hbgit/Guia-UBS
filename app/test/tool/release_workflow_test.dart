/// O `app-release.yml` tem DOIS caminhos de build: os APKs passam pelo
/// `tool/build_apk.sh`, que roda a guarda dos defines; o AAB chama o
/// `flutter build appbundle` direto. Sem um passo de guarda antes do AAB, um
/// defines com a chave de desenvolvimento chegaria à Play (plano B, Task 1).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflow = File(
    '../.github/workflows/app-release.yml',
  ).readAsStringSync();

  test('a guarda roda antes do AAB', () {
    final guarda = workflow.indexOf('tool/model_url_check.dart');
    final aab = workflow.indexOf('flutter build appbundle');
    expect(aab, greaterThan(-1));
    expect(guarda, greaterThan(-1), reason: 'nenhum passo chama a guarda');
    expect(guarda, lessThan(aab));
  });

  test('o ensaio define PACK_SIGNING_KEY_K1', () {
    final heredoc = RegExp(
      r"cat > config/defines\.release\.json <<'?EOF'?([\s\S]*?)EOF",
    ).firstMatch(workflow);
    expect(heredoc, isNotNull);
    expect(heredoc!.group(1), contains('PACK_SIGNING_KEY_K1'));
  });
}
