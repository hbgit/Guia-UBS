/// Tela "Sobre": versão instalada, créditos e licenças.
///
/// ## A versão vem do APK, não de uma constante
///
/// `package_info_plus` lê o `versionName` e o `versionCode` que o Android tem
/// de fato. Uma constante gerada do `pubspec` seria mais simples e mentiria no
/// primeiro dia em que alguém publicasse sem rodar o gerador — e uma tela
/// "Sobre" que informa a versão errada é pior que uma que não informa nada:
/// quem pede suporte passa a descrever um build que não é o dele.
///
/// O plugin fica na BORDA, atrás de [appReleaseProvider]. Os testes sobrepõem
/// o provider e nunca tocam no canal de plataforma.
///
/// ## Por que o aviso clínico está aqui
///
/// Esta é a única tela do app que mostra logotipo de instituição. Logotipo ao
/// lado de orientação de saúde é lido como endosso — e o conteúdo deste app
/// ainda é marcado `clinical_source: "revisão clínica pendente"`, com o packer
/// avisando a cada build. O aviso na mesma tela impede a leitura errada, e sai
/// no mesmo commit em que a dupla aprovação clínica entrar.
///
/// ## Licenças
///
/// `showLicensePage` do próprio Flutter, alimentada pelo `LicenseRegistry`.
/// É offline, é exata e cobre as dependências transitivas que uma lista escrita
/// à mão esqueceria no primeiro `pub upgrade`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/app_localizations.dart';
import '../shell/gubs_scaffold.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';

/// Versão e build do pacote instalado.
typedef AppRelease = ({String version, String build});

/// Sobreposto nos testes. **Nunca lança:** um plugin que falha não pode
/// derrubar uma tela informativa (INV-8) — a tela apenas omite os números.
final appReleaseProvider = FutureProvider<AppRelease?>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return (version: info.version, build: info.buildNumber);
  } on Object {
    return null;
  }
});

/// Os logotipos, na ordem em que aparecem.
///
/// Empilhados e não lado a lado: as proporções são muito diferentes (um é uma
/// faixa de 3,8:1, o outro é quase quadrado) e alinhá-los numa fila deixaria
/// um deles ilegível em tela estreita.
const List<String> aboutLogos = [
  'assets/branding/about_logo_prism.png',
  'assets/branding/about_telessaude_ufrr.png',
];

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final colors = context.gubs;
    final release = ref.watch(appReleaseProvider);

    return GubsScaffold(
      title: l.aboutTitle,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Text(
            l.appTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.ink,
                ),
          ),
          const SizedBox(height: spacing),
          _Release(release: release.valueOrNull),
          const SizedBox(height: spacing * 3),
          _ClinicalNotice(text: l.aboutClinicalNotice),
          const SizedBox(height: spacing * 3),
          Text(
            l.aboutCredits,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.ink,
                ),
          ),
          const SizedBox(height: spacing * 2),
          for (final logo in aboutLogos)
            Padding(
              padding: const EdgeInsets.only(bottom: spacing * 2),
              child: Center(
                child: Container(
                  // Placa de tamanho ÚNICO, com a imagem contida dentro.
                  //
                  // Limitar a ALTURA de cada logo parecia natural e desequilibra
                  // a fila: as proporções são muito diferentes (3,8:1 contra
                  // 1,1:1), então o logo largo ocupava a tela inteira e o quase
                  // quadrado virava um selo perdido. Com placa igual, cada marca
                  // se ajusta pelo lado que a limita — e as duas ficam com o
                  // mesmo peso visual, que é o que "créditos" quer dizer.
                  height: 96,
                  width: double.infinity,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: spacing * 3,
                    vertical: spacing * 1.5,
                  ),
                  decoration: BoxDecoration(
                    // Placa CLARA FIXA, que NÃO segue o tema. Marca de
                    // instituição não é cromo de interface: tem dono e regra
                    // de uso, e reinterpretá-la vai além do que este app pode
                    // decidir sozinho.
                    //
                    // Não é preciosismo: no tema escuro os vazados brancos do
                    // logo do Telessaúde invertem e "U F R R" praticamente
                    // some. A placa garante que a marca apareça como foi
                    // desenhada nos dois temas.
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(radiusCard),
                    border: Border.all(color: colors.line),
                  ),
                  child: Image.asset(
                    logo,
                    fit: BoxFit.contain,
                    // Decorativo para leitor de tela: o nome da instituição
                    // já está no desenho, e um texto alternativo inventado
                    // aqui seria uma segunda fonte para o mesmo dado.
                    excludeFromSemantics: true,
                    // Asset ausente não pode derrubar a tela: quem não rodou
                    // `tool/gen_about_logos.sh` ainda vê o resto.
                    errorBuilder: (context, error, stack) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          const SizedBox(height: spacing * 2),
          _LicensesButton(label: l.aboutLicenses),
          const SizedBox(height: spacing * 2),
        ],
      ),
    );
  }
}

class _Release extends StatelessWidget {
  const _Release({required this.release});

  final AppRelease? release;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final colors = context.gubs;
    final info = release;
    if (info == null) return const SizedBox.shrink();

    return Column(
      children: [
        Text(
          l.aboutVersion(info.version),
          key: const ValueKey('about-version'),
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: colors.inkSoft),
        ),
        Text(
          l.aboutBuild(info.build),
          key: const ValueKey('about-build'),
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: colors.inkSoft),
        ),
      ],
    );
  }
}

class _ClinicalNotice extends StatelessWidget {
  const _ClinicalNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return Container(
      key: const ValueKey('about-clinical-notice'),
      padding: const EdgeInsets.all(spacing * 2),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: colors.amber, width: 2),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, size: 28, color: colors.amber),
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

class _LicensesButton extends StatelessWidget {
  const _LicensesButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final colors = context.gubs;

    return OutlinedButton.icon(
      key: const ValueKey('about-licenses'),
      onPressed: () => showLicensePage(
        context: context,
        applicationName: l.appTitle,
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(minTouchTarget),
        side: BorderSide(color: colors.line, width: 2),
      ),
      icon: Icon(Icons.article_outlined, size: 28, color: colors.inkSoft),
      label: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(color: colors.ink),
      ),
    );
  }
}
