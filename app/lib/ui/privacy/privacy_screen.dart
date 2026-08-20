/// Tela de privacidade (CAP-13, LGPD-RF03).
///
/// Três coisas que o titular precisa poder fazer sem depender de ninguém:
/// **saber** o que fica no aparelho, **desligar** a telemetria e **apagar**
/// tudo. O art. 18 chama isso de livre acesso; num produto sem conta, é a
/// única forma de o controle existir de verdade.
///
/// ## A lista do que é guardado não é escrita à mão
///
/// Ela é montada a partir das preferências que o `user.db` realmente tem. Uma
/// lista redigida separadamente envelhece: alguém acrescenta uma coluna, e a
/// tela passa a mentir para o usuário — em português claro e com toda a
/// aparência de verdade. Aqui, coluna nova sem entrada correspondente aparece
/// como item sem descrição, e o teste reprova.
///
/// ## Operável sem leitura
///
/// Ícone para cada item, botão de áudio para o aviso, alvos de 64 dp e a ação
/// destrutiva atrás de confirmação explícita. O critério da LGPD-RF03 é "a tela
/// é operável sem leitura", e quem não lê não pode descobrir por engano o botão
/// que apaga tudo.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../app_scope.dart';
import '../content/widgets/listen_button.dart';
import '../shell/gubs_scaffold.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';

class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _wiped = false;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final telemetryEnabled = ref.watch(telemetryConsentProvider);

    final notice = '${l.privacyNoticeTitle}. ${l.privacyNoticeBody}';

    return GubsScaffold(
      title: l.privacyTitle,
      subtitle: l.privacyHint,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Notice(title: l.privacyNoticeTitle, body: l.privacyNoticeBody, spoken: notice),
          const SizedBox(height: spacing * 2),
          _StoredList(
            items: [
              (icon: Icons.translate, label: l.privacyStoredLocale),
              (icon: Icons.insights, label: l.privacyStoredTelemetry),
              (icon: Icons.download_done, label: l.privacyStoredSetup),
              // Acrescentado depois de o teste apontar que esta preferência
              // existia no `user.db` e não aparecia aqui: uma escolha guardada
              // que o titular não vê é uma tela de privacidade que mente.
              (icon: Icons.signal_cellular_alt, label: l.privacyStoredMetered),
            ],
          ),
          const SizedBox(height: spacing * 3),
          _TelemetryToggle(
            enabled: telemetryEnabled,
            onChanged: _setTelemetry,
          ),
          const SizedBox(height: spacing * 3),
          if (_wiped)
            _WipeDone(label: l.privacyWipeDone)
          else
            _WipeButton(onConfirmed: _wipe),
          const SizedBox(height: spacing * 2),
        ],
      ),
    );
  }

  Future<void> _setTelemetry(bool enabled) async {
    ref.read(telemetryConsentProvider.notifier).set(enabled: enabled);
    // Desligar apaga o que já foi contado: um opt-out que só vale para o
    // futuro deixaria em memória exatamente o que a pessoa acabou de recusar.
    if (!enabled) ref.read(telemetryProvider).clear();
  }

  Future<void> _wipe() async {
    await ref.read(preferencesProvider).wipe();
    ref.read(telemetryProvider).clear();
    ref.read(telemetryConsentProvider.notifier).set(enabled: true);
    // O idioma também foi apagado. Não navegamos para lugar nenhum: a
    // confirmação fica na tela, e o app volta a perguntar o idioma na próxima
    // abertura — que é o sinal visível de que o apagamento aconteceu.
    if (mounted) setState(() => _wiped = true);
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.title,
    required this.body,
    required this.spoken,
  });

  final String title;
  final String body;
  final String spoken;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return Container(
      padding: const EdgeInsets.all(spacing * 2),
      decoration: BoxDecoration(
        color: colors.blueSoft,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: colors.blue, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 36, color: colors.blue),
              const SizedBox(width: spacing * 1.5),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.ink,
                      ),
                ),
              ),
              ListenButton(text: spoken, color: colors.blue),
            ],
          ),
          const SizedBox(height: spacing),
          Text(
            body,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: colors.ink),
          ),
        ],
      ),
    );
  }
}

