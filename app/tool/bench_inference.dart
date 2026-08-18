/// Bench de latência da inferência local (RF-05 / RNF-02).
///
/// Critério de aceite (RF-05, revisto pelo ADR-003 em 2026-08-17):
/// **p95 entre 3 s e 5 s** em aparelho mínimo (≥ 4 GB de RAM). O orçamento
/// padrão é o teto da faixa; este utilitário produz o número, não o presume.
///
/// Uso:
///
/// ```
/// dart run tool/bench_inference.dart \
///   --pack=<content.db> --model=<modelo.gguf> [--lib=<libgubs_llama.so>] \
///   [--iterations=30] [--threads=4] [--ctx=512] [--budget-ms=5000]
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
import 'package:guia_ubs/triage/engine/inference_bench.dart';
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

String _ms(int micros) => (micros / 1000).toStringAsFixed(1);

Future<int> _run(List<String> args) async {
  final options = _parseArgs(args);
  final packPath = options['pack'];
  final modelPath = options['model'];

  if (packPath == null || modelPath == null) {
    stderr.writeln('uso: --pack=<content.db> --model=<modelo.gguf> [--lib=...] '
        '[--iterations=30] [--threads=4] [--ctx=512] [--budget-ms=5000]');
    return 2;
  }

  final iterations = int.parse(options['iterations'] ?? '30');
  final threads = int.parse(options['threads'] ?? '4');
  final contextTokens = int.parse(options['ctx'] ?? '512');
  final budgetMs = int.parse(options['budget-ms'] ?? '5000');
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
  final cases = promptCasesFromModel(model);
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

  // MESMO código que o bench de aparelho (integration_test/): é o que torna os
  // dois números comparáveis.
  final result = await runInferenceBench(
    engine: engine,
    cases: cases,
    iterations: iterations,
    loadMillis: loadWatch.elapsedMilliseconds,
  );

  await engine.dispose();
  db.dispose();

  stdout
    ..writeln('')
    ..writeln('p50:  ${_ms(result.p50)}ms')
    ..writeln('p95:  ${_ms(result.p95)}ms')
    ..writeln('máx:  ${_ms(result.max)}ms')
    // Sugestão nula não é defeito: é o modelo se abstendo, e o gate decide. Mas
    // abstenção alta significa que o SLM não está agregando nada — informação
    // de produto, não de performance.
    ..writeln('com opinião: ${result.withOpinion}/${result.iterations}');

  final rssMb = result.peakRssMb;
  final rssBudgetMb = int.parse(options['rss-budget-mb'] ?? '1536');
  if (rssMb != null) {
    final veredito = rssMb >= rssBudgetMb ? 'ESTOUROU' : 'ok';
    stdout.writeln('pico de RAM: ${rssMb}MB / ${rssBudgetMb}MB  ($veredito)');
  }
  stdout.writeln('');

  if (result.p95 >= budgetMs * 1000) {
    stdout.writeln(
        'REPROVADO: p95 ${_ms(result.p95)}ms >= orçamento ${budgetMs}ms (RF-05)');
    return 1;
  }

  stdout.writeln(
      'APROVADO: p95 ${_ms(result.p95)}ms < orçamento ${budgetMs}ms (RF-05)');
  return 0;
}

Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}
