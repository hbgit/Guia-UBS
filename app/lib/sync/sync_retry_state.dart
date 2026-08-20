/// Estado de retentativa do sync, **persistido**.
///
/// ===========================================================================
/// POR QUE ISTO NÃO PODE VIVER EM MEMÓRIA
/// ===========================================================================
///
/// O item 9 guardava contador de falhas, backoff e circuito em campos da
/// instância do `SyncService`. Funciona num teste e no app aberto; em produção,
/// não funciona nunca — o WorkManager executa o trabalho num **isolate novo a
/// cada disparo**, e um isolate novo nasce com o circuito fechado e sem backoff
/// pendente.
///
/// Ou seja: o freio existia no código e não existia no aparelho. Uma frota
/// inteira sem rede voltaria a bater no servidor a cada janela, com o circuito
/// "aberto" em memórias que já morreram.
///
/// Aqui o estado vira dado em disco, ao lado do ETag e das blacklists — mesmo
/// arquivo, mesma vida útil. E o circuito deixa de ser um booleano ("aberto
/// até a próxima janela") para virar um INSTANTE ("fechado a partir de"),
/// porque um processo que acabou de nascer não tem como saber em que janela
/// está, mas sabe que horas são.
library;

import 'dart:math';

import 'package:meta/meta.dart';

/// Quanto o circuito fica aberto depois de esgotado o orçamento de tentativas.
///
/// Casado com a frequência do trabalho periódico (6 h): na prática, "até a
/// próxima janela do WorkManager", que é o que a [espec.md §4.2] pede.
const Duration circuitCooldown = Duration(hours: 6);

/// Teto do backoff exponencial.
///
/// Sem teto, `2^n` passa de dias na décima falha e o aparelho pararia de tentar
/// para sempre — o oposto do que backoff serve para fazer.
const Duration maxBackoff = Duration(minutes: 30);

@immutable
class SyncRetryState {
  const SyncRetryState({
    this.failures = 0,
    this.nextAttemptAt,
    this.circuitOpenUntil,
  });

  /// Falhas seguidas desde o último ciclo bem-sucedido.
  final int failures;

  /// Antes disto, não se tenta de novo (backoff + jitter já aplicados).
  final DateTime? nextAttemptAt;

  /// Circuito aberto até este instante.
  final DateTime? circuitOpenUntil;

  static const SyncRetryState clean = SyncRetryState();

  bool circuitClosedAt(DateTime now) =>
      circuitOpenUntil == null || !now.isBefore(circuitOpenUntil!);

  bool backoffElapsedAt(DateTime now) =>
      nextAttemptAt == null || !now.isBefore(nextAttemptAt!);

  Map<String, Object?> toJson() => {
        'failures': failures,
        if (nextAttemptAt != null)
          'nextAttemptAt': nextAttemptAt!.toUtc().toIso8601String(),
        if (circuitOpenUntil != null)
          'circuitOpenUntil': circuitOpenUntil!.toUtc().toIso8601String(),
      };

  /// Lê do JSON, tolerando lixo.
  ///
  /// Estado de retentativa corrompido não pode travar o sync: no pior caso
  /// recomeçamos sem freio, que é o comportamento de um aparelho novo.
  static SyncRetryState fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return clean;
    return SyncRetryState(
      failures: raw['failures'] is int ? raw['failures']! as int : 0,
      nextAttemptAt: _parse(raw['nextAttemptAt']),
      circuitOpenUntil: _parse(raw['circuitOpenUntil']),
    );
  }

  static DateTime? _parse(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}

/// Atraso até a próxima tentativa: `2^n` segundos, com jitter, limitado a
/// [maxBackoff].
///
/// Função pura para poder ser verificada em toda a faixa de `n`, e não só na
/// faixa que o orçamento de falhas atual alcança.
///
/// **O teto não binda com os parâmetros de hoje** — o circuito abre em 5
/// falhas, então `n` nunca passa de 4 e `2^4` são 16 segundos. Ele fica assim
/// mesmo: se alguém aumentar `maxFailuresPerWindow`, `2^11` já passa de meia
/// hora e `2^16` passa de 18 horas — um freio que nunca solta é
/// indistinguível de um app que parou de sincronizar. O teto é a rede de
/// segurança dessa mudança futura, e tem teste que o exercita fora da faixa
/// alcançável hoje.
///
/// **O jitter não é enfeite.** Sem ele, uma frota que perdeu a rede ao mesmo
/// tempo volta ao mesmo tempo, e o servidor de conteúdo — um VPS único, sem
/// CDN — recebe o pico exatamente quando se recupera. O fator vive em
/// [0,5, 1,5): metade a uma vez e meia do atraso nominal.
Duration backoffDelay(int failures, Random random) {
  if (failures <= 0) return Duration.zero;
  final nominal = pow(2, failures).toDouble();
  final jittered = nominal * (0.5 + random.nextDouble());
  final delay = Duration(milliseconds: (jittered * 1000).round());
  return delay > maxBackoff ? maxBackoff : delay;
}
