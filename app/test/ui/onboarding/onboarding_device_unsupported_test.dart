/// APK sem o shim nativo (armeabi-v7a, ADR-009): o onboarding nao oferece
/// download nem pendrive e libera a tela clinica pelas regras.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/model_downloader.dart';
import 'package:guia_ubs/sync/model_provisioning.dart';
import 'package:guia_ubs/ui/onboarding/onboarding_screen.dart';

void main() {
  testWidgets('sem shim: explica, nao oferece download e libera direto',
      (tester) async {
    final tmp = Directory.systemTemp.createTempSync('gubs_onb_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final provisioning = ModelProvisioning(
      artifact: const ModelArtifact(
        url: 'http://espelho.invalid/modelo.gguf',
        sha256: '00',
        sizeBytes: 1,
        fileName: 'modelo.gguf',
      ),
      destinationDirectory: () async => tmp,
      networkClass: () async => NetworkClass.unmetered,
      runtimeSupported: () => false,
    );
    addTearDown(provisioning.dispose);
    var ready = false;

    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(
        provisioning: provisioning,
        onReady: () => ready = true,
        pickLocalModel: () async => null,
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump();

    expect(provisioning.state.blockReason, SetupBlockReason.deviceUnsupported);
    expect(find.text('Assistente indisponível'), findsOneWidget);
    expect(
      find.text('Este aparelho não roda o assistente. O atendimento funciona '
          'sem ele.'),
      findsOneWidget,
    );
    // A frase de sempre do degradado promete baixar quando houver Wi-Fi —
    // promessa falsa num aparelho que nunca vai rodar o modelo.
    expect(find.textContaining('quando houver Wi-Fi'), findsNothing);
    expect(find.text('Baixar agora'), findsNothing);
    expect(find.text('Tentar novamente'), findsNothing);
    expect(find.text('Importar de um pendrive'), findsNothing);
    expect(ready, isTrue);
  });
}
