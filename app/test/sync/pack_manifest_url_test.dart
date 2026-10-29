/// O manifest de conteúdo não tem host padrão (#45).
///
/// Antes, `PACK_MANIFEST_URL` caía em `http://127.0.0.1:9000/...`: um release
/// construído sem o define buscava conteúdo no próprio aparelho, falhava em
/// silêncio e a frota nunca recebia correção clínica.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/pack_background_sync.dart';

void main() {
  test('o app nao carrega host padrao para o manifest', () {
    final fonte = File('lib/sync/pack_background_sync.dart').readAsStringSync();

    expect(fonte, isNot(contains('127.0.0.1')));
    expect(RegExp(r'https?://').hasMatch(fonte), isFalse);
    // `flutter test` roda sem PACK_MANIFEST_URL: este e o build "esquecido".
    expect(packManifestUrl, isEmpty);
  });
}
