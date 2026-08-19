/// `ThemeData` do app, derivado dos tokens de [GubsColors].
///
/// Duas escolhas que não são cosméticas:
///
/// 1. **Alvos de toque de 64 dp entram no tema, não em cada tela.** Se o
///    tamanho mínimo vive no `ButtonStyle` padrão, uma tela nova nasce
///    acessível sem ninguém lembrar. Se vive no widget, a primeira tela
///    escrita com pressa nasce com 40 dp e ninguém percebe.
/// 2. **Nenhuma animação de tema.** A troca claro/escuro atravessaria cores
///    intermediárias que nenhum teste de contraste cobre. Num app cuja cor
///    carrega a mensagem clínica, meio segundo de cartão vermelho desbotado é
///    meio segundo de mensagem errada.
library;

import 'package:flutter/material.dart';

import 'gubs_colors.dart';
import 'gubs_metrics.dart';

/// Monta o tema a partir da paleta.
///
/// O `ColorScheme` do Material é preenchido a partir dos MESMOS tokens, para
/// que widgets prontos (diálogos, `SnackBar`) não apareçam com cores de outro
/// app — mas nenhum código de tela deve ler severidade dele: quem responde por
/// isso é `GubsColors.forSeverity`.
ThemeData buildGubsTheme(GubsColors colors, Brightness brightness) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: colors.green,
    onPrimary: colors.onGreen,
    primaryContainer: colors.greenSoft,
    onPrimaryContainer: colors.ink,
    secondary: colors.blue,
    onSecondary: brightness == Brightness.light ? Colors.white : colors.ground,
    secondaryContainer: colors.blueSoft,
    onSecondaryContainer: colors.ink,
    error: colors.red,
    onError: brightness == Brightness.light ? Colors.white : colors.ground,
    errorContainer: colors.redSoft,
    onErrorContainer: colors.ink,
    surface: colors.surface,
    onSurface: colors.ink,
    surfaceContainerHighest: colors.surfaceAlt,
    onSurfaceVariant: colors.inkSoft,
    outline: colors.line,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.ground,
    extensions: [colors],
  );

  final minimumTarget = WidgetStateProperty.all(
    const Size(minTouchTarget, minTouchTarget),
  );

  return base.copyWith(
    // Sem transição entre temas — ver o comentário da biblioteca.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    // ARMADILHA, registrada porque custou um defeito visível no aparelho:
    //
    // todo estilo de `Theme.of(context).textTheme` já vem com COR — o Flutter
    // o coloriza com `ColorScheme.onSurface`. E cor explícita num `TextStyle`
    // VENCE o `foregroundColor` do botão que contém o texto. Ou seja, escrever
    //
    //     Text(x, style: Theme.of(c).textTheme.titleLarge)
    //
    // dentro de um botão colorido produz texto de cor de fundo de tela sobre o
    // preenchimento do botão. Foi assim que o rótulo do botão principal do app
    // saiu com **1,94:1** no tema escuro do aparelho, contra os 4,5:1 exigidos.
    //
    // O teste de paleta não pegou: `ink`×`green` não é um par que a paleta
    // preveja — foi o widget que o inventou. Quem pega isso é
    // `test/ui/rendered_contrast_test.dart`, que lê a cor do texto JÁ PINTADO.
    // Dentro de botão colorido, informe a cor do par (`onGreen`, `onRed`,
    // `onAmber`) explicitamente.
    iconTheme: IconThemeData(color: colors.ink, size: 32),
    dividerTheme: DividerThemeData(color: colors.line, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: minimumTarget,
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusButton),
          ),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: minimumTarget,
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusButton),
          ),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(minimumSize: minimumTarget),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(minimumSize: minimumTarget),
    ),
    cardTheme: CardThemeData(
      color: colors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusCard),
        side: BorderSide(color: colors.line),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.greenSoft,
      height: 80,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
  );
}

ThemeData get gubsLightTheme => buildGubsTheme(GubsColors.light, Brightness.light);
ThemeData get gubsDarkTheme => buildGubsTheme(GubsColors.dark, Brightness.dark);
