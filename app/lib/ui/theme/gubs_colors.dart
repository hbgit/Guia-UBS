/// A semântica de cor do app, como extensão de tema.
///
/// ===========================================================================
/// VERDE = UBS/ROTINA · VERMELHO = EMERGÊNCIA · AZUL = INFORMAÇÃO
/// ===========================================================================
///
/// Isto **não é preferência visual**. Para quem não lê o texto do cartão — que
/// é exatamente o público que este app existe para atender — a cor é o canal
/// primário da mensagem. Um cartão de emergência pintado de verde manda para
/// casa alguém que precisa de UPA. Por isso a semântica é fixa (RNF-06) e o
/// acesso a ela é por [severity], não por nome de cor: quem escreve tela nova
/// pede "a cor deste nível de severidade" e recebe a certa, em vez de escolher
/// entre `green` e `red` no momento do layout.
///
/// A paleta reproduz os tokens de `docs/design.html`, claro e escuro. O que
/// garante que ela continue legível não é a origem, é o teste de contraste:
/// `test/ui/theme/contrast_test.dart` calcula a razão WCAG 2.2 de cada par
/// usado e reprova abaixo de AA.
library;

import 'package:flutter/material.dart';

import '../../triage/domain/severity.dart';

@immutable
class GubsColors extends ThemeExtension<GubsColors> {
  const GubsColors({
    required this.ground,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkSoft,
    required this.line,
    required this.green,
    required this.greenDeep,
    required this.greenSoft,
    required this.onGreen,
    required this.red,
    required this.redDeep,
    required this.redSoft,
    required this.onRed,
    required this.blue,
    required this.blueSoft,
    required this.amber,
    required this.onAmber,
    required this.focus,
  });

  final Color ground;
  final Color surface;
  final Color surfaceAlt;

  /// Texto principal.
  final Color ink;

  /// Texto secundário. Nunca use para informação que só existe nele.
  final Color inkSoft;

  final Color line;

  /// UBS, rotina, "pode esperar".
  final Color green;
  final Color greenDeep;
  final Color greenSoft;
  final Color onGreen;

  /// Emergência. Só emergência.
  final Color red;
  final Color redDeep;
  final Color redSoft;

  /// Informação neutra: onde ir, documentos, fluxo.
  final Color blue;
  final Color blueSoft;

  /// Texto sobre preenchimento vermelho. **Não é branco por definição:** no
  /// tema escuro o vermelho é claro, e branco sobre ele dá 3,2:1 — reprovado.
  /// Foi exatamente o que o teste de contraste pegou quando esta cor estava
  /// escrita como `Colors.white` dentro de [forSeverity].
  final Color onRed;

  /// Atenção — entre rotina e emergência.
  final Color amber;

  /// Texto sobre preenchimento âmbar.
  final Color onAmber;

  final Color focus;

  /// Cor de destaque e cor de fundo para um nível de severidade.
  ///
  /// É por aqui que as telas de resultado pedem cor. Pedir por nome (`red`)
  /// abriria espaço para o erro que a INV-1 protege no motor mas ninguém
  /// protege no layout: pintar de verde um desfecho de emergência.
  ({Color accent, Color background, Color onAccent}) forSeverity(
    GubsSeverity severity,
  ) =>
      switch (severity) {
        GubsSeverity.routine =>
          (accent: green, background: greenSoft, onAccent: onGreen),
        GubsSeverity.attention =>
          (accent: amber, background: surfaceAlt, onAccent: onAmber),
        GubsSeverity.emergency =>
          (accent: red, background: redSoft, onAccent: onRed),
      };

  // A conversão de `routing_outcome.severity_level` para [GubsSeverity] NÃO
  // mora aqui, de propósito — ver `severityFor` em
  // `triage/domain/severity.dart`.
  //
  // Uma versão anterior deste arquivo tinha um `forSeverityLevel(int)` com
  // limiares fixos (`<= 1` rotina, `2` atenção, resto emergência). O pack real
  // usa a escala 10/100, então TODO resultado de rotina caía no `resto` e era
  // pintado de vermelho, com "Ligue 192" embaixo. A UI havia inventado uma
  // escala; a escala pertence ao conteúdo, que é revisado clinicamente e pode
  // mudar de pack para pack.

  @override
  GubsColors copyWith({
    Color? ground,
    Color? surface,
    Color? surfaceAlt,
    Color? ink,
    Color? inkSoft,
    Color? line,
    Color? green,
    Color? greenDeep,
    Color? greenSoft,
    Color? onGreen,
    Color? red,
    Color? redDeep,
    Color? redSoft,
    Color? onRed,
    Color? blue,
    Color? blueSoft,
    Color? amber,
    Color? onAmber,
    Color? focus,
  }) =>
      GubsColors(
        ground: ground ?? this.ground,
        surface: surface ?? this.surface,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        ink: ink ?? this.ink,
        inkSoft: inkSoft ?? this.inkSoft,
        line: line ?? this.line,
        green: green ?? this.green,
        greenDeep: greenDeep ?? this.greenDeep,
        greenSoft: greenSoft ?? this.greenSoft,
        onGreen: onGreen ?? this.onGreen,
        red: red ?? this.red,
        redDeep: redDeep ?? this.redDeep,
        redSoft: redSoft ?? this.redSoft,
        onRed: onRed ?? this.onRed,
        blue: blue ?? this.blue,
        blueSoft: blueSoft ?? this.blueSoft,
        amber: amber ?? this.amber,
        onAmber: onAmber ?? this.onAmber,
        focus: focus ?? this.focus,
      );

