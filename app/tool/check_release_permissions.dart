/// Confere que o APK release pede exatamente as permissões da lista fechada.
///
/// Lê o manifest mesclado de release, que só existe depois do build. Roda
/// localmente até a #14 levar o build de release ao CI:
///
/// ```sh
/// flutter build apk --release --target-platform=android-arm64
/// dart run tool/check_release_permissions.dart
/// ```
///
/// Saída: 0 lista fechada; 1 permissão a mais ou a menos; 2 manifest mesclado
/// ausente; 3 manifest mesclado não reflete a fonte (build por refazer); 64 uso.
library;

import 'dart:io';

import 'release_permissions.dart';

Future<void> main(List<String> args) async {
  if (args.length > 1) {
    stderr.writeln('uso: check_release_permissions.dart [AndroidManifest.xml]');
    exit(64);
  }

  final path = args.isEmpty ? defaultReleaseManifestPath : args.first;
  final merged = File(path);
  if (!merged.existsSync()) {
    stderr
      ..writeln('FALHA  manifest mesclado de release não encontrado em $path.')
      ..writeln('       Rode antes: flutter build apk --release '
          '--target-platform=android-arm64')
      ..writeln('       (caminho interno do AGP 9.0.1; se o AGP mudou, confira '
          "com find build/app/intermediates -path '*release*' "
          '-name AndroidManifest.xml)');
    exit(2);
  }

  final declared = declaredPermissions(merged.readAsStringSync());

  // Sem isto, editar a fonte e esquecer o build deixaria o guarda verde
  // olhando para o manifest de antes da edição.
  final source = File(mainManifestSourcePath);
  if (source.existsSync() &&
      isStale(
        source: declaredPermissions(source.readAsStringSync()),
        merged: declared,
      )) {
    stderr.writeln('FALHA  manifest mesclado não reflete '
        '$mainManifestSourcePath; refaça o build de release.');
    exit(3);
  }

  final diff = diffPermissions(declared);
  if (!diff.isClean) {
    stderr.writeln('FALHA  permissões do release fora da lista fechada:');
    for (final permission in diff.unexpected.toList()..sort()) {
      stderr.writeln('  + $permission  '
          '(fora da lista; LGPD-RF01 exige justificar — ver #28)');
    }
    for (final permission in diff.missing.toList()..sort()) {
      stderr.writeln('  - $permission  (esperada e ausente)');
    }
    exit(1);
  }

  stdout.writeln('ok  ${releasePermissionAllowlist.length} permissões, '
      'lista fechada (LGPD-RF01)');
}
