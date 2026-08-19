/// FSM-B — ciclo de vida do content pack, como máquina **explícita**.
///
/// A [espec.md §4.2] define esta máquina numa matriz de transições. Este
/// arquivo é essa matriz transcrita em código, e nada mais: sem I/O, sem
/// relógio, sem rede. O [SyncService] é quem faz as chamadas e traduz o que
/// aconteceu em [SyncEvent]s.
///
/// Essa separação é deliberada e está registrada como anti-padrão a evitar em
/// [espec.md §6]: *"FSM-B implementada ad hoc dentro do SyncService"* produz
/// drift entre a especificação e o código. Com a tabela isolada, cada linha da
/// matriz vira um teste que falha se alguém mudar a regra sem mudar a spec.
///
/// ## Uma divergência de ordem em relação à matriz, de propósito
///
/// As linhas 3–5 da matriz (o que fazer com um `200`) têm guardas que se
/// sobrepõem. Avaliamos **assinatura primeiro**, depois versão, depois schema —
/// a ordem de [contract/src/manifest.ts], não a ordem em que as linhas aparecem
/// na tabela. Motivo: num manifest com assinatura inválida, `packVersion` e
/// `schemaVersion` são campos escritos pelo atacante. Decidir qualquer coisa a
/// partir deles antes de saber de quem é o manifest seria confiar no conteúdo
/// para decidir se confiamos no conteúdo.
library;

import 'package:meta/meta.dart';

/// Σ da FSM-B. `p5Committed` é final e colapsa em `p0Steady` com vN+1.
enum SyncState {
  /// Pack vN ativo, nada em voo. Estado inicial e de repouso.
  p0Steady,

  p1ManifestFetch,
  p2Downloading,
  p3Verifying,

  /// Pack vN+1 baixado e verificado, aguardando janela para trocar.
  p4Staged,

  p5Committed,

  /// Erro transitório: tentar de novo faz sentido (RNF-08).
  f1Retryable,

  /// Erro permanente para *este* manifest (RNF-05). Não é poço: um manifest de
  /// versão superior resgata a máquina (análise L2 da espec).
  f2Rejected,
}

/// Efeitos que o driver deve executar ao tomar uma transição. São *comandos*,
/// não descrições — a máquina não os executa, apenas diz quais são.
enum SyncAction {
  /// GET no manifest com `If-None-Match`, timeout de 10 s.
  fetchManifestWithEtag,

  /// Inicia ou retoma o download do pack por Range.
  startOrResumeDownload,

  /// Persiste offset parcial e ETag para a próxima janela.
  persistOffsetAndEtag,

  /// Conta a falha contra o orçamento de tentativas da janela.
  incrementCircuitCounter,

  /// Marca os bytes do manifest recusado para não reprocessá-los.
  ///
  /// **Os bytes do manifest, não o `packHash` que ele declara.** Com assinatura
  /// inválida, o `packHash` é um campo sob controle de quem forjou o arquivo;
  /// blacklistá-lo permitiria envenenar a lista contra um pack legítimo futuro
  /// — o atacante bloquearia conteúdo real sem precisar de chave nenhuma.
  blacklistManifestDigest,

  /// Marca o `packHash` de um manifest **autêntico** cujo artefato não conferiu.
  /// Aqui o hash veio de manifest com assinatura válida, então é seguro.
  blacklistPackHash,

  /// Apaga o arquivo em staging que falhou na verificação.
  discardStaging,

  /// Nada a fazer senão esperar um binário novo: schema major incompatível.
  awaitBinaryUpdate,

  /// Move o artefato verificado para o staging identificado pelo `packHash`.
  stagePack,

  /// Troca o pack ativo com um rename POSIX e reabre as conexões do SQLite.
  atomicSwap,

  /// Adia a troca porque há triagem em curso. No-wait: não bloqueia ninguém.
  deferSwap,

  /// vN+1 passa a ser o ativo; vN é removido.
  activateAndDropPrevious,

  /// Abre o circuito até a próxima janela do WorkManager.
  openCircuit,
}

@immutable
sealed class SyncEvent {
  const SyncEvent();
}

/// Janela do WorkManager abriu.
@immutable
final class OnConnectivity extends SyncEvent {
  const OnConnectivity({required this.circuitClosed, this.backoffElapsed = true});

