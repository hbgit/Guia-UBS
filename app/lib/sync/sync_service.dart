/// Driver da FSM-B: executa um ciclo de sincronização de conteúdo.
///
/// Divisão de responsabilidade com [sync_fsm.dart]: **a máquina decide, o
/// driver executa**. Este arquivo faz rede, disco e relógio, converte o que
/// aconteceu em [SyncEvent], e cumpre as [SyncAction] que a máquina devolve.
/// Nenhuma decisão de aceitar ou recusar conteúdo mora aqui.
///
/// ## Um ciclo, não um laço
///
/// [runCycle] roda uma vez e volta. Quem decide quando chamar é o agendador
/// (WorkManager, com as mesmas restrições do sync do modelo). Isso mantém o
/// serviço testável sem relógio de parede e alinhado ao modelo de execução do
/// Android, onde processo em segundo plano não escolhe quanto tempo vive.
///
/// O estado da máquina sobrevive entre ciclos **na instância**: uma troca
/// adiada por triagem em curso (linha B12) continua adiada no ciclo seguinte,
/// sem re-baixar nada.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';

import 'manifest_verifier.dart';
import 'pack_manifest.dart';
import 'pack_store.dart';
import 'resumable_downloader.dart';
import 'sync_fsm.dart';
import 'sync_retry_state.dart';

/// Relatório de um ciclo. Serve ao teste e ao log local — **nunca à tela**:
/// sync é invisível para o usuário (INV-8).
@immutable
class SyncReport {
  const SyncReport({
    required this.state,
    required this.rules,
    required this.detail,
    this.committedVersion,
  });

  /// Onde a máquina parou. Se for `p2Downloading` ou `p4Staged`, o ciclo
  /// seguinte continua daí.
  final SyncState state;

  /// Linhas da matriz percorridas, em ordem. É a evidência de que o caminho
  /// tomado foi o que a spec descreve.
  final List<String> rules;

  final String detail;

  /// Versão que passou a ser ativa neste ciclo, quando houve commit.
  final int? committedVersion;

  bool get committed => committedVersion != null;
}

/// Estado da FSM-A, consultado pelo guard de quiescência (linha B11).
typedef QuiescenceProbe = bool Function();

class SyncService {
  SyncService({
    required this.manifestUrl,
    required this.store,
    required this.quiescence,
    HttpClient? client,
    ResumableDownloader? downloader,
    ManifestVerifier verifier = const ManifestVerifier(),
    this.manifestTimeout = const Duration(seconds: 10),
    this.maxFailuresPerWindow = 5,
    DateTime Function()? now,
    Random? random,
  })  : _client = client ?? HttpClient(),
        _downloader = downloader ?? ResumableDownloader(),
        // ignore: prefer_initializing_formals — o nome público é `verifier`.
        _verifier = verifier,
        _now = now ?? DateTime.now,
        _random = random ?? Random();

  /// URL do `manifest.json`. Os artefatos são resolvidos relativamente a ela.
  final Uri manifestUrl;

  final PackStore store;

  /// Pergunta se a FSM-A está em `S0_IDLE`. Sem sessão de triagem em curso não
  /// há como uma leitura atravessar a troca de pack (análise S1).
  final QuiescenceProbe quiescence;

  final HttpClient _client;
  final ResumableDownloader _downloader;
  final ManifestVerifier _verifier;
  final DateTime Function() _now;
  final Random _random;

  /// Timeout do GET do manifest — 10 s, conforme a linha B1.
  final Duration manifestTimeout;

  /// Orçamento de falhas antes de abrir o circuito (linha B15).
  final int maxFailuresPerWindow;

  SyncState _state = SyncState.p0Steady;
  final List<String> _rules = [];

  /// Manifest aceito e ainda não commitado. Sobrevive entre ciclos para que
  /// uma troca adiada não precise refazer o trabalho.
  PackManifest? _staged;

  /// Versão recusada mais alta — usada para decidir a saída de F2 (linha B16).
  int _rejectedVersion = 0;

  /// Estado de retentativa do ciclo corrente, lido do disco no início de cada
  /// `runCycle`. Ver `sync_retry_state.dart` para por que ele não pode viver
  /// só aqui.
  SyncRetryState _retry = SyncRetryState.clean;

  SyncState get state => _state;

  /// Circuito aberto agora.
  bool get circuitOpen => !_retry.circuitClosedAt(_now());

