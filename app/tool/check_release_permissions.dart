/// Confere que o APK release pede exatamente as permissões da lista fechada.
///
/// Lê o manifest mesclado de release, que só existe depois do build. Roda
/// localmente, de dentro de `app/`, até a #14 levar o build de release ao CI:
///
/// ```sh
/// flutter build apk --release --target-platform=android-arm64
/// dart run tool/check_release_permissions.dart
/// ```
///
/// Saída: 0 lista fechada; 1 permissão a mais ou a menos; 2 manifest mesclado
/// ou fonte não encontrados; 3 manifest mesclado não reflete a fonte (build por
/// refazer); 64 uso.
library;

import 'dart:io';

import 'release_permissions.dart';

Future<void> main(List<String> args) async {
  exit(runCheck(args, out: stdout, err: stderr));
}

/// Corpo do CLI, separado de [main] para ser testado sem processo.
int runCheck(
  List<String> args, {
  String sourcePath = mainManifestSourcePath,
  required StringSink out,
  required StringSink err,
}) {
  if (args.length > 1) {
    err.writeln('uso: check_release_permissions.dart [AndroidManifest.xml]');
    return 64;
  }

  // Os dois caminhos padrão são relativos a `app/`. Fora dele, pular o guarda
  // de fonte em silêncio deixaria passar justamente o build velho.
  final source = File(sourcePath);
  if (!source.existsSync()) {
    err
      ..writeln('FALHA  fonte do manifest não encontrada em $sourcePath.')
      ..writeln('       Rode de dentro de app/ (diretório atual: '
          '${Directory.current.path}).');
    return 2;
  }

  final path = args.isEmpty ? defaultReleaseManifestPath : args.first;
  final merged = File(path);
  if (!merged.existsSync()) {
    err
      ..writeln('FALHA  manifest mesclado de release não encontrado em $path.')
      ..writeln('       Rode antes: flutter build apk --release '
          '--target-platform=android-arm64')
      ..writeln('       (caminho interno do AGP 9.0.1; se o AGP mudou, confira '
          "com find build/app/intermediates -path '*release*' "
          '-name AndroidManifest.xml)');
    return 2;
  }

  final declared = declaredPermissions(merged.readAsStringSync());

  // Sem isto, editar a fonte e esquecer o build deixaria o guarda verde
  // olhando para o manifest de antes da edição.
  if (isStale(
    source: declaredPermissions(source.readAsStringSync()),
    merged: declared,
  )) {
    err.writeln('FALHA  manifest mesclado não reflete $sourcePath; '
        'refaça o build de release.');
    return 3;
  }

  final diff = diffPermissions(declared);
  if (!diff.isClean) {
    err.writeln('FALHA  permissões do release fora da lista fechada:');
    for (final permission in diff.unexpected.toList()..sort()) {
      err.writeln('  + $permission  '
          '(fora da lista; LGPD-RF01 exige justificar — ver #28)');
    }
    for (final permission in diff.missing.toList()..sort()) {
      err.writeln('  - $permission  (esperada e ausente)');
    }
    return 1;
  }

  out.writeln('ok  ${releasePermissionAllowlist.length} permissões, '
      'lista fechada (LGPD-RF01)');
  return 0;
}
