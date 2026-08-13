/// Política de falha do motor local.
///
/// Nenhum destes testes precisa de biblioteca nativa, de modelo GGUF ou de
/// aparelho — é exatamente por isso que a fronteira `LlamaRunner` existe. O que
/// está sob teste aqui não é a qualidade da inferência; é o que acontece com a
/// triagem quando a inferência dá errado.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/triage/domain/routing_rule.dart';
import 'package:guia_ubs/triage/domain/severity.dart';
import 'package:guia_ubs/triage/engine/llama_engine.dart';
import 'package:guia_ubs/triage/engine/llama_runner.dart';

final _model = RuleModel(
  rules: const [],
  outcomes: const {
    'ROUTINE_UBS': RoutingOutcome(id: 'ROUTINE_UBS', severityLevel: 10),
    'EMERGENCY': RoutingOutcome(id: 'EMERGENCY', severityLevel: 100),
  },
  defaultOutcomeId: 'ROUTINE_UBS',
);

/// Runner controlado: cada modo representa uma falha real do lado nativo.
class _FakeRunner implements LlamaRunner {
  _FakeRunner({this.response, this.alive = true, this.throws = false});

  /// `null` simula timeout ou erro já convertido pelo runner real.
  final String? response;
  final bool throws;

  bool alive;

  int calls = 0;
  String? lastPrompt;
  Duration? lastTimeout;
  int? lastMaxTokens;
  bool disposed = false;

  @override
  bool get isAlive => alive;

  @override
  Future<String?> generate(
    String prompt, {
    required int maxTokens,
    required Duration timeout,
  }) async {
    calls++;
    lastPrompt = prompt;
    lastTimeout = timeout;
    lastMaxTokens = maxTokens;
    if (throws) throw StateError('falha nativa simulada');
    return response;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    alive = false;
  }
}

void main() {
  group('LlamaEngine', () {
    test('converte um identificador válido em sugestão', () async {
      final runner = _FakeRunner(response: 'EMERGENCY');
      final engine = LlamaEngine(model: _model, runner: runner);

      final suggestion = await engine.infer({'sym.chest', 'sym.pain'});

      expect(suggestion!.outcomeId, 'EMERGENCY');
      expect(suggestion.severityLevel, 100);
    });

    test('timeout do runner vira "sem opinião", não exceção', () async {
      final engine = LlamaEngine(model: _model, runner: _FakeRunner());

      expect(await engine.infer({'sym.pain'}), isNull);
    });

    test('exceção do runner vira "sem opinião"', () async {
      final engine = LlamaEngine(model: _model, runner: _FakeRunner(throws: true));

      // O contrato é `infer` nunca lançar: um motor que derruba a tela é pior
      // que um motor ausente.
      expect(await engine.infer({'sym.pain'}), isNull);
    });

    test('alucinação vira "sem opinião"', () async {
      final engine = LlamaEngine(
        model: _model,
        runner: _FakeRunner(response: 'talvez procure alguem'),
      );

      expect(await engine.infer({'sym.pain'}), isNull);
    });

    test('motor morto não é sequer chamado', () async {
      final runner = _FakeRunner(response: 'EMERGENCY', alive: false);
      final engine = LlamaEngine(model: _model, runner: runner);

      expect(await engine.infer({'sym.pain'}), isNull);
      expect(runner.calls, 0);
      expect(engine.isAvailable, isFalse);
    });

    test('o teto de 5 s do RF-05 chega ao runner', () async {
      final runner = _FakeRunner(response: 'EMERGENCY');
      final engine = LlamaEngine(model: _model, runner: runner);

      await engine.infer({'sym.pain'});

      expect(runner.lastTimeout, const Duration(seconds: 5));
      expect(runner.lastMaxTokens, 16);
    });

    test('o prompt enviado não depende da ordem dos toques', () async {
      final a = _FakeRunner(response: 'EMERGENCY');
      final b = _FakeRunner(response: 'EMERGENCY');

      await LlamaEngine(model: _model, runner: a).infer({'sym.chest', 'sym.pain'});
      await LlamaEngine(model: _model, runner: b).infer({'sym.pain', 'sym.chest'});

      expect(a.lastPrompt, b.lastPrompt);
    });

    test('dispose encerra o runner', () async {
      final runner = _FakeRunner(response: 'EMERGENCY');
      await LlamaEngine(model: _model, runner: runner).dispose();

      expect(runner.disposed, isTrue);
    });
  });

  group('LlamaEngine + gate (INV-1 ponta a ponta)', () {
    const redFlagGate = TriageVerdict(
      outcomeId: 'EMERGENCY',
      severityLevel: 100,
      matchedRuleId: 'rf.chest_pain',
    );

    test('modelo insistindo em rotina não desfaz uma red flag', () async {
      // Cenário adversarial: o SLM devolve, com confiança, o desfecho errado
      // para alguém com dor torácica.
      final engine = LlamaEngine(
        model: _model,
        runner: _FakeRunner(response: 'ROUTINE_UBS'),
      );

      final suggestion = await engine.infer({'sym.chest', 'sym.pain'});
      final result = mergeVerdict(redFlagGate, suggestion, degraded: false);

      expect(result.outcomeId, 'EMERGENCY');
      expect(result.severityLevel, 100);
    });

    test('motor indisponível ainda entrega o desfecho do gate', () async {
      final engine = LlamaEngine(model: _model, runner: _FakeRunner(alive: false));

      final result = mergeVerdict(
        redFlagGate,
        await engine.infer({'sym.chest'}),
        degraded: true,
      );

      expect(result.outcomeId, 'EMERGENCY');
      expect(result.degraded, isTrue);
    });
  });

  group('degradação real, sem biblioteca nativa', () {
    test('startLlamaEngine devolve null quando o shim não existe', () async {
      // Caminho que a maioria dos aparelhos vai percorrer enquanto o modelo não
      // tiver sido baixado: precisa terminar em degradação limpa, não em crash.
      final engine = await startLlamaEngine(
        model: _model,
        modelPath: '/caminho/que/nao/existe/modelo.gguf',
        libraryCandidates: const ['libgubs_llama_inexistente.so'],
      );

      expect(engine, isNull);
    });
  });
}
