/// Seleção de idioma (RF-01, CAP-01).
///
/// Primeira tela que qualquer pessoa vê. Duas regras a governam:
///
/// 1. **Ela não pode estar em nenhum idioma.** Quem chega aqui ainda não disse
///    qual entende, então a tela mostra os dois nomes escritos como cada um se
///    escreve — "Português" e "Español" — e a pergunta aparece nas duas
///    línguas simultaneamente. Perguntar "Toque no seu idioma" só em português
///    é pedir para o hispanofalante adivinhar.
/// 2. **A bandeira não é o rótulo.** Bandeira identifica país, não língua, e o
///    público inclui bolivianos, venezuelanos e paraguaios. O nome da língua é
///    o que decide; o ícone acompanha.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../prefs/locale_store.dart';
import '../app_scope.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';

class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.gubs;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(spacing * 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 72, color: colors.green),
                const SizedBox(height: spacing * 2),
                Text(
                  L.of(context).appTitle,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: spacing * 3),
                // As duas perguntas juntas, sem depender do locale ativo.
                Text(
                  'Toque no seu idioma\nToca tu idioma',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: colors.inkSoft),
                ),
                const SizedBox(height: spacing * 4),
                _LanguageButton(
                  locale: AppLocale.pt,
                  label: 'Português',
                  onPressed: () =>
                      ref.read(localeControllerProvider.notifier).select(AppLocale.pt),
                ),
                const SizedBox(height: spacing * 2),
                _LanguageButton(
                  locale: AppLocale.es,
                  label: 'Español',
                  onPressed: () =>
                      ref.read(localeControllerProvider.notifier).select(AppLocale.es),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({
    required this.locale,
    required this.label,
    required this.onPressed,
  });

  final AppLocale locale;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        key: ValueKey('lang-${locale.code}'),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          // Bem acima do mínimo de 64 dp: é a decisão mais importante da tela
          // e não há nada disputando o espaço.
          minimumSize: const Size.fromHeight(96),
          side: BorderSide(color: colors.line, width: 2),
          backgroundColor: colors.surface,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.translate, size: 32, color: colors.blue),
            const SizedBox(width: spacing * 2),
            // `Flexible`, não `Text` solto: com a fonte ampliada em tela
            // estreita, "Português" sozinho passa da largura do botão. Sem
            // isto o nome do idioma sai pela borda — na única tela em que a
            // pessoa ainda não pode ler nenhuma instrução para se orientar.
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: colors.ink, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
