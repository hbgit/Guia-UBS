/// Leitor do aviso de privacidade e dos termos de uso.
///
/// Os dois documentos num scroll só, e não em duas telas: são textos que a
/// pessoa lê de uma vez ou não lê, e uma tela a mais custaria um nível de
/// profundidade sem entregar nada.
///
/// A data da versão local fica no TOPO, antes do texto — quem confere se está
/// lendo a versão vigente não deveria ter de rolar até o fim para descobrir.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../app_scope.dart';
import '../shell/gubs_scaffold.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';
import 'legal_document.dart';

/// Documentos do idioma ativo. `family` pelo código de idioma: trocar o idioma
/// recarrega sozinho, sem a tela precisar saber que isso aconteceu.
final legalDocumentsProvider =
    FutureProvider.family<List<LegalDocument>, String>(
  (ref, languageCode) => loadLegalDocuments(languageCode),
);

class LegalDocumentsScreen extends ConsumerWidget {
  const LegalDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final language = ref.watch(contentLanguageProvider);
    final documents = ref.watch(legalDocumentsProvider(language));

    return GubsScaffold(
      title: l.legalTitle,
      child: documents.when(
        // Espaço vazio, e NÃO um `CircularProgressIndicator`: ler dois
        // arquivos do bundle leva um frame, então o giro seria teatro — e um
        // indicador indeterminado anima para sempre, o que trava qualquer
        // `pumpAndSettle` que passe por esta rota. Foi assim que o teste de
        // navegação da casca começou a estourar por timeout.
        loading: () => const SizedBox.shrink(),
        // `loadLegalDocuments` não lança; este ramo é a rede de segurança para
        // uma falha do próprio provider.
        error: (error, stack) => _Unavailable(message: l.legalUnavailable),
        data: (docs) => docs.isEmpty
            ? _Unavailable(message: l.legalUnavailable)
            : _Documents(documents: docs),
      ),
    );
  }
}

class _Documents extends StatelessWidget {
  const _Documents({required this.documents});

  final List<LegalDocument> documents;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final date = documents.first.displayDate;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (date != null) _VersionBadge(text: l.privacyDocumentsVersion(date)),
        const SizedBox(height: spacing * 2),
        // O aviso de minuta sai daqui no mesmo commit em que os documentos
        // forem aprovados juridicamente.
        _DraftWarning(text: l.legalDraft),
        for (final document in documents) ...[
          const SizedBox(height: spacing * 3),
          for (final block in document.blocks) _Block(block: block),
        ],
        const SizedBox(height: spacing * 4),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.block});

  final LegalBlock block;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    final text = Theme.of(context).textTheme;

    return switch (block.kind) {
      LegalBlockKind.title => Padding(
          padding: const EdgeInsets.only(top: spacing * 2, bottom: spacing),
          child: Text(
            block.text,
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.ink,
            ),
          ),
        ),
      LegalBlockKind.heading => Padding(
          padding: const EdgeInsets.only(top: spacing * 2, bottom: spacing),
          child: Text(
            block.text,
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.ink,
            ),
          ),
        ),
      LegalBlockKind.paragraph => Padding(
          padding: const EdgeInsets.only(bottom: spacing),
          child: Text(
            block.text,
            style: text.bodyLarge?.copyWith(color: colors.ink, height: 1.45),
          ),
        ),
      LegalBlockKind.bullet => Padding(
          padding: const EdgeInsets.only(bottom: spacing * 0.75, left: spacing),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: spacing * 0.75),
                child: Icon(Icons.circle, size: 8, color: colors.inkSoft),
              ),
              const SizedBox(width: spacing * 1.5),
              Expanded(
                child: Text(
                  block.text,
                  style: text.bodyLarge
                      ?.copyWith(color: colors.ink, height: 1.45),
                ),
              ),
            ],
          ),
        ),
    };
  }
}

class _VersionBadge extends StatelessWidget {
  const _VersionBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return Row(
      children: [
        Icon(Icons.event_outlined, size: 24, color: colors.inkSoft),
        const SizedBox(width: spacing),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colors.inkSoft),
          ),
        ),
      ],
    );
  }
}

class _DraftWarning extends StatelessWidget {
  const _DraftWarning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return Container(
      padding: const EdgeInsets.all(spacing * 2),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: colors.amber, width: 2),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, size: 28, color: colors.amber),
          const SizedBox(width: spacing * 1.5),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 64, color: colors.inkSoft),
          const SizedBox(height: spacing * 2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: colors.inkSoft),
          ),
        ],
      ),
    );
  }
}
