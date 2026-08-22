/// Tutorial de uso: cinco passos, offline, sem vídeo.
///
/// ## Não há áudio embarcado, e isso é deliberado
///
/// A narração sai do TTS do sistema (`speech/speaker.dart`), como em todo o
/// resto do app, e não de arquivos de som no APK. Três consequências, todas
/// desejadas:
///
/// * **Peso zero.** Narrar cinco passos em pt e es custaria alguns MB num APK
///   de 24,9 MB, para dizer o que o TTS já diz nos dois idiomas.
/// * **Transcrição por construção.** O texto na tela *é* a fonte da fala —
///   não existe cópia separada para envelhecer em silêncio. Legenda à parte
///   seria uma segunda versão do mesmo texto, com o defeito clássico de
///   divergir na primeira edição.
/// * **Degradação limpa.** ROM sem engine de TTS é risco previsto (A3): o
///   [ListenButton] se esconde sozinho e o tutorial fica **apenas visual**.
///   Botão que não fala é pior que botão nenhum — quem depende do áudio tocaria
///   nele e concluiria que o app está quebrado.
///
/// ## Um passo por tela
///
/// `PageView` horizontal em vez de uma lista rolável: cada passo ocupa a tela
/// inteira, com um desenho grande. Rolagem exige entender que há mais conteúdo
/// abaixo da borda — leitura que o público-alvo pode não fazer. Os pontos de
/// posição e as setas dizem, visualmente, quantos passos faltam.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../content/widgets/listen_button.dart';
import '../shell/gubs_scaffold.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';

/// Um passo do tutorial. Ícone + título + uma frase, nada mais.
@immutable
class HowToStep {
  const HowToStep({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String Function(L l) title;
  final String Function(L l) body;
}

/// Os passos, na ordem da jornada real: compor sintomas, ler o resultado,
/// ouvir, e a garantia de que tudo funciona sem rede.
const List<HowToStep> howToSteps = [
  HowToStep(icon: Icons.accessibility_new, title: _t1, body: _b1),
  HowToStep(icon: Icons.touch_app_outlined, title: _t2, body: _b2),
  HowToStep(icon: Icons.assignment_outlined, title: _t3, body: _b3),
  HowToStep(icon: Icons.volume_up_outlined, title: _t4, body: _b4),
  HowToStep(icon: Icons.cloud_off_outlined, title: _t5, body: _b5),
];

String _t1(L l) => l.howToStep1Title;
String _b1(L l) => l.howToStep1Body;
String _t2(L l) => l.howToStep2Title;
String _b2(L l) => l.howToStep2Body;
String _t3(L l) => l.howToStep3Title;
String _b3(L l) => l.howToStep3Body;
String _t4(L l) => l.howToStep4Title;
String _b4(L l) => l.howToStep4Body;
String _t5(L l) => l.howToStep5Title;
String _b5(L l) => l.howToStep5Body;

class HowToScreen extends StatefulWidget {
  const HowToScreen({super.key});

  @override
  State<HowToScreen> createState() => _HowToScreenState();
}

class _HowToScreenState extends State<HowToScreen> {
  final PageController _pages = PageController();
  int _current = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= howToSteps.length) return;
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return GubsScaffold(
      title: l.howToTitle,
      subtitle: l.howToStepOf(_current + 1, howToSteps.length),
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: howToSteps.length,
              onPageChanged: (index) => setState(() => _current = index),
              itemBuilder: (context, index) =>
                  _StepCard(step: howToSteps[index]),
            ),
          ),
          const SizedBox(height: spacing * 2),
          _Pager(
            current: _current,
            total: howToSteps.length,
            onPrevious: () => _goTo(_current - 1),
            onNext: () => _goTo(_current + 1),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step});

  final HowToStep step;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final colors = context.gubs;
    final title = step.title(l);
    final body = step.body(l);

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: spacing * 2),
          Container(
            padding: const EdgeInsets.all(spacing * 3),
            decoration: BoxDecoration(
              color: colors.blueSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(step.icon, size: 72, color: colors.blue),
          ),
          const SizedBox(height: spacing * 3),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.ink,
                ),
          ),
          const SizedBox(height: spacing * 1.5),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: colors.inkSoft),
          ),
          const SizedBox(height: spacing * 2),
          // Fala exatamente o que está escrito acima: a transcrição não é um
          // arquivo à parte, é o mesmo texto.
          ListenButton(text: '$title. $body', color: colors.blue),
          const SizedBox(height: spacing * 2),
        ],
      ),
    );
  }
}

/// Voltar, pontos de posição e avançar.
///
/// As setas existem além do arrastar: arrastar para o lado é gesto aprendido,
/// e parte do público nunca usou um app com carrossel.
class _Pager extends StatelessWidget {
  const _Pager({
    required this.current,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final int current;
  final int total;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final colors = context.gubs;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SizedBox(
          width: minTouchTarget,
          height: minTouchTarget,
          child: current == 0
              ? null
              : IconButton(
                  key: const ValueKey('howto-previous'),
                  onPressed: onPrevious,
                  tooltip: l.actionBack,
                  icon: Icon(Icons.chevron_left, size: 36, color: colors.blue),
                ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < total; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: spacing * 0.5),
                child: Container(
                  width: i == current ? 14 : 10,
                  height: i == current ? 14 : 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == current ? colors.blue : colors.line,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(
          width: minTouchTarget,
          height: minTouchTarget,
          child: current == total - 1
              ? null
              : IconButton(
                  key: const ValueKey('howto-next'),
                  onPressed: onNext,
                  tooltip: l.actionContinue,
                  icon: Icon(Icons.chevron_right, size: 36, color: colors.blue),
                ),
        ),
      ],
    );
  }
}
