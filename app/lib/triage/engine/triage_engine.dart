/// Contrato dos motores de triagem (padrão Strategy — espec.md §2.1).
///
/// A escada de degradação do RF-12 (`LlamaEngine → RuleOnlyEngine → conteúdo
/// estático`) é implementada trocando a estratégia ativa, não espalhando
/// condicionais pelo orquestrador.
library;

import 'package:meta/meta.dart';

/// Sugestão de desfecho vinda de um motor.
///
/// `severityLevel` NÃO é escolhido pelo motor: é lido da tabela
/// `routing_outcome` do pacote a partir do `outcomeId`. Um modelo local não
/// consegue inventar um nível de severidade — no máximo consegue nomear um
/// desfecho que já existe e já passou por revisão clínica.
@immutable
class EngineSuggestion {
  const EngineSuggestion({required this.outcomeId, required this.severityLevel});

  final String outcomeId;
  final int severityLevel;

  @override
  String toString() => 'EngineSuggestion($outcomeId, sev=$severityLevel)';
}

/// Motor de triagem.
///
/// Contrato que toda implementação deve honrar:
///
/// 1. `infer` **nunca lança** para entrada válida — falha vira `null`.
/// 2. `null` significa "sem opinião": o veredito do gate prevalece.
/// 3. `infer` respeita [timeout] como limite de parede.
abstract interface class TriageEngine {
  /// Identificador estável para telemetria agregada (nunca por sessão).
  String get id;

  /// `false` desqualifica o motor antes de qualquer tentativa: sem modelo em
  /// disco, sem biblioteca nativa, RAM insuficiente (espec.md A1).
  bool get isAvailable;

  /// Limite de parede da inferência. RF-05 fixa 5 s como teto duro.
  Duration get timeout;

  /// Sugere um desfecho para o conjunto de tokens da sessão.
  Future<EngineSuggestion?> infer(Set<String> tokens);

  /// Libera recursos nativos. Idempotente.
  Future<void> dispose();
}
