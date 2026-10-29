/// O Notice e os termos do Gemma (ADR-004).
///
/// Quem recebe o modelo recebe também, nesta tela, o que a §3.1 dos Gemma
/// Terms of Use exige: o Notice literal e a cópia do Agreement em inglês. O
/// resumo e a Política em pt/es vêm antes, como cortesia, e dizem que o inglês
/// prevalece.
///
/// O Notice fica em destaque com a cor de INFORMAÇÃO (azul). Lilás é da
/// procedência da orientação e não aparece aqui; verde e vermelho são clínicos.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../app_scope.dart';
import '../shell/gubs_scaffold.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';
import 'legal_document.dart';
import 'legal_documents_screen.dart';

/// Documentos do idioma ativo; `family` pelo código, como os legais.
final gemmaDocumentsProvider = FutureProvider.family<GemmaDocuments, String>(
  (ref, languageCode) => loadGemmaDocuments(languageCode),
);

class GemmaDocumentsScreen extends ConsumerWidget {
  const GemmaDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final language = ref.watch(contentLanguageProvider);
    final docs = ref.watch(gemmaDocumentsProvider(language));

    return GubsScaffold(
      title: l.gemmaDocumentsTitle,
      child: docs.when(
        // Sem indicador animado: ver o comentário de LegalDocumentsScreen.
        loading: () => const SizedBox.shrink(),
        error: (error, stack) => _Unavailable(l.gemmaDocumentsUnavailable),
        data: (d) => d.notice.isEmpty && d.documents.isEmpty
            ? _Unavailable(l.gemmaDocumentsUnavailable)
            : ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (d.notice.isNotEmpty) _NoticeBox(text: d.notice),
                  for (final document in d.documents) ...[
                    const SizedBox(height: spacing * 3),
                    for (final block in document.blocks)
                      LegalBlockView(block: block),
                  ],
                  const SizedBox(height: spacing * 4),
                ],
              ),
      ),
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return Container(
      key: const ValueKey('gemma-notice'),
      padding: const EdgeInsets.all(spacing * 2),
      decoration: BoxDecoration(
        color: colors.blueSoft,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: colors.blue, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 28, color: colors.blue),
          const SizedBox(width: spacing * 1.5),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.ink, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: context.gubs.inkSoft),
        ),
      );
}
