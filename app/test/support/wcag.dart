/// Razão de contraste da WCAG 2.x, compartilhada pelos testes de cor.
///
/// Vive aqui, e não dentro de um arquivo de teste, porque dois testes a usam:
/// um verifica a PALETA (os pares que declaramos) e outro verifica o
/// RENDERIZADO (os pares que os widgets de fato produzem). Os dois precisam
/// medir com a mesma régua, ou uma discordância entre eles viraria discussão
/// sobre a fórmula em vez de sobre a cor.
library;

import 'dart:math' as math;
import 'dart:ui';

/// Luminância relativa, conforme a definição da WCAG 2.x.
double relativeLuminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// Razão de contraste entre duas cores opacas.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// AA para texto normal.
const double aaNormalText = 4.5;

/// AA para texto grande (≥ 24 px, ou ≥ 18,66 px em negrito) e para componentes
/// de interface — bordas, ícones, indicadores.
const double aaLargeTextOrUi = 3.0;

String hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
