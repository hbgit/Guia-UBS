/// Saída de áudio (RF-06, CAP-06).
///
/// ===========================================================================
/// ESTE MÓDULO É UMA FOLHA. FALHA AQUI NÃO PROPAGA. NUNCA.
/// ===========================================================================
///
/// O áudio existe porque parte do público não lê — então ele importa muito. E
/// justamente por isso ele **não pode** ser um caminho de falha: se o TTS
/// derrubar ou travar a tela de resultado, quem não lê fica sem o cartão
/// *também*. A INV-8 diz isso em uma linha: falha de TTS nunca impede
/// navegação.
///
/// Consequências no desenho, todas verificadas por teste:
///
/// * nenhum método deste arquivo lança;
/// * nenhum método deste arquivo faz o chamador esperar pelo áudio —
///   [speak] resolve assim que o pedido foi despachado, não quando a fala
///   termina. A UI renderiza o cartão e dispara o áudio em paralelo
///   (`fire-and-forget`, [espec.md §3.1]);
/// * indisponibilidade é detectada **uma vez**, no boot. ROMs cortadas sem
///   engine TTS são um risco previsto (A3 da espec); reconsultar a cada
///   resultado seria pagar o timeout de novo a cada tela.
library;

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:meta/meta.dart';

/// Idiomas com voz. Espelha os locales suportados pela casca.
enum SpeechLocale {
  pt('pt-BR'),
  es('es-ES');

  const SpeechLocale(this.tag);

  /// Tag BCP-47 que o engine do sistema espera.
  final String tag;
}

/// O que a UI precisa saber sobre o áudio.
///
/// Interface e não classe concreta porque a UI tem de ser testável sem engine
/// de TTS — e porque a v2 prevê trocar o engine do SO por Piper/sherpa-onnx
/// sem tocar em nenhuma tela ([stack.md §9]).
abstract interface class Speaker {
  /// Detecta o engine, uma única vez. Idempotente e nunca lança.
  ///
  /// **Não é chamado dentro do boot bloqueante.** Um engine de ROM modificada
  /// pode não responder nem com erro, e esperar por ele atrasaria a abertura do
  /// app por causa de um componente opcional — o oposto do que a INV-8 pede. O
  /// app abre, e o botão de áudio aparece quando (e se) a detecção concluir.
  Future<void> ensureInitialized();

  /// `false` quando não há engine utilizável. A UI usa isto apenas para
  /// **esconder o botão de áudio**, nunca para bloquear a tela.
  bool get isAvailable;

  /// Fala [text] em [locale]. Interrompe o que estiver falando.
  ///
  /// Retorna assim que o pedido é despachado. Não lança.
  Future<void> speak(String text, SpeechLocale locale);

  /// Silencia. Não lança.
  Future<void> stop();

  Future<void> dispose();
}

/// Implementação sobre o engine do sistema operacional.
class SystemSpeaker implements Speaker {
  SystemSpeaker({
    FlutterTts? tts,
    this.probeTimeout = const Duration(seconds: 3),
  }) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  /// Teto para a sondagem do engine. Existe porque engines de ROM modificada
  /// às vezes não respondem nem com erro — ficam pendurados.
  final Duration probeTimeout;

  bool _available = false;
  Future<void>? _probe;

  @override
  bool get isAvailable => _available;

  @override
  Future<void> ensureInitialized() => _probe ??= _detect();

  Future<void> _detect() async {
    try {
      final languages = await _tts
          .getLanguages
          .timeout(probeTimeout) as Object?;
      final tags = switch (languages) {
        final List<Object?> list => list.map((e) => '$e'.toLowerCase()).toSet(),
        _ => <String>{},
      };
      // Basta o idioma-base: um aparelho com `pt` mas sem `pt-BR` fala
      // português, e recusar isso deixaria mudo quem tem voz disponível.
      _available = SpeechLocale.values.any(
        (locale) => tags.any(
          (tag) => tag.startsWith(locale.tag.split('-').first.toLowerCase()),
        ),
      );
      if (_available) {
        await _tts.awaitSpeakCompletion(false).timeout(probeTimeout);
      }
    } on Object {
      // ROM sem engine, plugin ausente no host de teste, timeout: todos o
      // mesmo desfecho — o app segue, sem áudio.
      _available = false;
    }
  }

  @override
  Future<void> speak(String text, SpeechLocale locale) async {
    if (!_available || text.isEmpty) return;
    try {
      await _tts.stop();
      await _tts.setLanguage(locale.tag);
      await _tts.speak(text);
    } on Object {
      // Uma fala que falhou não desabilita o áudio para sempre: pode ser
      // disputa momentânea com outro app pelo canal de saída.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object {
      // Nada a fazer: já estava calado, ou o engine sumiu.
    }
  }

  @override
  Future<void> dispose() => stop();
}

/// Speaker que não fala. É o comportamento correto quando não há engine —
/// e o que os testes de UI usam para não depender de plataforma.
@immutable
class SilentSpeaker implements Speaker {
  const SilentSpeaker();

  @override
  Future<void> ensureInitialized() async {}

  @override
  bool get isAvailable => false;

  @override
  Future<void> speak(String text, SpeechLocale locale) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
