/// Persistência do idioma (RF-01) e a troca em si.
///
/// O critério de aceitação da RF-01 tem duas partes: a escolha sobrevive ao
/// fechamento do app, e a interface responde em menos de 200 ms. As duas são
/// verificáveis, e as duas estão aqui.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/speech/speaker.dart';
import 'package:guia_ubs/ui/app_scope.dart';
import 'package:guia_ubs/ui/theme/gubs_metrics.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('gubs_prefs_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File prefsFile() => File('${tmp.path}/locale.json');

  group('FileLocaleStore', () {
    test('sem arquivo, ninguém escolheu ainda', () async {
      expect(await FileLocaleStore(prefsFile()).read(), isNull);
    });

    test('a escolha sobrevive a uma nova instância', () async {
      await FileLocaleStore(prefsFile()).write(AppLocale.es);

      expect(await FileLocaleStore(prefsFile()).read(), AppLocale.es);
    });

    test('arquivo corrompido devolve "não escolheu", não uma exceção', () async {
      // Travar o boot por causa de uma preferência seria desproporcional: o
      // custo de perdê-la é um toque a mais.
      prefsFile().writeAsStringSync('{isto nao e json');

      expect(await FileLocaleStore(prefsFile()).read(), isNull);
    });

    test('idioma desconhecido no arquivo é ignorado', () async {
      // Um pack futuro pode acrescentar idiomas; um binário antigo não pode
      // travar por causa disso.
      prefsFile().writeAsStringSync('{"locale":"gn"}');

      expect(await FileLocaleStore(prefsFile()).read(), isNull);
    });

    test('gravar em diretório inexistente não lança', () async {
      final store = FileLocaleStore(File('${tmp.path}/fundo/do/poco/l.json'));

      await expectLater(store.write(AppLocale.pt), completes);
      expect(await store.read(), AppLocale.pt);
    });

    test('disco somente leitura não derruba o app', () async {
      final store = FileLocaleStore(File('/proc/nao-posso-escrever/l.json'));

      await expectLater(store.write(AppLocale.pt), completes);
      expect(await store.read(), isNull);
    });
  });

  group('troca de idioma', () {
    ProviderContainer containerWith(LocaleStore store) {
      final container = ProviderContainer(
        overrides: [
          localeStoreProvider.overrideWithValue(store),
          speakerProvider.overrideWithValue(const SilentSpeaker()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('começa sem idioma, o que leva à tela de seleção', () {
      final container = containerWith(MemoryLocaleStore());

      expect(container.read(localeControllerProvider), isNull);
    });

    test('restaura a escolha anterior', () async {
      final container = containerWith(MemoryLocaleStore(AppLocale.es));

      await container.read(localeControllerProvider.notifier).restore();

      expect(container.read(localeControllerProvider), AppLocale.es);
    });

    test('a interface muda dentro do orçamento da RF-01', () {
      // A UI muda ANTES do disco, de propósito: esperar um `write` em
      // armazenamento lento colocaria I/O no caminho de uma troca que precisa
      // ser instantânea.
      final container = containerWith(_SlowStore());

      final clock = Stopwatch()..start();
      container.read(localeControllerProvider.notifier).select(AppLocale.es);
      clock.stop();

      expect(container.read(localeControllerProvider), AppLocale.es);
      expect(clock.elapsed, lessThan(localeSwitchBudget));
    });

    test('a voz acompanha a interface — nunca ficam em idiomas diferentes', () {
      // Quem depende do áudio é justamente quem não consegue perceber a
      // divergência lendo a tela.
      final container = containerWith(MemoryLocaleStore());

      container.read(localeControllerProvider.notifier).select(AppLocale.es);
      expect(container.read(speechLocaleProvider), SpeechLocale.es);
      expect(container.read(flutterLocaleProvider).languageCode, 'es');

      container.read(localeControllerProvider.notifier).select(AppLocale.pt);
      expect(container.read(speechLocaleProvider), SpeechLocale.pt);
      expect(container.read(flutterLocaleProvider).languageCode, 'pt');
    });

    test('falha ao gravar não impede a troca nesta sessão', () {
      final container = containerWith(_FailingStore());

      container.read(localeControllerProvider.notifier).select(AppLocale.es);

      expect(container.read(localeControllerProvider), AppLocale.es);
    });
  });
}

/// Simula armazenamento lento — cartão SD ruim é comum no público-alvo.
class _SlowStore implements LocaleStore {
  @override
  Future<AppLocale?> read() async => null;

  @override
  Future<void> write(AppLocale locale) =>
      Future.delayed(const Duration(seconds: 2));
}

class _FailingStore implements LocaleStore {
  @override
  Future<AppLocale?> read() async => null;

  @override
  Future<void> write(AppLocale locale) async => throw StateError('sem espaço');
}
