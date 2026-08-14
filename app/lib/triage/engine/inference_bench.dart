/// Medição de latência e memória da inferência local (RF-05 / RNF-02 / RNF-03).
///
/// Este arquivo existe para que o bench de host (`tool/bench_inference.dart`) e
/// o bench de aparelho (`integration_test/inference_bench_test.dart`) executem
/// **o mesmo código**. Duas implementações produziriam dois números que
/// ninguém poderia comparar — e comparar host com aparelho é exatamente o
/// ponto: a diferença entre eles é o custo real do hardware de entrada.
library;

import 'dart:io';

import 'package:meta/meta.dart';

import '../domain/routing_rule.dart';
import 'triage_engine.dart';

/// Resultado de uma execução de bench. Tempos em microssegundos.
@immutable
class BenchResult {
  const BenchResult({
    required this.latenciesMicros,
    required this.withOpinion,
    required this.loadMillis,
    required this.peakRssMb,
  });

  /// Ordenado. Uma medição por iteração.
  final List<int> latenciesMicros;

  /// Quantas iterações produziram sugestão utilizável. Abstenção não é defeito
  /// (o gate decide), mas taxa alta significa que o SLM não agrega nada.
  final int withOpinion;

  /// Tempo de carga do modelo, fora das iterações.
  final int loadMillis;

  /// Pico de RSS do processo, ou `null` fora de Linux/Android.
  final int? peakRssMb;

  int get iterations => latenciesMicros.length;

  int get p50 => _percentile(0.50);
  int get p95 => _percentile(0.95);
  int get max => latenciesMicros.isEmpty ? 0 : latenciesMicros.last;

  /// Percentil por posto mais próximo (nearest-rank). Sem interpolação, que
  /// inventaria uma latência que nenhuma execução observou.
  int _percentile(double p) {
    if (latenciesMicros.isEmpty) return 0;
    final rank =
        (p * latenciesMicros.length).ceil().clamp(1, latenciesMicros.length);
    return latenciesMicros[rank - 1];
  }
}

/// Um conjunto de tokens por grupo de regra.
///
/// Os casos saem das REGRAS DO PRÓPRIO PACOTE, não de uma lista escrita à mão:
/// se a curadoria clínica crescer, o bench passa a medir a carga real sem que
/// ninguém precise lembrar de atualizá-lo.
List<Set<String>> promptCasesFromModel(RuleModel model) {
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

/// Pico de memória residente do processo, em MB, ou `null` onde não há procfs.
///
/// `VmHWM` é a marca d'água alta do RSS — o maior valor já atingido, não o
/// instantâneo. É o número que o RNF-03 limita (pico ≤ 1,5 GB).
///
/// Com `mmap` o kernel pode devolver páginas sob pressão, então num aparelho
/// apertado o RSS observado tende a ser MENOR que o do host — ao custo de
/// releitura do armazenamento, que reaparece como latência.
int? peakRssMb() {
  if (!Platform.isLinux && !Platform.isAndroid) return null;
  try {
    for (final line in File('/proc/self/status').readAsLinesSync()) {
      if (!line.startsWith('VmHWM:')) continue;
      final kb = int.tryParse(RegExp(r'\d+').firstMatch(line)?.group(0) ?? '');
      if (kb != null) return (kb / 1024).round();
    }
  } on FileSystemException {
    return null;
  }
  return null;
}

/// Roda [iterations] inferências, ciclando por [cases].
///
/// A primeira inferência é de AQUECIMENTO e não entra na conta: ela paga
/// paginação do `mmap` e alocação de buffers, e incluí-la mascararia a latência
/// de regime — que é o que o usuário sente da segunda triagem em diante.
Future<BenchResult> runInferenceBench({
  required TriageEngine engine,
  required List<Set<String>> cases,
  required int iterations,
  int loadMillis = 0,
}) async {
  if (cases.isEmpty) {
    throw ArgumentError('sem casos para medir — o pacote não tem regras');
  }

  await engine.infer(cases.first);

  final latencies = <int>[];
  var withOpinion = 0;

  for (var i = 0; i < iterations; i++) {
    final watch = Stopwatch()..start();
    final suggestion = await engine.infer(cases[i % cases.length]);
    watch.stop();

    latencies.add(watch.elapsedMicroseconds);
    if (suggestion != null) withOpinion++;
  }

  latencies.sort();

  return BenchResult(
    latenciesMicros: latencies,
    withOpinion: withOpinion,
    loadMillis: loadMillis,
    peakRssMb: peakRssMb(),
  );
}
