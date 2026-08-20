/// Resultado da triagem (RF-06, CAP-06).
///
/// ===========================================================================
/// A TELA QUE DECIDE SE ALGUÉM VAI À UPA OU PARA CASA
/// ===========================================================================
///
/// Três regras que a governam:
///
/// 1. **A cor vem da SEVERIDADE, nunca do nome.** `GubsColors.forSeverity`
///    resolve o par; escolher entre verde e vermelho aqui seria o caminho para
///    um cartão de emergência pintado de verde. O `color_token` do pack é
///    ignorado de propósito no resultado — quem manda é o `severity_level`, que
///    é a mesma coluna que o gate usa.
/// 2. **O cartão renderiza sem esperar o áudio.** O TTS é disparado em
///    paralelo e sua falha não bloqueia nada (INV-8). Quem não lê perde o
///    áudio, mas continua vendo o ícone e a cor.
/// 3. **Sair apaga a sessão.** Num posto, o aparelho é compartilhado: a
///    triagem de quem saiu não pode ficar na tela para o próximo.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../triage/domain/severity.dart';
import '../app_scope.dart';
import '../shell/gubs_scaffold.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';
import 'triage_controller.dart';
import 'widgets/token_icons.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  bool _spoken = false;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final colors = context.gubs;
    final result = ref.watch(triageControllerProvider).result;
    final card = ref.watch(resultCardProvider);

    // Sessão encerrada (ou aparelho retomado depois do timeout de 120 s): não
    // há o que mostrar, e insistir numa tela vazia seria um dead-end.
    if (result == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/');
      });
      return const SizedBox.shrink();
    }

    // A escala de severidade vem do PACK, não de limiares em Dart: `10` é
    // rotina neste pacote e poderia ser outra coisa no próximo.
    final model = ref.watch(ruleModelProvider);
    final severity = model == null
        ? GubsSeverity.emergency // sem regras, o conservador é o vermelho
        : severityFor(result.severityLevel, model);
    final role = colors.forSeverity(severity);

    // Fire-and-forget, uma vez por resultado. A tela já está montada quando
    // isto roda: o áudio acompanha o cartão, não o precede.
    if (!_spoken && card != null) {
      _spoken = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        speakCard(ref, card).ignore();
      });
    }

    final speechAvailable =
        ref.watch(speechAvailabilityProvider).valueOrNull ?? false;

    return GubsScaffold(
      title: card?.title.value ?? '',
      accent: role.accent,
      // Botão de áudio só quando há voz: um botão que não fala faria quem
      // depende dele concluir que o app está quebrado.
      onListen: speechAvailable && card != null
          ? () => speakCard(ref, card).ignore()
          : null,
      onBack: () => _leave(context),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(spacing * 3),
                    decoration: BoxDecoration(
                      color: role.background,
                      borderRadius: BorderRadius.circular(radiusCard),
                      border: Border.all(color: role.accent, width: 3),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          iconForRef(card?.iconRef ?? ''),
                          size: 96,
                          color: role.accent,
                        ),
                        const SizedBox(height: spacing * 2),
                        Text(
                          card?.title.value ?? '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: colors.ink,
                              ),
                        ),
                        if (card?.body != null) ...[
                          const SizedBox(height: spacing * 1.5),
                          Text(
                            card!.body!.value,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: colors.ink),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (severity == GubsSeverity.emergency) ...[
                    const SizedBox(height: spacing * 2),
                    _EmergencyCall(label: l.resultEmergencyCall),
                  ],
                  if (result.degraded) ...[
                    const SizedBox(height: spacing * 2),
                    _DegradedNote(label: l.resultDegradedNote),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: spacing * 2),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('result-done'),
              onPressed: () => _leave(context),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(88),
                backgroundColor: colors.surfaceAlt,
                foregroundColor: colors.ink,
              ),
              child: Text(
                l.resultNext,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: colors.ink, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _leave(BuildContext context) {
    ref.read(triageControllerProvider.notifier).finish();
    context.go('/');
  }
}

/// Destaque do 192 no cartão de emergência.
///
/// Número em texto grande e ícone de telefone — **não** um botão que disca:
/// discagem automática a partir de um toque acidental ocupa a linha do SAMU.
/// A decisão de ligar é da pessoa.
class _EmergencyCall extends StatelessWidget {
  const _EmergencyCall({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return Container(
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
            label,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colors.onRed,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

/// Aviso de que a triagem rodou sem o modelo (RF-12).
///
/// Discreto de propósito: a orientação é clinicamente válida — o gate
/// determinístico decidiu sozinho e a INV-1 protege as emergências. Alarmar
/// aqui faria a pessoa desconfiar de um resultado correto.
class _DegradedNote extends StatelessWidget {
  const _DegradedNote({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.info_outline, size: 20, color: colors.inkSoft),
        const SizedBox(width: spacing),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.inkSoft),
          ),
        ),
      ],
    );
  }
}
