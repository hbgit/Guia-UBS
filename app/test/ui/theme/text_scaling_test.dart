/// A composicao entre a escala de fonte do sistema e a escolhida no app.
///
/// Funcoes puras, testadas fora de qualquer widget: a regra "multiplica e
/// limita em 2x" e decisao de produto, e precisa continuar verdadeira mesmo
/// que a tela de ajustes seja reescrita.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/ui/theme/text_scaling.dart';

void main() {
  group('compor com o sistema, nao substituir', () {
    test('sistema em 1x: vale a escolha do app', () {
      expect(
        gubsTextScaler(TextScaler.noScaling, 1.3).scale(16),
        closeTo(16 * 1.3, 0.01),
      );
    });

    test('sistema ampliado MULTIPLICA a escolha do app', () {
      // Quem ja pediu letra grande no aparelho inteiro nao pode ver a letra
      // ENCOLHER ao abrir o app em 1x.
      expect(
        gubsTextScaler(TextScaler.linear(1.5), 1.0).scale(16),
        closeTo(24, 0.01),
      );
    });

    test('a escolha do app nunca reduz o que o sistema pediu', () {
      final sistema = TextScaler.linear(1.5);
      for (final escolha in [1.0, 1.3, 1.6]) {
        expect(
          gubsTextScaler(sistema, escolha).scale(16),
          greaterThanOrEqualTo(sistema.scale(16) - 0.01),
          reason: 'escolha $escolha encolheu a fonte de quem pediu 1,5x',
        );
      }
    });
  });

  group('o teto de 2x', () {
    test('corta o produto que passaria do verificado', () {
      // 1,5 x 1,6 = 2,4. Nenhuma tela deste app foi verificada acima de 2x.
      expect(
        gubsTextScaler(TextScaler.linear(1.5), 1.6).scale(16),
        closeTo(32, 0.01),
      );
      expect(maxTextScale, 2.0);
    });

    test('nao corta o que cabe', () {
      // 1,2 x 1,6 = 1,92: cabe, e o app entrega a ampliacao inteira.
      expect(textScaleIsCapped(TextScaler.noScaling, 1.6), isFalse);
      expect(textScaleIsCapped(TextScaler.linear(1.2), 1.6), isFalse);
      // 1,3 x 1,6 = 2,08: passa do verificado, e o teto entra.
      expect(textScaleIsCapped(TextScaler.linear(1.3), 1.6), isTrue);
    });

    test('a tela consegue AVISAR que cortou', () {
      // Sem isto, tocar "Muito grande" nao mudaria nada e pareceria defeito.
      expect(textScaleIsCapped(TextScaler.linear(2.0), 1.3), isTrue);
    });
  });

  test('o fator do sistema e lido em torno do corpo de texto', () {
    // O Android 14 escala de forma NAO linear; linearizamos em 16 px, que e o
    // tamanho que domina estas telas. A aproximacao esta assumida no codigo.
    expect(systemTextScaleFactor(TextScaler.linear(1.75)), closeTo(1.75, 0.001));
    expect(systemTextScaleFactor(TextScaler.noScaling), closeTo(1.0, 0.001));
  });
}
