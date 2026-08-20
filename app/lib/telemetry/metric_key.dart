/// A allowlist de telemetria, do lado do aparelho.
///
/// ===========================================================================
/// ESTA LISTA É O MECANISMO QUE MANTÉM A TELEMETRIA FORA DO ART. 12
/// ===========================================================================
///
/// Telemetria agregada só permanece fora do conceito de dado pessoal se for
/// irreversível (LGPD-RF14). A lista fechada é o que garante isso em código:
/// não existe API neste módulo que aceite uma chave arbitrária, então não
/// existe caminho pelo qual um campo novo chegue ao acumulador sem passar por
/// esta enum — e mexer nela aparece no diff, que é onde a revisão do encarregado
/// acontece.
///
/// **Proibidos por construção:** identificador de aparelho ou de instalação,
/// timestamp fino, sequência de tokens de sintoma, texto livre, localização.
/// Nenhum deles é expressável aqui, e é assim que deve continuar.
///
/// Espelha `METRIC_KEYS` em `contract/src/telemetry.ts`. As duas listas
/// divergirem faria o app emitir métrica que o pipeline rejeita — ou pior,
/// deixar de emitir uma que alguém acha que está sendo coletada. Há teste que
/// confere esta enum contra o `contract/telemetry-schema.json` gerado.
library;

/// Métricas que o app pode contar. Nada além disto.
enum MetricKey {
  triageCompletedTotal('triage_completed_total'),
  triageOutcomeRoutineTotal('triage_outcome_routine_total'),
  triageOutcomeEmergencyTotal('triage_outcome_emergency_total'),
  triageFallbackTotal('triage_fallback_total'),
  inferenceMsP50('inference_ms_p50'),
  inferenceMsP95('inference_ms_p95'),
  syncSuccessTotal('sync_success_total'),
  syncFailureTotal('sync_failure_total'),
  crashTotal('crash_total'),
  sessionTotal('session_total');

  const MetricKey(this.wireName);

  /// Nome no contrato. É o que apareceria num lote, se um dia houver envio.
  final String wireName;
}

/// Coorte mínima para um lote ser aceito no pipeline (LGPD-RF14).
///
/// Vive aqui como **documentação do contrato**, não como regra que o aparelho
/// possa aplicar: k é uma propriedade do conjunto de aparelhos, e um aparelho
/// sozinho não tem como saber quantos outros compõem sua coorte. Quem recusa
/// lote com k < 20 é o pipeline de ingestão.
const int kAnonymityMin = 20;
