/// Ponto de entrada. A responsabilidade aqui é uma só: decidir se o usuário vê
/// o onboarding ou o app, e nunca deixar uma falha de provisionamento virar
/// tela de erro.
///
/// A casca definitiva (tema, GoRouter, i18n) é o item 10 da Fase 2; isto é o
/// mínimo para que o fluxo de primeiro acesso exista de ponta a ponta.
library;

import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'core/app_paths.dart';
import 'sync/model_background_sync.dart';
import 'sync/model_catalog.dart';
import 'sync/model_provisioning.dart';
import 'sync/model_sync_scheduler.dart';
import 'ui/onboarding/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Falha aqui não pode impedir o app de abrir: sem agendador, o modelo só é
  // baixado em primeiro plano — degradação, não impedimento (INV-8).
  try {
    await initModelBackgroundSync();
  } on Object {
    // Segue sem sync em background.
  }
  runApp(const GuiaUbsApp());
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
  final unmetered = results.any((r) =>
      r == ConnectivityResult.wifi ||
      r == ConnectivityResult.ethernet);
  return unmetered ? NetworkClass.unmetered : NetworkClass.metered;
}

class GuiaUbsApp extends StatefulWidget {
  const GuiaUbsApp({super.key});

  @override
  State<GuiaUbsApp> createState() => _GuiaUbsAppState();
}

class _GuiaUbsAppState extends State<GuiaUbsApp> {
  late final ModelProvisioning _provisioning = ModelProvisioning(
    artifact: activeModel,
    destinationDirectory: modelsDirectory,
    networkClass: currentNetworkClass,
  );

  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // O agendador só interessa enquanto falta modelo. Quando o provisionamento
    // conclui, cancelamos: manter um job periódico para baixar algo que já
    // existe é gasto de bateria sem contrapartida.
    _provisioning.states.listen((state) {
      if (state.stage == SetupStage.ready) {
        cancelModelSync().ignore();
      } else if (state.stage == SetupStage.readyDegraded ||
          state.stage == SetupStage.blocked) {
        // Seguiu sem o modelo, ou travou: o background assume a partir daqui.
        scheduleModelSync(
          policy: const ModelSyncPolicy()
              .withMeteredOverride(allowed: _provisioning.allowMeteredNetworks),
        ).ignore();
      }
    });
  }

  @override
  void dispose() {
    _provisioning.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guia UBS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
        useMaterial3: true,
      ),
      home: _ready
          ? const _ClinicalHomePlaceholder()
          : OnboardingScreen(
              provisioning: _provisioning,
              pickLocalModel: pickModelFromStorage,
              onReady: () {
                if (!_ready && mounted) setState(() => _ready = true);
              },
            ),
    );
  }
}

/// Marcador da tela clínica. O conteúdo real chega nos itens 10–13 da Fase 2.
class _ClinicalHomePlaceholder extends StatelessWidget {
  const _ClinicalHomePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.local_hospital, size: 96),
              const SizedBox(height: 24),
              Text(
                'Pronto para atender',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Telas de triagem chegam nos itens 10-13 da Fase 2.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
