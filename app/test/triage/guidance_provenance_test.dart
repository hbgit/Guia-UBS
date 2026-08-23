/// A derivacao da procedencia, percorrida inteira.
///
/// Existe porque a regra tem uma armadilha de ORDEM: um resultado degradado
/// tambem tem `source == gate`, e se a verificacao de `degraded` viesse depois
/// do caso comum, o app diria "o assistente participou" para um resultado
/// produzido com o assistente indisponivel. Nao seria erro de compilacao nem
/// de layout — seria o app mentindo sobre a origem de uma orientacao de saude.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/triage/domain/guidance_provenance.dart';
import 'package:guia_ubs/triage/domain/severity.dart';

TriageResult _resultado({
  required TriageSource source,
  required bool degraded,
}) =>
    TriageResult(
      outcomeId: 'ubs_rotina',
      severityLevel: 10,
      source: source,
      degraded: degraded,
      matchedRuleId: 'r1',
    );

void main() {
  group('a tabela source x degraded', () {
    test('gate com motor disponivel: regras do posto', () {
      expect(
        provenanceFor(_resultado(source: TriageSource.gate, degraded: false)),
        GuidanceProvenance.rules,
      );
    });

    test('motor escalou: assistente virtual', () {
      expect(
        provenanceFor(_resultado(source: TriageSource.engine, degraded: false)),
        GuidanceProvenance.assistant,
      );
    });

    test('degradado: regras do posto SEM assistente', () {
      expect(
        provenanceFor(_resultado(source: TriageSource.gate, degraded: true)),
        GuidanceProvenance.rulesOnly,
      );
    });
  });

  test('degradado nunca e confundido com o caso comum', () {
    // A prova da ordem: os dois tem `source == gate` e precisam sair
    // diferentes. Inverter as duas linhas da funcao quebra ESTE teste.
    final comum = _resultado(source: TriageSource.gate, degraded: false);
    final degradado = _resultado(source: TriageSource.gate, degraded: true);

    expect(provenanceFor(comum), isNot(provenanceFor(degradado)));
  });

  test('o estado inalcancavel nao inventa um quarto caso', () {
    // `mergeVerdict` nunca produz (engine, degraded: true) — o motor nao pode
    // ter opinado estando indisponivel. Se um dia produzir, "assistente" e a
    // resposta honesta: ele opinou, e e isso que o usuario precisa saber.
    expect(
      provenanceFor(_resultado(source: TriageSource.engine, degraded: true)),
      GuidanceProvenance.assistant,
    );
  });

  test('a severidade nao influencia a procedencia', () {
    // Sao eixos independentes: uma emergencia pode vir das regras ou do
    // assistente, e o selo precisa dizer qual — nao adivinhar pela cor.
    for (final nivel in [10, 50, 100]) {
      final r = TriageResult(
        outcomeId: 'x',
        severityLevel: nivel,
        source: TriageSource.engine,
        degraded: false,
        matchedRuleId: null,
      );
      expect(provenanceFor(r), GuidanceProvenance.assistant, reason: 'sev $nivel');
    }
  });
}
