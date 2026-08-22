/// Como a escolha de fonte do app se combina com a do sistema.
///
/// ## Compor, não substituir
///
/// Ampliar a fonte nos ajustes do Android é a primeira coisa que faz quem tem
/// presbiopia e não tem óculos — parte relevante do público deste app. Se a
/// escolha feita aqui dentro IGNORASSE a do sistema, abrir o app em 1× voltaria
/// a letra ao tamanho original para quem já tinha pedido letra grande no
/// aparelho inteiro. Por isso as duas se multiplicam.
///
/// ## Por que existe um teto
///
/// `accessibility_test` verifica layout de 1× a 2×; acima disso nenhuma tela
/// deste app foi verificada. Com sistema em 1,5× e escolha em 1,6× o produto
/// daria 2,4×, e o que acontece lá é desconhecido — provavelmente conteúdo
/// escondido abaixo da borda, sem aviso. O teto entrega a maior letra que
/// sabemos desenhar, em vez de uma tela quebrada.
///
/// O corte não é silencioso: [textScaleIsCapped] permite à tela de ajustes
/// dizer que o pedido foi limitado.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Maior ampliação total que alguma tela deste app já foi verificada suportando.
const double maxTextScale = 2.0;

/// Tamanho usado para converter um [TextScaler] em fator.
///
/// O Android 14 introduziu escala NÃO linear: o fator depende do tamanho do
/// texto, e não existe "o fator" isolado. Linearizamos em torno do corpo de
/// texto, que é o que domina estas telas — aproximação assumida, não descuido.
const double _referenceFontSize = 16;

/// O fator efetivo que o sistema está aplicando.
double systemTextScaleFactor(TextScaler system) =>
    system.scale(_referenceFontSize) / _referenceFontSize;

/// A escala final: a do sistema vezes a escolhida, limitada a [maxTextScale].
TextScaler gubsTextScaler(TextScaler system, double choice) =>
    TextScaler.linear(
      math.min(systemTextScaleFactor(system) * choice, maxTextScale),
    );

/// `true` quando o teto cortou o pedido — a tela de ajustes avisa, em vez de
/// mostrar um botão selecionado que já não muda mais nada.
bool textScaleIsCapped(TextScaler system, double choice) =>
    systemTextScaleFactor(system) * choice > maxTextScale;
