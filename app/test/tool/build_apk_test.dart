/// `tool/build_apk.sh` de verdade (#45): o guarda roda ANTES do `flutter
/// build`. Um `flutter` falso, apontado por `FLUTTER`, deixa um marcador com
/// os argumentos — se o marcador existir, o build teria começado.
@TestOn('linux || mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/model_url_check.dart';

void main() {
  late Directory tmp;
  late File marcador;
  late File flutterFalso;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gubs_build_');
    marcador = File('${tmp.path}/flutter-chamado');
    flutterFalso = File('${tmp.path}/flutter')
      ..writeAsStringSync('#!/bin/sh\necho "\$@" > "${marcador.path}"\n');
    Process.runSync('chmod', ['+x', flutterFalso.path]);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ProcessResult build(String config) => Process.runSync(
        'bash',
        ['tool/build_apk.sh', 'release', config],
        environment: {'FLUTTER': flutterFalso.path},
      );

  test('release com o defines de exemplo sai com erro antes do flutter build',
      () {
    final r = build('config/defines.example.json');

    expect(r.exitCode, isNot(0), reason: '${r.stdout}${r.stderr}');
    expect('${r.stderr}', contains('PACK_MANIFEST_URL'));
    expect(marcador.existsSync(), isFalse, reason: 'o build comecou');
  });

  test('release valido chama flutter build com o define', () {
    // Fictício; o teste não faz rede. Trocar pelo domínio real quando a #55
    // decidir.
    final config = File('${tmp.path}/defines.release.json')
      ..writeAsStringSync(jsonEncode({
        'MODEL_URL': huggingFaceExceptionUrl,
        'PACK_MANIFEST_URL': 'https://edge.dominio-do-projeto-a-definir.org/'
            'content-packs/0000000/manifest.json',
      }));

    final r = build(config.path);

    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    final args = marcador.readAsStringSync();
    expect(args, contains('build apk --release'));
    expect(args, contains('--dart-define-from-file='));
  });
}
