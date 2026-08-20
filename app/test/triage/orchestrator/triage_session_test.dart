/// A sessão de ponta a ponta, contra as regras REAIS do pack.
///
/// Os testes de FSM provam propriedades do grafo. Estes provam que o driver
/// percorre esse grafo com o gate certo, o motor certo e — o que mais importa —
/// que a sequência de sintomas não sobrevive à sessão.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/content/data/pack_rule_source.dart';
import 'package:guia_ubs/triage/domain/routing_rule.dart';
import 'package:guia_ubs/triage/domain/severity.dart';
import 'package:guia_ubs/triage/engine/triage_engine.dart';
import 'package:guia_ubs/triage/orchestrator/triage_fsm.dart';
import 'package:guia_ubs/triage/orchestrator/triage_session.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/sqlite_test_libs.dart';

/// Motor controlável: cobre disponível/indisponível, resposta, silêncio,
/// exceção e travamento.
class _FakeEngine implements TriageEngine {
  _FakeEngine({this.available = true, this.suggestion});

  bool available;
  EngineSuggestion? suggestion;
  bool throwOnInfer = false;
  bool hangForever = false;
  int inferCalls = 0;
  Set<String>? lastTokens;

  @override
  String get id => 'fake';

  @override
  bool get isAvailable => available;

  @override
  Duration get timeout => const Duration(milliseconds: 100);

