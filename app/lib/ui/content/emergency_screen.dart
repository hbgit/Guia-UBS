/// Emergência — o atalho vermelho da tela inicial.
///
/// ===========================================================================
/// ESTA TELA NUNCA DEPENDE DE NADA
/// ===========================================================================
///
/// Quem chega aqui pode estar tendo um infarto. Ela é conteúdo estático
/// assinado: não usa o modelo SLM, não espera sync, não consulta rede e não
/// exige triagem. É por isso que `/emergencia` **não** está entre as rotas com
/// `requiresModel` — a exceção da INV-8 autorizada pelo ADR-003 alcança a
/// triagem, e só ela.
///
/// O 192 aparece como número em destaque, **não** como botão que disca:
/// discagem a partir de um toque acidental ocupa a linha do SAMU. A decisão de
/// ligar é da pessoa.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../shell/gubs_scaffold.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';
import '../triage/widgets/token_icons.dart';
import 'content_providers.dart';
import 'widgets/content_color.dart';
import 'widgets/empty_content.dart';
import 'widgets/listen_button.dart';

class EmergencyScreen extends ConsumerWidget {
  const EmergencyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final colors = context.gubs;

    // O cartão de emergência é o de MAIOR severidade do pack — descoberto pelo
    // conteúdo, não por um id escrito aqui. Um pack que renomeie o desfecho
    // continua funcionando.
    final cards = ref.watch(resultCardsProvider);
    final emergencyCard = cards
        .where((c) => isEmergencyToken(c.colorToken))
        .firstOrNull;

    // Locais marcados como emergência pelo próprio pack.
    final venues = ref
        .watch(venuesProvider)
        .where((v) => isEmergencyToken(v.venue.colorToken))
        .toList();

    if (emergencyCard == null && venues.isEmpty) {
      return EmptyContent(
        title: l.emergencyTitle,
        message: l.contentUnavailable,
      );
    }

    final spoken = [
      emergencyCard?.title.value,
      emergencyCard?.body?.value,
      l.resultEmergencyCall,
    ].whereType<String>().join('. ');

    return GubsScaffold(
      title: emergencyCard?.title.value ?? l.emergencyTitle,
      accent: colors.red,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (emergencyCard != null)
            Container(
              padding: const EdgeInsets.all(spacing * 3),
              decoration: BoxDecoration(
                color: colors.redSoft,
                borderRadius: BorderRadius.circular(radiusCard),
                border: Border.all(color: colors.red, width: 3),
              ),
              child: Column(
                children: [
                  Icon(
                    iconForRef(emergencyCard.iconRef),
                    size: 88,
                    color: colors.red,
                  ),
                  const SizedBox(height: spacing * 2),
                  Text(
                    emergencyCard.title.value,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.ink,
                        ),
                  ),
                  if (emergencyCard.body != null) ...[
                    const SizedBox(height: spacing * 1.5),
                    Text(
                      emergencyCard.body!.value,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: colors.ink),
                    ),
                  ],
                  const SizedBox(height: spacing),
                  ListenButton(text: spoken, color: colors.red),
                ],
              ),
            ),
          const SizedBox(height: spacing * 2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(spacing * 2),
            decoration: BoxDecoration(
              color: colors.red,
              borderRadius: BorderRadius.circular(radiusCard),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.call, size: 40, color: colors.onRed),
                const SizedBox(width: spacing * 2),
                Text(
                  l.resultEmergencyCall,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: colors.onRed,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
          ),
          if (venues.isNotEmpty) ...[
            const SizedBox(height: spacing * 3),
            Text(
              l.emergencyHint,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: colors.inkSoft),
            ),
            const SizedBox(height: spacing * 1.5),
            for (final entry in venues) ...[
              Container(
                key: ValueKey('emergency-venue-${entry.venue.id}'),
                padding: const EdgeInsets.all(spacing * 2),
                margin: const EdgeInsets.only(bottom: spacing * 1.5),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(radiusCard),
                  border: Border.all(color: colors.red, width: 2),
                ),
                child: Row(
                  children: [
                    Icon(
                      iconForRef(entry.venue.iconRef),
                      size: 36,
                      color: colors.red,
                    ),
                    const SizedBox(width: spacing * 1.5),
                    Expanded(
                      child: Text(
                        entry.venue.label.value,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.ink,
                            ),
                      ),
                    ),
                    ListenButton(
                      text: entry.venue.label.value,
                      color: colors.red,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
