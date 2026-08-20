/// Moldura comum de toda tela de conteúdo.
///
/// Existe para que "voltar e casa sempre visíveis" (CAP-02) seja uma
/// propriedade da moldura e não uma lembrança de quem escreve a tela. Uma tela
/// nova que use este widget nasce sem dead-end; uma que monte o próprio
/// `Scaffold` pode nascer com um, e ninguém percebe até o teste de usabilidade.
///
/// O botão de áudio só aparece quando há voz disponível ([Speaker.isAvailable]).
/// Mostrar um botão que não fala seria pior que não mostrá-lo: quem depende do
/// áudio tocaria nele e concluiria que o app está quebrado.
///
/// ## O voltar não depende de haver pilha
///
/// `context.canPop()` responde "existe algo empilhado", que **não** é a mesma
/// pergunta que "existe para onde voltar". As abas navegam com `go`, que
/// substitui a rota em vez de empilhar — então uma tela alcançada por um
/// ladrilho da inicial tem `canPop() == false` e ficaria sem seta.
///
/// Foi assim no aparelho: a tela de triagem apareceu sem nenhum voltar. Não
/// era dead-end absoluto (a barra de abas continuava ali), mas obrigava a
/// pessoa a entender que "Início" é a saída — leitura que o público-alvo pode
/// não fazer.
///
/// Por isso o destino do voltar vem do MANIFESTO (`parentPath`), não do
/// histórico: `pop` quando há pilha, `go(parentPath)` quando não há. Assim
/// toda tela não-raiz tem seta, inclusive as alcançadas por deep link.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../app_router.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';

class GubsScaffold extends StatelessWidget {
  const GubsScaffold({
    required this.title,
    required this.child,
    this.subtitle,
    this.onListen,
    this.accent,
    this.onBack,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// Ação de áudio. `null` esconde o botão — ver o comentário da biblioteca.
  final VoidCallback? onListen;

  /// Cor semântica desta tela. `null` usa a de informação (azul).
  final Color? accent;

  /// Ação do botão voltar. `null` usa o destino do manifesto de rotas.
  ///
  /// A composição precisa disto: o voltar dela recua um PASSO, e só sai da
  /// triagem no primeiro. Sem o gancho, sair no meio exigiria "casa" e a
  /// composição inteira se perderia sem aviso.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    final l = L.of(context);
    final back = onBack ?? _backTarget(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(spacing, spacing, spacing, 0),
              child: Row(
                children: [
                  // Ocupa o espaço mesmo sem poder voltar, para que o título
                  // não dance de posição entre telas.
                  SizedBox(
                    width: minTouchTarget,
                    height: minTouchTarget,
                    child: back == null
                        ? null
                        : IconButton(
                            onPressed: back,
                            tooltip: l.actionBack,
                            icon: const Icon(Icons.arrow_back, size: 32),
                          ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: colors.inkSoft),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: minTouchTarget,
                    height: minTouchTarget,
                    child: onListen == null
                        ? null
                        : IconButton(
                            onPressed: onListen,
                            tooltip: l.actionListen,
                            icon: Icon(
                              Icons.volume_up,
                              size: 32,
                              color: accent ?? colors.blue,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(spacing * 2),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Para onde o voltar leva, ou `null` se esta tela é raiz de aba.
VoidCallback? _backTarget(BuildContext context) {
  if (context.canPop()) return context.pop;

  final location = GoRouterState.of(context).matchedLocation;
  final parent = gubsRoutes
      .where((r) => r.path == location)
      .map((r) => r.parentPath)
      .firstOrNull;
  if (parent == null) return null;

  return () => context.go(parent);
}
