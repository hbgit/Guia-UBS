/// Tela inicial (aba 1).
///
/// Cinco elementos acionáveis mais as três abas = **oito**, que é exatamente o
/// teto da RNF-06. Não sobra espaço: qualquer coisa nova aqui precisa tirar
/// outra. O teto não é estético — acima de oito alvos a tela passa a exigir
/// leitura para ser escaneada, e o público-alvo é definido por não conseguir
/// fazer essa leitura.
///
/// A hierarquia visual carrega a decisão clínica: o botão de sintomas é grande
/// e verde (o caminho esperado), emergência é vermelho (o desvio raro e grave),
/// e o resto é azul (informação). Ver [GubsColors].
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../app_routes.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final colors = context.gubs;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(spacing * 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabeçalho utilitário: selo de offline e acesso à privacidade.
              //
              // O escudo NÃO conta contra o teto de oito elementos, e a
              // distinção importa: o teto existe para limitar as ESCOLHAS que
              // competem pela atenção de quem escaneia a tela, não os controles
              // de moldura. O voltar e a barra de abas nunca foram contados
              // pelo mesmo motivo. E a tela de privacidade precisa existir num
              // caminho alcançável: é exigência da LGPD-RF03, não um extra.
              Row(
                children: [
                  Icon(Icons.cloud_off, size: 20, color: colors.inkSoft),
                  const SizedBox(width: spacing * 0.75),
                  Expanded(
                    child: Text(
                      l.offlineBadge,
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: colors.inkSoft),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('home-privacy'),
                    onPressed: () => context.goNamed(Routes.privacy),
                    tooltip: l.privacyTitle,
                    iconSize: 28,
                    constraints: const BoxConstraints(
                      minWidth: minTouchTarget,
                      minHeight: minTouchTarget,
                    ),
                    icon: Icon(Icons.shield_outlined, color: colors.blue),
                  ),
                ],
              ),
              Text(
                l.homeQuestion,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: spacing),
              Text(
                l.homeHint,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: colors.inkSoft),
              ),
              const SizedBox(height: spacing * 3),
              FilledButton.icon(
                key: const ValueKey('home-triage'),
                onPressed: () => context.goNamed(Routes.triageBody),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(96),
                  backgroundColor: colors.green,
                  foregroundColor: colors.onGreen,
                ),
                icon: const Icon(Icons.accessibility_new, size: 36),
                label: Text(
                  l.homeStartTriage,
                  // `color` explícito: os estilos do `textTheme` já vêm
                  // coloridos com `onSurface`, e essa cor venceria o
                  // `foregroundColor` do botão. Ver a armadilha documentada em
                  // `ui/theme/gubs_theme.dart`.
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.onGreen,
                      ),
                ),
              ),
              const SizedBox(height: spacing * 3),
              // Duas linhas de dois, e NÃO um `GridView` com proporção fixa.
              // Proporção fixa trava a altura do ladrilho enquanto o texto
              // dentro dele cresce com a fonte do sistema — e ampliar a fonte
              // é a primeira coisa que faz quem tem presbiopia sem óculos,
              // parte relevante do público. Com `IntrinsicHeight`, o ladrilho
              // cresce junto: nada some por baixo da borda.
              _TileRow(
                left: _Tile(
                  id: 'home-whereto',
                  icon: Icons.place,
                  label: l.homeWhereTo,
                  color: colors.blue,
                  onTap: () => context.go(GubsTab.whereTo.rootPath),
                ),
                right: _Tile(
                  id: 'home-docs',
                  icon: Icons.badge,
                  label: l.homeDocuments,
                  color: colors.blue,
                  onTap: () => context.go(GubsTab.documents.rootPath),
                ),
              ),
              const SizedBox(height: spacing * 1.5),
              _TileRow(
                left: _Tile(
                  id: 'home-flow',
                  icon: Icons.list_alt,
                  label: l.homeHowItWorks,
                  color: colors.green,
                  onTap: () => context.goNamed(Routes.flow),
                ),
                right: _Tile(
                  id: 'home-emergency',
                  icon: Icons.emergency,
                  label: l.homeEmergency,
                  color: colors.red,
                  onTap: () => context.goNamed(Routes.emergency),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Duas colunas de mesma altura, dimensionadas pelo conteúdo.
class _TileRow extends StatelessWidget {
  const _TileRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            const SizedBox(width: spacing * 1.5),
            Expanded(child: right),
          ],
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.id,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String id;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return OutlinedButton(
      key: ValueKey(id),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: colors.surface,
        side: BorderSide(color: colors.line, width: 2),
        padding: const EdgeInsets.all(spacing * 1.5),
        minimumSize: const Size(minTouchTarget, 112),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: spacing),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colors.ink,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
