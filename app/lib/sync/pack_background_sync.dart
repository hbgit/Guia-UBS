/// Ponte com o WorkManager para o ciclo de conteúdo (FSM-B).
///
/// O item 9 entregou a máquina e o driver; isto é o que faz o ciclo acontecer
/// sem ninguém abrir o app — que é o ponto do RF-10, já que o usuário nunca
/// pede um sync.
///
/// ## Quiescência no background é trivialmente verdadeira, e isso não é folga
///
/// O guard da linha B11 impede a troca de pack durante uma sessão de triagem.
/// Aqui não há sessão: o isolate de background não tem UI. Mas a troca ainda é
/// segura porque o desenho não depende só do guard — packs vivem nomeados pelo
/// hash e o commit é um rename do manifest, então uma leitura em voo no
/// processo de UI termina no arquivo antigo, íntegro (análise S1 da espec).
///
/// O que o background NÃO faz é reabrir as conexões do processo de UI. Por
/// isso o app recarrega o `ActiveContent` ao voltar para o primeiro plano.
library;

import 'package:workmanager/workmanager.dart';

import '../core/app_paths.dart';
import 'pack_store.dart';
import 'pack_sync_scheduler.dart';
import 'sync_service.dart';

/// URL do manifest do município. Versionada no código, como o artefato do
/// modelo: um espelho não pode redirecionar a frota para outro conteúdo.
const String packManifestUrl = String.fromEnvironment(
  'PACK_MANIFEST_URL',
  defaultValue: 'http://127.0.0.1:9000/content-packs/0000000/manifest.json',
);

/// Executa um ciclo da FSM-B.
///
/// Não é o dispatcher: o WorkManager tem UM ponto de entrada, em
/// `background_sync.dart`.
Future<bool> runPackSyncTask() async {
    final service = SyncService(
      manifestUrl: Uri.parse(packManifestUrl),
      store: PackStore(await packsDirectory()),
      // Sem UI, sem sessão de triagem: a FSM-A está em repouso por construção.
      quiescence: () => true,
    );

    try {
      await service.runCycle();
      // `true` sempre: o reagendamento de verdade é o trabalho PERIÓDICO, e o
      // freio é o `SyncRetryState` persistido. Pedir backoff ao WorkManager
      // aqui somaria dois freios independentes sobre o mesmo problema, e o
      // resultado seria uma frota que demora mais do que qualquer um dos dois
      // pretendia.
      return true;
    } on Object {
      // Nunca lança: falha de sync não pode virar crash de background.
      return true;
    } finally {
      service.close();
    }
}

Constraints _constraintsFrom(PackSyncPolicy policy) => Constraints(
      networkType:
          policy.requiresUnmetered ? NetworkType.unmetered : NetworkType.connected,
      requiresBatteryNotLow: policy.requiresBatteryNotLow,
    );

Future<void> schedulePackSync({
  PackSyncPolicy policy = const PackSyncPolicy(),
}) async {
  await Workmanager().registerPeriodicTask(
    packSyncTaskName,
    packSyncTaskName,
    frequency: policy.frequency,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: _constraintsFrom(policy),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: policy.backoff,
  );
}

Future<void> cancelPackSync() =>
    Workmanager().cancelByUniqueName(packSyncTaskName);
