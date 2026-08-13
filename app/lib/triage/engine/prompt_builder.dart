/// Montagem determinística do prompt (RF-05).
///
/// Função pura: o mesmo conjunto de tokens produz a MESMA string, byte a byte.
/// Determinismo aqui é pré-requisito de reprodutibilidade clínica — junto com
/// temperatura 0 e seed fixa no lado nativo, é o que permite que um caso
/// investigado depois seja reexecutado e dê o mesmo resultado.
///
/// Por isso os tokens são **ordenados** antes de entrar no texto: `Set` em Dart
/// preserva ordem de inserção, então "dor" + "peito" e "peito" + "dor" gerariam
/// prompts diferentes — e potencialmente respostas diferentes — se o usuário
/// tocasse nos ícones em ordem trocada.
library;

import '../domain/routing_rule.dart';

/// Teto de tokens de sintoma por sessão (FSM-A, guarda de S1_COMPOSING).
///
/// O construtor de prompt trunca de forma defensiva: se um bug de UI deixar
/// passar mais que isso, o orçamento de contexto do modelo continua fechado e
/// a latência p95 não estoura por causa de um prompt inflado.
const int maxSessionTokens = 5;

/// Orçamento de caracteres do prompt. Estourar significa que o catálogo de
/// desfechos cresceu além do que cabe no contexto de um device de entrada —
/// falha ruidosa em teste, nunca degradação silenciosa de latência em campo.
const int promptCharBudget = 1200;

/// Monta o prompt de classificação.
///
/// O modelo recebe uma tarefa fechada: escolher UM identificador de uma lista
/// que veio do pacote. Não pedimos texto livre nem justificativa — o que não é
/// um identificador conhecido é descartado pelo decodificador.
String buildTriagePrompt(Set<String> tokens, RuleModel model) {
  final orderedTokens = tokens.toList()..sort();
  final truncated = orderedTokens.length > maxSessionTokens
      ? orderedTokens.sublist(0, maxSessionTokens)
      : orderedTokens;

  final outcomeIds = model.outcomes.keys.toList()..sort();

  final buffer = StringBuffer()
    ..writeln('Classifique o encaminhamento de saude a partir dos sinais.')
    ..writeln('Responda APENAS com um identificador da lista, sem explicacao.')
    ..writeln()
    ..writeln('Identificadores permitidos:');
  for (final id in outcomeIds) {
    buffer.writeln('- $id');
  }
  buffer
    ..writeln()
    ..writeln('Sinais:');
  for (final token in truncated) {
    buffer.writeln('- $token');
  }
  buffer
    ..writeln()
    ..write('Resposta:');

  final prompt = buffer.toString();
  if (prompt.length > promptCharBudget) {
    throw StateError(
      'Prompt com ${prompt.length} caracteres excede o orcamento de '
      '$promptCharBudget — o catalogo de desfechos cresceu alem do contexto '
      'previsto para device de entrada (RNF-02).',
    );
  }
  return prompt;
}
