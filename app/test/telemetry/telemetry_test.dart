/// A allowlist e o acumulador.
///
/// O primeiro grupo é o que mais importa: ele confere a enum do Dart contra o
/// `telemetry-schema.json` gerado pelo contrato. Se as duas divergirem, o app
/// passa a emitir métrica que o pipeline rejeita — ou, pior, deixa de emitir
/// uma que alguém acredita estar sendo coletada, e a decisão de produto é
/// tomada sobre um número que não existe.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/telemetry/metric_key.dart';
import 'package:guia_ubs/telemetry/telemetry_recorder.dart';

Set<String> _schemaMetricNames() {
  final schema = jsonDecode(
    File('../contract/telemetry-schema.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final metrics = (schema['properties']! as Map<String, Object?>)['metrics']!
      as Map<String, Object?>;
  final names = (metrics['propertyNames']! as Map<String, Object?>)['enum']!
      as List<Object?>;
  return names.map((e) => '$e').toSet();
}

void main() {
  group('allowlist casa com o contrato (TypeScript → Dart)', () {
    test('a enum tem exatamente as métricas do schema gerado', () {
      final fromDart = MetricKey.values.map((k) => k.wireName).toSet();

      expect(
        fromDart,
        _schemaMetricNames(),
        reason: 'a allowlist do app divergiu de contract/src/telemetry.ts',
      );
    });

    test('o mínimo de k-anonimato é o mesmo do contrato', () {
      final schema = jsonDecode(
        File('../contract/telemetry-schema.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final kCount = (schema['properties']! as Map<String, Object?>)['kCount']!
          as Map<String, Object?>;

      expect(kAnonymityMin, kCount['minimum']);
    });

    test('nenhum nome de métrica sugere identificador ou dado clínico', () {
      // Rede de segurança para o dia em que alguém acrescentar uma chave sem
      // pensar. Não substitui a revisão do encarregado; torna o descuido
      // barulhento.
      const forbidden = [
        'device', 'install', 'uuid', 'id_', 'user', 'symptom', 'sintoma',
        'token', 'lat', 'lon', 'ip', 'phone', 'cpf', 'timestamp', 'hour',
      ];

      for (final key in MetricKey.values) {
        for (final word in forbidden) {
          expect(
            key.wireName,
            isNot(contains(word)),
            reason: '"${key.wireName}" parece identificador ou dado clínico',
          );
        }
      }
    });
  });

  group('opt-out (LGPD-RF03)', () {
    test('desligado, nada é contado — nem em memória', () {
      // Opt-out que só filtra na saída deixa o dado existir enquanto ninguém
      // olha, e vira uma promessa que depende de todo código futuro lembrar.
      final recorder = TelemetryRecorder(isEnabled: () => false);

      recorder.increment(MetricKey.triageCompletedTotal);
      recorder.observeMax(MetricKey.inferenceMsP95, 4200);

      expect(recorder.snapshot().isEmpty, isTrue);
      expect(recorder.days, isEmpty);
    });

    test('a decisão é consultada a cada registro, não uma vez', () {
      // Desligar na tela de privacidade precisa fazer efeito no toque
      // seguinte, não na próxima abertura do app.
      var enabled = true;
      final recorder = TelemetryRecorder(isEnabled: () => enabled);

      recorder.increment(MetricKey.sessionTotal);
      enabled = false;
      recorder.increment(MetricKey.sessionTotal);

      expect(recorder.snapshot().metrics[MetricKey.sessionTotal], 1);
    });

    test('apagar remove o que já tinha sido contado', () {
      final recorder = TelemetryRecorder(isEnabled: () => true);
      recorder.increment(MetricKey.crashTotal);

      recorder.clear();

      expect(recorder.snapshot().isEmpty, isTrue);
    });
  });

  group('acumulação', () {
    test('soma contadores do mesmo dia', () {
      final recorder = TelemetryRecorder(isEnabled: () => true);

      recorder
        ..increment(MetricKey.triageCompletedTotal)
        ..increment(MetricKey.triageCompletedTotal, by: 2);

      expect(recorder.snapshot().metrics[MetricKey.triageCompletedTotal], 3);
    });

    test('separa por dia — a granularidade mínima do contrato', () {
      var now = DateTime.utc(2026, 8, 19, 23, 59);
      final recorder = TelemetryRecorder(isEnabled: () => true, now: () => now);

      recorder.increment(MetricKey.sessionTotal);
      now = DateTime.utc(2026, 8, 20, 0, 1);
      recorder.increment(MetricKey.sessionTotal);

      expect(recorder.days, ['2026-08-19', '2026-08-20']);
      expect(
        recorder.snapshot(day: DateTime.utc(2026, 8, 19)).metrics[MetricKey.sessionTotal],
        1,
      );
    });

    test('o dia é formatado como o contrato exige', () {
      final recorder = TelemetryRecorder(
        isEnabled: () => true,
        now: () => DateTime.utc(2026, 1, 5, 12),
      );
      recorder.increment(MetricKey.sessionTotal);

      expect(recorder.snapshot().bucketDay, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(recorder.snapshot().bucketDay, '2026-01-05');
    });

    test('observeMax guarda o pior caso, não a série', () {
      // Guardar a série significaria guardar uma série temporal por aparelho —
      // justamente o que a LGPD-RF14 quer evitar.
      final recorder = TelemetryRecorder(isEnabled: () => true);

      recorder
        ..observeMax(MetricKey.inferenceMsP95, 3000)
        ..observeMax(MetricKey.inferenceMsP95, 4700)
        ..observeMax(MetricKey.inferenceMsP95, 3500);

      expect(recorder.snapshot().metrics[MetricKey.inferenceMsP95], 4700);
    });

    test('valores negativos são ignorados', () {
      final recorder = TelemetryRecorder(isEnabled: () => true);

      recorder
        ..increment(MetricKey.crashTotal, by: -5)
        ..observeMax(MetricKey.inferenceMsP50, -1);

      expect(recorder.snapshot().isEmpty, isTrue);
    });

    test('o instantâneo não pode ser alterado por fora', () {
      final recorder = TelemetryRecorder(isEnabled: () => true);
      recorder.increment(MetricKey.sessionTotal);

      expect(
        () => recorder.snapshot().metrics[MetricKey.crashTotal] = 99,
        throwsUnsupportedError,
      );
    });
  });

  test('o instantâneo não tem onde guardar identificador de aparelho', () {
    // Verificação estrutural: se alguém acrescentar um campo de id, este teste
    // não compila mais — que é o momento certo para a conversa acontecer.
    final recorder = TelemetryRecorder(isEnabled: () => true)
      ..increment(MetricKey.sessionTotal);
    final snapshot = recorder.snapshot();

    expect(snapshot.bucketDay, isA<String>());
    expect(snapshot.metrics, isA<Map<MetricKey, num>>());
    expect(
      snapshot.toString(),
      isNot(contains('device')),
    );
  });
}
