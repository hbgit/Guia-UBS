/// Estado em disco do conteúdo: qual pack está ativo, o que está em staging,
/// o que já foi recusado.
///
/// ## O ponto de commit é o rename do manifest
///
/// Os packs vivem em disco nomeados pelo próprio hash (`pack-<sha256>.db`).
/// Um pack só é **ativo** porque o `manifest.json` corrente aponta para ele.
/// Trocar de versão é, portanto, um único `rename()` POSIX do manifest — e
/// rename no mesmo filesystem é atômico.
///
/// Isso resolve o cenário S3 da [espec.md §4.4] (processo morto no meio da
/// troca) sem nenhum protocolo de recuperação: ou o manifest antigo está lá,
/// apontando para o pack antigo que não foi apagado, ou o novo está lá,
/// apontando para o novo que já foi verificado. Não existe estado híbrido
/// porque não existe segundo passo capaz de falhar sozinho.
///
/// Nomear pelo hash também dá de graça a idempotência exigida pelo cenário S2:
/// duas execuções concorrentes do WorkManager baixam para o **mesmo** caminho,
/// e a segunda encontra o trabalho pronto em vez de duplicá-lo.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import 'manifest_verifier.dart';
import 'pack_manifest.dart';
import 'sync_retry_state.dart';

/// Nome do manifest ativo. O `.novo` é o arquivo temporário que vira este por
/// rename — nunca é lido por ninguém.
const String _activeManifestName = 'manifest.json';
const String _stateName = 'state.json';

/// Versão usada quando não há pack ativo. Como `packVersion` é sempre positivo
/// no contrato, zero significa "qualquer coisa é mais nova".
const int noActivePackVersion = 0;

@immutable
class ActivePack {
  const ActivePack(this.manifest, this.file);

  final PackManifest manifest;

  /// `pack-<sha256>.db` já verificado.
  final File file;
}

class PackStore {
  PackStore(
    this.directory, {
    ManifestVerifier verifier = const ManifestVerifier(),
    this.verifyActivePackDigest = true,
    // ignore: prefer_initializing_formals — o nome público é `verifier`.
  }) : _verifier = verifier;

  final Directory directory;
  final ManifestVerifier _verifier;

  /// Reconferir o SHA-256 do pack ativo a cada abertura.
  ///
  /// Ligado porque o pack semente tem centenas de KB e o custo é irrelevante.
  /// **Se os packs crescerem para dezenas de MB** (áudio embarcado), isto sai
  /// do caminho crítico do boot — foi exatamente o erro que o marcador
  /// `.verificado` do modelo SLM corrigiu, e a lição vale aqui.
  final bool verifyActivePackDigest;

  File get _activeManifestFile => File('${directory.path}/$_activeManifestName');
  File get _stateFile => File('${directory.path}/$_stateName');

  /// Caminho determinístico de um pack pelo seu hash. É staging e destino
  /// final ao mesmo tempo: o que muda no commit é o manifest, não o arquivo.
  File packFile(String sha256) => File('${directory.path}/pack-$sha256.db');

  Future<void> ensureDirectory() async {
    if (!directory.existsSync()) await directory.create(recursive: true);
  }

  // -------------------------------------------------------------------------
  // Pack ativo
  // -------------------------------------------------------------------------

  /// Lê e **revalida** o pack ativo (INV-3).
  ///
  /// Reverificar no cold start não é paranoia decorativa: o manifest em disco
  /// é o que autoriza o conteúdo que o usuário vai ler, e revalidá-lo é a
  /// única forma de garantir que um arquivo trocado por fora não seja servido
  /// como se fosse nosso. Devolve `null` quando não há ativo utilizável — o
  /// chamador trata como "sem pack", não como erro fatal.
  Future<ActivePack?> loadActive() async {
    if (!_activeManifestFile.existsSync()) return null;

    final outcome = await _verifier.verify(await _activeManifestFile.readAsBytes());
    if (outcome is! ManifestAccepted) return null;

    final manifest = outcome.manifest;
    final file = packFile(manifest.pack.sha256);
    if (!file.existsSync()) return null;

    if (verifyActivePackDigest) {
      final digest = await sha256OfFile(file);
      if (digest != manifest.pack.sha256) return null;
    }
    return ActivePack(manifest, file);
  }

  /// Versão ativa, ou [noActivePackVersion] se não houver pack utilizável.
  Future<int> activeVersion() async =>
      (await loadActive())?.manifest.packVersion ?? noActivePackVersion;