  final bool circuitClosed;

  /// Só consultado a partir de `f1Retryable`: em `p0Steady` não há backoff
  /// pendente.
  final bool backoffElapsed;
}

/// `304 Not Modified` — o servidor confirmou que nada mudou.
@immutable
final class ManifestNotModified extends SyncEvent {
  const ManifestNotModified();
}

/// `200` com um manifest, já com as três guardas avaliadas pelo driver.
@immutable
final class ManifestFetched extends SyncEvent {
  const ManifestFetched({
    required this.signatureValid,
    required this.versionIsNewer,
    required this.schemaSupported,
  });

  final bool signatureValid;

  /// `m.packVersion > vN`. Falso inclui o caso de igualdade — reinstalar a
  /// versão ativa não é downgrade, mas também não é trabalho útil.
  final bool versionIsNewer;

  final bool schemaSupported;
}

/// Timeout ou erro de rede buscando o manifest.
@immutable
final class NetworkFailure extends SyncEvent {
  const NetworkFailure();
}

/// A janela fechou no meio do download. Os bytes parciais estão em disco.
@immutable
final class DownloadWindowClosed extends SyncEvent {
  const DownloadWindowClosed();
}

@immutable
final class DownloadComplete extends SyncEvent {
  const DownloadComplete();
}

/// Resultado do `sha256(file) = m.packHash`.
@immutable
final class HashChecked extends SyncEvent {
  const HashChecked({required this.matches});

  final bool matches;
}

/// Estado da FSM-A no momento de tentar a troca.
@immutable
final class QuiescenceChecked extends SyncEvent {
  const QuiescenceChecked({required this.idle});

  /// `true` quando a FSM-A está em `S0_IDLE`. É o guard que impede uma sessão
  /// de triagem ler duas versões de pack (análise S1 da espec).
  final bool idle;
}

/// ε — o commit terminou.
@immutable
final class CommitFinished extends SyncEvent {
  const CommitFinished();
}

/// n ≥ 5 falhas na mesma janela.
@immutable
final class RetryBudgetExhausted extends SyncEvent {
  const RetryBudgetExhausted();
}

/// Chegou manifest com versão maior que a recusada — garante liveness (L2).
@immutable
final class HigherVersionOffered extends SyncEvent {
  const HigherVersionOffered();
}

/// Transição tomada: para onde vamos e o que o driver deve fazer.
@immutable
class SyncTransition {
  const SyncTransition(this.next, {this.actions = const [], required this.rule});

  final SyncState next;
  final List<SyncAction> actions;

  /// Identificador da linha da matriz que autorizou esta transição. Aparece
  /// nas mensagens de teste, para que uma falha aponte direto para a spec.
  final String rule;
}

