/// Política de agendamento do download do modelo em segundo plano.
///
/// O onboarding baixa em PRIMEIRO plano, com o usuário olhando. Este agendador
/// cobre o resto: retomar o que ficou pela metade quando o Wi-Fi voltar, sem
/// que ninguém precise abrir o app.
///
/// A política vive aqui, em Dart puro e testável; o `WorkManager` do Android é
/// só o gatilho. Essa separação existe porque a regra "só em rede não tarifada,
/// a menos que o administrador libere" é decisão de produto — e decisão de
/// produto não deve morar em configuração de plugin.
library;

import 'package:meta/meta.dart';

import 'model_provisioning.dart';

/// Identificador único do trabalho periódico. Fixo: reagendar não pode
/// multiplicar downloads de 800 MB.
const String modelSyncTaskName = 'br.gov.exemplo.guia_ubs.model_sync';

@immutable
class ModelSyncPolicy {
  const ModelSyncPolicy({
    this.requiresUnmetered = true,
    this.requiresBatteryNotLow = true,
    this.backoff = const Duration(minutes: 15),
  });

  /// Restrição UNMETERED: só Wi-Fi ou cabo.
  ///
  /// 800 MB no plano de dados de um agente comunitário é um custo que ninguém
  /// autorizou. O override do administrador desliga isto conscientemente.
  final bool requiresUnmetered;

  /// Não disputar bateria com o aparelho quase descarregado — o app precisa
  /// estar vivo para o atendimento, não para terminar um download.
  final bool requiresBatteryNotLow;

  /// Espera antes de tentar de novo após falha transitória.
  final Duration backoff;

  /// Política efetiva dado o override do administrador.
  ModelSyncPolicy withMeteredOverride({required bool allowed}) =>
      ModelSyncPolicy(
        requiresUnmetered: !allowed,
        requiresBatteryNotLow: requiresBatteryNotLow,
        backoff: backoff,
      );
}

/// Decide se vale acordar o download agora.
///
/// Pura de propósito: a mesma regra é avaliada pelo agendador nativo e pelos
/// testes, sem emulador no meio.
bool shouldAttemptDownload({
  required NetworkClass network,
  required ModelSyncPolicy policy,
  required bool batteryLow,
  required bool alreadyProvisioned,
}) {
  if (alreadyProvisioned) return false;
  if (network == NetworkClass.none) return false;
  if (policy.requiresUnmetered && network != NetworkClass.unmetered) {
    return false;
  }
  if (policy.requiresBatteryNotLow && batteryLow) return false;
  return true;
}
