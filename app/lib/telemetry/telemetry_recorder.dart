/// Contador local de métricas agregadas.
///
/// ## O que este módulo deliberadamente NÃO faz
///
/// **Não transmite nada.** A INV-3 do CLAUDE.md diz que o app faz exatamente
/// duas chamadas de rede — manifest/pack e modelo — e ambas fora do caminho do
/// usuário. Acrescentar um envio de telemetria seria uma terceira, e isso exige
/// ADR, não uma decisão tomada de passagem enquanto se implementa um contador.
///
/// **Não persiste nada.** Contadores em disco precisariam de justificativa
/// contra a INV-2 e apareceriam como tabela nova no `user.db`, onde
/// `lgpd_surface_test` obriga a explicar cada coluna. Enquanto não existe
/// consumidor — sem envio, ninguém lê —, persistir seria criar risco para
/// nenhum benefício. Os contadores morrem com o processo, e está certo assim.
///
/// O que ele faz, e o que o item 14 pede, é a **allowlist funcionando**: um
/// ponto único onde só chave conhecida entra, o opt-out é respeitado antes da
/// contagem, e nada que identifique alguém é expressável.
///
/// ## Opt-out na CONTAGEM, não no envio
///
/// A LGPD-RF03 exige que o opt-out zere os envios. Aqui ele zera a **contagem**,
/// que é mais forte: quem desligou não tem nem número em memória a respeito de
/// si. Um opt-out que só filtra na saída deixa o dado existir enquanto ninguém
/// olha — e "existe mas não enviamos" é uma promessa que depende de todo código
/// futuro se lembrar dela.
library;

import 'dart:collection';

import 'package:meta/meta.dart';

import 'metric_key.dart';

/// Contadores de um dia, por coorte. Sem identificador de aparelho — o tipo
/// não tem onde guardar um.
@immutable
class MetricSnapshot {
  const MetricSnapshot({required this.bucketDay, required this.metrics});

  /// Granularidade mínima do contrato: o dia (LGPD-RF14). Não há hora aqui, e
  /// não deve haver: timestamp fino reidentifica.
  final String bucketDay;

  final Map<MetricKey, num> metrics;

  bool get isEmpty => metrics.isEmpty;
}

/// Acumula métricas em memória, respeitando a allowlist e o opt-out.
class TelemetryRecorder {
  TelemetryRecorder({
    required bool Function() isEnabled,
    DateTime Function()? now,
        // ignore: prefer_initializing_formals — o nome público é `isEnabled`.
  })  : _isEnabled = isEnabled,
        _now = now ?? DateTime.now;

  /// Consultado a CADA registro, não uma vez na construção: desligar a
  /// telemetria na tela de privacidade precisa fazer efeito no toque seguinte,
  /// não na próxima abertura do app.
  final bool Function() _isEnabled;

  final DateTime Function() _now;

  final Map<String, Map<MetricKey, num>> _byDay = {};

  /// Soma 1 (ou [by]) a um contador.
  ///
  /// Não existe sobrecarga que aceite `String`: se aceitasse, a allowlist
  /// deixaria de ser fechada e passaria a depender de disciplina.
  void increment(MetricKey key, {num by = 1}) {
    if (by < 0) return; // contador não anda para trás
    _record(key, (current) => current + by);
  }

  /// Registra uma observação de duração, mantendo o MAIOR valor do dia.
  ///
  /// Aproximação deliberada: guardar a série para calcular percentil exato
  /// significaria guardar uma série temporal por aparelho, que é justamente o
  /// tipo de dado que a LGPD-RF14 quer evitar. O percentil real é calculado no
  /// pipeline, sobre a coorte.
  void observeMax(MetricKey key, num value) {
    if (value < 0) return;
    _record(key, (current) => value > current ? value : current);
  }

  void _record(MetricKey key, num Function(num current) update) {
    if (!_isEnabled()) return;
    final day = _dayOf(_now());
    final metrics = _byDay.putIfAbsent(day, () => <MetricKey, num>{});
    metrics[key] = update(metrics[key] ?? 0);
  }

  /// Contadores de um dia. Vazio quando não houve nada — ou quando o usuário
  /// desligou a telemetria.
  MetricSnapshot snapshot({DateTime? day}) {
    final key = _dayOf(day ?? _now());
    return MetricSnapshot(
      bucketDay: key,
      metrics: UnmodifiableMapView(_byDay[key] ?? const {}),
    );
  }

  /// Dias com contadores. Existe para o teste e para um futuro envio.
  List<String> get days => List.unmodifiable(_byDay.keys.toList()..sort());

  /// Apaga tudo. Chamado por "apagar meus dados" (LGPD-RF03) e ao desligar a
  /// telemetria: desligar precisa remover o que já foi contado, senão o
  /// opt-out valeria só para o futuro.
  void clear() => _byDay.clear();

  static String _dayOf(DateTime when) {
    final utc = when.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}-$month-$day';
  }
}
