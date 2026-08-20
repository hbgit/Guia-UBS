/// Onde ir — UBS, UPA ou hospital (RF-07, CAP-07).
///
/// A pergunta que esta tela responde é a mais frequente do público-alvo, e a
/// que mais congestiona pronto-socorro quando respondida errado: *cada lugar
/// cuida de uma coisa*.
///
/// Todo o conteúdo — nomes, serviços, cor — vem do `content.db` assinado
/// (RF-07). O binário não sabe que "UBS" existe: ele desenha o que o pack
/// publicou, na ordem que o pack publicou.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../app_routes.dart';
import '../shell/gubs_scaffold.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';
import '../triage/widgets/token_icons.dart';
import 'content_providers.dart';
import 'widgets/content_color.dart';
import 'widgets/empty_content.dart';
import 'widgets/listen_button.dart';

class WhereToScreen extends ConsumerWidget {
  const WhereToScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final venues = ref.watch(venuesProvider);

    if (venues.isEmpty) {
      return EmptyContent(title: l.whereToTitle, message: l.contentUnavailable);
    }

    return GubsScaffold(
      title: l.whereToTitle,
      subtitle: l.whereToHint,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: venues.length,
        separatorBuilder: (_, _) => const SizedBox(height: spacing * 2),
        itemBuilder: (context, index) => _VenueCard(entry: venues[index]),
      ),
    );
  }
}

class _VenueCard extends StatelessWidget {
  const _VenueCard({required this.entry});

  final VenueWithServices entry;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final colors = context.gubs;
    final role = colorsForToken(entry.venue.colorToken, colors);
    final services = entry.services.map((s) => s.label.value).join(', ');

    // O que o áudio lê: nome do local e o que ele atende, na mesma ordem da
    // tela. Quem ouve precisa receber a mesma informação de quem vê.
    final spoken = services.isEmpty
        ? entry.venue.label.value
        : '${entry.venue.label.value}. ${l.whereToServices}: $services.';

    return Container(
      key: ValueKey('venue-${entry.venue.id}'),
      padding: const EdgeInsets.all(spacing * 2),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: role.accent, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(spacing),
                decoration: BoxDecoration(
                  color: role.background,
                  borderRadius: BorderRadius.circular(radiusButton),
                ),
                child: Icon(
                  iconForRef(entry.venue.iconRef),
                  size: 40,
                  color: role.accent,
                ),
              ),
              const SizedBox(width: spacing * 1.5),
              Expanded(
                child: Text(
                  entry.venue.label.value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.ink,
                      ),
                ),
              ),
              ListenButton(text: spoken, color: role.accent),
            ],
          ),
          if (entry.services.isNotEmpty) ...[
            const SizedBox(height: spacing * 1.5),
            Text(
              l.whereToServices,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: colors.inkSoft),
            ),
            const SizedBox(height: spacing),
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final service in entry.services)
                  _ServiceChip(
                    id: service.id,
                    label: service.label.value,
                    iconRef: service.iconRef,
                    accent: role.accent,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Um serviço. Tocar leva aos documentos daquele atendimento — é a ponte
/// natural entre "onde ir" (RF-07) e "o que levar" (RF-08).
class _ServiceChip extends ConsumerWidget {
  const _ServiceChip({
    required this.id,
    required this.label,
    required this.iconRef,
    required this.accent,
  });

  final String id;
  final String label;
  final String iconRef;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.gubs;
    return OutlinedButton.icon(
      key: ValueKey('service-$id'),
      onPressed: () {
        ref.read(selectedServiceProvider.notifier).state = id;
        context.go(GubsTab.documents.rootPath);
      },
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: colors.line, width: 2),
        backgroundColor: colors.surface,
        padding: const EdgeInsets.symmetric(
          horizontal: spacing * 1.5,
          vertical: spacing,
        ),
      ),
      icon: Icon(iconForRef(iconRef), size: 28, color: accent),
      label: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(color: colors.ink, fontWeight: FontWeight.w600),
      ),
    );
  }
}
