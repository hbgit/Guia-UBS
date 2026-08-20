/// Política de quando sincronizar conteúdo. Dart puro, testável.
///
/// Separada da tradução para o WorkManager pelo mesmo motivo do modelo: "só em
/// rede não tarifada" é decisão de produto, e decisão de produto não mora em
/// configuração de plugin.
///
/// ## Por que o pack tolera dados móveis e o modelo não
///
/// O modelo tem ~800 MB e é baixado uma vez. Um pack de conteúdo tem centenas
/// de KB e precisa chegar: ele carrega correção clínica revisada, e um posto
/// sem Wi-Fi não pode ficar meses com orientação desatualizada porque a
/// política do download de 800 MB foi aplicada a um arquivo mil vezes menor.
library;

import 'package:meta/meta.dart';

const String packSyncTaskName = 'br.gov.exemplo.guia_ubs.pack_sync';

@immutable
class PackSyncPolicy {
  const PackSyncPolicy({
    this.requiresUnmetered = false,
    this.requiresBatteryNotLow = true,
    this.frequency = const Duration(hours: 6),
    this.backoff = const Duration(minutes: 15),
  });

  /// `false` por padrão: pack é pequeno e carrega correção clínica.
  final bool requiresUnmetered;

  final bool requiresBatteryNotLow;

  /// Frequência do trabalho periódico. Casada com [circuitCooldown]: não
  /// adianta acordar antes de o circuito soltar.
  final Duration frequency;

  final Duration backoff;
}
