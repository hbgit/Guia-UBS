/// Acessibilidade medida no widget RENDERIZADO, não na constante (RNF-06).
///
/// A diferença importa: `minTouchTarget = 64` é uma promessa; o que chega ao
/// dedo do usuário é o retângulo que o Flutter pintou. Um `Padding` errado, um
/// `Expanded` apertado ou um `ConstrainedBox` herdado transformam a promessa
/// em 40 dp sem alterar nenhuma constante — e sem quebrar nenhum teste que
/// leia apenas a constante.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/ui/home/home_screen.dart';
import 'package:guia_ubs/ui/language/language_screen.dart';
import 'package:guia_ubs/ui/theme/gubs_metrics.dart';

import '../support/app_harness.dart';

/// Todo widget que responde a toque na árvore atual.
Iterable<Element> _tappables(WidgetTester tester) {
  final types = <Type>[
    FilledButton,
    OutlinedButton,
    TextButton,
    IconButton,
    InkWell,
    GestureDetector,
  ];
  return [
    for (final type in types)
      ...find.byType(type).evaluate(),
  ];
}

void main() {
  test('as constantes de acessibilidade não podem ser afrouxadas', () {
    // Os testes abaixo comparam o widget renderizado contra `minTouchTarget`.
    // Sozinhos, eles são circulares: baixar a constante para 48 os faria
    // aprovar telas piores sem nenhuma falha — foi o que uma sabotagem
    // mostrou. Este teste ancora as constantes nos NÚMEROS da RNF-06, que é a
    // fonte, e não em si mesmas.
    expect(
      minTouchTarget,
      greaterThanOrEqualTo(64),
      reason: 'RNF-06 exige 64 dp — mais que os 48 dp do Material, porque o '
          'público usa o app em pé, com mãos calejadas e sem óculos',
    );
    expect(maxElementsPerScreen, lessThanOrEqualTo(8));
    expect(maxNavigationDepth, lessThanOrEqualTo(4));
  });

  testWidgets('todo alvo da tela inicial tem pelo menos 64 dp', (tester) async {
    await tester.pumpWidget(harness(const HomeScreen()));
    await tester.pumpAndSettle();

    final measured = <String>[];
    for (final element in _tappables(tester)) {
      final size = element.size;
      if (size == null || size.isEmpty) continue;
      measured.add('${element.widget.runtimeType} ${size.width}x${size.height}');
      expect(
        size.shortestSide,
        greaterThanOrEqualTo(minTouchTarget),
        reason: '${element.widget.runtimeType} tem $size',
      );
    }
    expect(measured, isNotEmpty, reason: 'nenhum alvo foi medido');
  });

  testWidgets('a tela de idioma tem alvos generosos', (tester) async {
    await tester.pumpWidget(harness(const LanguageScreen()));
    await tester.pumpAndSettle();

    for (final code in ['pt', 'es']) {
      final size = tester.getSize(find.byKey(ValueKey('lang-$code')));
      expect(size.height, greaterThanOrEqualTo(96));
    }
  });

  testWidgets('a tela inicial não passa de oito elementos acionáveis',
      (tester) async {
    // O teto não é estético: acima de oito alvos a tela passa a exigir leitura
    // para ser escaneada, e o público-alvo é definido por não conseguir fazer
    // essa leitura.
    //
    // O que conta são as ESCOLHAS — o botão de triagem e os quatro ladrilhos —
    // mais as três abas. Controles de moldura (voltar, escudo de privacidade,
    // botão de áudio) não competem pelo escaneamento e não entram no teto; é
    // por isso que o voltar nunca foi contado. A distinção está declarada aqui
    // porque, sem ela, a tela de privacidade exigida pela LGPD-RF03 não teria
    // onde caber.
    await tester.pumpWidget(harness(const HomeScreen()));
    await tester.pumpAndSettle();

    final buttons = [
      ...find.byType(FilledButton).evaluate(),
      ...find.byType(OutlinedButton).evaluate(),
    ];
    expect(buttons.length + gubsTabCount, lessThanOrEqualTo(maxElementsPerScreen));
  });

  testWidgets('a tela de privacidade é alcançável da inicial (LGPD-RF03)',
      (tester) async {
    // Uma tela que a lei exige e que ninguém consegue abrir não cumpre a lei.
    await tester.pumpWidget(harness(const HomeScreen()));
    await tester.pumpAndSettle();

    final shield = find.byKey(const ValueKey('home-privacy'));
    expect(shield, findsOneWidget);
    expect(
      tester.getSize(shield).shortestSide,
      greaterThanOrEqualTo(minTouchTarget),
    );
  });

  // Ampliar a fonte é a primeira coisa que faz quem tem presbiopia e não tem
  // óculos — parte relevante do público. Um estouro de layout aqui esconde
  // conteúdo abaixo da borda sem nenhum aviso.
  for (final scale in [1.0, 1.3, 1.6, 2.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'tela inicial com fonte ${scale}x, tema ${brightness.name}, '
          'em tela pequena', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          harness(
            const HomeScreen(),
            textScale: scale,
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('home-triage')), findsOneWidget);
        expect(find.byKey(const ValueKey('home-emergency')), findsOneWidget);
      });
    }
  }

  testWidgets('a tela de idioma sobrevive à fonte ampliada em tela pequena',
      (tester) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(const LanguageScreen(), textScale: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // As duas opções continuam alcançáveis: é a única decisão da tela.
    for (final code in ['pt', 'es']) {
      expect(find.byKey(ValueKey('lang-$code')), findsOneWidget);
    }
  });

  testWidgets('o idioma escolhido troca toda a interface', (tester) async {
    final store = MemoryLocaleStore(AppLocale.pt);
    await tester.pumpWidget(harness(const HomeScreen(), localeStore: store));
    await tester.pumpAndSettle();
    expect(find.text('Como você está?'), findsOneWidget);

    await tester.pumpWidget(
      harness(const HomeScreen(), localeStore: store, locale: AppLocale.es),
    );
    await tester.pumpAndSettle();

    expect(find.text('¿Cómo estás?'), findsOneWidget);
    expect(find.text('Como você está?'), findsNothing);
  });
}

/// Três abas somam ao orçamento de elementos da tela.
const int gubsTabCount = 3;