  /// Estado de retentativa como está em memória neste instante.
  SyncRetryState get retryState => _retry;

  /// Executa um ciclo completo. **Nunca lança** — falha de sync jamais pode
  /// derrubar o app (INV-8).
  Future<SyncReport> runCycle() async {
    _rules.clear();

    try {
      _retry = await store.readRetryState();

      // Restaura a POSIÇÃO da máquina a partir do estado persistido.
      //
      // Um processo novo nasce em `p0Steady`, onde a linha B1 só consulta o
      // circuito — o backoff é guarda da linha B14, que sai de `f1Retryable`.
      // Sem isto, cada reinício pularia o backoff e iria direto à rede, o que
      // é exatamente o caso comum: o WorkManager cria um isolate por disparo.
      // Se há falhas registradas, a máquina estava em F1 quando o processo
      // morreu, e é de lá que ela deve continuar.
      if (_state == SyncState.p0Steady && _retry.failures > 0) {
        _state = SyncState.f1Retryable;
      }

      return await _cycle();
    } on Object catch (error) {
      // Qualquer exceção não prevista degrada para retentável: o pack ativo
      // continua intacto e o usuário não percebe nada.
      _state = SyncState.f1Retryable;
      await _registerFailure();
      return _report('exceção não prevista: $error');
    }
  }

  Future<SyncReport> _cycle() async {
    await store.ensureDirectory();

    switch (_state) {
      // Troca pendente de janela ociosa: nada de rede, só re-checar a FSM-A.
      case SyncState.p4Staged:
        return _attemptSwap();

      case SyncState.p0Steady:
        if (!_fire(OnConnectivity(circuitClosed: _retry.circuitClosedAt(_now())))) {
          return _report('circuito aberto até ${_retry.circuitOpenUntil}');
        }

      case SyncState.f1Retryable:
        final now = _now();
        if (!_fire(
          OnConnectivity(
            circuitClosed: _retry.circuitClosedAt(now),
            backoffElapsed: _retry.backoffElapsedAt(now),
          ),
        )) {
          return _report(
            _retry.circuitClosedAt(now)
                ? 'backoff ainda não decorreu'
                : 'circuito aberto',
          );
        }

      case SyncState.f2Rejected:
        // A saída de F2 exige saber que existe versão maior — e só o manifest
        // conta isso. Buscamos primeiro e decidimos depois; a transição B16 é
        // disparada dentro de [_fetchManifest] quando a versão qualifica.
        break;

      case SyncState.p1ManifestFetch:
      case SyncState.p2Downloading:
      case SyncState.p3Verifying:
      case SyncState.p5Committed:
        // Estados transitórios dentro de um ciclo. Encontrá-los no início
        // significa ciclo anterior interrompido de forma anômala; recomeçar do
        // repouso é seguro porque nada foi ativado.
        _state = SyncState.p0Steady;
        return _cycle();
    }

    return _fetchManifest();
  }

  // -------------------------------------------------------------------------
  // P1 — manifest com ETag
  // -------------------------------------------------------------------------