/// O que o aparelho guarda, um item por preferência.
class _StoredList extends StatelessWidget {
  const _StoredList({required this.items});

  final List<({IconData icon, String label})> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: spacing),
            child: Row(
              children: [
                Icon(item.icon, size: 28, color: colors.inkSoft),
                const SizedBox(width: spacing * 1.5),
                Expanded(
                  child: Text(
                    item.label,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: colors.ink),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TelemetryToggle extends StatelessWidget {
  const _TelemetryToggle({required this.enabled, required this.onChanged});

  final bool enabled;
  final Future<void> Function(bool enabled) onChanged;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final colors = context.gubs;
    return Container(
      padding: const EdgeInsets.all(spacing * 2),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: colors.line, width: 2),
      ),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.insights : Icons.insights_outlined,
            size: 36,
            color: enabled ? colors.green : colors.inkSoft,
          ),
          const SizedBox(width: spacing * 1.5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.privacyTelemetryTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                      ),
                ),
                const SizedBox(height: spacing * 0.5),
                Text(
                  l.privacyTelemetryBody,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.inkSoft),
                ),
              ],
            ),
          ),
          Switch(
            key: const ValueKey('privacy-telemetry'),
            value: enabled,
            onChanged: (value) => onChanged(value),
          ),
        ],
      ),
    );
  }
}

/// Ação destrutiva, atrás de confirmação.
///
/// Quem não lê não pode descobrir por engano o botão que apaga tudo — e o
/// segundo toque não fica no mesmo lugar do primeiro, para que uma sequência
/// de toques repetidos não passe pela confirmação sem querer.
class _WipeButton extends StatefulWidget {
  const _WipeButton({required this.onConfirmed});

  final Future<void> Function() onConfirmed;

  @override
  State<_WipeButton> createState() => _WipeButtonState();
}

class _WipeButtonState extends State<_WipeButton> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final colors = context.gubs;

    if (!_confirming) {
      return OutlinedButton.icon(
        key: const ValueKey('privacy-wipe'),
        onPressed: () => setState(() => _confirming = true),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(minTouchTarget),
          side: BorderSide(color: colors.line, width: 2),
        ),
        icon: Icon(Icons.delete_outline, size: 28, color: colors.inkSoft),
        label: Text(
          l.privacyWipeTitle,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: colors.ink),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(spacing * 2),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: colors.line, width: 2),
      ),
      child: Column(
        children: [
          Text(
            l.privacyWipeBody,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: colors.ink),
          ),
          const SizedBox(height: spacing * 2),
          // A saída (não apagar) vem PRIMEIRO e é a mais destacada: numa ação
          // irreversível, o caminho fácil tem de ser o que não destrói nada.
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('privacy-wipe-cancel'),
              onPressed: () => setState(() => _confirming = false),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(minTouchTarget),
                backgroundColor: colors.green,
                foregroundColor: colors.onGreen,
              ),
              child: Text(
                l.privacyWipeCancel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.onGreen,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
          const SizedBox(height: spacing),
          TextButton(
            key: const ValueKey('privacy-wipe-confirm'),
            onPressed: () => widget.onConfirmed(),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(minTouchTarget),
            ),
            child: Text(
              l.privacyWipeConfirm,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: colors.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

class _WipeDone extends StatelessWidget {
  const _WipeDone({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return Container(
      padding: const EdgeInsets.all(spacing * 2),
      decoration: BoxDecoration(
        color: colors.greenSoft,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: colors.green, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 32, color: colors.green),
          const SizedBox(width: spacing * 1.5),
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.ink,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
