/// Selo de procedência: de onde veio a orientação exibida.
///
/// ===========================================================================
/// O SELO NÃO PODE TOCAR A COR DO CARTÃO
/// ===========================================================================
///
/// O fundo do cartão de resultado codifica a GRAVIDADE, e para quem não lê o
/// texto essa cor é o canal primário da mensagem. O tingimento lilás deste
/// componente vive inteiramente dentro dos limites do badge: ele não envolve,
/// não sobrepõe e não altera `role.background` nem `role.accent`.
///
/// Há teste que fixa isso (`result_screen` — "o selo não invade a cor do
/// cartão"), porque o modo de falha é silencioso: um `Container` a mais em
/// volta e a codificação de gravidade some sem ninguém notar em revisão.
///
/// ## Por que os papéis do MD3 e não `GubsColors` direto
///
/// A cor vem de `Theme.of(context).colorScheme.tertiaryContainer`, não de
/// `context.gubs.lilacSoft`. O papel acompanha o contraste alto do sistema e
/// qualquer reescala futura do esquema; o campo direto ficaria congelado.
///
/// ## Por que não é um `Chip`
///
/// `Chip` traz semântica de acionável — ripple, foco, alvo de toque — para
/// algo que não se toca. O selo é rótulo: informação que precisa estar visível
/// sem nenhuma interação, porque quem depende dela é justamente quem não
/// descobre affordances escondidas.
library;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../triage/domain/guidance_provenance.dart';
import '../../theme/gubs_metrics.dart';

/// Ícone de cada estado.
///
/// **Todos vazados, todos redundantes ao texto** (WCAG 1.4.1): nenhum carrega
/// significado que o rótulo ao lado não diga. Emoji está fora de propósito —
/// renderiza diferente por fabricante, falha em Android antigo e o leitor de
/// tela o anuncia de forma imprevisível.
IconData provenanceIcon(GuidanceProvenance provenance) => switch (provenance) {
      // Lista com marcas de conferência: é literalmente o que a tabela faz.
      GuidanceProvenance.rules => Icons.rule,
      // Cabeça de robô geométrica. Sem olhos expressivos e sem sorriso: o selo
      // não pode sugerir agência nem empatia. `auto_awesome` (as estrelinhas)
      // foi descartado por ser convenção de MARKETING de IA — promete mágica.
      GuidanceProvenance.assistant => Icons.smart_toy_outlined,
      // Mesmo glifo que a inicial usa para "100% offline", com o mesmo
      // significado de recurso ausente.
      GuidanceProvenance.rulesOnly => Icons.cloud_off,
    };

/// Rótulo de cada estado, no idioma ativo.
///
/// Termos literais e factualmente corretos: saída determinística não é
/// rotulada como assistente, nem o contrário.
String provenanceLabel(L l, GuidanceProvenance provenance) =>
    switch (provenance) {
      GuidanceProvenance.rules => l.provenanceRules,
      GuidanceProvenance.assistant => l.provenanceAssistant,
      GuidanceProvenance.rulesOnly => l.provenanceRulesOnly,
    };

class ProvenanceBadge extends StatelessWidget {
  const ProvenanceBadge({required this.provenance, super.key});

  final GuidanceProvenance provenance;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Align(
      // À esquerda enquanto o resto do cartão é centralizado. O desalinhamento
      // é deliberado: é ele que faz o selo ler como ETIQUETA sobre o conteúdo,
      // e não como mais uma linha do conteúdo.
      alignment: Alignment.centerLeft,
      child: Container(
        key: ValueKey('provenance-${provenance.name}'),
        // Sem `width: double.infinity`: largura pelo conteúdo. Um badge de
        // largura total vira faixa e passa a competir com o cartão.
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(
          horizontal: spacing * 1.5,
          vertical: spacing * 0.75,
        ),
        // Elevação zero, sem sombra: sombra sugeriria que o selo é acionável.
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(radiusButton),
          // Contorno ≥ 3:1 contra todo fundo de cartão possível (WCAG 1.4.11),
          // verificado em `contrast_test`.
          border: Border.all(color: scheme.tertiary, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Decorativo EM RELAÇÃO AO RÓTULO: sem isto o leitor de tela
            // anunciaria o ícone e o texto, dizendo a mesma coisa duas vezes.
            ExcludeSemantics(
              child: Icon(
                provenanceIcon(provenance),
                size: 20,
                color: scheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(width: spacing),
            Flexible(
              child: Text(
                provenanceLabel(l, provenance),
                // Sem `maxLines` e sem `ellipsis`: o rótulo mais longo é o de
                // "sem o assistente", e com fonte ampliada ele quebra linha.
                // Truncar cortaria justamente a palavra que dá sentido ao ícone.
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
