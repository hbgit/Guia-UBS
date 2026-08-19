/// Providers da casca: idioma, voz e o estado de "já escolheu idioma?".
///
/// São escritos à mão em vez de gerados (`riverpod_generator`) porque o que a
/// casca guarda é um enum e um objeto de voz. O sabor com codegen + freezed
/// entra no item 12, onde a triagem tem estados que se beneficiam de união
/// exaustiva — ali o gerador paga por si.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:io';

import '../prefs/locale_store.dart';
import '../speech/speaker.dart';
import '../sync/model_provisioning.dart';

/// Onde o idioma é persistido. Sobrescrito no `main` e nos testes.
final localeStoreProvider = Provider<LocaleStore>(
  (ref) => throw UnimplementedError('localeStoreProvider precisa de override'),
);

/// Voz. Padrão silencioso: um app sem engine de TTS é um app válido (A3), e
/// testes de UI não devem depender de plataforma.
final speakerProvider = Provider<Speaker>((ref) => const SilentSpeaker());

/// Idioma ativo. `null` = ainda não escolhido, que é o que leva à tela de
/// seleção no primeiro acesso (RF-01).
class LocaleController extends StateNotifier<AppLocale?> {
  LocaleController(this._store) : super(null);

  final LocaleStore _store;

  /// Lê a escolha anterior. Chamado uma vez, no boot.
  Future<void> restore() async => state = await _store.read();

  /// Troca o idioma. **A UI muda antes do disco:** o critério da RF-01 é
  /// 200 ms para a interface responder, e esperar um `write` em armazenamento
  /// lento colocaria I/O no caminho de uma troca que precisa ser instantânea.
  /// Se a gravação falhar, o app pergunta de novo na próxima abertura — o
  /// custo é um toque, não uma tela travada.
  void select(AppLocale locale) {
    state = locale;
    // O erro é engolido AQUI e não só dentro do store: a interface
    // [LocaleStore] não promete que `write` não lança, e o item 11 vai
    // reimplementá-la sobre Drift. Confiar na educação da implementação atual
    // deixaria uma exceção assíncrona escapar no dia em que ela mudar — e
    // "não consegui salvar sua preferência" nunca deve virar erro na tela.
    unawaited(_store.write(locale).catchError((Object _) {}));
  }
}

final localeControllerProvider =
    StateNotifierProvider<LocaleController, AppLocale?>(
  (ref) => LocaleController(ref.watch(localeStoreProvider)),
);

/// Locale do Flutter derivado da escolha. Antes da escolha, português — a tela
/// de idioma mostra os dois nomes lado a lado, então o idioma da moldura ali
/// não decide nada.
final flutterLocaleProvider = Provider<Locale>((ref) {
  final locale = ref.watch(localeControllerProvider) ?? AppLocale.pt;
  return Locale(locale.code);
});

/// Idioma da voz, derivado do mesmo estado.
///
/// Deriva em vez de duplicar: se UI e TTS guardassem idiomas separados, uma
/// troca poderia deixar a tela em espanhol e a voz em português — e quem
/// depende do áudio é justamente quem não consegue perceber a diferença lendo.
final speechLocaleProvider = Provider<SpeechLocale>((ref) {
  return switch (ref.watch(localeControllerProvider) ?? AppLocale.pt) {
    AppLocale.pt => SpeechLocale.pt,
    AppLocale.es => SpeechLocale.es,
  };
});

/// Disponibilidade de voz, resolvida fora do caminho do boot.
///
/// A sondagem do engine acontece aqui, não no `main`: a tela abre com o botão
/// de áudio escondido e ele aparece quando a detecção conclui. Trocar isso por
/// um `await` no boot devolveria ao usuário até 3 s de tela preta por causa de
/// um componente que a INV-8 classifica como opcional.
final speechAvailabilityProvider = FutureProvider<bool>((ref) async {
  final speaker = ref.watch(speakerProvider);
  await speaker.ensureInitialized();
  return speaker.isAvailable;
});

/// Provisionamento do modelo SLM. Sobrescrito no `main` e nos testes.
final provisioningProvider = Provider<ModelProvisioning>(
  (ref) => throw UnimplementedError('provisioningProvider precisa de override'),
);

/// Seletor de arquivo para importação por pendrive/OTG. `null` desabilita a
/// opção — é o padrão nos testes, que não têm plugin de picker.
final localModelPickerProvider = Provider<Future<File?> Function()?>((ref) => null);

/// Estado corrente do setup, para o portão do roteador.
final setupStateProvider = StreamProvider<SetupState>((ref) {
  final provisioning = ref.watch(provisioningProvider);
  return provisioning.states;
});