  /// Torna [manifest] o ativo. **Este é o swap atômico** da linha B11.
  ///
  /// Gravamos os bytes ORIGINAIS do manifest, não uma reserialização nossa: a
  /// assinatura fecha sobre aqueles bytes, e é ela que a próxima abertura vai
  /// conferir.
  Future<void> commit(PackManifest manifest) async {
    final staged = packFile(manifest.pack.sha256);
    if (!staged.existsSync()) {
      throw StateError('commit sem artefato em staging: ${staged.path}');
    }
    final temp = File('${_activeManifestFile.path}.novo');
    await temp.writeAsBytes(manifest.rawBytes, flush: true);
    await temp.rename(_activeManifestFile.path);
  }

  /// Remove packs e parciais que o manifest ativo não referencia.
  ///
  /// Roda depois do commit (apaga vN) e no cold start (limpa staging órfão
  /// deixado por um processo morto — cenário S3). [keep] protege o artefato
  /// que o ciclo corrente está baixando neste instante.
  Future<int> dropUnreferenced({String? keep}) async {
    if (!directory.existsSync()) return 0;
    final active = (await loadActive())?.manifest.pack.sha256;

    var removed = 0;
    for (final entity in directory.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('pack-')) continue;

      final hash = name
          .substring('pack-'.length)
          .replaceAll('.parcial', '')
          .replaceAll('.db', '');
      if (hash == active || hash == keep) continue;

      await entity.delete();
      removed++;
    }
    return removed;
  }

  // -------------------------------------------------------------------------
  // Estado auxiliar: ETag e recusas
  // -------------------------------------------------------------------------

  Future<Map<String, Object?>> _readState() async {
    if (!_stateFile.existsSync()) return <String, Object?>{};
    try {
      final decoded = jsonDecode(await _stateFile.readAsString());
      return decoded is Map<String, Object?> ? decoded : <String, Object?>{};
    } on Object {
      // Estado auxiliar corrompido não é motivo para travar o sync: ele é
      // cache e memória de recusas, não fonte de verdade. Recomeçar do vazio
      // custa um download a mais; travar custaria conteúdo desatualizado para
      // sempre.
      return <String, Object?>{};
    }
  }

  Future<void> _writeState(Map<String, Object?> state) async {
    await ensureDirectory();
    await _stateFile.writeAsString(jsonEncode(state), flush: true);
  }

  /// ETag do último manifest visto — é o que permite o `304` da linha B2.
  Future<String?> readEtag() async => (await _readState())['etag'] as String?;

  Future<void> saveEtag(String? etag) async {
    final state = await _readState();
    if (etag == null) {
      state.remove('etag');
    } else {
      state['etag'] = etag;
    }
    await _writeState(state);
  }

  /// Descarta o ETag para forçar o servidor a mandar o corpo na próxima volta.
  ///
  /// Necessário depois de uma recusa: com o ETag guardado, o servidor
  /// responderia `304` e a máquina nunca reavaliaria o manifest — o que
  /// transformaria F2_REJECTED no poço que a análise L2 diz não existir.
  Future<void> forgetEtag() => saveEtag(null);

  Future<Set<String>> _rejected(String key) async {
    final raw = (await _readState())[key];
    return raw is List ? raw.whereType<String>().toSet() : <String>{};
  }

  Future<void> _reject(String key, String value) async {
    final state = await _readState();
    final current = await _rejected(key);
    state[key] = (current..add(value)).toList()..sort();
    await _writeState(state);
  }

  /// Hashes de packs que vieram de manifest autêntico mas cujo artefato não
  /// conferiu (linha B10).
  Future<bool> isPackRejected(String sha256) async =>
      (await _rejected('rejectedPacks')).contains(sha256);

  Future<void> rejectPack(String sha256) => _reject('rejectedPacks', sha256);

  /// Digest dos **bytes** de manifests recusados por assinatura (linha B4a).
  Future<bool> isManifestRejected(String digest) async =>
      (await _rejected('rejectedManifests')).contains(digest);

  Future<void> rejectManifest(String digest) => _reject('rejectedManifests', digest);

  // -------------------------------------------------------------------------
  // Retentativa: backoff e circuito
  // -------------------------------------------------------------------------

  /// Estado de retentativa. Fica no MESMO arquivo do ETag e das blacklists:
  /// é bookkeeping de sync, não dado do usuário, e não tem por que atravessar
  /// a superfície auditável do `user.db`.
  Future<SyncRetryState> readRetryState() async =>
      SyncRetryState.fromJson((await _readState())['retry']);

  Future<void> saveRetryState(SyncRetryState retry) async {
    final state = await _readState();
    state['retry'] = retry.toJson();
    await _writeState(state);
  }

  Future<void> clearRetryState() async {
    final state = await _readState();
    state.remove('retry');
    await _writeState(state);
  }
}

/// SHA-256 hex de um arquivo, em streaming.
Future<String> sha256OfFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// SHA-256 hex de bytes em memória — usado para identificar manifests.
String sha256OfBytes(List<int> bytes) => sha256.convert(bytes).toString();