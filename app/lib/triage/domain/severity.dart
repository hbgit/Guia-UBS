/// Combinação de severidades — o ponto onde a INV-1 é imposta em código.
///
/// ===========================================================================
/// CÓDIGO CRÍTICO DE SEGURANÇA DO PACIENTE
/// ===========================================================================
///
/// `severidade_final = max(gate, llm)` (espec.md §5.1 INV-1, RF-05).
///
/// Existe uma única função capaz de produzir o resultado final de uma triagem,
/// e ela é monotônica: a sugestão do modelo só consegue SUBIR a severidade.
/// Nenhum caminho do código permite que uma inferência rebaixe o veredito
/// determinístico — não por convenção, mas porque não há outra função.
library;

import 'package:meta/meta.dart';

import '../engine/triage_engine.dart';
import 'routing_rule.dart';

/// Classe clínica de um desfecho, usada para escolher ícone, cor e ênfase.
///
/// Vive no domínio da triagem, e não no tema: é uma classificação clínica que
/// a UI CONSOME. A regra de dependência da espec §2.2 é `ui → triage`, nunca o
/// contrário — e um enum de severidade dentro da paleta convidaria a decidir
/// severidade a partir de cor, que é a inversão exata que a INV-1 proíbe.
enum GubsSeverity {
  /// Rotina: procurar a UBS. Verde.
  routine,

  /// Entre rotina e emergência: procurar atendimento sem urgência máxima.
  attention,

  /// Emergência: UPA, hospital ou 192. Vermelho.
  emergency,
}

/// De onde veio o desfecho final apresentado ao usuário.
enum TriageSource {
  /// Gate determinístico decidiu sozinho (red flag ou modelo sem opinião).
  gate,

  /// Modelo local escalou a severidade acima do gate.
  engine,
}

/// Resultado final de uma sessão de triagem.
///
/// Não guarda os tokens: a sequência de sintomas morre em memória junto com a
/// sessão e nunca é persistida (LGPD-RF13, INV-2).
@immutable
class TriageResult {
  const TriageResult({
    required this.outcomeId,
    required this.severityLevel,
    required this.source,
    required this.degraded,
    required this.matchedRuleId,
  });

  final String outcomeId;
  final int severityLevel;
  final TriageSource source;

  /// `true` quando o motor local não pôde ser usado e a triagem completou só
  /// com regras (RF-12). Vira contador agregado de telemetria, nunca evento
  /// individual.
  final bool degraded;

  /// Regra determinística vencedora, quando houve.
  final String? matchedRuleId;

  @override
  String toString() => 'TriageResult($outcomeId, sev=$severityLevel, '
      'origem=${source.name}, degradado=$degraded)';
}

/// Combina o veredito determinístico com a sugestão do motor local.
///
/// A sugestão é DESCARTADA quando não supera o gate. Isso cobre três casos com
/// a mesma regra, sem ramificação especial para nenhum deles:
///
/// * modelo concorda com o gate  → gate prevalece (mesma severidade);
/// * modelo tenta rebaixar       → ignorado;
/// * modelo sem opinião (`null`) → gate prevalece.
///
/// `degraded` descreve a DISPONIBILIDADE do motor, não o desfecho: uma red flag
/// resolvida sem consultar o modelo não é degradação, é o caminho previsto.
TriageResult mergeVerdict(
  TriageVerdict gate,
  EngineSuggestion? suggestion, {
  required bool degraded,
}) {
  if (suggestion == null || suggestion.severityLevel <= gate.severityLevel) {
    return TriageResult(
      outcomeId: gate.outcomeId,
      severityLevel: gate.severityLevel,
      source: TriageSource.gate,
      degraded: degraded,
      matchedRuleId: gate.matchedRuleId,
    );
  }

  return TriageResult(
    outcomeId: suggestion.outcomeId,
    severityLevel: suggestion.severityLevel,
    source: TriageSource.engine,
    degraded: degraded,
    matchedRuleId: gate.matchedRuleId,
  );
}

/// Classe visual de um `severity_level`, **relativa à escala do pack**.
///
/// ===========================================================================
/// CÓDIGO CRÍTICO DE SEGURANÇA DO PACIENTE
/// ===========================================================================
///
/// `severity_level` é um inteiro definido pelo CONTEÚDO, não pelo binário: o
/// pack semente usa 10 para rotina e 100 para emergência, e um município pode
/// publicar outra escala amanhã. Limiares fixos em Dart são, portanto, uma
/// segunda fonte de verdade sobre severidade clínica — e a primeira versão
/// desta conversão tinha exatamente isso, o que fazia todo resultado de rotina
/// aparecer vermelho, com "Ligue 192" embaixo.
///
/// Aqui os extremos vêm dos desfechos do próprio pack, os mesmos que o gate lê:
///
/// * `level >= max` → emergência (é a definição de red flag em [isRedFlag]);
/// * `level <= min` → rotina;
/// * entre os dois → atenção.
///
/// **Fail-safe para cima:** um pack degenerado, sem desfechos, devolve
/// emergência. Na dúvida, o conservador é mandar procurar atendimento — custa
/// um cartão vermelho a mais; o contrário custa um encaminhamento errado.
GubsSeverity severityFor(int level, RuleModel model) {
  if (model.outcomes.isEmpty) return GubsSeverity.emergency;

  final levels = model.outcomes.values.map((o) => o.severityLevel);
  final max = levels.reduce((a, b) => a > b ? a : b);
  final min = levels.reduce((a, b) => a < b ? a : b);

  if (level >= max) return GubsSeverity.emergency;
  if (level <= min) return GubsSeverity.routine;
  return GubsSeverity.attention;
}
