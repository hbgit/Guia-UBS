/// Leitura do conteúdo estático para as telas de RF-07, RF-08 e RF-09.
///
/// Tudo aqui deriva do `content.db` ativo e do idioma corrente. Nenhuma destas
/// telas depende do modelo SLM, do sync ou de rede: são o **piso da escada de
/// degradação** (RF-12) e continuam funcionando quando tudo o mais falha.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../content/domain/content_models.dart';
import '../app_scope.dart';

/// Um local e o que ele atende.
class VenueWithServices {
  const VenueWithServices({required this.venue, required this.services});

  final Venue venue;
  final List<Service> services;
}

/// Locais com seus serviços, na ordem do pack.
final venuesProvider = Provider<List<VenueWithServices>>((ref) {
  final content = ref.watch(contentProvider);
  if (content == null) return const [];
  final lang = ref.watch(contentLanguageProvider);
  return [
    for (final venue in content.venues(lang: lang))
      VenueWithServices(
        venue: venue,
        services: content.servicesOf(venue.id, lang: lang),
      ),
  ];
});

/// Todos os serviços de todos os locais — a lista que a tela de documentos usa
/// para perguntar "documentos para quê?".
final servicesProvider = Provider<List<Service>>(
  (ref) => [for (final v in ref.watch(venuesProvider)) ...v.services],
);

/// Serviço selecionado na tela de documentos. `null` = ainda não escolheu.
final selectedServiceProvider = StateProvider<String?>((ref) => null);

/// Documentos do serviço selecionado, obrigatórios primeiro.
final documentsProvider = Provider<List<RequiredDocument>>((ref) {
  final content = ref.watch(contentProvider);
  final serviceId = ref.watch(selectedServiceProvider) ??
      ref.watch(servicesProvider).firstOrNull?.id;
  if (content == null || serviceId == null) return const [];
  return content.documentsFor(
    serviceId,
    lang: ref.watch(contentLanguageProvider),
  );
});

/// Locais que têm fluxo publicado, com seus passos.
///
/// Nada aqui sabe que "UBS" é o local com fluxo: o pack decide. Fixar o id em
/// Dart faria um município que publica o fluxo da UPA ficar sem tela.
final flowsProvider = Provider<Map<Venue, List<FlowStep>>>((ref) {
  final content = ref.watch(contentProvider);
  if (content == null) return const {};
  final lang = ref.watch(contentLanguageProvider);
  final result = <Venue, List<FlowStep>>{};
  for (final venue in content.venues(lang: lang)) {
    final steps = content.flowOf(venue.id, lang: lang);
    if (steps.isNotEmpty) result[venue] = steps;
  }
  return result;
});

/// Local cujo fluxo está na tela. `null` = o primeiro que tiver fluxo.
final selectedFlowVenueProvider = StateProvider<String?>((ref) => null);

/// Cartão informativo por id, no idioma ativo.
final infoCardProvider = Provider.family<ContentCard?, String>((ref, id) {
  final content = ref.watch(contentProvider);
  if (content == null) return null;
  return content.cardById(id, lang: ref.watch(contentLanguageProvider));
});

/// Cartões de resultado do pack — a tela de emergência mostra o de maior
/// severidade sem que o binário precise saber o id dele.
final resultCardsProvider = Provider<List<ContentCard>>((ref) {
  final content = ref.watch(contentProvider);
  if (content == null) return const [];
  return content.cardsOfKind(
    'result',
    lang: ref.watch(contentLanguageProvider),
  );
});
