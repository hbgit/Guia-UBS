/// Ponto de entrada.
///
/// A responsabilidade aqui é montar as dependências reais e entregá-las à
/// casca. Nenhuma decisão de navegação mora neste arquivo — quem decide é o
/// `redirect` em `ui/router_provider.dart`, que é uma função pura e por isso
/// testável sem inflar tela nenhuma.
///
/// **Nada opcional bloqueia o boot.** O agendador de sync e a sondagem do
/// engine de TTS podem falhar ou demorar; ambos ficam fora do caminho crítico,
/// porque a INV-8 classifica os dois como folhas.
library;

import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'content/data/active_content.dart';
import 'core/app_paths.dart';
import 'l10n/app_localizations.dart';
import 'prefs/preferences_repository.dart';
import 'prefs/user_database_connection.dart';
import 'speech/speaker.dart';
import 'sync/pack_store.dart';
import 'sync/model_background_sync.dart';
import 'sync/model_catalog.dart';
import 'sync/model_provisioning.dart';
import 'sync/model_sync_scheduler.dart';
import 'ui/app_scope.dart';
import 'ui/router_provider.dart';
import 'ui/triage/triage_controller.dart';
import 'ui/theme/gubs_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Falha aqui não pode impedir o app de abrir: sem agendador, o modelo só é
  // baixado em primeiro plano — degradação, não impedimento (INV-8).
  try {
    await initModelBackgroundSync();
  } on Object {
    // Segue sem sync em background.
  }

  final support = await appSupportDirectory();

  // `user.db` (item 11) substitui o `locale.json` do item 10. A migração traz
  // o idioma já escolhido: trocar de armazenamento sem ela faria todo aparelho
  // em uso voltar a perguntar o idioma.
  final preferences = PreferencesRepository(await openUserDatabase());
  await preferences.migrateFromFile(File('${support.path}/locale.json'));

  // Pack de conteúdo. Abrir aqui, e não na primeira tela, faz um pack
  // corrompido virar "conteúdo indisponível" antes de qualquer navegação.
  final content = ActiveContent(PackStore(await packsDirectory()));
  await content.reload();

  // Override de dados móveis: decisão do administrador do posto, tomada uma
  // vez e válida até ser desfeita. Antes do `user.db` ela se perdia a cada
  // fechamento do app — e um posto sem Wi-Fi voltava a recusar o download.
  final stored = await preferences.readAll();
  final provisioning = ModelProvisioning(
    artifact: activeModel,
    destinationDirectory: modelsDirectory,
    networkClass: currentNetworkClass,
  )..allowMeteredNetworks = stored.allowMeteredDownload;

  runApp(
    ProviderScope(
      overrides: [
        preferencesProvider.overrideWithValue(preferences),
        localeStoreProvider.overrideWithValue(preferences),
        activeContentProvider.overrideWithValue(content),
        // O motor SLM entra quando existir modelo provisionado. Enquanto for
        // `null`, a triagem roda pelo `RuleOnlyEngine` — que e o degrau
        // seguinte da escada do RF-12, nao um erro.
        triageEngineProvider.overrideWithValue(null),
        speakerProvider.overrideWithValue(SystemSpeaker()),
        localModelPickerProvider.overrideWithValue(pickModelFromStorage),
        provisioningProvider.overrideWithValue(provisioning),
      ],
      child: const GuiaUbsApp(),
    ),
  );
}

/// Abre o seletor de arquivos para importar o modelo de um pendrive/OTG.
///
/// Usa `pickFile` (singular) e lê apenas o CAMINHO — nunca os bytes. Carregar
/// 800 MB na memória para depois gravar em disco derrubaria o app.
///
/// Sem filtro de extensão: gerenciadores de arquivos de pendrive costumam
/// reportar `.gguf` como tipo desconhecido, e filtrar esconderia justamente o
/// arquivo que a pessoa veio buscar. Quem valida é o SHA-256, não a extensão.
///
/// `path` é nulo quando a origem não é um arquivo local (provedor em nuvem,
/// por exemplo). Nesse caso desistimos: copiar via stream de um provedor
/// remoto não é "importar de armazenamento local".
Future<File?> pickModelFromStorage() async {
  final picked = await FilePicker.pickFile(
    dialogTitle: 'Selecione o arquivo do modelo (.gguf)',
    type: FileType.any,
  );
  final path = picked?.path;
  return path == null ? null : File(path);
}

/// Traduz o resultado do plugin para a classe de rede que a política entende.
///
/// Wi-Fi e Ethernet são não tarifados; celular é tarifado. VPN é ambíguo —
/// tratamos como tarifado por prudência: melhor pedir confirmação do que gastar
/// 800 MB do plano de dados de alguém.
Future<NetworkClass> currentNetworkClass() async {
  final results = await Connectivity().checkConnectivity();
  if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
    return NetworkClass.none;
  }
  final unmetered = results.any(
    (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
  );
  return unmetered ? NetworkClass.unmetered : NetworkClass.metered;
}

class GuiaUbsApp extends ConsumerStatefulWidget {
  const GuiaUbsApp({super.key});

  @override
  ConsumerState<GuiaUbsApp> createState() => _GuiaUbsAppState();
}

class _GuiaUbsAppState extends ConsumerState<GuiaUbsApp> {
  @override
  void initState() {
    super.initState();
    // Idioma persistido, se houver — é o que decide entre abrir na tela de
    // seleção ou direto no app.
    ref.read(localeControllerProvider.notifier).restore();
    ref.read(setupCompletedProvider.notifier).restore();

    // O agendador só interessa enquanto falta modelo. Quando o provisionamento
    // conclui, cancelamos: manter um job periódico para baixar algo que já
    // existe é gasto de bateria sem contrapartida.
    ref.read(provisioningProvider).states.listen((state) {
      // Sair do estado de bloqueio — concluindo ou desistindo — encerra o
      // First-Time Setup para sempre. Persistir aqui, e não na tela, garante
      // que a decisão sobreviva a um fechamento do app no instante seguinte.
      if (!state.blocksClinicalScreen) {
        ref.read(setupCompletedProvider.notifier).markCompleted();
      }
      switch (state.stage) {
        case SetupStage.ready:
          cancelModelSync().ignore();
        case SetupStage.readyDegraded || SetupStage.blocked:
          scheduleModelSync(
            policy: const ModelSyncPolicy().withMeteredOverride(
              allowed: ref.read(provisioningProvider).allowMeteredNetworks,
            ),
          ).ignore();
        case _:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => L.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: gubsLightTheme,
      darkTheme: gubsDarkTheme,
      locale: ref.watch(flutterLocaleProvider),
      // `GlobalCupertinoLocalizations` entra mesmo o app sendo Material e
      // só-Android: o `MaterialApp` a exige, e sem ela pt e es levantam
      // exceção em tempo de execução. Tentar removê-la por peso quebrou 15
      // testes — fica registrado para ninguém repetir a tentativa.
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
