/// Tradução do `color_token` do pack para a paleta do app.
///
/// O pack diz `green`, `red`, `blue` — **nomes semânticos**, não cores. Quem
/// converte para pixel é o binário, e isso não é detalhe de arquitetura: se o
/// conteúdo pudesse ditar a cor em hexadecimal, uma republicação seria capaz de
/// pintar um encaminhamento de emergência de verde sem passar por nenhuma
/// revisão de código.
///
/// ## O padrão é AZUL, e é isso que importa aqui
///
/// Token desconhecido — pack novo, token digitado errado — vira **informação**,
/// nunca rotina nem emergência. Chutar verde diria "pode esperar"; chutar
/// vermelho diria "corra". Azul diz "isto é informação", que é a única coisa
/// verdadeira sobre um token que este binário não entende.
library;

import 'package:flutter/material.dart';

import '../../theme/gubs_colors.dart';

/// Par de cores para um token de cor do pack.
({Color accent, Color background}) colorsForToken(
  String token,
  GubsColors colors,
) =>
    switch (token) {
      'green' => (accent: colors.green, background: colors.greenSoft),
      'red' => (accent: colors.red, background: colors.redSoft),
      'amber' => (accent: colors.amber, background: colors.surfaceAlt),
      _ => (accent: colors.blue, background: colors.blueSoft),
    };

/// `true` quando o token pede a semântica de emergência — usado para decidir
/// ênfase (borda mais grossa, 192 em destaque), nunca para decidir conteúdo.
bool isEmergencyToken(String token) => token == 'red';
