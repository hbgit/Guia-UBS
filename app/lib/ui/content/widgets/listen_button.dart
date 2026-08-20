/// Botão de ouvir, para qualquer texto de conteúdo.
///
/// Só existe quando há voz disponível: um botão que não fala faria quem depende
/// dele concluir que o app está quebrado (risco A3 da espec). E ele é
/// fire-and-forget — a tela nunca espera o áudio, porque falha de TTS não pode
/// bloquear navegação (INV-8).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../theme/gubs_colors.dart';
import '../../theme/gubs_metrics.dart';

class ListenButton extends ConsumerWidget {
  const ListenButton({required this.text, this.color, super.key});

  /// O que falar. Vazio esconde o botão.
  final String text;

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available =
        ref.watch(speechAvailabilityProvider).valueOrNull ?? false;
    if (!available || text.trim().isEmpty) return const SizedBox.shrink();

    final colors = context.gubs;
    return IconButton(
      onPressed: () => speakContent(ref, text).ignore(),
      tooltip: L.of(context).actionListen,
      iconSize: 32,
      constraints: const BoxConstraints(
        minWidth: minTouchTarget,
        minHeight: minTouchTarget,
      ),
      icon: Icon(Icons.volume_up, color: color ?? colors.blue),
    );
  }
}

/// Fala um texto no idioma ativo. Nunca lança, nunca faz esperar.
Future<void> speakContent(WidgetRef ref, String text) async {
  await ref.read(speakerProvider).speak(text, ref.read(speechLocaleProvider));
}
