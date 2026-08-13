/// ===========================================================================
/// SUITE GOLDEN CLÍNICA — implementação Dart
/// ===========================================================================
///
/// Roda os MESMOS casos de `seed/golden/clinical_cases.yaml` contra as MESMAS
/// regras de `seed/003_routing.sql`, usando o gate do app.
///
/// É este teste que garante que o gate Dart e o avaliador de referência em
/// TypeScript (`packer/src/rules.ts`) não divergem: os dois são obrigados a
/// concordar com o mesmo arquivo de casos. Uma divergência reprova aqui ou no
/// packer — nunca chega a um dispositivo.
///
/// Critério de aprovação: 100%. Falso negativo (esperava a maior severidade e
/// obteve menos) é relatado à parte: é o caso em que o app mandaria para casa
/// quem precisava de emergência.
///
/// O pacote é construído em memória a partir do DDL do contrato e do SQL
/// semente, então o teste não depende de o packer ter rodado antes.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/content/data/pack_rule_source.dart';
import 'package:guia_ubs/triage/domain/routing_rule.dart';
import 'package:guia_ubs/triage/gate/red_flag_gate.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:yaml/yaml.dart';

import '../support/in_memory_pack.dart';

void main() {
  late Database db;
  late RuleModel model;
  late List<dynamic> cases;

  setUpAll(() {
    db = buildInMemoryPack();
    model = loadRuleModel(db);
    final yaml = loadYaml(goldenCasesFile.readAsStringSync()) as YamlMap;
    cases = (yaml['cases'] as YamlList).toList();
  });

  tearDownAll(() => db.dispose());

  test('o pacote semente tem regras e desfechos carregáveis', () {
    expect(model.rules, isNotEmpty);
    expect(model.outcomes.keys, containsAll(<String>['ROUTINE_UBS', 'EMERGENCY']));
    expect(model.maxSeverity, greaterThan(model.outcomes['ROUTINE_UBS']!.severityLevel));
  });

  test('a suite golden não está vazia', () {
    expect(cases, isNotEmpty, reason: 'sem casos golden não há rede de segurança');
  });

  test('todos os casos golden passam, sem nenhum falso negativo clínico', () {
    final failures = <String>[];
    final falseNegatives = <String>[];

    for (final raw in cases) {
      final testCase = raw as YamlMap;
      final id = testCase['id'] as String;
      final tokens = (testCase['tokens'] as YamlList).cast<String>().toSet();
      final expected = testCase['expect'] as String;

      final verdict = evaluate(tokens, model);
      if (verdict.outcomeId == expected) continue;

      final expectedSeverity = model.outcomes[expected]?.severityLevel ?? -1;
      final line = 'caso "$id" [${tokens.join(' + ')}]: '
          'esperado $expected, obtido ${verdict.outcomeId} '
          '(${verdict.matchedRuleId ?? "desfecho padrão"})';

      if (expectedSeverity == model.maxSeverity &&
          verdict.severityLevel < expectedSeverity) {
        falseNegatives.add(line);
      } else {
        failures.add(line);
      }
    }

    expect(
      falseNegatives,
      isEmpty,
      reason: 'FALSO NEGATIVO CLÍNICO — o app mandaria para casa quem precisa '
          'de emergência:\n${falseNegatives.join('\n')}',
    );
    expect(failures, isEmpty, reason: 'casos golden reprovados:\n${failures.join('\n')}');
  });

  test('toda red flag do pacote é alcançável por algum caso golden', () {
    // Regra de emergência sem caso golden é regra sem rede de segurança:
    // ninguém perceberia se ela parasse de disparar.
    final redFlagIds = model.rules
        .where((r) => model.outcomes[r.outcomeId]?.severityLevel == model.maxSeverity)
        .map((r) => r.id)
        .toSet();

    final exercised = <String>{};
    for (final raw in cases) {
      final testCase = raw as YamlMap;
      final tokens = (testCase['tokens'] as YamlList).cast<String>().toSet();
      final verdict = evaluate(tokens, model);
      if (verdict.matchedRuleId != null) exercised.add(verdict.matchedRuleId!);
    }

    expect(
      redFlagIds.difference(exercised),
      isEmpty,
      reason: 'red flags sem nenhum caso golden que as exercite',
    );
  });
}
