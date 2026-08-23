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
import '../../triage/domain/guidance_provenance.dart';
import '../../triage/domain/severity.dart';
import '../app_scope.dart';
import '../shell/gubs_scaffold.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';
import 'triage_controller.dart';
import 'widgets/provenance_badge.dart';
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

    // Derivada, nunca guardada: ver `triage/domain/guidance_provenance.dart`.
    final provenance = provenanceFor(result);

    // O aviso de falibilidade some na EMERGÊNCIA, e só nela. Ali a única
    // mensagem é procurar atendimento agora; uma ressalva ao lado de "Ligue
    // 192" enfraquece a instrução que menos admite hesitação. É exceção
    // declarada — há teste que a fixa nos dois sentidos.
    final showNote = severity != GubsSeverity.emergency;

    // A MESMA frase para os três canais: tela, leitor de tela e voz. Montada
    // uma vez, aqui, para que não exista versão que diga procedência diferente.
    final announcement = resultAnnouncement(
      l,
      provenance: provenance,
      severity: severity,
      title: card?.title.value ?? '',
      body: card?.body?.value,
      withNote: showNote,
    );

    // Fire-and-forget, uma vez por resultado. A tela já está montada quando
    // isto roda: o áudio acompanha o cartão, não o precede.
    if (!_spoken && card != null) {
      _spoken = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        speakAnnouncement(ref, announcement).ignore();
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
          ? () => speakAnnouncement(ref, announcement).ignore()
          : null,
      onBack: () => _leave(context),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _ResultCard(
                    provenance: provenance,
                    role: role,
                    iconRef: card?.iconRef ?? '',
                    title: card?.title.value ?? '',
                    body: card?.body?.value,
                    announcement: announcement,
                  ),
                  if (severity == GubsSeverity.emergency) ...[
                    const SizedBox(height: spacing * 2),
                    _EmergencyCall(label: l.resultEmergencyCall),
                  ],
                  if (showNote) ...[
                    const SizedBox(height: spacing),
                    _FallibilityNote(label: l.resultFallibilityNote),
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

/// Nome falado da severidade.
///
/// A gravidade existia só como COR e ÍCONE — dois canais que o leitor de tela
/// não enxerga. Sem estas três palavras, quem usa TalkBack recebia o título e a
/// orientação sem nunca ouvir o quão grave o app considerou o caso.
String severityLabel(L l, GubsSeverity severity) => switch (severity) {
      GubsSeverity.routine => l.severityRoutine,
      GubsSeverity.attention => l.severityAttention,
      GubsSeverity.emergency => l.severityEmergency,
    };

/// A frase única que o leitor de tela anuncia pelo cartão inteiro.
///
/// Ordem fixa: **procedência → status → título → orientação → aviso**.
///
/// É função pura para que a ORDEM seja testável por índice de substring, sem
/// depender da árvore de widgets. E o cartão é um nó semântico único: com nós
/// irmãos, o TalkBack anunciaria "selo" e "cartão" separados e a pessoa poderia
/// parar no cartão sem passar pelo selo. Fundido, é impossível ouvir a
/// orientação sem ouvir de onde ela veio.
String resultAnnouncement(
  L l, {
  required GuidanceProvenance provenance,
  required GubsSeverity severity,
  required String title,
  required String? body,
  required bool withNote,
}) =>
    [
      provenanceLabel(l, provenance),
      severityLabel(l, severity),
      title,
      body,
      if (withNote) l.resultFallibilityNote,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join('. ');

/// O cartão de resultado, com o selo no topo.
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.provenance,
    required this.role,
    required this.iconRef,
    required this.title,
    required this.body,
    required this.announcement,
  });

  final GuidanceProvenance provenance;
  final ({Color accent, Color background, Color onAccent}) role;
  final String iconRef;
  final String title;
  final String? body;
  final String announcement;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;

    return MergeSemantics(
      child: Semantics(
        label: announcement,
        // O conteúdo interno é excluído para não ser anunciado duas vezes: uma
        // pela frase ordenada acima, outra widget a widget na ordem do layout —
        // que colocaria o ícone de gravidade antes da procedência.
        child: ExcludeSemantics(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(spacing * 3),
            // A cor vem de `forSeverity` e NADA aqui a altera. O selo tinge
            // apenas a própria área — ver `widgets/provenance_badge.dart`.
            decoration: BoxDecoration(
              color: role.background,
              borderRadius: BorderRadius.circular(radiusCard),
              border: Border.all(color: role.accent, width: 3),
            ),
            child: Column(
              children: [
                // PRIMEIRO filho: quem olha a tela encontra a procedência antes
                // do ícone de gravidade e do título.
                ProvenanceBadge(provenance: provenance),
                const SizedBox(height: spacing * 2),
                Icon(iconForRef(iconRef), size: 96, color: role.accent),
                const SizedBox(height: spacing * 2),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.ink,
                      ),
                ),
                if (body != null) ...[
                  const SizedBox(height: spacing * 1.5),
                  Text(
                    body!,
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
        ),
      ),
    );
  }
}

/// Aviso de falibilidade, ancorado ao cartão.
///
/// **Sóbrio, não discreto.** Fica FORA do cartão de propósito: dentro,
/// herdaria o fundo de severidade e passaria a parecer parte da orientação
/// clínica. A proximidade de 8 dp é o que o ancora.
///
/// Estático e sempre visível — nunca atrás de toque, tooltip ou expansão. Não
/// diz "procure um médico", que descreve consulta eletiva e não urgência.
class _FallibilityNote extends StatelessWidget {
  const _FallibilityNote({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return Row(
      key: const ValueKey('result-fallibility'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Redundante ao texto: o aviso inteiro está escrito ao lado.
        ExcludeSemantics(
          child: Icon(
            Icons.warning_amber_outlined,
            size: 20,
            color: colors.amber,
          ),
        ),
        const SizedBox(width: spacing),
        Expanded(
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
