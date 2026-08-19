/// Espelha a matriz de transições da [espec.md §4.2], linha a linha.
///
/// Cada teste nomeia a linha que verifica. Se alguém mudar a regra sem mudar a
/// spec — ou vice-versa — a falha aponta direto para a linha divergente. É o
/// antídoto para o anti-padrão registrado em espec.md §6: *"FSM-B implementada
/// ad hoc dentro do SyncService"*.
///
/// O último grupo é o mais importante: ele verifica o que a máquina **recusa**
/// fazer. Uma FSM que inventa transição para evento inesperado é uma FSM capaz
/// de ativar conteúdo sem passar pela verificação.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/sync_fsm.dart';

SyncTransition _take(SyncState state, SyncEvent event) {
  final result = transition(state, event);
  expect(result, isNotNull, reason: 'a matriz prevê esta transição');
  return result!;
}

void main() {
  group('P0_STEADY', () {
    test('B1 — onConnectivity com circuito fechado busca o manifest', () {
      final t = _take(
        SyncState.p0Steady,
        const OnConnectivity(circuitClosed: true),
      );

      expect(t.next, SyncState.p1ManifestFetch);
      expect(t.actions, [SyncAction.fetchManifestWithEtag]);
    });

    test('circuito aberto não produz transição — nem uma requisição sai', () {
      expect(
        transition(SyncState.p0Steady, const OnConnectivity(circuitClosed: false)),
        isNull,
      );
    });
  });

  group('P1_MANIFEST_FETCH', () {
    test('B2 — 304 volta ao repouso sem efeito algum', () {
      final t = _take(SyncState.p1ManifestFetch, const ManifestNotModified());

      expect(t.next, SyncState.p0Steady);
      expect(t.actions, isEmpty);
    });

    test('B3 — 200 com as três guardas satisfeitas inicia o download', () {
      final t = _take(
        SyncState.p1ManifestFetch,
        const ManifestFetched(
          signatureValid: true,
          versionIsNewer: true,
          schemaSupported: true,
        ),
      );

      expect(t.next, SyncState.p2Downloading);
      expect(t.actions, [SyncAction.startOrResumeDownload]);
    });

    test('B4a — assinatura inválida recusa e memoriza os BYTES do manifest', () {
      final t = _take(
        SyncState.p1ManifestFetch,
        const ManifestFetched(
          signatureValid: false,
          versionIsNewer: true,
          schemaSupported: true,
        ),
      );

      expect(t.next, SyncState.f2Rejected);
      expect(t.actions, [SyncAction.blacklistManifestDigest]);
      expect(
        t.actions,
        isNot(contains(SyncAction.blacklistPackHash)),
        reason: 'sem assinatura válida o packHash é campo do atacante: '
            'blacklistá-lo deixaria qualquer um bloquear um pack legítimo',
      );
    });

    test('B4b — downgrade é recusado MESMO com assinatura válida (INV-7)', () {
      final t = _take(
        SyncState.p1ManifestFetch,
        const ManifestFetched(
          signatureValid: true,
          versionIsNewer: false,
          schemaSupported: true,
        ),
      );

      expect(t.next, SyncState.f2Rejected);
      expect(
        t.actions,
        isEmpty,
        reason: 'manifest autêntico e velho não é hostil — não vai à blacklist',
      );
    });

    test('a assinatura é avaliada ANTES da versão', () {
      // Manifest forjado que se declara mais novo. Se a versão fosse avaliada
      // primeiro, ele seguiria para o download.
      final t = _take(
        SyncState.p1ManifestFetch,
        const ManifestFetched(
          signatureValid: false,
          versionIsNewer: false,
          schemaSupported: false,
        ),
      );

      expect(t.actions, [SyncAction.blacklistManifestDigest]);
    });

    test('B5 — schema major não suportado espera atualização do binário', () {
      final t = _take(
        SyncState.p1ManifestFetch,
        const ManifestFetched(
          signatureValid: true,
          versionIsNewer: true,
          schemaSupported: false,
        ),
      );

      expect(t.next, SyncState.f2Rejected);
      expect(t.actions, [SyncAction.awaitBinaryUpdate]);
    });

    test('B6 — erro de rede é retentável e conta contra o circuito', () {
      final t = _take(SyncState.p1ManifestFetch, const NetworkFailure());

      expect(t.next, SyncState.f1Retryable);
      expect(t.actions, [SyncAction.incrementCircuitCounter]);
    });
  });

  group('P2_DOWNLOADING', () {
    test('B7 — janela fechando persiste o progresso antes de desistir', () {
      final t = _take(SyncState.p2Downloading, const DownloadWindowClosed());

      expect(t.next, SyncState.f1Retryable);
      expect(t.actions.first, SyncAction.persistOffsetAndEtag);
    });

    test('B8 — download completo vai verificar, nunca direto para staging', () {
      final t = _take(SyncState.p2Downloading, const DownloadComplete());

      expect(t.next, SyncState.p3Verifying);
      expect(t.actions, isEmpty);
    });
  });

  group('P3_VERIFYING', () {
    test('B9 — hash conferido move para staging', () {
      final t = _take(SyncState.p3Verifying, const HashChecked(matches: true));

      expect(t.next, SyncState.p4Staged);
      expect(t.actions, [SyncAction.stagePack]);
    });

    test('B10 — hash divergente apaga o staging e blacklista o packHash', () {
      final t = _take(SyncState.p3Verifying, const HashChecked(matches: false));

      expect(t.next, SyncState.f2Rejected);
      expect(t.actions, [SyncAction.discardStaging, SyncAction.blacklistPackHash]);
    });
  });

  group('P4_STAGED', () {
    test('B11 — quiescência autoriza o rename atômico', () {
      final t = _take(SyncState.p4Staged, const QuiescenceChecked(idle: true));

      expect(t.next, SyncState.p5Committed);
      expect(t.actions, [SyncAction.atomicSwap]);
    });

    test('B12 — triagem em curso adia a troca sem bloquear (análise S1)', () {
      final t = _take(SyncState.p4Staged, const QuiescenceChecked(idle: false));

      expect(t.next, SyncState.p4Staged);
      expect(t.actions, [SyncAction.deferSwap]);
      expect(
        t.actions,
        isNot(contains(SyncAction.atomicSwap)),
        reason: 'trocar o pack sob leitura faria a sessão ler duas versões',
      );
    });
  });

  group('P5_COMMITTED e F1/F2', () {
    test('B13 — commit ativa vN+1 e remove vN', () {
      final t = _take(SyncState.p5Committed, const CommitFinished());

      expect(t.next, SyncState.p0Steady);
      expect(t.actions, [SyncAction.activateAndDropPrevious]);
    });

    test('B14 — retry só depois do backoff decorrido', () {
      final t = _take(
        SyncState.f1Retryable,
        const OnConnectivity(circuitClosed: true),
      );

      expect(t.next, SyncState.p1ManifestFetch);
      expect(
        transition(
          SyncState.f1Retryable,
          const OnConnectivity(circuitClosed: true, backoffElapsed: false),
        ),
        isNull,
      );
    });

    test('B15 — orçamento esgotado abre o circuito e volta ao repouso', () {
      final t = _take(SyncState.f1Retryable, const RetryBudgetExhausted());

      expect(t.next, SyncState.p0Steady);
      expect(t.actions, [SyncAction.openCircuit]);
    });

    test('B16 — versão superior resgata F2: o estado não é poço (L2)', () {
      final t = _take(SyncState.f2Rejected, const HigherVersionOffered());

      expect(t.next, SyncState.p1ManifestFetch);
      expect(t.actions, [SyncAction.fetchManifestWithEtag]);
    });
  });

  group('o que a máquina se recusa a fazer', () {
    test('nenhum evento leva de P0 direto a estado de conteúdo ativo', () {
      // Se existisse atalho de P0 para P4/P5, haveria caminho para ativar um
      // pack sem passar por assinatura e hash.
      for (final event in _allEvents) {
        final next = transition(SyncState.p0Steady, event)?.next;
        expect(
          next,
          isNot(anyOf(SyncState.p4Staged, SyncState.p5Committed)),
          reason: '${event.runtimeType} criou atalho para ativação',
        );
      }
    });

    test('nenhum caminho chega a P4 sem passar por P3', () {
      for (final state in SyncState.values) {
        if (state == SyncState.p3Verifying || state == SyncState.p4Staged) continue;
        for (final event in _allEvents) {
          expect(
            transition(state, event)?.next,
            isNot(SyncState.p4Staged),
            reason: '$state + ${event.runtimeType} pulou a verificação de hash',
          );
        }
      }
    });

    test('atomicSwap só é emitido a partir de P4_STAGED', () {
      for (final state in SyncState.values) {
        if (state == SyncState.p4Staged) continue;
        for (final event in _allEvents) {
          expect(
            transition(state, event)?.actions ?? const <SyncAction>[],
            isNot(contains(SyncAction.atomicSwap)),
            reason: '$state + ${event.runtimeType} trocou o pack fora de P4',
          );
        }
      }
    });

    test('eventos fora de contexto são descartados, não improvisados', () {
      expect(transition(SyncState.p0Steady, const HashChecked(matches: true)), isNull);
      expect(transition(SyncState.p0Steady, const CommitFinished()), isNull);
      expect(transition(SyncState.p3Verifying, const DownloadComplete()), isNull);
      expect(
        transition(SyncState.f2Rejected, const OnConnectivity(circuitClosed: true)),
        isNull,
        reason: 'sair de F2 exige ver versão superior, não apenas ter rede',
      );
    });
  });
}

const List<SyncEvent> _allEvents = [
  OnConnectivity(circuitClosed: true),
  OnConnectivity(circuitClosed: false),
  ManifestNotModified(),
  ManifestFetched(signatureValid: true, versionIsNewer: true, schemaSupported: true),
  ManifestFetched(signatureValid: false, versionIsNewer: true, schemaSupported: true),
  ManifestFetched(signatureValid: true, versionIsNewer: false, schemaSupported: true),
  ManifestFetched(signatureValid: true, versionIsNewer: true, schemaSupported: false),
  NetworkFailure(),
  DownloadWindowClosed(),
  DownloadComplete(),
  HashChecked(matches: true),
  HashChecked(matches: false),
  QuiescenceChecked(idle: true),
  QuiescenceChecked(idle: false),
  CommitFinished(),
  RetryBudgetExhausted(),
  HigherVersionOffered(),
];
