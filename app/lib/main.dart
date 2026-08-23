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

import 'dart:async';
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
import 'sync/background_sync.dart';
import 'sync/model_background_sync.dart';
import 'sync/model_catalog.dart';
import 'sync/model_provisioning.dart';
import 'sync/model_sync_scheduler.dart';
import 'sync/pack_background_sync.dart';
import 'triage/engine/llama_engine.dart';
import 'ui/app_scope.dart';
import 'ui/router_provider.dart';
import 'ui/triage/triage_controller.dart';
import 'ui/theme/gubs_theme.dart';
import 'ui/theme/text_scaling.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Falha aqui não pode impedir o app de abrir: sem agendador, o modelo só é
  // baixado em primeiro plano — degradação, não impedimento (INV-8).
  try {
    await initBackgroundSync();
    // O sync de conteúdo (FSM-B) também roda em background: o usuário nunca
    // pede um sync, então ele precisa acontecer sem ninguém abrir o app.
    await schedulePackSync();
  } on Object {
    // Segue sem sync em background. O ciclo de primeiro plano ainda roda ao
    // voltar do segundo plano, e o pack ativo continua servindo conteúdo.
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
        // O motor SLM NAO e sobrescrito aqui: ele comeca nulo e e preenchido
        // depois do boot, em `_startEngine`. Carregar 800 MB de GGUF leva
        // segundos, e esperar por isso antes da primeira tela travaria o app
        // por causa de um componente que a INV-8 classifica como opcional.
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

class _GuiaUbsAppState extends ConsumerState<GuiaUbsApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Idioma persistido, se houver — é o que decide entre abrir na tela de
    // seleção ou direto no app.
    ref.read(localeControllerProvider.notifier).restore();
    ref.read(setupCompletedProvider.notifier).restore();
    ref.read(telemetryConsentProvider.notifier).restore();
    // Tema e fonte também são lidos aqui, e não na tela de ajustes: quem
    // escolheu tema escuro precisa que o app ABRA escuro, e não que ele pisque
    // claro até alguém entrar em Ajustes.
    ref.read(themeModeProvider.notifier).restore();
    ref.read(fontScaleProvider.notifier).restore();
    ref.read(meteredDownloadProvider.notifier).restore();

    // Fora do caminho do boot, de propósito. Ver `_startEngine`.
    unawaited(_startEngine());

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

  /// Sobe o motor SLM quando houver modelo verificado em disco.
  ///
  /// ## Por que aqui, e não antes do `runApp`
  ///
  /// `startLlamaEngine` abre um isolate e carrega um GGUF de 800 MB — segundos
  /// de trabalho. Fazer isso no caminho do boot devolveria tela preta a quem só
  /// quer consultar "Onde ir", que não usa modelo nenhum. Enquanto ele não
  /// chega, `triageEngineProvider` continua nulo e a triagem roda por regras:
  /// o degrau seguinte da escada do RF-12.
  ///
  /// ## Nunca lança
  ///
  /// Modelo ausente, marcador que não confere, `.so` que não carrega, isolate
  /// que morre — todos os caminhos terminam em "sem motor", que é degradação
  /// prevista. Uma exceção aqui derrubaria o app por causa do componente que a
  /// INV-8 declara opcional.
  Future<void> _startEngine() async {
    try {
      final model = await ref.read(provisioningProvider).verifiedModel();
      if (model == null) return;

      // As regras do pack são exigidas pelo motor: ele escolhe entre desfechos
      // que existem NAQUELE pacote, e sem elas não há o que escolher.
      final rules = ref.read(ruleModelProvider);
      if (rules == null) return;

      final engine = await startLlamaEngine(
        model: rules,
        modelPath: model.path,
      );
      if (engine == null || !mounted) {
        await engine?.dispose();
        return;
      }
      ref.read(triageEngineProvider.notifier).state = engine;
    } on Object {
      // Segue sem motor. Ver o comentário acima.
    }
  }

  @override
  void dispose() {
    // O isolate do llama.cpp segura a memória do modelo: deixá-lo vivo depois
    // da árvore de widgets manteria centenas de MB presos no processo.
    ref.read(triageEngineProvider)?.dispose().ignore();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Um ciclo de sync ao voltar para o primeiro plano.
  ///
  /// Complementa o trabalho periódico, não o substitui: em aparelho que fica
  /// dias sem rede, a janela do WorkManager pode não encontrar conectividade, e
  /// abrir o app costuma coincidir com estar num lugar que tem Wi-Fi. O freio
  /// persistido impede que isso vire uma batida no servidor a cada abertura.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      runPackSyncCycle(ref).ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => L.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: gubsLightTheme,
      darkTheme: gubsDarkTheme,
      // Sem esta linha o `MaterialApp` usa `ThemeMode.system` e a escolha de
      // tema feita em Ajustes não teria efeito nenhum — o app já tinha os dois
      // temas e nenhuma forma de escolher entre eles.
      themeMode: switch (ref.watch(themeModeProvider)) {
        GubsThemeMode.system => ThemeMode.system,
        GubsThemeMode.light => ThemeMode.light,
        GubsThemeMode.dark => ThemeMode.dark,
      },
      // A ampliação escolhida no app MULTIPLICA a do sistema, com teto em 2x.
      // O porquê de cada metade dessa frase está em `ui/theme/text_scaling.dart`.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: gubsTextScaler(
              media.textScaler,
              ref.watch(fontScaleProvider),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
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
