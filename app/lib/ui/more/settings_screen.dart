/// Ajustes: idioma, cores, tamanho da letra e dados móveis.
///
/// ## Onde cada escolha é persistida
///
/// Todas no `user.db` (`lib/prefs/user_database.dart`), tabela `preferences`,
/// linha única — que é a superfície auditável da LGPD deste app:
///
/// | Controle          | Coluna                   |
/// |-------------------|--------------------------|
/// | Idioma            | `locale_code`            |
/// | Cores da tela     | `theme_mode`             |
/// | Tamanho da letra  | `font_scale`             |
/// | Dados móveis      | `allow_metered_download` |
///
/// Nenhuma delas descreve a pessoa: descrevem como o app opera neste aparelho.
/// Nada sai do aparelho, e `test/prefs/lgpd_surface_test.dart` reprova o build
/// se aparecer coluna que ninguém revisou.
///
/// ## Aplicação imediata, sem reinício
///
/// Os quatro controles escrevem em `StateNotifier`s que a casca observa
/// (`themeModeProvider`, `fontScaleProvider`, `localeControllerProvider`), e o
/// `MaterialApp` repinta no mesmo frame. **O estado muda antes do disco**: a
/// RF-01 dá 200 ms para a interface responder, e esperar I/O deixaria o toque
/// parecendo perdido em armazenamento lento.
///
/// ## "Baixar por dados móveis", e não "economia de dados"
///
/// É a mesma preferência, dita ao contrário. Interruptor negado — ligar para
/// que algo NÃO aconteça — é a origem clássica de leitura errada, e o público
/// deste app é definido por não conseguir desfazer a negação lendo. O rótulo
/// afirmativo diz o que o toque provoca.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../prefs/locale_store.dart';
import '../../prefs/preferences_repository.dart';
import '../app_scope.dart';
import '../shell/gubs_scaffold.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';
import '../theme/text_scaling.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final locale = ref.watch(localeControllerProvider) ?? AppLocale.pt;
    final theme = ref.watch(themeModeProvider);
    final scale = ref.watch(fontScaleProvider);
    final metered = ref.watch(meteredDownloadProvider);

    return GubsScaffold(
      title: l.settingsTitle,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Group(
            icon: Icons.translate_outlined,
            label: l.settingsLanguage,
            child: _Choices<AppLocale>(
              prefix: 'settings-language',
              value: locale,
              options: [
                (value: AppLocale.pt, label: l.languagePortuguese),
                (value: AppLocale.es, label: l.languageSpanish),
              ],
              onSelected: (value) =>
                  ref.read(localeControllerProvider.notifier).select(value),
            ),
          ),
          const SizedBox(height: spacing * 3),
          _Group(
            icon: Icons.contrast_outlined,
            label: l.settingsTheme,
            child: _Choices<GubsThemeMode>(
              prefix: 'settings-theme',
              value: theme,
              options: [
                (value: GubsThemeMode.system, label: l.settingsThemeSystem),
                (value: GubsThemeMode.light, label: l.settingsThemeLight),
                (value: GubsThemeMode.dark, label: l.settingsThemeDark),
              ],
              onSelected: (value) =>
                  ref.read(themeModeProvider.notifier).select(value),
            ),
          ),
          const SizedBox(height: spacing * 3),
          _Group(
            icon: Icons.format_size_outlined,
            label: l.settingsFont,
            child: _Choices<double>(
              prefix: 'settings-font',
              value: scale,
              options: [
                (value: fontScaleSteps[0], label: l.settingsFontNormal),
                (value: fontScaleSteps[1], label: l.settingsFontLarge),
                (value: fontScaleSteps[2], label: l.settingsFontLarger),
              ],
              onSelected: (value) =>
                  ref.read(fontScaleProvider.notifier).select(value),
            ),
          ),
          // O teto de 2x é invisível: a pessoa toca "Muito grande" e nada
          // muda, porque o aparelho já estava ampliado. Dizer isso é a
          // diferença entre um limite e um botão quebrado.
          if (textScaleIsCapped(MediaQuery.textScalerOf(context), scale))
            Padding(
              padding: const EdgeInsets.only(top: spacing),
              child: _Note(text: l.settingsFontCapped),
            ),
          const SizedBox(height: spacing * 3),
          _MeteredToggle(
            enabled: metered,
            onChanged: (allowed) => ref
                .read(meteredDownloadProvider.notifier)
                .select(allowed: allowed),
          ),
          const SizedBox(height: spacing * 2),
        ],
      ),
    );
  }
}

/// Rótulo com ícone acima de um grupo de opções.
class _Group extends StatelessWidget {
  const _Group({required this.icon, required this.label, required this.child});

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 28, color: colors.inkSoft),
            const SizedBox(width: spacing * 1.5),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: spacing * 1.5),
        child,
      ],
    );
  }
}

/// Opções empilhadas, uma por linha, com a escolhida marcada.
///
/// Empilhadas e não lado a lado: três botões numa linha só ficam estreitos
/// demais para os 64 dp quando a fonte cresce, e "Muito grande" quebraria em
/// três linhas dentro de um botão de um terço da tela.
///
/// A marca da escolha é **redundante** — cor de fundo, borda mais grossa E um
/// ícone de visto. Só a cor não serve: parte do público tem alguma deficiência
/// de visão de cores, e este é o app dessas pessoas também.
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.prefix,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final String prefix;
  final T value;
  final List<({T value, String label})> options;
  final void Function(T value) onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;

    return Column(
      children: [
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: spacing),
            child: _ChoiceButton(
              id: '$prefix-${_slug(option.value)}',
              label: option.label,
              selected: option.value == value,
              onTap: () => onSelected(option.value),
              colors: colors,
            ),
          ),
      ],
    );
  }
}

/// Sufixo estável para a chave de teste de cada opção.
String _slug(Object? value) => switch (value) {
      AppLocale(:final code) => code,
      GubsThemeMode(:final storageKey) => storageKey,
      // As escalas viram `10`, `13`, `16` — sem ponto, que atrapalharia a
      // leitura da chave no relatório de teste.
      final double d => (d * 10).round().toString(),
      _ => value.toString(),
    };

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  final String id;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final GubsColors colors;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: ValueKey(id),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? colors.greenSoft : colors.surface,
        side: BorderSide(
          color: selected ? colors.green : colors.line,
          width: selected ? 3 : 2,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: spacing * 2,
          vertical: spacing * 1.5,
        ),
        minimumSize: const Size.fromHeight(minTouchTarget),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.ink,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ),
          if (selected)
            Icon(Icons.check_circle_outline, size: 28, color: colors.green),
        ],
      ),
    );
  }
}

class _MeteredToggle extends StatelessWidget {
  const _MeteredToggle({required this.enabled, required this.onChanged});

  final bool enabled;
  final void Function(bool allowed) onChanged;

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
            enabled
                ? Icons.signal_cellular_alt
                : Icons.signal_cellular_alt_outlined,
            size: 36,
            color: enabled ? colors.green : colors.inkSoft,
          ),
          const SizedBox(width: spacing * 1.5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.settingsMetered,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: spacing * 0.5),
                Text(
                  l.settingsMeteredBody,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.inkSoft),
                ),
              ],
            ),
          ),
          Switch(
            key: const ValueKey('settings-metered'),
            value: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return Container(
      padding: const EdgeInsets.all(spacing * 1.5),
      decoration: BoxDecoration(
        color: colors.blueSoft,
        borderRadius: BorderRadius.circular(radiusButton),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 24, color: colors.blue),
          const SizedBox(width: spacing * 1.5),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
