/// Contraste WCAG 2.2 AA de cada par de cores que o app realmente usa (RNF-06).
///
/// Este teste existe porque contraste é o tipo de requisito que passa na
/// revisão visual de quem tem visão boa, monitor bom e sala escura — e reprova
/// no aparelho de quem vai usar o app: tela riscada, sol batendo, presbiopia.
/// A razão de contraste é calculável, então ela é verificada, não julgada.
///
/// Limiares da WCAG 2.2:
/// * **4,5:1** texto normal (AA);
/// * **3:1** texto grande (≥ 24 px, ou ≥ 18,66 px em negrito) e componentes
///   de interface — bordas, ícones, indicadores.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/triage/domain/severity.dart';
import 'package:guia_ubs/ui/theme/gubs_colors.dart';

import '../../support/wcag.dart';

void main() {
  test('a função de contraste bate com os valores canônicos da WCAG', () {
    // Sem esta âncora, um erro na fórmula tornaria todos os testes abaixo
    // aprovações vazias.
    expect(
      contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21, 0.01),
    );
    expect(
      contrastRatio(const Color(0xFF767676), const Color(0xFFFFFFFF)),
      closeTo(4.54, 0.02),
    );
    expect(contrastRatio(const Color(0xFF123456), const Color(0xFF123456)), 1);
  });

  for (final (name, c) in [
    ('claro', GubsColors.light),
    ('escuro', GubsColors.dark),
  ]) {
    group('tema $name', () {
      test('texto principal sobre cada fundo atinge AA', () {
        for (final (surfaceName, surface) in [
          ('ground', c.ground),
          ('surface', c.surface),
          ('surfaceAlt', c.surfaceAlt),
        ]) {
          expect(
            contrastRatio(c.ink, surface),
            greaterThanOrEqualTo(aaNormalText),
            reason: 'ink sobre $surfaceName',
          );
        }
      });

      test('texto secundário atinge AA — ele carrega instrução, não enfeite',
          () {
        // `inkSoft` é usado em subtítulos do tipo "Toque na parte do corpo".
        // Se ele falhar, some justamente a instrução de como usar a tela.
        for (final (surfaceName, surface) in [
          ('ground', c.ground),
          ('surface', c.surface),
        ]) {
          expect(
            contrastRatio(c.inkSoft, surface),
            greaterThanOrEqualTo(aaNormalText),
            reason: 'inkSoft sobre $surfaceName',
          );
        }
      });

      test('as três cores semânticas se destacam do fundo do app', () {
        // Componente de interface: 3:1. É o mínimo para que a COR — não o
        // texto — comunique rotina, emergência ou informação.
        for (final (semantic, color) in [
          ('verde/UBS', c.green),
          ('vermelho/emergência', c.red),
          ('azul/informação', c.blue),
          ('âmbar/atenção', c.amber),
        ]) {
          expect(
            contrastRatio(color, c.ground),
            greaterThanOrEqualTo(aaLargeTextOrUi),
            reason: '$semantic sobre o fundo do app',
          );
          expect(
            contrastRatio(color, c.surface),
            greaterThanOrEqualTo(aaLargeTextOrUi),
            reason: '$semantic sobre cartão',
          );
        }
      });

      test('texto sobre botão preenchido de cada severidade atinge AA', () {
        for (final severity in GubsSeverity.values) {
          final role = c.forSeverity(severity);
          expect(
            contrastRatio(role.onAccent, role.accent),
            greaterThanOrEqualTo(aaNormalText),
            reason: 'texto sobre o preenchimento de ${severity.name}',
          );
        }
      });

      test('texto principal sobre o fundo suave de cada severidade atinge AA',
          () {
        // O cartão de resultado é `ink` sobre `background`. É o texto que a
        // pessoa lê depois de decidir que quer ler.
        for (final severity in GubsSeverity.values) {
          final role = c.forSeverity(severity);
          expect(
            contrastRatio(c.ink, role.background),
            greaterThanOrEqualTo(aaNormalText),
            reason: 'ink sobre o fundo suave de ${severity.name}',
          );
        }
      });

      test('o indicador de foco é visível sobre os fundos', () {
        expect(
          contrastRatio(c.focus, c.ground),
          greaterThanOrEqualTo(aaLargeTextOrUi),
        );
        expect(
          contrastRatio(c.focus, c.surface),
          greaterThanOrEqualTo(aaLargeTextOrUi),
        );
      });

      test('verde e vermelho são distinguíveis um do outro por luminância',
          () {
        // Cerca de 5% dos homens têm deficiência de visão de cores vermelho-
        // verde — e a semântica deste app é literalmente verde contra
        // vermelho. Se as duas tiverem a mesma luminância, quem não distingue
        // matiz não distingue nada. Não é limiar da WCAG; é o mínimo para que
        // a diferença sobreviva em escala de cinza.
        expect(
          contrastRatio(c.green, c.red),
          greaterThanOrEqualTo(1.3),
          reason: 'verde e vermelho ficam idênticos em escala de cinza',
        );
      });
    });
  }
}
