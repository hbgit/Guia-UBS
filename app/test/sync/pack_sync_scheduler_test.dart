/// Política de agendamento do sync de conteúdo, e o estado de retentativa que
/// sobrevive ao processo.
///
/// A política vive em Dart puro justamente para ser testada assim: "só em rede
/// não tarifada" é decisão de produto, e decisão de produto verificada só pela
/// configuração de um plugin não é verificada.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/model_sync_scheduler.dart';
import 'package:guia_ubs/sync/pack_sync_scheduler.dart';
import 'package:guia_ubs/sync/sync_retry_state.dart';

void main() {
  group('política do pack', () {
    test('pack tolera dados móveis; modelo não', () {
      // O modelo tem ~800 MB e é baixado uma vez. Um pack tem centenas de KB e
      // carrega correção clínica revisada: um posto sem Wi-Fi não pode ficar
      // meses com orientação desatualizada porque a política de um arquivo mil
      // vezes maior foi aplicada a ele.
      expect(const PackSyncPolicy().requiresUnmetered, isFalse);
      expect(const ModelSyncPolicy().requiresUnmetered, isTrue);
    });

    test('não acorda com bateria baixa', () {
      expect(const PackSyncPolicy().requiresBatteryNotLow, isTrue);
    });

    test('a frequência não é menor que o tempo de circuito aberto', () {
      // Acordar antes de o circuito soltar seria gastar bateria para não fazer
      // nada: o ciclo abriria e voltaria na primeira guarda.
      expect(
        const PackSyncPolicy().frequency,
        greaterThanOrEqualTo(circuitCooldown),
      );
    });

    test('os dois trabalhos têm nomes distintos', () {
      // Nome repetido faria um substituir o outro no WorkManager, e o app
      // ficaria com metade do sync que acha que tem.
      expect(packSyncTaskName, isNot(modelSyncTaskName));
    });
  });

  group('estado de retentativa', () {
    test('sobrevive a uma ida e volta pelo JSON', () {
      final original = SyncRetryState(
        failures: 3,
        nextAttemptAt: DateTime.utc(2026, 8, 19, 12),
        circuitOpenUntil: DateTime.utc(2026, 8, 19, 18),
      );

      final restored = SyncRetryState.fromJson(original.toJson());

      expect(restored.failures, 3);
      expect(restored.nextAttemptAt, original.nextAttemptAt);
      expect(restored.circuitOpenUntil, original.circuitOpenUntil);
    });

    test('lixo no disco vira estado limpo, não exceção', () {
      // Estado de retentativa corrompido não pode travar o sync: no pior caso
      // recomeçamos sem freio, que é o comportamento de um aparelho novo.
      for (final garbage in <Object?>[
        null,
        'isto não é objeto',
        42,
        {'failures': 'muitas', 'nextAttemptAt': 'ontem'},
      ]) {
        final state = SyncRetryState.fromJson(garbage);

        expect(state.failures, 0);
        expect(state.nextAttemptAt, isNull);
        expect(state.circuitOpenUntil, isNull);
      }
    });

    test('estado limpo não freia nada', () {
      final now = DateTime.utc(2026, 8, 19, 12);

      expect(SyncRetryState.clean.circuitClosedAt(now), isTrue);
      expect(SyncRetryState.clean.backoffElapsedAt(now), isTrue);
    });

    test('o circuito fecha exatamente no instante marcado', () {
      final until = DateTime.utc(2026, 8, 19, 18);
      final state = SyncRetryState(circuitOpenUntil: until);

      expect(state.circuitClosedAt(until.subtract(const Duration(seconds: 1))), isFalse);
      expect(state.circuitClosedAt(until), isTrue);
    });
  });

  group('backoff', () {
    test('cresce exponencialmente com as falhas', () {
      // Sem jitter, para medir a curva: `Random` fixo em 0,5 dá fator 1,0.
      final fixed = _FixedRandom(0.5);

      final delays = [
        for (var n = 1; n <= 4; n++) backoffDelay(n, fixed).inMilliseconds,
      ];

      expect(delays, [2000, 4000, 8000, 16000]);
    });

    test('o teto binda fora da faixa que o orçamento atual alcança', () {
      // Com 5 falhas o circuito abre, então `n` nunca passa de 4 hoje. O teto
      // existe para o dia em que alguém aumentar esse orçamento: `2^11` já
      // passa de meia hora e `2^16` passa de 18 horas, e um freio que nunca
      // solta é indistinguível de um app que parou de sincronizar.
      final fixed = _FixedRandom(0.5);

      expect(backoffDelay(10, fixed), lessThan(maxBackoff));
      expect(backoffDelay(11, fixed), maxBackoff);
      expect(backoffDelay(30, fixed), maxBackoff);
      expect(
        backoffDelay(4, fixed),
        lessThan(maxBackoff),
        reason: 'na faixa de hoje o teto não deve interferir',
      );
    });

    test('o jitter espalha aparelhos que falharam ao mesmo tempo', () {
      // Sem isto, uma frota que perdeu a rede junto volta junta, e o servidor
      // — um VPS único, sem CDN — recebe o pico quando se recupera. Dois
      // aparelhos com a MESMA contagem de falhas precisam agendar horários
      // diferentes.
      final delays = {
        for (var seed = 0; seed < 20; seed++)
          backoffDelay(4, Random(seed)).inMilliseconds,
      };

      expect(
        delays.length,
        greaterThan(10),
        reason: 'os atrasos coincidiram: o jitter sumiu',
      );
    });

    test('o jitter fica entre metade e uma vez e meia do nominal', () {
      // Espalhar sem exagerar: um fator maior faria o atraso real perder
      // relação com a curva pretendida.
      for (var seed = 0; seed < 50; seed++) {
        final delay = backoffDelay(4, Random(seed)).inMilliseconds;

        expect(delay, greaterThanOrEqualTo(8000));
        expect(delay, lessThanOrEqualTo(24000));
      }
    });

    test('sem falhas, não há espera', () {
      expect(backoffDelay(0, Random(1)), Duration.zero);
    });
  });
}

/// `Random` determinístico, para medir a curva sem o jitter no caminho.
class _FixedRandom implements Random {
  _FixedRandom(this._value);

  final double _value;

  @override
  double nextDouble() => _value;

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => 0;
}
