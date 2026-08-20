/// Ponte com o WorkManager do Android para concluir o download do modelo.
///
/// O onboarding baixa em primeiro plano, com o usuário olhando. Isto cobre o
/// resto: o aparelho que ficou em modo degradado, ou cujo download foi cortado,
/// termina sozinho quando aparecer Wi-Fi — sem ninguém precisar abrir o app.
///
/// A POLÍTICA (o que é aceitável) mora em `model_sync_scheduler.dart`, em Dart
/// puro e testável. Aqui fica só a TRADUÇÃO dela para as restrições do
/// WorkManager. A separação existe porque "só em rede não tarifada, a menos que
/// o administrador libere" é decisão de produto, e decisão de produto não deve
/// morar em configuração de plugin.
library;

import 'dart:io';

import 'package:workmanager/workmanager.dart';

import '../core/app_paths.dart';
import 'model_catalog.dart';
import 'model_downloader.dart';
import 'model_sync_scheduler.dart';

/// Executa a tarefa de download do modelo.
///
/// Não é o dispatcher: o WorkManager tem UM ponto de entrada, em
/// `background_sync.dart`, que roteia as tarefas. Ver o comentário de lá para
/// o defeito que essa separação corrigiu.
///
/// Devolve `false` para pedir reagendamento com backoff.
Future<bool> runModelSyncTask() async {
    final dir = await modelsDirectory();
    final downloader = ModelDownloader(
      artifact: activeModel,
      destination: File('${dir.path}/${activeModel.fileName}'),
    );

    try {
      final result = await downloader.ensureAvailable();
      return switch (result) {
        // Pronto: o trabalho cumpriu seu papel e não precisa voltar.
        ModelReady() => true,
        // `false` pede REAGENDAMENTO com backoff. É o desfecho normal de uma
        // janela que fechou no meio — o parcial ficou salvo e a próxima
        // execução continua dele.
        ModelUnavailable(reason: ModelUnavailableReason.interrupted) => false,
        // Sem disco ou arquivo inválido: repetir agora não resolve. Devolver
        // `true` evita queimar bateria numa tentativa que já sabemos inútil;
        // a próxima janela periódica tenta de novo.
        ModelUnavailable() => true,
      };
    } finally {
      downloader.close();
    }
}

/// Traduz a política do projeto para as restrições do WorkManager.
Constraints _constraintsFrom(ModelSyncPolicy policy) => Constraints(
      networkType:
          policy.requiresUnmetered ? NetworkType.unmetered : NetworkType.connected,
      requiresBatteryNotLow: policy.requiresBatteryNotLow,
      // Alinhado ao portão de 3 GB do RNF-03: nem acordar quando o
      // armazenamento já está apertado.
      requiresStorageNotLow: true,
    );

/// Registra (ou reconfigura) o trabalho periódico.
///
/// `ExistingPeriodicWorkPolicy.update` é deliberado: quando o administrador
/// liga o override de dados móveis, o trabalho já agendado carrega a restrição
/// ANTIGA. Sem atualizar, o override não teria efeito até o próximo boot —
/// e `keep` (o padrão) preservaria silenciosamente a política velha.
Future<void> scheduleModelSync({
  ModelSyncPolicy policy = const ModelSyncPolicy(),
  Duration frequency = const Duration(hours: 6),
}) async {
  await Workmanager().registerPeriodicTask(
    modelSyncTaskName,
    modelSyncTaskName,
    frequency: frequency,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: _constraintsFrom(policy),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: policy.backoff,
  );
}

/// Cancela o trabalho. Chamado quando o modelo fica pronto — manter um job
/// periódico vivo para baixar algo que já existe só gasta bateria.
Future<void> cancelModelSync() =>
    Workmanager().cancelByUniqueName(modelSyncTaskName);

