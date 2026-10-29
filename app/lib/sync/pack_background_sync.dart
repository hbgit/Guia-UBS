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

/// URL do manifest do município, constante de compilação: um espelho não
/// pode redirecionar a frota para outro conteúdo.
///
/// ===========================================================================
/// SEM VALOR PADRÃO, DE PROPÓSITO (#45)
/// ===========================================================================
///
/// O padrão antigo era o loopback do próprio aparelho: um release construído
/// sem o define buscava conteúdo em lugar nenhum, contava cada tentativa como
/// falha, e a frota nunca recebia correção clínica — sem nenhum erro visível.
/// Vazio (ou `http` fora do debug), o `SyncService` se declara não configurado
/// e não toca a rede; o "Sobre" avisa; e `tool/build_apk.sh` recusa o build
/// antes de compilar. O valor chega por
/// `--dart-define-from-file=config/defines.<modo>.json`, como o `MODEL_URL`.
const String packManifestUrl = String.fromEnvironment('PACK_MANIFEST_URL');

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

/// Cancela o job periódico do pack. Usado quando o build não tem origem de
/// conteúdo (#45), inclusive para o job herdado de um build antigo.
Future<void> cancelPackSync() =>
    Workmanager().cancelByUniqueName(packSyncTaskName);
