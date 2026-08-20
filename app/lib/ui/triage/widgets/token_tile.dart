/// Um ícone de sintoma, tocável.
///
/// A seleção é comunicada por **quatro canais simultâneos**: cor de fundo,
/// espessura da borda, marca de conferido e rótulo em negrito. Redundância
/// deliberada — cor sozinha exclui quem tem deficiência de visão de cores, e
/// texto sozinho exclui quem não lê. Este app não pode escolher um dos dois.
library;

import 'package:flutter/material.dart';

import '../../../content/domain/content_models.dart';
import '../../theme/gubs_colors.dart';
import '../../theme/gubs_metrics.dart';
import 'token_icons.dart';

class TokenTile extends StatelessWidget {
  const TokenTile({
    required this.token,
    required this.selected,
    required this.onTap,
    this.disabled = false,
    this.justRejected = false,
    super.key,
  });

  final SymptomToken token;
  final bool selected;

  /// Teto de 5 atingido e este não está entre os escolhidos.
  final bool disabled;

  /// Recusado no último toque — pisca em vermelho (linha A3 da FSM-A).
  final bool justRejected;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;

    final border = justRejected
        ? colors.red
        : selected
            ? colors.green
            : colors.line;

    return Semantics(
      button: true,
      selected: selected,
      enabled: !disabled,
      label: token.label.value,
      child: Opacity(
        // Indisponível PARECE indisponível: um toque que não faz nada e não
        // explica por quê é indistinguível de app quebrado.
        opacity: disabled ? 0.4 : 1,
        child: OutlinedButton(
          key: ValueKey('token-${token.id}'),
          onPressed: disabled ? null : onTap,
          style: OutlinedButton.styleFrom(
            backgroundColor: selected ? colors.greenSoft : colors.surface,
            side: BorderSide(color: border, width: selected ? 3 : 2),
            padding: const EdgeInsets.all(spacing),
            minimumSize: const Size(minTouchTarget, minTouchTarget),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      iconForToken(token),
                      size: 40,
                      color: selected ? colors.greenDeep : colors.ink,
                    ),
                    const SizedBox(height: spacing * 0.75),
                    Text(
                      token.label.value,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.ink,
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(Icons.check_circle, size: 22, color: colors.green),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
