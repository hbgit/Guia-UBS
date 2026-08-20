/// O que levar (RF-08, CAP-08).
///
/// Documentos **por serviço**: vacina e curativo pedem menos que consulta, e o
/// atendimento de urgência pede menos ainda. Mostrar uma lista única faria
/// alguém desistir de ir à UBS por achar que falta um papel que aquele
/// atendimento não exige.
///
/// ## A ordem não é estética
///
/// Obrigatórios primeiro, sempre — a ordenação vem do repositório, não do
/// layout. Quem tem cinco minutos de atenção precisa ver o que IMPEDE o
/// atendimento antes do que apenas ajuda; e a distinção entre os dois é
/// visível em três canais (rótulo, cor da faixa e ícone), não só na posição.
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
import 'widgets/empty_content.dart';
import 'widgets/listen_button.dart';

class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final services = ref.watch(servicesProvider);
    final documents = ref.watch(documentsProvider);

    if (services.isEmpty) {
      return EmptyContent(
        title: l.documentsTitle,
        message: l.contentUnavailable,
      );
    }

    final selected = ref.watch(selectedServiceProvider) ?? services.first.id;

    return GubsScaffold(
      title: l.documentsTitle,
      subtitle: l.documentsHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ServicePicker(services: services, selected: selected),
          const SizedBox(height: spacing * 2),
          Expanded(
            child: documents.isEmpty
                ? Center(
                    child: Text(
                      l.contentUnavailable,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: context.gubs.inkSoft),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: documents.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: spacing * 1.5),
                    itemBuilder: (context, index) =>
                        _DocumentCard(document: documents[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ServicePicker extends ConsumerWidget {
  const _ServicePicker({required this.services, required this.selected});

  final List<Service> services;
  final String selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.gubs;
    // `Wrap`, não lista horizontal: numa régua que rola, o último atendimento
    // fica FORA da tela, e para este público conteúdo fora da tela é conteúdo
    // que não existe — não há por que supor que alguém vá arrastar de lado
    // atrás de algo cuja existência não foi anunciada.
    return Wrap(
      key: const ValueKey('doc-service-picker'),
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (final service in services)
          Builder(
            builder: (context) {
              final isSelected = service.id == selected;
              return ChoiceChip(
                key: ValueKey('doc-service-${service.id}'),
            selected: isSelected,
            onSelected: (_) => ref
                .read(selectedServiceProvider.notifier)
                .state = service.id,
            showCheckmark: false,
            // O selecionado se distingue por preenchimento, borda E ícone —
            // não só por cor.
            avatar: Icon(
              isSelected ? Icons.check_circle : iconForRef(service.iconRef),
              size: 24,
              color: isSelected ? colors.greenDeep : colors.inkSoft,
            ),
            selectedColor: colors.greenSoft,
            backgroundColor: colors.surface,
            side: BorderSide(
              color: isSelected ? colors.green : colors.line,
              width: isSelected ? 3 : 2,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: spacing * 1.5,
              vertical: spacing,
            ),
                label: Text(
                  service.label.value,
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

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document});

  final RequiredDocument document;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final colors = context.gubs;

    // Obrigatório usa a cor de INFORMAÇÃO reforçada, não vermelho: falta de
    // documento não é emergência clínica, e pintar de vermelho competiria com
    // o único significado que o vermelho tem neste app.
    final accent = document.required ? colors.blue : colors.inkSoft;
    final badge =
        document.required ? l.documentsRequired : l.documentsOptional;

    final spoken = [
      document.label.value,
      badge,
      document.hint?.value,
    ].whereType<String>().join('. ');

    return Container(
      key: ValueKey('document-${document.id}'),
      padding: const EdgeInsets.all(spacing * 2),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: colors.line, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconForRef(document.iconRef), size: 40, color: accent),
          const SizedBox(width: spacing * 1.5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.label.value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                      ),
                ),
                const SizedBox(height: spacing * 0.5),
                Row(
                  children: [
                    Icon(
                      document.required
                          ? Icons.priority_high
                          : Icons.info_outline,
                      size: 16,
                      color: accent,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        badge,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: accent),
                      ),
                    ),
                  ],
                ),
                if (document.hint != null) ...[
                  const SizedBox(height: spacing),
                  Text(
                    document.hint!.value,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: colors.inkSoft),
                  ),
                ],
              ],
            ),
          ),
          ListenButton(text: spoken),
        ],
      ),
    );
  }
}
