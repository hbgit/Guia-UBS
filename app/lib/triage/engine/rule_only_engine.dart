/// Kill switch da triagem (RF-12) — o último degrau antes do conteúdo estático.
///
/// ===========================================================================
/// CÓDIGO CRÍTICO DE SEGURANÇA DO PACIENTE
/// ===========================================================================
///
/// Este motor **não tem lógica clínica própria**: ele chama `evaluate()`, o
/// mesmo avaliador que o gate usa, sobre a MESMA tabela do pacote.
///
/// Isso é uma exigência de projeto, não uma economia de código (CLAUDE.md;
/// espec.md §7 — "proibido lógica duplicada em código"). Se o fallback tivesse
/// sua própria cópia das regras, ela sairia de sincronia com o gate na primeira
/// revisão clínica e o app degradado passaria a discordar do app saudável
/// exatamente quando ninguém está olhando.
///
/// Propriedades que o restante do sistema assume:
///
/// * **Total** — responde para qualquer conjunto de tokens, inclusive vazio.
/// * **Determinístico** — mesma entrada, mesma saída, sem relógio nem I/O.
/// * **Sempre disponível** — `isAvailable` é constante `true`; não há nada que
///   possa faltar. É por isso que ele é o piso da escada de degradação.
library;

import '../domain/routing_rule.dart';
import '../gate/red_flag_gate.dart';
import 'triage_engine.dart';

class RuleOnlyEngine implements TriageEngine {
  const RuleOnlyEngine(this._model);

  final RuleModel _model;

  @override
  String get id => 'rule_only';

  /// Sem biblioteca nativa, sem modelo em disco, sem alocação: nada a checar.
  @override
  bool get isAvailable => true;

  /// Execução é síncrona e em memória; o timeout existe só para satisfazer o
  /// contrato da interface. Nenhum caminho aqui pode esgotá-lo.
  @override
  Duration get timeout => Duration.zero;

  @override
  Future<EngineSuggestion?> infer(Set<String> tokens) async => decide(tokens);

  /// Versão síncrona — o orquestrador usa esta no caminho de fallback para não
  /// introduzir um salto de event loop onde não existe espera de verdade.
  ///
  /// Nunca retorna `null`: diferente de um motor probabilístico, o avaliador
  /// determinístico sempre tem uma resposta (o desfecho padrão do pacote, no
  /// pior caso).
  EngineSuggestion decide(Set<String> tokens) {
    final verdict = evaluate(tokens, _model);
    return EngineSuggestion(
      outcomeId: verdict.outcomeId,
      severityLevel: verdict.severityLevel,
    );
  }

  @override
  Future<void> dispose() async {}
}
