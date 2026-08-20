/// Composição de sintomas (RF-02/RF-03, CAP-03).
///
/// Três passos — onde dói, o que sente, como é — que correspondem aos `kind`
/// da ontologia do pack. A FSM-A permanece em `S1_COMPOSING` durante os três:
/// compor é um estado só, e os passos são apresentação.
///
/// ## Zero texto obrigatório
///
/// Cada opção é ícone + rótulo, e o rótulo é redundante: quem lê usa, quem não
/// lê usa o ícone. O que a tela NÃO pode fazer é depender do texto para
/// comunicar estado — por isso o selecionado tem borda grossa, cor de destaque
/// e marca de conferido, três canais além da cor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../content/domain/content_models.dart';
import '../../l10n/app_localizations.dart';
import '../../triage/orchestrator/triage_session.dart';
import '../app_routes.dart';
import '../shell/gubs_scaffold.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';
import 'triage_controller.dart';
import 'widgets/token_tile.dart';

class CompositionScreen extends ConsumerStatefulWidget {
  const CompositionScreen({super.key});

  @override
  ConsumerState<CompositionScreen> createState() => _CompositionScreenState();
}

class _CompositionScreenState extends ConsumerState<CompositionScreen> {
  @override
  void initState() {
    super.initState();
    // Abre a sessão no primeiro frame: `begin()` mexe em providers, e fazer
    // isso durante o build de outro provider seria erro de ciclo de vida.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = ref.read(triageControllerProvider.notifier);
      if (ref.read(triageControllerProvider).state.name == 's0Idle') {
        controller.begin();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final colors = context.gubs;
    final controller = ref.watch(triageControllerProvider.notifier);
    final snapshot = ref.watch(triageControllerProvider);
    final step = controller.step;
    final tokens = ref.watch(stepTokensProvider(step));

    if (!ref.watch(triageAvailableProvider)) {
      return _NoContent(message: l.contentUnavailable);
    }

    return GubsScaffold(
      title: switch (step) {
        CompositionStep.bodyPart => l.triageWhereQuestion,
        CompositionStep.symptom => l.triageWhatQuestion,
        CompositionStep.modifier => l.triageHowQuestion,
      },
      subtitle: step == CompositionStep.bodyPart
          ? l.triageTapHint
          : l.triageMultiHint,
      accent: colors.green,
      onBack: () {
        // Voltar no primeiro passo sai da triagem e apaga a sessão; nos
        // demais, recua um passo. Sem isso, sair exigiria "casa", e a
        // composição inteira se perderia sem aviso.
        if (step.previous == null) {
          controller.finish();
          context.go('/');
        } else {
          setState(controller.previousStep);
        }
      },
      child: Column(
        children: [
          _StepDots(current: step.indexInFlow, total: CompositionStep.values.length),
          const SizedBox(height: spacing * 2),
          Expanded(
            child: _TokenGrid(
              tokens: tokens,
              selected: snapshot.tokens.toSet(),
              rejected: snapshot.rejectedToken,
              full: snapshot.isFull,
              onTap: (id) => setState(() => controller.toggleToken(id)),
            ),
          ),
          const SizedBox(height: spacing * 2),
          _SelectionBar(count: snapshot.tokens.length),
          const SizedBox(height: spacing * 2),
          _PrimaryAction(
            step: step,
            snapshot: snapshot,
            onNext: () => setState(controller.nextStep),
            onConfirm: () async {
              await controller.confirm();
              if (context.mounted) context.goNamed(Routes.triageResult);
            },
          ),
        ],
      ),
    );
  }
}

/// Progresso da composição, sem números: três pontos, o atual preenchido.
class _StepDots extends StatelessWidget {
  const _StepDots({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          Container(
            width: i == current ? 32 : 12,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: i <= current ? colors.green : colors.line,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
      ],
    );
  }
}

class _TokenGrid extends StatelessWidget {
  const _TokenGrid({
    required this.tokens,
    required this.selected,
    required this.rejected,
    required this.full,
    required this.onTap,
  });

  final List<SymptomToken> tokens;
  final Set<String> selected;
  final String? rejected;
  final bool full;
  final void Function(String id) onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // Extensão máxima, não contagem fixa: em tela estreita dá duas
        // colunas, em tablet dá três ou quatro, e o alvo nunca encolhe abaixo
        // do mínimo de toque.
        maxCrossAxisExtent: 200,
        mainAxisExtent: 132,
        crossAxisSpacing: spacing * 1.5,
        mainAxisSpacing: spacing * 1.5,
      ),
      itemCount: tokens.length,
      itemBuilder: (context, index) {
        final token = tokens[index];
        return TokenTile(
          token: token,
          selected: selected.contains(token.id),
          // Um ícone que não pode mais ser escolhido precisa PARECER
          // indisponível, senão o toque some sem explicação.
          disabled: full && !selected.contains(token.id),
          justRejected: rejected == token.id,
          onTap: () => onTap(token.id),
        );
      },
    );
  }
}

/// Quantos ícones já foram escolhidos, com o teto visível.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return Semantics(
      label: L.of(context).triageSelectedCount(count, maxSessionTokens),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < maxSessionTokens; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                i < count ? Icons.check_circle : Icons.circle_outlined,
                size: 28,
                color: i < count ? colors.green : colors.line,
              ),
            ),
        ],
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.step,
    required this.snapshot,
    required this.onNext,
    required this.onConfirm,
  });

  final CompositionStep step;
  final TriageSnapshot snapshot;
  final VoidCallback onNext;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final colors = context.gubs;
    final isLast = step.next == null;
    final canConfirm = snapshot.tokens.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: const ValueKey('triage-primary'),
        // No último passo, sem token nenhum, não há o que avaliar — a FSM
        // recusaria o `confirm` de qualquer forma (linha A4).
        onPressed: isLast && !canConfirm ? null : (isLast ? onConfirm : onNext),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(88),
          backgroundColor: colors.green,
          foregroundColor: colors.onGreen,
        ),
        icon: Icon(isLast ? Icons.check : Icons.arrow_forward, size: 32),
        label: Text(
          isLast ? l.triageSeeGuidance : l.actionContinue,
          // Cor explícita: os estilos do `textTheme` já vêm coloridos com
          // `onSurface` e venceriam o `foregroundColor` do botão.
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.onGreen,
              ),
        ),
      ),
    );
  }
}

class _NoContent extends StatelessWidget {
  const _NoContent({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return GubsScaffold(
      title: L.of(context).homeStartTriage,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 96, color: colors.inkSoft),
            const SizedBox(height: spacing * 3),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: colors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}
