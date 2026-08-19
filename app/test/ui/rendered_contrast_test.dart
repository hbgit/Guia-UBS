/// Contraste medido no texto RENDERIZADO, não na paleta.
///
/// `contrast_test.dart` verifica os pares que a paleta declara. Este verifica
/// os pares que os widgets realmente produzem — e a diferença não é acadêmica:
/// no aparelho, o rótulo do botão principal saiu com `ink` claro sobre o verde
/// claro do tema escuro, **1,94:1**. Nenhum par da paleta previa `ink`×`green`;
/// quem o inventou foi o widget, ao carregar uma cor explícita do `textTheme`
/// que venceu o `foregroundColor` do botão.
///
/// Moral: verificar a paleta prova que as cores escolhidas são boas. Só
/// verificar o renderizado prova que são elas que chegam à tela.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/ui/home/home_screen.dart';
import 'package:guia_ubs/ui/theme/gubs_colors.dart';

import '../support/app_harness.dart';
import '../support/wcag.dart';

/// Cor com que o texto foi de fato pintado.
Color? _renderedColor(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
  return paragraph.text.style?.color;
}

/// Fundo efetivo de um botão.
Color? _buttonBackground(WidgetTester tester, Key key) {
  final button = tester.widget<ButtonStyleButton>(find.byKey(key));
  final style = button.style ?? const ButtonStyle();
  return style.backgroundColor?.resolve(<WidgetState>{});
}

void main() {
  for (final (name, brightness, colors) in [
    ('claro', Brightness.light, GubsColors.light),
    ('escuro', Brightness.dark, GubsColors.dark),
  ]) {
    testWidgets('tema $name: o rótulo do botão de triagem é legível sobre o verde',
        (tester) async {
      await tester.pumpWidget(
        harness(const HomeScreen(), brightness: brightness),
      );
      await tester.pumpAndSettle();

      final background =
          _buttonBackground(tester, const ValueKey('home-triage'))!;
      final foreground = _renderedColor(tester, 'Estou com sintomas')!;

      expect(
        background,
        colors.green,
        reason: 'o botão de rotina precisa ser verde (semântica fixa)',
      );
      expect(
        contrastRatio(foreground, background),
        greaterThanOrEqualTo(aaNormalText),
        reason: 'rótulo ${hex(foreground)} sobre fundo ${hex(background)}',
      );
    });

    testWidgets('tema $name: os textos da tela inicial são legíveis sobre o fundo',
        (tester) async {
      await tester.pumpWidget(
        harness(const HomeScreen(), brightness: brightness),
      );
      await tester.pumpAndSettle();

      for (final text in [
        'Como você está?',
        'Toque em uma opção para começar',
        'Onde ir?',
        'Documentos',
        'Como funciona a UBS',
        'Emergência',
      ]) {
        final color = _renderedColor(tester, text);
        expect(color, isNotNull, reason: '"$text" não foi encontrado');
        expect(
          contrastRatio(color!, colors.ground),
          greaterThanOrEqualTo(aaNormalText),
          reason: '"$text" foi pintado em ${hex(color)}',
        );
      }
    });

    testWidgets('tema $name: os ladrilhos usam a cor semântica correta',
        (tester) async {
      // Verde = rotina, vermelho = emergência, azul = informação. Se um
      // ladrilho trocar de cor, a mensagem que quem não lê recebe muda.
      await tester.pumpWidget(
        harness(const HomeScreen(), brightness: brightness),
      );
      await tester.pumpAndSettle();

      Color iconColor(String key) => tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(Icon),
            ),
          )
          .color!;

      expect(iconColor('home-emergency'), colors.red);
      expect(iconColor('home-flow'), colors.green);
      expect(iconColor('home-whereto'), colors.blue);
      expect(iconColor('home-docs'), colors.blue);
    });
  }
}