/// Aplica a matriz de [espec.md §4.2].
///
/// Devolve `null` para pares (estado, evento) que a matriz não prevê. Isso é
/// **rejeição, não erro**: o driver descarta o evento e permanece onde está.
/// Uma máquina que inventa transição para evento inesperado é uma máquina que
/// pode ativar pack sem passar pela verificação.
SyncTransition? transition(SyncState state, SyncEvent event) {
  switch ((state, event)) {
    // --- P0_STEADY ---------------------------------------------------------
    case (SyncState.p0Steady, final OnConnectivity e):
      if (!e.circuitClosed) return null; // circuito aberto: nada acontece.
      return const SyncTransition(
        SyncState.p1ManifestFetch,
        actions: [SyncAction.fetchManifestWithEtag],
        rule: 'B1 P0→P1 onConnectivity [circuito fechado]',
      );

    // --- P1_MANIFEST_FETCH -------------------------------------------------
    case (SyncState.p1ManifestFetch, ManifestNotModified()):
      return const SyncTransition(
        SyncState.p0Steady,
        rule: 'B2 P1→P0 304 [noop]',
      );

    case (SyncState.p1ManifestFetch, final ManifestFetched e):
      if (!e.signatureValid) {
        return const SyncTransition(
          SyncState.f2Rejected,
          actions: [SyncAction.blacklistManifestDigest],
          rule: 'B4a P1→F2 assinatura inválida [INV-7]',
        );
      }
      if (!e.versionIsNewer) {
        // Downgrade recusado MESMO com assinatura válida (INV-7). Sem
        // blacklist: o manifest é autêntico, só é velho.
        return const SyncTransition(
          SyncState.f2Rejected,
          rule: 'B4b P1→F2 packVersion ≤ vN [anti-downgrade]',
        );
      }
      if (!e.schemaSupported) {
        return const SyncTransition(
          SyncState.f2Rejected,
          actions: [SyncAction.awaitBinaryUpdate],
          rule: 'B5 P1→F2 schemaVersion não suportado [INV-6]',
        );
      }
      return const SyncTransition(
        SyncState.p2Downloading,
        actions: [SyncAction.startOrResumeDownload],
        rule: 'B3 P1→P2 200 [sig ok ∧ v>vN ∧ schema ok]',
      );

    case (SyncState.p1ManifestFetch, NetworkFailure()):
      return const SyncTransition(
        SyncState.f1Retryable,
        actions: [SyncAction.incrementCircuitCounter],
        rule: 'B6 P1→F1 timeout ou erro de rede',
      );

    // --- P2_DOWNLOADING ----------------------------------------------------
    case (SyncState.p2Downloading, DownloadWindowClosed()):
      return const SyncTransition(
        SyncState.f1Retryable,
        actions: [
          SyncAction.persistOffsetAndEtag,
          SyncAction.incrementCircuitCounter,
        ],
        rule: 'B7 P2→F1 janela fecha [persiste offset]',
      );

    case (SyncState.p2Downloading, DownloadComplete()):
      return const SyncTransition(
        SyncState.p3Verifying,
        rule: 'B8 P2→P3 download completo',
      );

    // --- P3_VERIFYING ------------------------------------------------------
    case (SyncState.p3Verifying, final HashChecked e):
      if (e.matches) {
        return const SyncTransition(
          SyncState.p4Staged,
          actions: [SyncAction.stagePack],
          rule: 'B9 P3→P4 sha256 = m.packHash',
        );
      }
      return const SyncTransition(
        SyncState.f2Rejected,
        actions: [SyncAction.discardStaging, SyncAction.blacklistPackHash],
        rule: 'B10 P3→F2 hash mismatch [blacklist]',
      );

    // --- P4_STAGED ---------------------------------------------------------
    case (SyncState.p4Staged, final QuiescenceChecked e):
      if (e.idle) {
        return const SyncTransition(
          SyncState.p5Committed,
          actions: [SyncAction.atomicSwap],
          rule: 'B11 P4→P5 app quiescente [rename atômico]',
        );
      }
      return const SyncTransition(
        SyncState.p4Staged,
        actions: [SyncAction.deferSwap],
        rule: 'B12 P4→P4 triagem ativa [adia, no-wait]',
      );

    // --- P5_COMMITTED ------------------------------------------------------
    case (SyncState.p5Committed, CommitFinished()):
      return const SyncTransition(
        SyncState.p0Steady,
        actions: [SyncAction.activateAndDropPrevious],
        rule: 'B13 P5→P0 ε [vN+1 ativo, vN removido]',
      );

    // --- F1_RETRYABLE ------------------------------------------------------
    case (SyncState.f1Retryable, final OnConnectivity e):
      if (!e.circuitClosed || !e.backoffElapsed) return null;
      return const SyncTransition(
        SyncState.p1ManifestFetch,
        actions: [SyncAction.fetchManifestWithEtag],
        rule: 'B14 F1→P1 retry [backoff+jitter decorrido]',
      );

    case (SyncState.f1Retryable, RetryBudgetExhausted()):
      return const SyncTransition(
        SyncState.p0Steady,
        actions: [SyncAction.openCircuit],
        rule: 'B15 F1→P0 n≥5 [abre circuito]',
      );

    // --- F2_REJECTED -------------------------------------------------------
    case (SyncState.f2Rejected, HigherVersionOffered()):
      return const SyncTransition(
        SyncState.p1ManifestFetch,
        actions: [SyncAction.fetchManifestWithEtag],
        rule: 'B16 F2→P1 manifest com versão > rejeitada [liveness L2]',
      );

    default:
      return null;
  }
}
