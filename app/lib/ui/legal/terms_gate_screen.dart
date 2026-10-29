/// "Li e concordo" na primeira abertura e a cada versão nova dos termos
/// (ADR-004, §3.1(1) dos Gemma Terms of Use).
///
/// ===========================================================================
/// RECUSAR DESLIGA SÓ O ASSISTENTE
/// ===========================================================================
///
/// Quem abre o app pode estar numa emergência. Por isso a saída "usar sem o
/// assistente" custa UM toque e leva à inicial, onde o gate de red flags, as
/// regras e o conteúdo estático funcionam igual (INV-1, INV-8). O que a
/// recusa desliga é o download e o carregamento do modelo
/// (`assistantAllowedProvider`).
///
/// A resposta fica só no aparelho, sem identificar ninguém e sem sair dele
/// (INV-2): não é registro de consentimento da LGPD-RF04.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../app_scope.dart';
import '../more/legal_document.dart';
import '../more/legal_documents_screen.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';

class TermsGateScreen extends ConsumerWidget {
  const TermsGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final colors = context.gubs;
    final text = Theme.of(context).textTheme;
    final answered = ref.watch(termsAnswerProvider)?.version != null;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // O texto rola; as duas RESPOSTAS não. A revisão final achou
            // "usar sem o assistente" no fim de uma coluna de ~750 dp, fora da
            // tela num 360×640: quem abre o app numa emergência logo depois de
            // uma atualização dos termos teria de rolar e ler para sair.
            //
            // Coluna rolável, não `ListView`: uma lista preguiçosa deixaria
            // itens fora da árvore — e do leitor de tela — até alguém rolar.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(spacing * 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 56,
                      color: colors.blue,
                    ),
                    const SizedBox(height: spacing * 1.5),
                    Text(
                      answered ? l.termsGateChangedTitle : l.termsGateTitle,
                      textAlign: TextAlign.center,
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: spacing * 2),
                    Text(
                      l.termsGateBody,
                      style: text.bodyLarge?.copyWith(
                        color: colors.ink,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: spacing * 2),
                    Text(
                      gemmaNoticeLine,
                      style: text.bodySmall?.copyWith(color: colors.inkSoft),
                    ),
                    const SizedBox(height: spacing * 3),
                    OutlinedButton.icon(
                      key: const ValueKey('terms-listen'),
                      style: _outlined(colors.line),
                      onPressed: () => ref
                          .read(speakerProvider)
                          .speak(
                            l.termsGateBody,
                            ref.read(speechLocaleProvider),
                          ),
                      icon: Icon(Icons.volume_up, color: colors.ink),
                      label: Text(
                        l.termsGateListen,
                        style: text.titleMedium?.copyWith(color: colors.ink),
                      ),
                    ),
                    const SizedBox(height: spacing * 1.5),
                    OutlinedButton.icon(
                      key: const ValueKey('terms-read'),
                      style: _outlined(colors.line),
                      // Por cima do portão: o redirect devolveria aqui quem
                      // saísse por rota antes de responder.
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (page) => LegalDocumentsScreen(
                            onBack: () => Navigator.of(page).pop(),
                          ),
                        ),
                      ),
                      icon: Icon(Icons.article_outlined, color: colors.ink),
                      label: Text(
                        l.termsGateOpenTerms,
                        style: text.titleMedium?.copyWith(color: colors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Barra fixa. As duas respostas com o MESMO peso visual e com
            // ícone (zero texto obrigatório): recusar não é a opção escondida.
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: colors.line)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  spacing * 3,
                  spacing * 1.5,
                  spacing * 3,
                  spacing * 1.5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('terms-accept'),
                      style: _outlined(colors.blue),
                      onPressed: () => ref
                          .read(termsAnswerProvider.notifier)
                          .answer(accepted: true),
                      icon: Icon(
                        Icons.check_circle_outline,
                        color: colors.blue,
                      ),
                      label: Text(
                        l.termsGateAccept,
                        style: text.titleMedium?.copyWith(color: colors.ink),
                      ),
                    ),
                    const SizedBox(height: spacing),
                    OutlinedButton.icon(
                      key: const ValueKey('terms-decline'),
                      style: _outlined(colors.line),
                      onPressed: () => ref
                          .read(termsAnswerProvider.notifier)
                          .answer(accepted: false),
                      icon: Icon(Icons.arrow_forward, color: colors.ink),
                      label: Text(
                        l.termsGateDecline,
                        style: text.titleMedium?.copyWith(color: colors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _outlined(Color border) => OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(minTouchTarget),
    side: BorderSide(color: border, width: 2),
  );
}
