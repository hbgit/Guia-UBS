/// Carrega o modelo de encaminhamento do `content.db`.
///
/// O pacote é aberto SOMENTE LEITURA: o app nunca escreve conteúdo, apenas
/// troca o arquivo inteiro quando o sync instala uma versão nova (espec.md
/// FSM-B). Separar esta leitura do gate mantém o gate uma função pura,
/// testável sem banco algum.
library;

import 'package:sqlite3/sqlite3.dart';

import '../../triage/domain/routing_rule.dart';

/// Lê regras, desfechos e o desfecho padrão de um pacote já verificado.
///
/// Pressupõe que a assinatura Ed25519 e o SHA-256 já foram conferidos pelo
/// sync — este ponto do código não valida procedência (espec.md INV-3).
RuleModel loadRuleModel(Database db) {
  final outcomes = <String, RoutingOutcome>{};
  for (final row in db.select('SELECT id, severity_level FROM routing_outcome')) {
    final id = row['id'] as String;
    outcomes[id] = RoutingOutcome(
      id: id,
      severityLevel: row['severity_level'] as int,
    );
  }

  final termsByRule = <String, List<RuleTerm>>{};
  for (final row in db.select(
    'SELECT rule_id, group_no, token_id, negated FROM routing_rule_term',
  )) {
    termsByRule.putIfAbsent(row['rule_id'] as String, () => <RuleTerm>[]).add(
          RuleTerm(
            groupNo: row['group_no'] as int,
            tokenId: row['token_id'] as String,
            negated: (row['negated'] as int) == 1,
          ),
        );
  }

  final rules = <RoutingRule>[];
  for (final row in db.select(
    'SELECT id, priority, outcome_id FROM routing_rule ORDER BY priority',
  )) {
    final id = row['id'] as String;
    rules.add(
      RoutingRule(
        id: id,
        priority: row['priority'] as int,
        outcomeId: row['outcome_id'] as String,
        terms: termsByRule[id] ?? const <RuleTerm>[],
      ),
    );
  }

  final meta = db.select('SELECT default_outcome_id FROM pack_meta WHERE id = 1');
  if (meta.isEmpty) {
    throw StateError('pack_meta ausente — pacote inválido');
  }

  return RuleModel(
    rules: rules,
    outcomes: outcomes,
    defaultOutcomeId: meta.first['default_outcome_id'] as String,
  );
}

/// Abre um pacote somente leitura no caminho informado.
Database openPack(String path) => sqlite3.open(path, mode: OpenMode.readOnly);
