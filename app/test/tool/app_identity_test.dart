/// O `applicationId` é permanente depois da 1ª publicação na Play (ADR-009,
/// item 1). Este teste fixa o valor e impede que o id de exemplo volte por um
/// arquivo esquecido.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/model_sync_scheduler.dart';
import 'package:guia_ubs/sync/pack_sync_scheduler.dart';

const String appId = 'br.com.prismrr.guiasaude';

void main() {
  test('o applicationId e o namespace sao $appId', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('applicationId = "$appId"'));
    expect(gradle, contains('namespace = "$appId"'));
  });

  test('nenhum arquivo do app cita o id de exemplo', () {
    final achados = <String>[];
    final alvos = <FileSystemEntity>[
      Directory('lib'),
      Directory('tool'),
      Directory('android/app/src'),
      File('android/app/build.gradle.kts'),
    ];
    for (final alvo in alvos) {
      final arquivos = alvo is Directory
          ? alvo.listSync(recursive: true).whereType<File>()
          : [alvo as File];
      for (final f in arquivos) {
        final String texto;
        try {
          texto = f.readAsStringSync();
        } on FileSystemException {
          continue; // binário (ícones)
        }
        if (texto.contains('br.gov.exemplo')) achados.add(f.path);
      }
    }
    expect(achados, isEmpty);
  });

  test('tarefas do WorkManager usam o prefixo do id', () {
    expect(packSyncTaskName, startsWith('$appId.'));
    expect(modelSyncTaskName, startsWith('$appId.'));
  });
}