  Future<SyncReport> _fetchManifest() async {
    final etag = await store.readEtag();

    final _ManifestResponse response;
    try {
      response = await _get(etag);
    } on Object catch (error) {
      _fire(const NetworkFailure());
      await _registerFailure();
      return _report('manifest inacessível: $error');
    }

    if (response.notModified) {
      // Em F2 um 304 confirma que continua sendo o manifest já recusado.
      if (_state == SyncState.f2Rejected) return _report('304 — segue recusado');
      _fire(const ManifestNotModified());
      return _report('304 — nada a fazer');
    }
    if (response.body == null) {
      _fire(const NetworkFailure());
      await _registerFailure();
      return _report('HTTP ${response.status} no manifest');
    }

    final bytes = response.body!;
    final outcome = await _verifier.verify(bytes);
    final activeVersion = await store.activeVersion();

    if (outcome is ManifestRejected) {
      // Sem manifest válido não há versão em que confiar, então a saída de F2
      // não pode ser autorizada por este arquivo.
      if (_state == SyncState.f2Rejected) {
        await store.saveEtag(response.etag);
        return _report('manifest recusado (${outcome.reason.name})');
      }
      _fire(
        ManifestFetched(
          signatureValid: outcome.reason != ManifestRejection.badSignature &&
              outcome.reason != ManifestRejection.unknownKey &&
              outcome.reason != ManifestRejection.missingSignature,
          versionIsNewer: false,
          schemaSupported: false,
        ),
      );
      await _runRejectionActions(manifestDigest: sha256OfBytes(bytes));
      await store.saveEtag(response.etag);
      return _report('manifest recusado (${outcome.reason.name}): ${outcome.detail}');
    }

    final manifest = (outcome as ManifestAccepted).manifest;

    if (_state == SyncState.f2Rejected) {
      if (manifest.packVersion <= _rejectedVersion) {
        await store.saveEtag(response.etag);
        return _report('versão ${manifest.packVersion} não supera a recusada');
      }
      _fire(const HigherVersionOffered());
    }

    _fire(
      ManifestFetched(
        signatureValid: true,
        versionIsNewer: manifest.packVersion > activeVersion,
        schemaSupported: manifest.isSchemaSupported,
      ),
    );

    if (_state == SyncState.f2Rejected) {
      _rejectedVersion = manifest.packVersion;
      await _runRejectionActions(manifestDigest: sha256OfBytes(bytes));
      await store.saveEtag(response.etag);
      return _report(
        'manifest v${manifest.packVersion} recusado '
        '(ativa=$activeVersion, schema=${manifest.schemaVersion})',
      );
    }

    // Artefato já reprovado antes: o destino pela máquina seria P2→P3→F2 de
    // novo. Atalho de ECONOMIA, não de decisão — poupa o plano de dados do
    // usuário para chegar exatamente ao mesmo estado.
    if (await store.isPackRejected(manifest.pack.sha256)) {
      _state = SyncState.f2Rejected;
      _rejectedVersion = manifest.packVersion;
      _rules.add('B10 (memorizado) packHash já na blacklist');
      await store.saveEtag(response.etag);
      return _report('pack ${manifest.pack.sha256.substring(0, 12)} já recusado');
    }

    return _download(manifest, response.etag);
  }

  Future<_ManifestResponse> _get(String? etag) async {
    final request = await _client.getUrl(manifestUrl).timeout(manifestTimeout);
    if (etag != null) {
      request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
    }
    final response = await request.close().timeout(manifestTimeout);
    final responseEtag = response.headers.value(HttpHeaders.etagHeader);

    if (response.statusCode == HttpStatus.notModified) {
      await response.drain<void>();
      return _ManifestResponse(status: 304, etag: etag, notModified: true);
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      return _ManifestResponse(status: response.statusCode, etag: responseEtag);
    }

    final bytes = <int>[];
    await response.timeout(manifestTimeout).forEach(bytes.addAll);
    return _ManifestResponse(status: 200, etag: responseEtag, body: bytes);
  }

  // -------------------------------------------------------------------------
  // P2/P3 — baixar e verificar
  // -------------------------------------------------------------------------

  Future<SyncReport> _download(PackManifest manifest, String? etag) async {
    // Limpa staging órfão antes de gastar rede, protegendo o alvo corrente.
    await store.dropUnreferenced(keep: manifest.pack.sha256);

    final destination = store.packFile(manifest.pack.sha256);
    final outcome = await _downloader.fetch(
      url: manifestUrl.resolve(manifest.pack.url),
      destination: destination,
      expectedSha256: manifest.pack.sha256,
      fallbackTotalBytes: manifest.pack.bytes,
    );

    switch (outcome) {
      case DownloadInterrupted(:final reason):
        _fire(const DownloadWindowClosed());
        await _registerFailure();
        // O ETag NÃO é gravado aqui: com download em voo, um 304 no próximo
        // ciclo esconderia o manifest que precisamos para retomar. O que
        // identifica a retomada é o `.parcial` nomeado pelo hash do pack, que
        // é endereço de conteúdo — mais forte que ETag, porque pack diferente
        // é arquivo diferente.
        return _report('janela fechou: $reason');

      case DownloadRejected(:final reason, :final kind):
        if (kind == DownloadRejectionKind.digestMismatch) {
          // Os bytes chegaram (P2→P3); o que falhou foi a conferência. Pular
          // P3_VERIFYING aqui deixaria a máquina parada em P2 achando que o
          // download ainda estava em curso — e um artefato adulterado sairia
          // do ciclo sem ir para a blacklist.
          _fire(const DownloadComplete());
          _fire(const HashChecked(matches: false));
          _rejectedVersion = manifest.packVersion;
          await _runRejectionActions(packHash: manifest.pack.sha256);
          await store.saveEtag(etag);
          return _report('artefato adulterado: $reason');
        }
        // 4xx no artefato: manifest autêntico, publicação quebrada. Não vai
        // para a blacklist — o hash é legítimo e o operador pode consertar.
        _fire(const DownloadWindowClosed());
        await _registerFailure();
        return _report('artefato indisponível: $reason');

      case DownloadCompleted():
        // O downloader só devolve isto depois de conferir o SHA-256, então a
        // verificação de P3 já aconteceu; a máquina registra o fato.
        _fire(const DownloadComplete());
        _fire(const HashChecked(matches: true));
        _staged = manifest;
        _pendingEtag = etag;
        return _attemptSwap();
    }
  }

