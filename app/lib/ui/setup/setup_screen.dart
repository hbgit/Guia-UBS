/// Rota do First-Time Setup (ADR-003).
///
/// Fina camada entre o roteador e a [OnboardingScreen], que já existia e foi
/// verificada em aparelho. O que muda aqui é só de onde vêm as dependências
/// (providers) e para onde se vai ao terminar (`/`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_scope.dart';
import '../more/gemma_documents_screen.dart';
import '../onboarding/onboarding_screen.dart';

class SetupScreen extends ConsumerWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OnboardingScreen(
      provisioning: ref.watch(provisioningProvider),
      pickLocalModel: ref.watch(localModelPickerProvider),
      // Por cima do portão, e não por rota: o redirect devolveria ao setup
      // quem saísse dele antes de concluir.
      openGemmaTerms: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (pageContext) => GemmaDocumentsScreen(
          onBack: () => Navigator.of(pageContext).pop(),
        ),
      )),
      onReady: () {
        // `canPop` é falso aqui: o setup é a raiz quando aparece, e voltar
        // dele não faria sentido. `go` substitui, não empilha.
        if (context.mounted) context.go('/');
      },
    );
  }
}