  /// Interpolação entre claro e escuro.
  ///
  /// A troca de tema atravessa cores intermediárias que ninguém revisou quanto
  /// a contraste. Por isso ela é instantânea no app (ver `gubs_theme.dart`):
  /// este método existe porque a API do [ThemeExtension] o exige, não porque
  /// haja animação de tema em produção.
  @override
  GubsColors lerp(ThemeExtension<GubsColors>? other, double t) {
    if (other is! GubsColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return GubsColors(
      ground: mix(ground, other.ground),
      surface: mix(surface, other.surface),
      surfaceAlt: mix(surfaceAlt, other.surfaceAlt),
      ink: mix(ink, other.ink),
      inkSoft: mix(inkSoft, other.inkSoft),
      line: mix(line, other.line),
      green: mix(green, other.green),
      greenDeep: mix(greenDeep, other.greenDeep),
      greenSoft: mix(greenSoft, other.greenSoft),
      onGreen: mix(onGreen, other.onGreen),
      red: mix(red, other.red),
      redDeep: mix(redDeep, other.redDeep),
      redSoft: mix(redSoft, other.redSoft),
      onRed: mix(onRed, other.onRed),
      blue: mix(blue, other.blue),
      blueSoft: mix(blueSoft, other.blueSoft),
      amber: mix(amber, other.amber),
      onAmber: mix(onAmber, other.onAmber),
      focus: mix(focus, other.focus),
    );
  }

  /// Tema claro.
  ///
  /// Deriva de `docs/design.html`, com **duas correções que o teste de
  /// contraste impôs** (e que foram propagadas de volta ao protótipo):
  ///
  /// * `red` escureceu de `#CE3A3A` para `#9E2626`. No original, verde e
  ///   vermelho tinham razão de contraste de **1,01** entre si — mesma
  ///   luminância. Para os ~5% de homens com deficiência de visão de cores
  ///   vermelho-verde, os dois cartões eram literalmente a mesma cor, e a
  ///   distinção rotina/emergência é a coisa mais importante que este app
  ///   comunica. Agora a razão é 1,55, e o vermelho mais escuro também lê
  ///   como mais urgente.
  /// * `amber` escureceu de `#B98A2F` para `#8F651A`: o original dava 2,91:1
  ///   contra o fundo, abaixo do mínimo de 3:1 para componente de interface.
  static const GubsColors light = GubsColors(
    ground: Color(0xFFF4F8F5),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFECF3EE),
    ink: Color(0xFF17251F),
    inkSoft: Color(0xFF5A6B63),
    line: Color(0xFFDFE8E2),
    green: Color(0xFF12805C),
    greenDeep: Color(0xFF0C5F44),
    greenSoft: Color(0xFFE3F2EB),
    onGreen: Color(0xFFFFFFFF),
    red: Color(0xFF9E2626),
    redDeep: Color(0xFF7A1B1B),
    redSoft: Color(0xFFFBE9E9),
    onRed: Color(0xFFFFFFFF),
    blue: Color(0xFF2F6DA8),
    blueSoft: Color(0xFFE7F0F8),
    amber: Color(0xFF8F651A),
    onAmber: Color(0xFFF4F8F5),
    focus: Color(0xFF2F6DA8),
  );

  /// Tema escuro.
  ///
  /// Aqui as cores semânticas são CLARAS sobre fundo escuro, então o texto que
  /// vai por cima delas é escuro — o oposto do tema claro. É por isso que
  /// `onRed`/`onAmber` existem como tokens em vez de um `Colors.white` escrito
  /// no meio do código.
  static const GubsColors dark = GubsColors(
    ground: Color(0xFF0E1613),
    surface: Color(0xFF182219),
    surfaceAlt: Color(0xFF1F2B24),
    ink: Color(0xFFE8F0EB),
    inkSoft: Color(0xFF94A79D),
    line: Color(0xFF28352E),
    green: Color(0xFF3FC28D),
    greenDeep: Color(0xFF7ADDB6),
    greenSoft: Color(0xFF153427),
    onGreen: Color(0xFF0E1613),
    red: Color(0xFFE36A6A),
    redDeep: Color(0xFFF0918F),
    redSoft: Color(0xFF3A1D1D),
    onRed: Color(0xFF0E1613),
    blue: Color(0xFF6BA6DC),
    blueSoft: Color(0xFF16293A),
    amber: Color(0xFFD9B25F),
    onAmber: Color(0xFF0E1613),
    focus: Color(0xFF6BA6DC),
  );
}

/// Atalho para o que toda tela precisa: `context.gubs.red`.
extension GubsColorsOf on BuildContext {
  GubsColors get gubs => Theme.of(this).extension<GubsColors>()!;
}
