/// O `speech/` é folha: falha aqui não pode chegar em lugar nenhum (INV-8).
///
/// Estes testes são quase todos sobre o que o módulo **não** faz — não lança,
/// não trava, não bloqueia. É a forma de verificar uma invariante que se
/// enuncia pela negativa.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:guia_ubs/speech/speaker.dart';

/// Engine de mentira, capaz das patologias que ROMs reais apresentam.
class _FakeTts implements FlutterTts {
  _FakeTts({this.languages = const ['pt-BR', 'es-ES']});

  final Object? languages;

  /// Lança em toda chamada — ROM sem serviço de TTS instalado.
  bool throwOnEverything = false;

  /// Nunca resolve — o caso que derruba um boot que espere por ele.
  bool hangForever = false;

  final List<String> spoken = [];
  int stops = 0;
  String? language;

  Future<T> _guard<T>(T value) {
    if (throwOnEverything) throw StateError('sem engine de TTS');
    if (hangForever) return Completer<T>().future;
    return Future.value(value);
  }

  @override
  Future<dynamic> get getLanguages => _guard<Object?>(languages);

  @override
  Future<dynamic> speak(String text, {bool? focus}) {
    spoken.add(text);
    return _guard<dynamic>(1);
  }

  @override
  Future<dynamic> stop() {
    stops++;
    return _guard<dynamic>(1);
  }

  @override
  Future<dynamic> setLanguage(String lang) {
    language = lang;
    return _guard<dynamic>(1);
  }

  @override
  Future<dynamic> awaitSpeakCompletion(bool value) => _guard<dynamic>(1);

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<dynamic>.value(1);
}

void main() {
  test('detecta voz quando o engine tem os idiomas', () async {
    final speaker = SystemSpeaker(tts: _FakeTts());
    await speaker.ensureInitialized();

    expect(speaker.isAvailable, isTrue);
  });

  test('idioma-base basta — "pt" sem "pt-BR" ainda fala português', () async {
    // Recusar aqui deixaria mudo um aparelho que tem voz disponível.
    final speaker = SystemSpeaker(tts: _FakeTts(languages: ['pt', 'en-US']));
    await speaker.ensureInitialized();

    expect(speaker.isAvailable, isTrue);
  });

  test('engine sem nenhum dos nossos idiomas fica indisponível', () async {
    final speaker = SystemSpeaker(tts: _FakeTts(languages: ['en-US', 'fr-FR']));
    await speaker.ensureInitialized();

    expect(speaker.isAvailable, isFalse);
  });

  test('ROM sem engine não lança — só fica sem áudio (risco A3)', () async {
    final speaker = SystemSpeaker(tts: _FakeTts()..throwOnEverything = true);

    await expectLater(speaker.ensureInitialized(), completes);
    expect(speaker.isAvailable, isFalse);
  });

  test('resposta que não chega não pendura o app', () async {
    // Este é o caso que justifica o timeout: engines de ROM modificada às
    // vezes não respondem nem com erro. Sem teto, o app ficaria esperando.
    final speaker = SystemSpeaker(
      tts: _FakeTts()..hangForever = true,
      probeTimeout: const Duration(milliseconds: 50),
    );

    await expectLater(speaker.ensureInitialized(), completes);
    expect(speaker.isAvailable, isFalse);
  });

  test('a detecção acontece uma vez só', () async {
    // Reconsultar a cada resultado pagaria o timeout de novo em cada tela.
    final tts = _CountingTts();
    final speaker = SystemSpeaker(tts: tts);

    await speaker.ensureInitialized();
    await speaker.ensureInitialized();
    await speaker.ensureInitialized();

    expect(tts.languageQueries, 1);
  });

  test('falar sem engine disponível é silencioso, não um erro', () async {
    final tts = _FakeTts(languages: ['en-US']);
    final speaker = SystemSpeaker(tts: tts);
    await speaker.ensureInitialized();

    await expectLater(speaker.speak('vá à UBS', SpeechLocale.pt), completes);
    expect(tts.spoken, isEmpty);
  });

  test('erro durante a fala não desliga o áudio para sempre', () async {
    // Pode ser disputa momentânea com outro app pelo canal de saída; punir com
    // silêncio permanente seria desproporcional.
    final tts = _FakeTts();
    final speaker = SystemSpeaker(tts: tts);
    await speaker.ensureInitialized();

    tts.throwOnEverything = true;
    await expectLater(speaker.speak('teste', SpeechLocale.pt), completes);

    tts.throwOnEverything = false;
    await speaker.speak('vá à UBS', SpeechLocale.pt);

    expect(speaker.isAvailable, isTrue);
    expect(tts.spoken, contains('vá à UBS'));
  });

  test('cada fala interrompe a anterior', () async {
    // Duas orientações clínicas sobrepostas seriam pior que nenhuma.
    final tts = _FakeTts();
    final speaker = SystemSpeaker(tts: tts);
    await speaker.ensureInitialized();

    await speaker.speak('primeira', SpeechLocale.pt);
    await speaker.speak('segunda', SpeechLocale.es);

    expect(tts.stops, greaterThanOrEqualTo(2));
    expect(tts.language, 'es-ES');
  });

  test('texto vazio não vira fala', () async {
    final tts = _FakeTts();
    final speaker = SystemSpeaker(tts: tts);
    await speaker.ensureInitialized();

    await speaker.speak('', SpeechLocale.pt);

    expect(tts.spoken, isEmpty);
  });

  test('resposta do engine em formato inesperado não derruba nada', () async {
    // `getLanguages` é `dynamic` na API do plugin; nada garante que venha lista.
    final speaker = SystemSpeaker(tts: _FakeTts(languages: 'pt-BR'));

    await expectLater(speaker.ensureInitialized(), completes);
    expect(speaker.isAvailable, isFalse);
  });

  test('o speaker silencioso satisfaz o contrato inteiro', () async {
    const speaker = SilentSpeaker();

    await speaker.ensureInitialized();
    await speaker.speak('qualquer coisa', SpeechLocale.pt);
    await speaker.stop();
    await speaker.dispose();

    expect(speaker.isAvailable, isFalse);
  });
}

class _CountingTts extends _FakeTts {
  int languageQueries = 0;

  @override
  Future<dynamic> get getLanguages {
    languageQueries++;
    return super.getLanguages;
  }
}
