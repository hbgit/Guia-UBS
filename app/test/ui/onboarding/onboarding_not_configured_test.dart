/// Build sem `MODEL_URL` (P1-1, ADR-004): o onboarding diz que não há de onde
/// baixar e oferece só as saídas que funcionam.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/model_downloader.dart';
import 'package:guia_ubs/sync/model_provisioning.dart';
import 'package:guia_ubs/ui/onboarding/onboarding_screen.dart';

void main() {
  testWidgets('sem origem: explica, esconde "tentar novamente" e deixa seguir',
      (tester) async {
    final tmp = Directory.systemTemp.createTempSync('gubs_onb_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final provisioning = ModelProvisioning(
      artifact: const ModelArtifact(
        url: '',
        sha256: '00',
        sizeBytes: 1,
        fileName: 'modelo.gguf',
      ),
      destinationDirectory: () async => tmp,
      networkClass: () async => NetworkClass.unmetered,
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
    // `checking` anima um indicador: `pumpAndSettle` nao voltaria.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(provisioning.state.blockReason, SetupBlockReason.notConfigured);
    expect(find.text('Assistente indisponível'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsNothing);
    expect(find.text('Importar de um pendrive'), findsOneWidget);

    await tester.ensureVisible(find.text('Usar sem a IA assistente'));
    await tester.tap(find.text('Usar sem a IA assistente'));
    await tester.pump();
    await tester.pump();

    expect(provisioning.state.stage, SetupStage.readyDegraded);
    expect(ready, isTrue);
  });
}
