/// O ÚNICO ponto de entrada do isolate de background.
///
/// ===========================================================================
/// UM DISPATCHER, NÃO UM POR TRABALHO
/// ===========================================================================
///
/// `Workmanager().initialize()` aceita **uma** função, e ela recebe TODAS as
/// tarefas. A primeira versão deste código tinha dois dispatchers — um para o
/// modelo, outro para o pack — e só o do modelo era registrado. O do pack
/// existia, compilava, tinha comentário explicando seu papel, e nunca era
/// chamado: a tarefa de conteúdo caía no `if (task != modelSyncTaskName)
/// return true` do outro dispatcher e era silenciosamente marcada como
/// concluída.
///
/// O sync de conteúdo estaria agendado e nunca aconteceria. Nada falharia,
/// nenhum log apareceria, e a frota simplesmente pararia de receber correção
/// clínica.
library;

import 'package:workmanager/workmanager.dart';

import 'model_background_sync.dart';
import 'model_sync_scheduler.dart';
import 'pack_background_sync.dart';
import 'pack_sync_scheduler.dart';

/// `@pragma('vm:entry-point')` é obrigatório: sem ele o AOT remove esta função
/// do binário de release, e o trabalho agendado falha em produção enquanto
/// continua funcionando em debug.
@pragma('vm:entry-point')
void gubsCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    return switch (task) {
      modelSyncTaskName => runModelSyncTask(),
      packSyncTaskName => runPackSyncTask(),
      // Tarefa desconhecida: `true` para o WorkManager parar de tentar. Pode
      // ser um agendamento de uma versão anterior do app que ainda não expirou.
      _ => true,
    };
  });
}

/// Inicializa o WorkManager. Chamado uma vez, no `main`.
Future<void> initBackgroundSync() =>
    Workmanager().initialize(gubsCallbackDispatcher);
