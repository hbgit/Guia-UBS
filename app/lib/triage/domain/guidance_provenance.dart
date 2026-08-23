/// De onde veio a orientação que o usuário está lendo.
///
/// ===========================================================================
/// PROCEDÊNCIA É DERIVADA, NUNCA GUARDADA DE NOVO
/// ===========================================================================
///
/// O dado já existe: [TriageResult] carrega `source` e `degraded` desde o item
/// 12. Guardar um terceiro campo dizendo a mesma coisa criaria duas fontes de
/// verdade para "quem produziu isto" — e a que ficasse para trás mentiria ao
/// usuário sobre a origem de uma orientação de saúde.
///
/// Por isso a regra mora aqui, como **função pura**, no mesmo lugar e pelo
/// mesmo motivo que `severityFor`: quando a regra é derivação, ela vira algo
/// que um teste percorre sem inflar tela nenhuma.
///
/// ## A diferença entre `source` e `degraded`
///
/// As duas respondem perguntas distintas, e confundi-las produziria um selo
/// errado:
///
/// * `source` diz **quem escolheu o desfecho exibido** — a tabela determinística
///   ou o motor local que escalou acima dela;
/// * `degraded` diz **se o motor estava disponível**, e não tem opinião sobre o
///   desfecho. Uma red flag resolvida sem consultar o motor não é degradação.
///
/// Como `mergeVerdict` só produz `source == engine` quando o motor opinou, o
/// par `(engine, degraded: true)` é inalcançável. A ordem de teste abaixo
/// reflete isso e não deixa estado impossível.
library;

import 'severity.dart';

/// Os três estados que o selo de procedência distingue.
enum GuidanceProvenance {
  /// O veredito determinístico prevaleceu, e a sessão **não** foi marcada como
  /// degradada. Dois caminhos chegam aqui, e os dois são honestos:
  ///
  /// * **red flag** (INV-1): a regra de segurança dispara, a FSM vai direto ao
  ///   resultado e o modelo sequer é consultado;
  /// * **modelo consultado que não superou o gate**: ele respondeu, a resposta
  ///   não escalou a severidade e foi descartada por `mergeVerdict`. Quem
  ///   decidiu o desfecho exibido foi a tabela de regras.
  ///
  /// Note a diferença para [rulesOnly]: lá o modelo respondeu **sem opinião**
  /// (`null`) ou falhou, e a sessão marca degradado. Aqui ele teve opinião — só
  /// não venceu.
  rules,

  /// O motor local escalou acima do gate: o desfecho exibido é a escolha dele.
  assistant,

  /// O modelo **não contribuiu** e o desfecho veio das regras.
  ///
  /// Cobre três situações que a sessão trata igual, e com razão: motor
  /// indisponível, motor que falhou ou estourou o teto, e motor que respondeu
  /// **sem opinião** — este último é o que surpreende, e está escrito em
  /// `triage_session.dart`: "Sem opinião do modelo também vai para o fallback".
  ///
  /// Do ponto de vista de quem lê a tela, as três dizem a mesma coisa: o
  /// assistente não participou desta orientação.
  rulesOnly,
}

/// Classifica um resultado para efeito de exibição.
///
/// A ordem importa: `degraded` é testado ANTES do caso comum, porque um
/// resultado degradado também tem `source == gate` e cairia em [rules] se a
/// verificação viesse depois — o app diria que o assistente participou quando
/// ele sequer estava disponível.
GuidanceProvenance provenanceFor(TriageResult result) {
  if (result.source == TriageSource.engine) return GuidanceProvenance.assistant;
  if (result.degraded) return GuidanceProvenance.rulesOnly;
  return GuidanceProvenance.rules;
}