  String? _pendingEtag;

  // -------------------------------------------------------------------------
  // P4/P5 — troca atômica sob quiescência
  // -------------------------------------------------------------------------

  Future<SyncReport> _attemptSwap() async {
    final manifest = _staged;
    if (manifest == null) {
      _state = SyncState.p0Steady;
      return _report('staging perdido; volta ao repouso');
    }

    final idle = quiescence();
    _fire(QuiescenceChecked(idle: idle));
    if (!idle) {
      return _report('triagem em curso; troca adiada');
    }

    await store.commit(manifest);
    _fire(const CommitFinished());
    await store.dropUnreferenced();
    await store.saveEtag(_pendingEtag);

    _staged = null;
    _pendingEtag = null;
    // Ciclo bem-sucedido zera o freio: o próximo problema recomeça do backoff
    // mínimo, e não de onde uma falha antiga tinha parado.
    _retry = SyncRetryState.clean;
    await store.clearRetryState();
    return _report(
      'pack v${manifest.packVersion} ativo',
      committedVersion: manifest.packVersion,
    );
  }

  // -------------------------------------------------------------------------
  // Ações e contabilidade
  // -------------------------------------------------------------------------

  /// Executa as ações de blacklist da última transição. Separado porque só
  /// estes efeitos escrevem em disco fora do caminho feliz.
  Future<void> _runRejectionActions({
    String? manifestDigest,
    String? packHash,
  }) async {
    for (final action in _lastActions) {
      switch (action) {
        case SyncAction.blacklistManifestDigest:
          if (manifestDigest != null) await store.rejectManifest(manifestDigest);
        case SyncAction.blacklistPackHash:
          if (packHash != null) await store.rejectPack(packHash);
        case SyncAction.discardStaging:
          // O downloader já apagou o parcial ao recusar; nada a fazer.
          break;
        default:
          break;
      }
    }
  }

  List<SyncAction> _lastActions = const [];

  /// Alimenta a máquina. Devolve `false` quando a matriz não prevê a transição
  /// — o evento é descartado e o estado permanece.
  bool _fire(SyncEvent event) {
    final result = transition(_state, event);
    if (result == null) {
      _lastActions = const [];
      return false;
    }
    _state = result.next;
    _lastActions = result.actions;
    _rules.add(result.rule);
    return true;
  }

  /// Conta a falha, agenda a próxima tentativa e **persiste** o resultado.
  ///
  /// Persistir é o que faz o freio existir de verdade: o WorkManager executa
  /// num isolate novo a cada disparo, e um freio em memória morre junto com o
  /// isolate que o criou.
  Future<void> _registerFailure() async {
    final failures = _retry.failures + 1;

    if (failures >= maxFailuresPerWindow) {
      _fire(const RetryBudgetExhausted());
      _retry = SyncRetryState(circuitOpenUntil: _now().add(circuitCooldown));
      await store.saveRetryState(_retry);
      return;
    }

    _retry = SyncRetryState(
      failures: failures,
      nextAttemptAt: _now().add(backoffDelay(failures, _random)),
      circuitOpenUntil: _retry.circuitOpenUntil,
    );
    await store.saveRetryState(_retry);
  }

  SyncReport _report(String detail, {int? committedVersion}) => SyncReport(
        state: _state,
        rules: List.unmodifiable(_rules),
        detail: detail,
        committedVersion: committedVersion,
      );

  void close() {
    _client.close(force: true);
    _downloader.close();
  }
}

@immutable
class _ManifestResponse {
  const _ManifestResponse({
    required this.status,
    this.etag,
    this.body,
    this.notModified = false,
  });

  final int status;
  final String? etag;
  final List<int>? body;
  final bool notModified;
}
