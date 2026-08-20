/// Ciclo FSM-B ponta a ponta contra um servidor de conteúdo de verdade.
///
/// O servidor é local e pequeno, mas fala HTTP real: ETag com `If-None-Match`,
/// `Range` com `206`, e corte de conexão no meio da transferência. Sem isso,
/// "retoma após corte" — que é **critério de saída da Fase 1** no PRD §6.2 —
/// seria uma afirmação sobre código que ninguém executou.
///
/// Os manifests não são inventados aqui: são os arquivos que o `packer` real
/// assinou com a chave de desenvolvimento, em `test/fixtures/sync/`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/manifest_verifier.dart';
import 'package:guia_ubs/sync/pack_signing_keys.dart';
import 'package:guia_ubs/sync/pack_store.dart';
import 'package:guia_ubs/sync/sync_fsm.dart';
import 'package:guia_ubs/sync/sync_service.dart';

import 'package:guia_ubs/content/data/pack_rule_source.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/manifest_signing.dart';
import '../support/sqlite_test_libs.dart';

const Map<String, String> _devKeys = {'k1': devPackSigningKeyK1, 'k2': ''};

List<int> _fixture(String name) =>
    File('test/fixtures/sync/$name').readAsBytesSync();

/// Servidor de conteúdo controlável.
class _Origin {
  _Origin();

  late HttpServer _server;

  /// Bytes do `manifest.json` servido agora. Trocar isto é publicar.
  List<int> manifest = _fixture('manifest-v1.json');

  /// `packs/<nome>` → bytes.
  final Map<String, List<int>> packs = {};

  /// ETag anunciado. Muda quando o operador publica.
  String etag = 'v1';

  /// Espelho que não implementa ETag — rsync + servidor de arquivos estáticos
  /// é uma topologia prevista em stack.md §4.2.
  bool sendEtag = true;

  /// Corta a conexão do pack após N bytes, simulando perda de sinal.
  int? cutPackAfterBytes;

  /// Falha o GET do manifest com este status.
  int? manifestStatus;

  int manifestRequests = 0;
  int notModifiedResponses = 0;
  int packRequests = 0;
  String? lastRange;

