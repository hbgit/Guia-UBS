/// O Notice do Gemma nos DOIS pontos de distribuição do onboarding (ADR-004).
///
/// Todo aparelho que recebe o modelo pelo app passa por um deles antes do
/// primeiro byte (download) ou do primeiro arquivo lido (pendrive). A
/// importação por pendrive também é distribuição.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/model_downloader.dart';
import 'package:guia_ubs/sync/model_provisioning.dart';
import 'package:guia_ubs/ui/more/legal_document.dart';
import 'package:guia_ubs/ui/onboarding/onboarding_screen.dart';
import 'package:guia_ubs/ui/theme/gubs_metrics.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('gubs_onb_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<ModelProvisioning> pump(
    WidgetTester tester, {
    required NetworkClass rede,
    Future<File?> Function()? picker,
    VoidCallback? abrirTermos,
  }) async {
    final p = ModelProvisioning(
      artifact: const ModelArtifact(
        url: 'https://exemplo.invalid/models/m.gguf',
        sha256: '00',
        sizeBytes: 1,
        fileName: 'modelo.gguf',
      ),
      destinationDirectory: () async => tmp,
      networkClass: () async => rede,
    );
    addTearDown(p.dispose);
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(
        provisioning: p,
        onReady: () {},
        pickLocalModel: picker,
        openGemmaTerms: abrirTermos,
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    return p;
  }

  testWidgets('download: Notice e Termos do Gemma antes de Baixar agora',
      (tester) async {
    var abriu = 0;
    final p = await pump(tester,
        rede: NetworkClass.unmetered, abrirTermos: () => abriu++);
    expect(p.state.stage, SetupStage.awaitingConsent);

    final notice = find.text(gemmaNoticeLine);
    final termos = find.byKey(const ValueKey('onboarding-gemma-terms'));
    final baixar = find.text('Baixar agora');
    expect(notice, findsOneWidget);
    expect(termos, findsOneWidget);
    expect(tester.getTopLeft(notice).dy, lessThan(tester.getTopLeft(baixar).dy),
        reason: 'o aviso vem antes do botao que inicia a distribuicao');
    expect(tester.getSize(termos).height, greaterThanOrEqualTo(minTouchTarget));

    await tester.ensureVisible(termos);
    await tester.tap(termos);
    expect(abriu, 1);
  });

  testWidgets('pendrive: Notice e Termos do Gemma antes de escolher o arquivo',
      (tester) async {
    var escolhas = 0;
    var abriu = 0;
    await pump(
      tester,
      rede: NetworkClass.none,
      picker: () async {
        escolhas++;
        return null;
      },
      abrirTermos: () => abriu++,
    );

    await tester.ensureVisible(find.text('Importar de um pendrive'));
    await tester.tap(find.text('Importar de um pendrive'));
    await tester.pump();

    expect(escolhas, 0, reason: 'o seletor so abre depois do aviso');
    expect(find.text(gemmaNoticeLine), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('onboarding-gemma-terms')));
    await tester.tap(find.byKey(const ValueKey('onboarding-gemma-terms')));
    expect(abriu, 1);

    await tester.ensureVisible(find.text('Escolher arquivo'));
    await tester.tap(find.text('Escolher arquivo'));
    await tester.pump();
    expect(escolhas, 1);
  });

  testWidgets('pendrive: a confirmacao cabe no teto de elementos e tem saida',
      (tester) async {
    await pump(tester,
        rede: NetworkClass.none, picker: () async => null, abrirTermos: () {});
    await tester.ensureVisible(find.text('Importar de um pendrive'));
    await tester.tap(find.text('Importar de um pendrive'));
    await tester.pump();

    final acionaveis = find.byWidgetPredicate((w) => w is ButtonStyleButton);
    expect(acionaveis.evaluate().length, lessThanOrEqualTo(maxElementsPerScreen));

    await tester.ensureVisible(find.text('Voltar'));
    await tester.tap(find.text('Voltar'));
    await tester.pump();
    expect(find.text('Importar de um pendrive'), findsOneWidget);
  });
}
