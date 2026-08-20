/// Como funciona o atendimento (RF-09, CAP-09).
///
/// Passos numerados, na ordem que o pack publicou (`step_order`). O objetivo é
/// tirar o medo do desconhecido: quem nunca foi a uma UBS não sabe que existe
/// acolhimento antes da consulta, e a incerteza é um dos motivos de as pessoas
/// irem direto ao pronto-socorro.
///
/// **Nada aqui sabe que "UBS" é o local com fluxo.** O pack decide quais locais
/// têm passos publicados; fixar o id em Dart deixaria sem tela um município que
/// publicasse o fluxo da UPA.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../content/domain/content_models.dart';
import '../../l10n/app_localizations.dart';
import '../shell/gubs_scaffold.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';
import '../triage/widgets/token_icons.dart';
import 'content_providers.dart';
import 'widgets/content_color.dart';
import 'widgets/empty_content.dart';
import 'widgets/listen_button.dart';

class FlowScreen extends ConsumerWidget {
  const FlowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final flows = ref.watch(flowsProvider);

    if (flows.isEmpty) {
      return EmptyContent(title: l.flowTitle, message: l.contentUnavailable);
    }

    final venues = flows.keys.toList();
    final selectedId = ref.watch(selectedFlowVenueProvider);
    final venue = venues.firstWhere(
      (v) => v.id == selectedId,
      orElse: () => venues.first,
    );
    final steps = flows[venue]!;
    final role = colorsForToken(venue.colorToken, context.gubs);

    // O áudio lê o fluxo inteiro, em ordem. É a forma de quem não lê receber a
    // mesma sequência que a tela mostra.
    final spoken = [
      venue.label.value,
      for (final step in steps)
        [step.title.value, step.body?.value].whereType<String>().join('. '),
    ].join('. ');

    return GubsScaffold(
      title: venue.label.value,
      subtitle: l.flowHint,
      accent: role.accent,
      onListen: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Seletor só quando há mais de um local com fluxo: um seletor de uma
          // opção é ruído numa tela com teto de oito elementos.
          if (venues.length > 1) ...[
            _VenuePicker(venues: venues, selected: venue.id),
            const SizedBox(height: spacing * 2),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: ListenButton(text: spoken, color: role.accent),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: steps.length,
              itemBuilder: (context, index) => _Step(
                step: steps[index],
                number: index + 1,
                accent: role.accent,
                background: role.background,
                isLast: index == steps.length - 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VenuePicker extends ConsumerWidget {
  const _VenuePicker({required this.venues, required this.selected});

  final List<Venue> venues;
  final String selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.gubs;
    // Mesma razão da tela de documentos: nada de rolagem horizontal, para que
    // nenhum local fique fora da tela sem anúncio.
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (final venue in venues)
          Builder(
            builder: (context) {
              final isSelected = venue.id == selected;
              final role = colorsForToken(venue.colorToken, colors);
              return ChoiceChip(
            key: ValueKey('flow-venue-${venue.id}'),
            selected: isSelected,
            showCheckmark: false,
            onSelected: (_) => ref
                .read(selectedFlowVenueProvider.notifier)
                .state = venue.id,
            avatar: Icon(
              isSelected ? Icons.check_circle : iconForRef(venue.iconRef),
              size: 24,
              color: isSelected ? role.accent : colors.inkSoft,
            ),
            selectedColor: role.background,
            backgroundColor: colors.surface,
            side: BorderSide(
              color: isSelected ? role.accent : colors.line,
              width: isSelected ? 3 : 2,
            ),
                label: Text(
                  venue.label.value,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.ink,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w500,
                      ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Um passo, com a linha que o liga ao seguinte.
///
/// A linha vertical é o que transforma quatro cartões soltos em uma
/// **sequência**. Para quem não lê os números, é ela que diz "isto vem depois
/// daquilo".
class _Step extends StatelessWidget {
  const _Step({
    required this.step,
    required this.number,
    required this.accent,
    required this.background,
    required this.isLast,
  });

  final FlowStep step;
  final int number;
  final Color accent;
  final Color background;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final colors = context.gubs;

    return IntrinsicHeight(
      key: ValueKey('flow-step-${step.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 2),
                ),
                child: Text(
                  '$number',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 3, color: accent.withValues(alpha: 0.4)),
                ),
            ],
          ),
          const SizedBox(width: spacing * 1.5),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : spacing * 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(iconForRef(step.iconRef), size: 28, color: accent),
                      const SizedBox(width: spacing),
                      Expanded(
                        child: Text(
                          step.title.value,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colors.ink,
                              ),
                        ),
                      ),
                    ],
                  ),
                  Semantics(
                    label: l.flowStepNumber(number),
                    child: const SizedBox.shrink(),
                  ),
                  if (step.body != null) ...[
                    const SizedBox(height: spacing * 0.5),
                    Text(
                      step.body!.value,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: colors.inkSoft),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