  Uri get manifestUrl =>
      Uri.parse('http://${_server.address.host}:${_server.port}/manifest.json');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server.forEach(_handle));
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (path == '/manifest.json') {
      manifestRequests++;
      if (manifestStatus != null) {
        request.response.statusCode = manifestStatus!;
        await request.response.close();
        return;
      }
      if (sendEtag && request.headers.value(HttpHeaders.ifNoneMatchHeader) == etag) {
        notModifiedResponses++;
        request.response
          ..statusCode = HttpStatus.notModified
          ..headers.set(HttpHeaders.etagHeader, etag);
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.ok;
      if (sendEtag) request.response.headers.set(HttpHeaders.etagHeader, etag);
      request.response.add(manifest);
      await request.response.close();
      return;
    }

    packRequests++;
    final payload = packs[path.substring(1)];
    if (payload == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final range = request.headers.value(HttpHeaders.rangeHeader);
    lastRange = range;
    var start = 0;
    if (range != null) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      request.response.statusCode = HttpStatus.partialContent;
    } else {
      request.response.statusCode = HttpStatus.ok;
    }

    final body = payload.sublist(start);
    final cut = cutPackAfterBytes;
    if (cut != null && cut < body.length) {
      final socket = await request.response.detachSocket(writeHeaders: false);
      final status = start > 0 ? '206 Partial Content' : '200 OK';
      final contentRange = start > 0
          ? 'Content-Range: bytes $start-${payload.length - 1}/${payload.length}\r\n'
          : '';
      socket
        ..add(utf8.encode('HTTP/1.1 $status\r\n'
            'Content-Length: ${body.length}\r\n'
            '${contentRange}Accept-Ranges: bytes\r\n\r\n'))
        ..add(body.sublist(0, cut));
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      socket.destroy();
      return;
    }

    request.response.add(body);
    await request.response.close();
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late Directory tmp;
  late _Origin origin;
  late PackStore store;
  late SyncService service;
  var idle = true;

  /// Relógio do teste. O backoff exponencial da linha B14 é real; sem poder
  /// avançar o tempo, todo teste de retomada esbarraria nele e mediria a
  /// espera em vez do comportamento.
  var clock = DateTime.utc(2026, 8, 19, 12);
  void advance(Duration by) => clock = clock.add(by);

  // Constantes tiradas dos fixtures. Sao estaveis porque o packer honra
  // SOURCE_DATE_EPOCH — ver test/fixtures/sync/README.md.
  const packV1Url = 'packs/pack-204477cedcc9.db';
  const packV2Url = 'packs/pack-6a3a078f2e24.db';
  const packV1Hash =
      '204477cedcc9a0260bc8f4dcfedc6aa52cf341e8483eef9eb5b2a0545af1b32e';

  SyncService build({ManifestVerifier verifier = const ManifestVerifier(keys: _devKeys)}) =>
      SyncService(
        manifestUrl: origin.manifestUrl,
        store: store,
        quiescence: () => idle,
        verifier: verifier,
        manifestTimeout: const Duration(seconds: 5),
        now: () => clock,
      );

  setUp(() async {
    idle = true;
    clock = DateTime.utc(2026, 8, 19, 12);
    tmp = Directory.systemTemp.createTempSync('gubs_sync_');
    origin = _Origin()
      ..packs[packV1Url] = _fixture('pack-v1.db')
      ..packs[packV2Url] = _fixture('pack-v2.db');
    await origin.start();
    store = PackStore(Directory('${tmp.path}/packs'), verifier: const ManifestVerifier(keys: _devKeys));
    service = build();
  });

  tearDown(() async {
    service.close();
    await origin.stop();
    tmp.deleteSync(recursive: true);
  });

  /// Publica a v2: manifest novo e ETag novo, como o operador faria.
  void publishV2() {
    origin
      ..manifest = _fixture('manifest-v2.json')
      ..etag = 'v2';
  }

  group('caminho feliz', () {
    test('primeiro ciclo instala o pack e o deixa ativo', () async {
      final report = await service.runCycle();

      expect(report.state, SyncState.p0Steady);
      expect(report.committedVersion, 1);
      expect(
        report.rules,
        containsAllInOrder([
          startsWith('B1'),
          startsWith('B3'),
          startsWith('B8'),
          startsWith('B9'),
          startsWith('B11'),
          startsWith('B13'),
        ]),
      );

      final active = await store.loadActive();
      expect(active, isNotNull);
      expect(active!.manifest.packVersion, 1);
      expect(active.file.path, endsWith('pack-$packV1Hash.db'));
    });

    test('segundo ciclo recebe 304 e não baixa nada', () async {
      await service.runCycle();
      final packRequestsAfterInstall = origin.packRequests;

      final report = await service.runCycle();

      expect(report.rules, [startsWith('B1'), startsWith('B2')]);
      expect(origin.notModifiedResponses, 1);
      expect(
        origin.packRequests,
        packRequestsAfterInstall,
        reason: 'ETag existe para não gastar o plano de dados do usuário',
      );
      expect((await store.loadActive())!.manifest.packVersion, 1);
    });

    test('publicação de v2 substitui v1 e apaga o pack antigo', () async {
      await service.runCycle();
      final oldPack = store.packFile(packV1Hash);
      expect(oldPack.existsSync(), isTrue);

      publishV2();
      final report = await service.runCycle();

      expect(report.committedVersion, 2);
      expect((await store.loadActive())!.manifest.packVersion, 2);
      expect(
        oldPack.existsSync(),
        isFalse,
        reason: 'B13 manda remover vN — dois packs em aparelho de 8 GB é caro',
      );
    });
  });

  group('retomada — critério de saída da Fase 1', () {
    test('corte no meio do download preserva o parcial e retoma depois',
        () async {
      origin.cutPackAfterBytes = 40000;

      final interrupted = await service.runCycle();

      expect(interrupted.state, SyncState.f1Retryable);
      expect(interrupted.committed, isFalse);
      final partial = File('${store.packFile(packV1Hash).path}.parcial');
      expect(partial.existsSync(), isTrue);
      expect(partial.lengthSync(), 40000);
      expect(
        await store.loadActive(),
        isNull,
        reason: 'nada pode ficar ativo com o download pela metade',
      );

      // Rede volta, na janela seguinte.
      origin.cutPackAfterBytes = null;
      advance(const Duration(minutes: 10));
      final resumed = await service.runCycle();

      expect(resumed.committedVersion, 1);
      expect(
        origin.lastRange,
        'bytes=40000-',
        reason: 'retomar do zero num posto rural significa nunca terminar',
      );
      expect(partial.existsSync(), isFalse);
    });

    test('o ETag não é gravado com download em voo', () async {
      // Gravar o ETag no corte faria o servidor responder 304 no ciclo
      // seguinte — e a máquina perderia o manifest de que precisa para saber
      // o que estava retomando.
      origin.cutPackAfterBytes = 40000;
      await service.runCycle();

      expect(await store.readEtag(), isNull);

      origin.cutPackAfterBytes = null;
      advance(const Duration(minutes: 10));
      await service.runCycle();

      expect(await store.readEtag(), 'v1');
    });
  });

  group('nenhum pack inválido é ativado', () {
    test('manifest com assinatura adulterada não instala nada', () async {
      final json =
          jsonDecode(utf8.decode(_fixture('manifest-v1.json'))) as Map<String, Object?>;
      (json['pack']! as Map<String, Object?>)['sha256'] = 'c' * 64;
      origin.manifest = utf8.encode(jsonEncode(json));

      final report = await service.runCycle();

      expect(report.state, SyncState.f2Rejected);
      expect(report.rules, contains(startsWith('B4a')));
      expect(await store.loadActive(), isNull);
      expect(origin.packRequests, 0, reason: 'nem chegou a pedir o artefato');
      expect(
        await store.isManifestRejected(sha256OfBytes(origin.manifest)),
        isTrue,
      );
    });

    test('artefato adulterado é recusado e o packHash vai para a blacklist',
        () async {
      // Manifest autêntico, artefato trocado no espelho: o cenário exato que a
      // assinatura sozinha não cobre.
      origin.packs[packV1Url] = utf8.encode('conteudo clinico falso' * 1000);

      final report = await service.runCycle();

      expect(report.state, SyncState.f2Rejected);
      expect(report.rules, contains(startsWith('B10')));
      expect(await store.loadActive(), isNull);
      expect(await store.isPackRejected(packV1Hash), isTrue);
      expect(store.packFile(packV1Hash).existsSync(), isFalse);
    });

    test('artefato já recusado não é baixado de novo', () async {
      // Espelho sem ETag: sem o 304 para encurtar o caminho, é a blacklist em
      // disco que precisa impedir a segunda transferência.
      origin.sendEtag = false;
      origin.packs[packV1Url] = utf8.encode('conteudo clinico falso' * 1000);
      await service.runCycle();
      final requestsAfterFirst = origin.packRequests;

      // Serviço novo (processo reiniciado), mesma blacklist em disco.
      service.close();
      service = build();
      final report = await service.runCycle();

      expect(report.rules, contains(contains('memorizado')));
      expect(
        origin.packRequests,
        requestsAfterFirst,
        reason: 'rebaixar o mesmo artefato adulterado gasta dados por nada',
      );
    });

    test('downgrade é recusado mesmo com assinatura válida (INV-7)', () async {
      publishV2();
      await service.runCycle();
      expect((await store.loadActive())!.manifest.packVersion, 2);

      // Operador republica a v1 — ou um espelho serve um manifest antigo.
      origin
        ..manifest = _fixture('manifest-v1.json')
        ..etag = 'v1-again';
      final report = await service.runCycle();

      expect(report.state, SyncState.f2Rejected);
      expect(report.rules, contains(startsWith('B4b')));
      expect((await store.loadActive())!.manifest.packVersion, 2);
    });

    test('schema major não suportado espera binário novo', () async {
      final signer = await TestSigner.generate();
      origin.manifest = await signer.sign(manifestTemplate(schemaVersion: '9.0'));
      service.close();
      service = build(verifier: ManifestVerifier(keys: {'k1': signer.publicKeyHex}));

      final report = await service.runCycle();

      expect(report.state, SyncState.f2Rejected);
      expect(report.rules, contains(startsWith('B5')));
      expect(origin.packRequests, 0);
    });

    test('F2 não é poço: a versão seguinte resgata o ciclo (L2)', () async {
      origin.packs[packV1Url] = utf8.encode('conteudo clinico falso' * 1000);
      final rejected = await service.runCycle();
      expect(rejected.state, SyncState.f2Rejected);

      publishV2();
      final rescued = await service.runCycle();

      expect(rescued.rules, contains(startsWith('B16')));
      expect(rescued.committedVersion, 2);
    });
  });

  group('troca sob quiescência', () {
    test('triagem em curso adia a troca sem perder o download', () async {
      idle = false;

      final deferred = await service.runCycle();

      expect(deferred.state, SyncState.p4Staged);
      expect(deferred.rules, contains(startsWith('B12')));
      expect(
        await store.loadActive(),
        isNull,
        reason: 'a sessão em curso continua lendo o que já lia',
      );
      expect(store.packFile(packV1Hash).existsSync(), isTrue);

      idle = true;
      final committed = await service.runCycle();

      expect(committed.committedVersion, 1);
      expect(
        origin.packRequests,
        1,
        reason: 'o ciclo adiado não pode re-baixar o que já verificou',
      );
    });

    test('ciclo adiado não toca a rede', () async {
      idle = false;
      await service.runCycle();
      final requests = origin.manifestRequests;

      await service.runCycle();

      expect(origin.manifestRequests, requests);
    });
  });

  group('falhas de rede e circuito', () {
    test('servidor fora do ar deixa a máquina retentável, sem efeito algum',
        () async {
      origin.manifestStatus = 503;

      final report = await service.runCycle();

      expect(report.state, SyncState.f1Retryable);
      expect(await store.loadActive(), isNull);
    });

    test('cinco falhas na mesma janela abrem o circuito', () async {
      origin.manifestStatus = 503;
      service.beginWindow();

      for (var i = 0; i < 5; i++) {
        await service.runCycle();
        advance(const Duration(minutes: 5)); // backoff decorrido
      }

      expect(service.circuitOpen, isTrue);
      expect(service.state, SyncState.p0Steady);

      // Circuito aberto: o próximo ciclo não chega a tocar a rede.
      final requests = origin.manifestRequests;
      final blocked = await service.runCycle();
      expect(blocked.rules, isEmpty);
      expect(origin.manifestRequests, requests);

      // A janela seguinte do agendador solta o freio.
      service.beginWindow();
      expect(service.circuitOpen, isFalse);
    });

    test('o backoff impede martelar o servidor dentro da mesma janela',
        () async {
      origin.manifestStatus = 503;
      service.beginWindow();
      await service.runCycle();
      final requests = origin.manifestRequests;

      final tooSoon = await service.runCycle();

      expect(tooSoon.detail, contains('backoff'));
      expect(origin.manifestRequests, requests);
    });

    test('pack ativo sobrevive a servidor indisponível', () async {
      await service.runCycle();
      origin.manifestStatus = 500;
      advance(const Duration(minutes: 10));

      await service.runCycle();

      expect((await store.loadActive())!.manifest.packVersion, 1);
    });
  });

  group('recuperação a frio', () {
    test('processo morto antes do commit não deixa pack ativo pela metade',
        () async {
      idle = false;
      await service.runCycle(); // fica em P4_STAGED, sem commit
      service.close();

      // Processo novo: a memória do staging se foi, o arquivo verificado não.
      idle = true;
      service = build();
      final report = await service.runCycle();

      expect(report.committedVersion, 1);
      expect((await store.loadActive())!.manifest.packVersion, 1);
    });

    test('staging órfão de outra versão é removido', () async {
      await service.runCycle();
      final orphan = store.packFile('d' * 64)..writeAsBytesSync([1, 2, 3]);

      publishV2();
      await service.runCycle();

      expect(orphan.existsSync(), isFalse);
    });

    test('manifest ativo com assinatura quebrada em disco não é servido',
        () async {
      await service.runCycle();
      final onDisk = File('${store.directory.path}/manifest.json');
      final json = jsonDecode(await onDisk.readAsString()) as Map<String, Object?>;
      json['municipality'] = '9999999';
      await onDisk.writeAsString(jsonEncode(json));

      expect(
        await store.loadActive(),
        isNull,
        reason: 'INV-3: o cold start reconfere a assinatura do pack ativo',
      );
    });

    test('pack ativo trocado no disco é detectado pelo hash', () async {
      await service.runCycle();
      store.packFile(packV1Hash).writeAsBytesSync(utf8.encode('outro banco'));

      expect(await store.loadActive(), isNull);
    });
  });

  group('o que o sync entrega é o que a triagem consome', () {
    setUpAll(configureSqliteForTests);

    test('o pack ativo abre e produz um modelo de regras utilizável', () async {
      // Fecha o laço da Fase 1: itens 6 (packer), 7 (gate) e 9 (sync) usam o
      // MESMO arquivo. Um sync que instala algo que a triagem não consegue ler
      // passaria em todos os testes anteriores deste arquivo.
      await service.runCycle();
      final active = await store.loadActive();

      final Database db = openPack(active!.file.path);
      addTearDown(db.dispose);
      final model = loadRuleModel(db);

      expect(model.rules, isNotEmpty);
      expect(model.outcomes, isNotEmpty);
      expect(model.outcomes.keys, contains(model.defaultOutcomeId));
      expect(
        db.select('SELECT pack_version FROM pack_meta WHERE id = 1').first
            ['pack_version'],
        active.manifest.packVersion,
        reason: 'o pack_version de dentro do banco tem de bater com o assinado',
      );
    });
  });
}
