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

import '../content/data/active_content.dart';
import '../content/data/content_repository.dart';
import '../prefs/locale_store.dart';
import '../prefs/preferences_repository.dart';
import '../speech/speaker.dart';
import '../telemetry/telemetry_recorder.dart';
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

// ---------------------------------------------------------------------------
// Preferências (user.db)
// ---------------------------------------------------------------------------

/// Repositório de preferências. Sobrescrito no `main` e nos testes.
///
/// É a MESMA instância que `localeStoreProvider` entrega como [LocaleStore]:
/// duas fontes para a mesma preferência sairiam de sincronia no primeiro
/// caminho que atualizasse só uma delas.
final preferencesProvider = Provider<PreferencesRepository>(
  (ref) => throw UnimplementedError('preferencesProvider precisa de override'),
);

// ---------------------------------------------------------------------------
// Conteúdo (content.db)
// ---------------------------------------------------------------------------

/// Pack ativo aberto. Sobrescrito no `main` e nos testes.
final activeContentProvider = Provider<ActiveContent>(
  (ref) => throw UnimplementedError('activeContentProvider precisa de override'),
);

/// Leitura do conteúdo, ou `null` enquanto não houver pack instalado.
///
/// As telas tratam `null` como "conteúdo ainda não disponível" e seguem
/// navegáveis: sem pack, o app não tem o que mostrar, mas continua de pé
/// (INV-8).
final contentProvider = Provider<ContentRepository?>(
  (ref) => ref.watch(activeContentProvider).repository,
);

/// Código de idioma para as consultas ao pack.
///
/// Deriva do mesmo estado que a interface e a voz. Se o conteúdo lesse um
/// idioma próprio, a tela poderia mostrar cartão em português com rótulo de
/// botão em espanhol.
final contentLanguageProvider = Provider<String>(
  (ref) => (ref.watch(localeControllerProvider) ?? AppLocale.pt).code,
);

/// O usuário já passou pelo First-Time Setup, persistido no `user.db`.
///
/// Sem isto, quem escolheu "usar sem a IA assistente" reveria a apresentação de
/// valor a cada abertura do app — a decisão vivia só na memória do processo.
class SetupCompletedController extends StateNotifier<bool> {
  SetupCompletedController(this._preferences) : super(false);

  final PreferencesRepository _preferences;

  Future<void> restore() async => state = (await _preferences.readAll()).setupCompleted;

  void markCompleted() {
    if (state) return;
    state = true;
    unawaited(
      _preferences.setSetupCompleted(completed: true).catchError((Object _) {}),
    );
  }
}

final setupCompletedProvider =
    StateNotifierProvider<SetupCompletedController, bool>(
  (ref) => SetupCompletedController(ref.watch(preferencesProvider)),
);

/// Opt-out de telemetria (LGPD-RF03).
///
/// Estado **síncrono** e fonte única. A primeira versão tinha dois providers
/// lendo a mesma preferência do `user.db` — a tela invalidava um e o contador
/// escutava o outro, e o resultado é o pior defeito possível numa opção de
/// privacidade: o botão desliga na tela e a coleta continua. Com um estado só,
/// não há como um deles ficar para trás.
class TelemetryConsentController extends StateNotifier<bool> {
  TelemetryConsentController(this._preferences) : super(true);

  final PreferencesRepository _preferences;

  Future<void> restore() async =>
      state = (await _preferences.readAll()).telemetryEnabled;

  /// Muda a decisão. A UI reflete antes do disco, como na troca de idioma:
  /// desligar telemetria não pode esperar I/O.
  void set({required bool enabled}) {
    state = enabled;
    unawaited(
      _preferences
          .setTelemetryEnabled(enabled: enabled)
          .catchError((Object _) {}),
    );
  }
}

final telemetryConsentProvider =
    StateNotifierProvider<TelemetryConsentController, bool>(
  (ref) => TelemetryConsentController(ref.watch(preferencesProvider)),
);

/// Contador de telemetria agregada.
///
/// Lê o consentimento a CADA registro — desligar na tela de privacidade precisa
/// fazer efeito no toque seguinte. Ver `telemetry/telemetry_recorder.dart` para
/// o que este módulo deliberadamente NÃO faz (não envia, não persiste).
final telemetryProvider = Provider<TelemetryRecorder>(
  (ref) => TelemetryRecorder(
    isEnabled: () => ref.read(telemetryConsentProvider),
  ),
);
