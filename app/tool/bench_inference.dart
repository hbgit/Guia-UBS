/// Bench de latência da inferência local (RF-05 / RNF-02).
///
/// Critério de aceite da Fase 1: **p95 < 3 s** em aparelho de entrada
/// (≤ 4 GB de RAM). Este utilitário produz o número; ele não o presume.
///
/// Uso:
///
/// ```
/// dart run tool/bench_inference.dart \
///   --pack=<content.db> --model=<modelo.gguf> [--lib=<libgubs_llama.so>] \
///   [--iterations=30] [--threads=4] [--ctx=512] [--budget-ms=3000]
/// ```
///
/// Sai com código 1 quando o orçamento estoura — dá para pendurar num job de
/// CI com device farm sem parsing de saída.
///
/// Os prompts são derivados das REGRAS DO PRÓPRIO PACOTE, não de uma lista
/// escrita à mão: se a curadoria clínica crescer, o bench passa a medir a
/// carga real sem que ninguém precise lembrar de atualizá-lo.
library;

import 'dart:io';

import 'package:guia_ubs/content/data/pack_rule_source.dart';
import 'package:guia_ubs/content/data/sqlite_native.dart';
import 'package:guia_ubs/triage/domain/routing_rule.dart';
import 'package:guia_ubs/triage/engine/llama_engine.dart';
import 'package:sqlite3/sqlite3.dart';

Map<String, String> _parseArgs(List<String> args) {
  final parsed = <String, String>{};
  for (final arg in args) {
    if (!arg.startsWith('--')) continue;
    final eq = arg.indexOf('=');
    if (eq < 0) {
      parsed[arg.substring(2)] = 'true';
    } else {
      parsed[arg.substring(2, eq)] = arg.substring(eq + 1);
    }
  }
  return parsed;
}

/// Um conjunto de tokens por grupo de regra: são as combinações que o app
/// precisa classificar bem, e por construção cobrem o vocabulário em uso.
List<Set<String>> _promptCases(RuleModel model) {
  final cases = <Set<String>>[];
  for (final rule in model.rules) {
    final byGroup = <int, Set<String>>{};
    for (final term in rule.terms) {
      if (term.negated) continue; // termo negado exige AUSÊNCIA do token
      byGroup.putIfAbsent(term.groupNo, () => <String>{}).add(term.tokenId);
    }
    for (final tokens in byGroup.values) {
      if (tokens.isNotEmpty) cases.add(tokens);
    }
  }
  return cases;
}

/// Percentil por posto mais próximo (nearest-rank) — sem interpolação, que
/// inventaria uma latência que nenhuma execução observou.
int _percentile(List<int> sortedMicros, double p) {
  if (sortedMicros.isEmpty) return 0;
  final rank = (p * sortedMicros.length).ceil().clamp(1, sortedMicros.length);
  return sortedMicros[rank - 1];
}

String _ms(int micros) => (micros / 1000).toStringAsFixed(1);

Future<int> _run(List<String> args) async {
  final options = _parseArgs(args);
  final packPath = options['pack'];
  final modelPath = options['model'];

  if (packPath == null || modelPath == null) {
    stderr.writeln('uso: --pack=<content.db> --model=<modelo.gguf> [--lib=...] '
        '[--iterations=30] [--threads=4] [--ctx=512] [--budget-ms=3000]');
    return 2;
  }

  final iterations = int.parse(options['iterations'] ?? '30');
  final threads = int.parse(options['threads'] ?? '4');
  final contextTokens = int.parse(options['ctx'] ?? '512');
  final budgetMs = int.parse(options['budget-ms'] ?? '3000');
  final libPath = options['lib'];

  configureSqliteForHost();

  final Database db;
  try {
    db = openPack(packPath);
  } on SqliteException catch (error) {
    stderr.writeln('não foi possível abrir o pacote "$packPath": ${error.message}');
    return 2;
  }

  final model = loadRuleModel(db);
  final cases = _promptCases(model);
  if (cases.isEmpty) {
    stderr.writeln('pacote sem regras — nada a medir');
    db.dispose();
    return 2;
  }

  stdout
    ..writeln('pacote:      $packPath '
        '(${model.rules.length} regras, ${cases.length} casos)')
    ..writeln('modelo:      $modelPath')
    ..writeln('threads:     $threads   contexto: $contextTokens tokens')
    ..writeln('iterações:   $iterations   orçamento p95: ${budgetMs}ms')
    ..writeln('');

  final loadWatch = Stopwatch()..start();
  final engine = await startLlamaEngine(
    model: model,
    modelPath: modelPath,
    contextTokens: contextTokens,
    threads: threads,
    libraryCandidates: libPath == null ? null : <String>[libPath],
  );
  loadWatch.stop();

  if (engine == null) {
    stderr.writeln('FALHOU: motor não subiu (biblioteca, ABI ou modelo). '
        'Em produção isto é degradação para o RuleOnlyEngine, não erro — '
        'mas aqui é justamente o objeto da medição.');
    db.dispose();
    return 2;
  }

  stdout.writeln('carga do modelo: ${loadWatch.elapsedMilliseconds}ms');

  final latencies = <int>[];
  var withOpinion = 0;

  // Uma passada de aquecimento: a primeira inferência paga paginação do mmap e
  // alocação de buffers, e contá-la mascararia a latência de regime.
  await engine.infer(cases.first);

  for (var i = 0; i < iterations; i++) {
    final tokens = cases[i % cases.length];
    final watch = Stopwatch()..start();
    final suggestion = await engine.infer(tokens);
    watch.stop();

    latencies.add(watch.elapsedMicroseconds);
    if (suggestion != null) withOpinion++;
  }

  await engine.dispose();
  db.dispose();

  latencies.sort();
  final p50 = _percentile(latencies, 0.50);
  final p95 = _percentile(latencies, 0.95);

  stdout
    ..writeln('')
    ..writeln('p50:  ${_ms(p50)}ms')
    ..writeln('p95:  ${_ms(p95)}ms')
    ..writeln('máx:  ${_ms(latencies.last)}ms')
    // Sugestão nula não é defeito: é o modelo se abstendo, e o gate decide. Mas
    // abstenção alta significa que o SLM não está agregando nada — informação
    // de produto, não de performance.
    ..writeln('com opinião: $withOpinion/$iterations')
    ..writeln('');

  if (p95 >= budgetMs * 1000) {
    stdout.writeln('REPROVADO: p95 ${_ms(p95)}ms >= orçamento ${budgetMs}ms (RF-05)');
    return 1;
  }

  stdout.writeln('APROVADO: p95 ${_ms(p95)}ms < orçamento ${budgetMs}ms (RF-05)');
  return 0;
}

Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}
