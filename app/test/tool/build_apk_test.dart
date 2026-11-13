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
  // Fictícia e NÃO a de desenvolvimento: a guarda recusa a de dev (plano B).
  final chaveFicticia = 'a' * 64;
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

  ProcessResult build(String config, [String? abi]) => Process.runSync(
        'bash',
        ['tool/build_apk.sh', 'release', config, ?abi],
        environment: {'FLUTTER': flutterFalso.path},
      );

  File configValido() => File('${tmp.path}/defines.release.json')
    ..writeAsStringSync(jsonEncode({
      'MODEL_URL': huggingFaceExceptionUrl,
      'PACK_MANIFEST_URL': 'https://edge.dominio-do-projeto-a-definir.org/'
          'content-packs/0000000/manifest.json',
      'PACK_SIGNING_KEY_K1': chaveFicticia,
    }));

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
        'PACK_SIGNING_KEY_K1': chaveFicticia,
      }));

    final r = build(config.path);

    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    final args = marcador.readAsStringSync();
    expect(args, contains('build apk --release'));
    expect(args, contains('--dart-define-from-file='));
  });

  // ADR-009, item 5: um build por ABI, com o MESMO versionCode. Por isso
  // nunca --split-per-abi, que o plugin do Flutter sobrescreve com
  // abi*1000 + codigo.
  test('sem abi: arm64, e nunca --split-per-abi', () {
    final r = build(configValido().path);

    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    final args = marcador.readAsStringSync();
    expect(args, contains('--target-platform=android-arm64'));
    expect(args, isNot(contains('--split-per-abi')));
  });

  test('abi arm passa --target-platform=android-arm ao flutter', () {
    final r = build(configValido().path, 'arm');

    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    final args = marcador.readAsStringSync();
    expect(args, contains('--target-platform=android-arm '));
    expect(args, isNot(contains('--split-per-abi')));
  });

  test('abi invalida sai com 64 antes do build', () {
    final r = build(configValido().path, 'x86');

    expect(r.exitCode, 64, reason: '${r.stdout}${r.stderr}');
    expect(marcador.existsSync(), isFalse, reason: 'o build comecou');
  });
}