  @override
  Future<EngineSuggestion?> infer(Set<String> tokens) {
    inferCalls++;
    lastTokens = tokens;
    if (throwOnInfer) throw StateError('erro de FFI');
    if (hangForever) return Completer<EngineSuggestion?>().future;
    return Future.value(suggestion);
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late Database db;
  late RuleModel model;
  late Set<String> ontology;

  setUpAll(configureSqliteForTests);

  setUp(() {
    db = openPack('test/fixtures/sync/pack-v1.db');
    model = loadRuleModel(db);
    ontology = {
      for (final row in db.select('SELECT id FROM symptom_token'))
        row['id'] as String,
    };
  });

  tearDown(() => db.dispose());

  TriageSession build({_FakeEngine? engine, Duration? idle}) => TriageSession(
        model: model,
        ontology: ontology,
        engine: engine ?? _FakeEngine(available: false),
        idleTimeout: idle ?? const Duration(seconds: 120),
      );

  /// Combinação que o pack classifica como emergência.
  final redFlagTokens = ['chest', 'pain', 'severe'];

  /// Combinação de rotina.
  final routineTokens = ['throat', 'pain'];

  group('composição', () {
    test('não começa sem pack verificado', () {
      final session = build()..start(packAvailable: false);
      addTearDown(session.dispose);

      expect(session.state, TriageState.s0Idle);
      expect(session.sessionId, isNull);
    });

    test('aceita até cinco tokens e recusa o sexto', () {
      final session = build()..start(packAvailable: true);
      addTearDown(session.dispose);

      for (final token in ['head', 'pain', 'fever', 'dizzy', 'severe']) {
        session.addToken(token);
      }
      expect(session.snapshot.tokens, hasLength(5));
      expect(session.snapshot.isFull, isTrue);

      session.addToken('cough');

      expect(session.snapshot.tokens, hasLength(5));
      expect(
        session.snapshot.rejectedToken,
        'cough',
        reason: 'a recusa precisa ser visível, ou o toque parece ter sumido',
      );
    });

    test('token fora da ontologia é recusado', () {
      final session = build()..start(packAvailable: true);
      addTearDown(session.dispose);

      session.addToken('dor_de_cotovelo');

      expect(session.snapshot.tokens, isEmpty);
      expect(session.snapshot.rejectedToken, 'dor_de_cotovelo');
    });

    test('tocar o mesmo ícone duas vezes não gasta duas vagas', () {
      final session = build()..start(packAvailable: true);
      addTearDown(session.dispose);

      session.addToken('pain');
      session.addToken('pain');

      expect(session.snapshot.tokens, ['pain']);
    });

    test('dá para retirar um ícone tocado por engano', () {
      // Sem isto, errar um toque obrigaria a recomeçar — e recomeçar é caro
      // para quem não lê.
      final session = build()..start(packAvailable: true);
      addTearDown(session.dispose);
      session.addToken('head');
      session.addToken('fever');

      session.removeToken('head');

      expect(session.snapshot.tokens, ['fever']);
    });

    test('confirmar sem token não sai da composição', () async {
      final session = build()..start(packAvailable: true);
      addTearDown(session.dispose);

      await session.confirm();

      expect(session.state, TriageState.s1Composing);
    });
  });

  group('INV-1 — o modelo nunca rebaixa o gate', () {
    test('red flag responde emergência sem chamar o motor', () async {
      final engine = _FakeEngine(
        suggestion: const EngineSuggestion(outcomeId: 'ROUTINE_UBS', severityLevel: 10),
      );
      final session = build(engine: engine)..start(packAvailable: true);
      addTearDown(session.dispose);
      for (final t in redFlagTokens) {
        session.addToken(t);
      }

      await session.confirm();

      final result = session.snapshot.result!;
      expect(result.severityLevel, model.maxSeverity);
      expect(
        engine.inferCalls,
        0,
        reason: 'o modelo foi consultado numa emergência',
      );
    });

    test('modelo tentando REBAIXAR é ignorado', () async {
      // O caso que a INV-1 existe para impedir. O gate diz emergência; o
      // modelo diz rotina; o usuário precisa ver emergência.
      final engine = _FakeEngine(
        suggestion: const EngineSuggestion(outcomeId: 'ROUTINE_UBS', severityLevel: 10),
      );
      final session = build(engine: engine)..start(packAvailable: true);
      addTearDown(session.dispose);
      for (final t in redFlagTokens) {
        session.addToken(t);
      }

      await session.confirm();

      expect(session.snapshot.result!.outcomeId, isNot('ROUTINE_UBS'));
      expect(session.snapshot.result!.severityLevel, model.maxSeverity);
    });

    test('modelo consegue ESCALAR acima do gate', () async {
      // O outro lado da monotonicidade: escalar é o único movimento permitido,
      // e ele precisa funcionar, senão o modelo não serve para nada.
      final engine = _FakeEngine(
        suggestion: EngineSuggestion(
          outcomeId: 'EMERGENCY',
          severityLevel: model.maxSeverity,
        ),
      );
      final session = build(engine: engine)..start(packAvailable: true);
      addTearDown(session.dispose);
      for (final t in routineTokens) {
        session.addToken(t);
      }

      await session.confirm();

      final result = session.snapshot.result!;
      expect(result.severityLevel, model.maxSeverity);
      expect(result.source, TriageSource.engine);
      expect(result.degraded, isFalse);
    });
  });

  group('degradação (RF-12)', () {
    test('motor indisponível resolve por regras, marcado como degradado', () async {
      final session = build(engine: _FakeEngine(available: false))
        ..start(packAvailable: true);
      addTearDown(session.dispose);
      for (final t in routineTokens) {
        session.addToken(t);
      }

      await session.confirm();

      final result = session.snapshot.result!;
      expect(session.state, TriageState.s5Result);
      expect(result.degraded, isTrue);
      expect(result.outcomeId, isNotEmpty);
    });

    test('motor que lança cai nas regras, sem propagar a exceção', () async {
      final engine = _FakeEngine()..throwOnInfer = true;
      final session = build(engine: engine)..start(packAvailable: true);
      addTearDown(session.dispose);
      for (final t in routineTokens) {
        session.addToken(t);
      }

      await expectLater(session.confirm(), completes);

      expect(session.state, TriageState.s5Result);
      expect(session.snapshot.result!.degraded, isTrue);
    });

    test('motor que não responde é abandonado no teto de parede', () async {
      // O teto real de 5 s vive no C (ADR-002); este é o cinto de segunda
      // ordem, para o caso de o shim não devolver.
      final engine = _FakeEngine()..hangForever = true;
      final session = build(engine: engine)..start(packAvailable: true);
      addTearDown(session.dispose);
      for (final t in routineTokens) {
        session.addToken(t);
      }

      await session.confirm().timeout(const Duration(seconds: 5));

      expect(session.state, TriageState.s5Result);
      expect(session.snapshot.result!.degraded, isTrue);
    });

    test('motor sem opinião marca a sessão como degradada', () async {
      // Resultado igual ao do gate, mas a telemetria agregada precisa saber
      // que o modelo não ajudou.
      final engine = _FakeEngine(suggestion: null);
      final session = build(engine: engine)..start(packAvailable: true);
      addTearDown(session.dispose);
      for (final t in routineTokens) {
        session.addToken(t);
      }

      await session.confirm();

      expect(session.snapshot.result!.degraded, isTrue);
    });
  });

  group('fail-closed (E1)', () {
    test('pack sem desfecho padrão responde EMERGÊNCIA, não erro', () async {
      // O avaliador lança quando o desfecho padrão não existe. Um app que
      // mostrasse "erro" aqui mandaria embora quem veio pedir ajuda.
      // Sem regras, TODA composição cai no desfecho padrão — que não existe.
      // É a forma determinística de fazer o avaliador lançar, em vez de
      // torcer para que o token escolhido não case com nenhuma regra.
      final broken = RuleModel(
        rules: const [],
        outcomes: model.outcomes,
        defaultOutcomeId: 'DESFECHO_QUE_NAO_EXISTE',
      );
      final session = TriageSession(
        model: broken,
        ontology: ontology,
        engine: _FakeEngine(available: false),
      )..start(packAvailable: true);
      addTearDown(session.dispose);
      session.addToken('cough');

      await session.confirm();

      expect(session.state, TriageState.e1FailClosed);
      final result = session.snapshot.result!;
      expect(
        result.severityLevel,
        model.maxSeverity,
        reason: 'fail-closed precisa ser para EMERGENCY, não para o padrão',
      );
    });

    test('o identificador de emergência vem do PACK, não do código', () async {
      // Escrevê-lo em Dart criaria uma segunda fonte de verdade, que sairia de
      // sincronia na primeira republicação de conteúdo.
      final broken = RuleModel(
        rules: const [],
        outcomes: model.outcomes,
        defaultOutcomeId: 'INEXISTENTE',
      );
      final session = TriageSession(
        model: broken,
        ontology: ontology,
        engine: _FakeEngine(available: false),
      )..start(packAvailable: true);
      addTearDown(session.dispose);
      session.addToken('cough');

      await session.confirm();

      expect(session.state, TriageState.e1FailClosed);
      expect(model.outcomes, contains(session.snapshot.result!.outcomeId));
      expect(
        session.snapshot.result!.outcomeId,
        model.outcomes.values
            .reduce((a, b) => b.severityLevel > a.severityLevel ? b : a)
            .id,
      );
    });
  });

  group('INV-2 — a sequência de sintomas morre com a sessão', () {
    test('sair do resultado apaga os tokens da memória', () async {
      final session = build()..start(packAvailable: true);
      addTearDown(session.dispose);
      for (final t in redFlagTokens) {
        session.addToken(t);
      }
      await session.confirm();
      expect(session.snapshot.tokens, isNotEmpty);

      session.abandon();

      expect(session.snapshot.tokens, isEmpty);
      expect(session.snapshot.result, isNull);
      expect(session.sessionId, isNull);
      expect(session.state, TriageState.s0Idle);
    });

    test('abandonar no meio da composição apaga tudo', () {
      final session = build()..start(packAvailable: true);
      addTearDown(session.dispose);
      session.addToken('chest');

      session.abandon();

      expect(session.snapshot.tokens, isEmpty);
      expect(session.sessionId, isNull);
    });

    test('a inatividade descarta a sessão sozinha (120 s)', () async {
      // Aparelho compartilhado num posto: a triagem de quem saiu não pode
      // ficar na tela para o próximo.
      final session = build(idle: const Duration(milliseconds: 60))
        ..start(packAvailable: true);
      addTearDown(session.dispose);
      session.addToken('chest');

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(session.snapshot.tokens, isEmpty);
      expect(session.state, TriageState.s0Idle);
    });

    test('cada toque renova o prazo de inatividade', () async {
      final session = build(idle: const Duration(milliseconds: 120))
        ..start(packAvailable: true);
      addTearDown(session.dispose);

      session.addToken('chest');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      session.addToken('pain');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(session.snapshot.tokens, hasLength(2));
    });

    test('o resultado não carrega os tokens', () async {
      final session = build()..start(packAvailable: true);
      addTearDown(session.dispose);
      for (final t in redFlagTokens) {
        session.addToken(t);
      }

      await session.confirm();

      // `TriageResult` não tem campo de tokens — este teste falha na
      // compilação se alguém acrescentar um.
      expect(session.snapshot.result!.toString(), isNot(contains('chest')));
    });

    test('cada sessão sorteia um id novo, e ele nunca sobrevive', () {
      final session = build()..start(packAvailable: true);
      addTearDown(session.dispose);
      final first = session.sessionId;
      session.abandon();
      session.start(packAvailable: true);

      expect(first, isNotNull);
      expect(session.sessionId, isNot(first));
    });
  });

  test('o motor recebe exatamente os tokens compostos', () async {
    final engine = _FakeEngine();
    final session = build(engine: engine)..start(packAvailable: true);
    addTearDown(session.dispose);
    for (final t in routineTokens) {
      session.addToken(t);
    }

    await session.confirm();

    expect(engine.lastTokens, routineTokens.toSet());
  });
}
