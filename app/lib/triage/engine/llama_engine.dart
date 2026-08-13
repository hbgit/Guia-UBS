/// Motor de triagem baseado no SLM local (RF-05).
///
/// Composição de três peças puras e uma impura:
///
///   tokens → buildTriagePrompt → LlamaRunner → decodeSuggestion → sugestão
///
/// Só o runner tem efeitos colaterais. Tudo que decide alguma coisa é função
/// pura e testável sem device.
///
/// ===========================================================================
/// O QUE ESTE MOTOR **NÃO** PODE FAZER
/// ===========================================================================
///
/// * Não pode rebaixar severidade — quem decide é `mergeVerdict` (INV-1).
/// * Não pode inventar severidade — o número vem de `routing_outcome`.
/// * Não pode nomear desfecho inexistente — `decodeSuggestion` filtra.
/// * Não pode bloquear a triagem — falha e timeout viram `null`.
///
/// Sobra ao modelo exatamente um poder: ESCALAR para um desfecho já revisado
/// clinicamente. É pouco de propósito.
library;

import '../domain/routing_rule.dart';
import 'engine_decoder.dart';
import 'llama_runner.dart';
import 'prompt_builder.dart';
import 'triage_engine.dart';

class LlamaEngine implements TriageEngine {
  LlamaEngine({
    required this.model,
    required this.runner,
    this.timeout = const Duration(seconds: 5),
    this.maxTokens = 16,
  });

  /// Modelo de encaminhamento do pacote ativo — a fonte dos identificadores
  /// que o SLM pode nomear e das severidades associadas a eles.
  final RuleModel model;

  final LlamaRunner runner;

  /// Teto duro do RF-05. É passado ao lado nativo, que o impõe abortando a
  /// geração — não é uma espera que desiste.
  @override
  final Duration timeout;

  /// A resposta esperada é UM identificador. O teto baixo é o principal
  /// controle de latência: cada token gerado custa uma passada pelo modelo, e
  /// um device de entrada paga caro por cada uma.
  final int maxTokens;

  @override
  String get id => 'llama_cpp';

  @override
  bool get isAvailable => runner.isAlive;

  @override
  Future<EngineSuggestion?> infer(Set<String> tokens) async {
    // Contrato da interface: `infer` NUNCA lança. Um motor que quebra a
    // triagem é pior que um motor ausente, porque o ausente degrada de forma
    // prevista (RF-12) e o que quebra derruba a tela.
    //
    // Daí o catch abrangente: não é preguiça de enumerar exceções, é a
    // fronteira onde qualquer falha vira "sem opinião" por decisão de projeto.
    try {
      if (!isAvailable) return null;

      final prompt = buildTriagePrompt(tokens, model);
      final raw = await runner.generate(
        prompt,
        maxTokens: maxTokens,
        timeout: timeout,
      );
      if (raw == null) return null;

      return decodeSuggestion(raw, model);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> dispose() => runner.dispose();
}

/// Sobe o motor local, ou `null` se ele não puder operar neste aparelho.
///
/// `null` é um resultado ordinário, não uma falha a ser reportada ao usuário:
/// aparelho sem o modelo baixado, sem a biblioteca nativa no ABI instalado ou
/// sem RAM suficiente simplesmente roda em modo degradado (espec.md A1).
Future<LlamaEngine?> startLlamaEngine({
  required RuleModel model,
  required String modelPath,
  int contextTokens = 512,
  int threads = 2,
  Duration timeout = const Duration(seconds: 5),
  List<String>? libraryCandidates,
}) async {
  final runner = await IsolateLlamaRunner.start(
    modelPath: modelPath,
    contextTokens: contextTokens,
    threads: threads,
    libraryCandidates: libraryCandidates,
  );
  if (runner == null) return null;

  return LlamaEngine(model: model, runner: runner, timeout: timeout);
}
