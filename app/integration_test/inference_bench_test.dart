/// Bench de inferência NO APARELHO — o número que o PoC precisa (PRD, Fase 1).
///
/// O bench de host (`tool/bench_inference.dart`) mede a mesma coisa com o mesmo
/// código (`lib/triage/engine/inference_bench.dart`), mas num processador que
/// nenhum usuário tem. Latência de inferência não transfere entre
/// arquiteturas; só aqui o critério do RF-05 — "p95 entre 3 s e 5 s em aparelho
/// mínimo de 4 GB" (ADR-003) — pode ser declarado atendido ou reprovado.
///
/// Preparação (o modelo e o pacote não cabem no APK):
///
/// ```
/// PKG=br.gov.exemplo.guia_ubs
/// DIR=/sdcard/Android/data/$PKG/files
/// adb shell mkdir -p $DIR
/// adb push modelo.gguf $DIR/model.gguf
/// adb push content.db  $DIR/pack.db
/// flutter test integration_test/inference_bench_test.dart
/// ```
///
/// Sem os arquivos, o teste é PULADO em vez de reprovado: ausência de modelo é
/// degradação prevista (RF-12), não defeito.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/content/data/pack_rule_source.dart';
import 'package:guia_ubs/triage/engine/inference_bench.dart';
import 'package:guia_ubs/triage/engine/llama_engine.dart';
import 'package:integration_test/integration_test.dart';

/// Diretório externo do app: gravável por `adb push` sem permissão de runtime.
const String _filesDir = String.fromEnvironment(
  'GUBS_FILES_DIR',
  defaultValue: '/sdcard/Android/data/br.gov.exemplo.guia_ubs/files',
);

const String _modelPath =
    String.fromEnvironment('GUBS_MODEL', defaultValue: '$_filesDir/model.gguf');
const String _packPath =
    String.fromEnvironment('GUBS_PACK', defaultValue: '$_filesDir/pack.db');

/// RF-05, revisto pelo ADR-003: p95 aceitável entre 3 s e 5 s. O padrão é o
/// teto da faixa, que coincide com o timeout duro — acima disso a inferência
/// nem chega a ser entregue, é abortada no C.
const int _budgetMillis =
    int.fromEnvironment('GUBS_BUDGET_MS', defaultValue: 5000);

/// RNF-03: pico de RAM ≤ 1,5 GB.
const int _rssBudgetMb = int.fromEnvironment('GUBS_RSS_MB', defaultValue: 1536);

const int _iterations = int.fromEnvironment('GUBS_ITERATIONS', defaultValue: 20);

/// Aparelho mínimo tem 4 núcleos grandes na melhor das hipóteses.
const int _threads = int.fromEnvironment('GUBS_THREADS', defaultValue: 4);

/// Contexto por atendimento. RF-05 fixa a faixa 512–1024 tokens; 512 é o piso
/// dela, e subir custa latência p95 direto.
const int _contextTokens =
    int.fromEnvironment('GUBS_CTX', defaultValue: 512);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('inferência local cabe no orçamento de latência e memória',
      (tester) async {
    if (!File(_modelPath).existsSync() || !File(_packPath).existsSync()) {
      markTestSkipped(
        'modelo ou pacote ausentes no aparelho.\n'
        '  modelo: $_modelPath\n'
        '  pacote: $_packPath\n'
        'Envie com `adb push` (ver cabeçalho deste arquivo).',
      );
      return;
    }

    final db = openPack(_packPath);
    addTearDown(db.dispose);
    final model = loadRuleModel(db);
    final cases = promptCasesFromModel(model);

    final loadWatch = Stopwatch()..start();
    final engine = await startLlamaEngine(
      model: model,
      modelPath: _modelPath,
      contextTokens: _contextTokens,
      threads: _threads,
    );
    loadWatch.stop();

    expect(
      engine,
      isNotNull,
      reason: 'o motor não subiu no aparelho: biblioteca nativa ausente, ABI '
          'divergente, GGUF corrompido ou RAM insuficiente',
    );
    addTearDown(engine!.dispose);

    final result = await runInferenceBench(
      engine: engine,
      cases: cases,
      iterations: _iterations,
      loadMillis: loadWatch.elapsedMilliseconds,
    );

    String ms(int micros) => (micros / 1000).toStringAsFixed(1);

    // Impresso sempre, inclusive quando reprova: o número É o entregável do
    // item 8, e um teste vermelho sem o valor medido não ajudaria ninguém.
    debugPrint(
      '\n=== BENCH NO APARELHO ===\n'
      'casos:        ${cases.length}   iterações: ${result.iterations}   '
      'threads: $_threads\n'
      'carga:        ${result.loadMillis}ms\n'
      'p50:          ${ms(result.p50)}ms\n'
      'p95:          ${ms(result.p95)}ms   (orçamento ${_budgetMillis}ms)\n'
      'máx:          ${ms(result.max)}ms\n'
      'com opinião:  ${result.withOpinion}/${result.iterations}\n'
      'pico de RAM:  ${result.peakRssMb ?? "-"}MB   '
      '(orçamento ${_rssBudgetMb}MB)\n'
      '=========================\n',
    );

    expect(
      result.p95,
      lessThan(_budgetMillis * 1000),
      reason: 'RF-05 reprovado: p95 ${ms(result.p95)}ms neste aparelho',
    );

    final rss = result.peakRssMb;
    if (rss != null) {
      expect(rss, lessThan(_rssBudgetMb),
          reason: 'RNF-03 reprovado: pico de ${rss}MB');
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
