/// O downloader é a peça que decide o que entra no aparelho. Estes testes
/// cobrem os caminhos em que ele poderia aceitar algo que não devia, ou
/// destruir progresso que devia preservar.
///
/// O servidor é local e de brinquedo, mas implementa Range de verdade — sem
/// isso, "retomável" seria uma afirmação não verificada.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/destination_lock.dart';
import 'package:guia_ubs/sync/resumable_downloader.dart';

/// Servidor controlável: serve [payload] com suporte a Range, e permite forçar
/// os comportamentos hostis que a rede real produz.
class _FakeOrigin {
  _FakeOrigin(this.payload);

  final List<int> payload;
  late HttpServer _server;

  /// Ignora `Range` e devolve 200 com o corpo inteiro (proxies fazem isso).
  bool ignoreRange = false;

  /// Status a devolver em vez do normal.
  int? forceStatus;

  /// Corta a conexão após N bytes, simulando janela que fecha.
  int? cutAfterBytes;

  /// Com [cutAfterBytes], corta só a 1ª requisição; as seguintes vão inteiras.
  bool cutFirstRequestOnly = false;

  /// No modo [interleave], pausa entre blocos — dá tempo ao batimento da trava
  /// de perceber algo antes de o corpo acabar.
  Duration blockDelay = Duration.zero;

  /// Quantas requisições recebeu — prova que a retomada não rebaixou.
  int requestCount = 0;

  /// Último cabeçalho Range recebido.
  String? lastRange;

  /// Requisições simultâneas agora e o maior valor já visto.
  int inFlight = 0;
  int maxConcurrent = 0;

  /// Bytes de corpo efetivamente enviados (soma de todas as respostas).
  int bytesServed = 0;

  /// Cabeçalho Range de cada requisição, na ordem de chegada.
  final List<String?> ranges = [];

  /// Chamado ao receber cada requisição, antes da resposta: o ponto em que o
  /// teste pode mexer no mundo (ex.: tomar a trava) com o cliente já em voo.
  void Function()? onRequest;

  /// Força sobreposição: cada resposta espera a outra chegar (no máximo 3 s,
  /// para não travar com um só cliente) e envia o corpo em blocos de 4 KiB,
  /// cedendo o laço de eventos entre eles.
  bool interleave = false;
  final Completer<void> _twoInFlight = Completer<void>();

  Uri get url => Uri.parse('http://${_server.address.host}:${_server.port}/m');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server.forEach(_handle));
  }

  Future<void> _handle(HttpRequest request) async {
    requestCount++;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    lastRange = range;
    ranges.add(range);
    onRequest?.call();
    inFlight++;
    if (inFlight > maxConcurrent) maxConcurrent = inFlight;
    if (inFlight >= 2 && !_twoInFlight.isCompleted) _twoInFlight.complete();
    try {
      await _respond(request, range);
    } finally {
      inFlight--;
    }
  }

  Future<void> _respond(HttpRequest request, String? range) async {
    final cut =
        cutAfterBytes != null && (!cutFirstRequestOnly || requestCount == 1);
    if (forceStatus != null) {
      request.response.statusCode = forceStatus!;
      await request.response.close();
      return;
    }

    var start = 0;
    if (range != null && !ignoreRange) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      if (start >= payload.length) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.partialContent;
    } else {
      request.response.statusCode = HttpStatus.ok;
    }

    final body = payload.sublist(start);
    if (cut && cutAfterBytes! < body.length) {
      // Escrevemos a resposta na mão para cortar de forma determinística:
      // anunciamos o tamanho total, entregamos só uma parte e derrubamos a
      // conexão. É o que a perda de sinal faz — e o cliente precisa guardar
      // os bytes que chegaram.
      final socket = await request.response.detachSocket(writeHeaders: false);
      final status = start > 0 ? '206 Partial Content' : '200 OK';
      final contentRange = start > 0
          ? 'Content-Range: bytes $start-${payload.length - 1}/${payload.length}\r\n'
          : '';
      socket
        ..add(
          utf8.encode(
            'HTTP/1.1 $status\r\n'
            'Content-Length: ${body.length}\r\n'
            '${contentRange}Accept-Ranges: bytes\r\n\r\n',
          ),
        )
        ..add(body.sublist(0, cutAfterBytes!));
      await socket.flush();
      // Dá tempo de os bytes chegarem antes do RST.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      socket.destroy();
      return;
    }

    if (interleave) {
      await Future.any([
        _twoInFlight.future,
        Future<void>.delayed(const Duration(seconds: 3)),
      ]);
      const bloco = 4096;
      for (var i = 0; i < body.length; i += bloco) {
        final fim = i + bloco < body.length ? i + bloco : body.length;
        request.response.add(body.sublist(i, fim));
        bytesServed += fim - i;
        await request.response.flush();
        await Future<void>.delayed(blockDelay);
      }
      await request.response.close();
      return;
    }

    bytesServed += body.length;
    request.response.add(body);
    await request.response.close();
  }

  Future<void> stop() => _server.close(force: true);
}

/// Entrada do isolate escritor 'b': tem o próprio ResumableDownloader (e,
/// portanto, nenhuma trava em memória compartilhada com o isolate de origem).
Future<void> _fetchInIsolate(List<Object> args) async {
  final porta = args[0] as SendPort;
  final lines = <String>[];
  final dl = ResumableDownloader(
    idleTimeout: const Duration(seconds: 10),
    connectTimeout: const Duration(seconds: 10),
    writerLabel: 'b',
    trace: lines.add,
    writerWait: const Duration(seconds: 30),
  );
  try {
    final outcome = await dl.fetch(
      url: Uri.parse(args[1] as String),
      destination: File(args[2] as String),
      expectedSha256: args[3] as String,
    );
    porta.send([outcome.runtimeType.toString(), lines]);
  } catch (e) {
    // Sem isto o isolate morre calado e o `porta.first` do teste trava.
    porta.send(['erro', '$e', lines]);
  } finally {
    dl.close();
  }
}

void main() {
  late Directory tmp;
  late _FakeOrigin origin;
  late ResumableDownloader downloader;

  final payload = utf8.encode('GGUF' * 4096); // 16 KB determinísticos
  final goodHash = sha256.convert(payload).toString();

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('gubs_dl_');
    origin = _FakeOrigin(payload);
    await origin.start();
    downloader = ResumableDownloader(
      idleTimeout: const Duration(seconds: 5),
      connectTimeout: const Duration(seconds: 5),
    );
  });

  tearDown(() async {
    downloader.close();
    await origin.stop();
    tmp.deleteSync(recursive: true);
  });

  File dest() => File('${tmp.path}/modelo.gguf');
  File partial() => File('${tmp.path}/modelo.gguf.parcial');

  test('baixa e verifica um arquivo íntegro', () async {
    final outcome = await downloader.fetch(
      url: origin.url,
      destination: dest(),
      expectedSha256: goodHash,
    );

    expect(outcome, isA<DownloadCompleted>());
    expect(dest().readAsBytesSync(), payload);
    expect(partial().existsSync(), isFalse, reason: 'parcial deve sumir');
  });

  test('conteúdo com hash divergente é REJEITADO e descartado', () async {
    // Cenário de espelho comprometido: o servidor entrega algo diferente do
    // que o app espera. Aceitar seria pôr um modelo desconhecido para opinar
    // sobre saúde.
    final outcome = await downloader.fetch(
      url: origin.url,
      destination: dest(),
      expectedSha256: sha256.convert(utf8.encode('outra coisa')).toString(),
    );

    expect(outcome, isA<DownloadRejected>());
    expect(
      dest().existsSync(),
      isFalse,
      reason: 'nao pode assumir o nome definitivo',
    );
    expect(partial().existsSync(), isFalse, reason: 'bytes errados nao ficam');
  });

  test('retoma de onde parou, sem rebaixar o progresso', () async {
    origin.cutAfterBytes = 4096;
    final first = await downloader.fetch(
      url: origin.url,
      destination: dest(),
      expectedSha256: goodHash,
    );

    expect(first, isA<DownloadInterrupted>());
    final saved = (first as DownloadInterrupted).bytesSoFar;
    expect(saved, greaterThan(0), reason: 'progresso tem de sobreviver');
    expect(dest().existsSync(), isFalse);

    origin.cutAfterBytes = null;
    final second = await downloader.fetch(
      url: origin.url,
      destination: dest(),
      expectedSha256: goodHash,
    );

    expect(second, isA<DownloadCompleted>());
    expect(dest().readAsBytesSync(), payload);
    expect(
      origin.lastRange,
      'bytes=$saved-',
      reason: 'a segunda tentativa precisa pedir só o que falta',
    );
  });

  test('servidor que IGNORA Range não produz arquivo duplicado', () async {
    // Proxies e CDNs mal configurados respondem 200 com o corpo inteiro mesmo
    // com Range pedido. Anexar cegamente geraria um arquivo com prefixo
    // repetido.
    origin.cutAfterBytes = 4096;
    await downloader.fetch(
      url: origin.url,
      destination: dest(),
      expectedSha256: goodHash,
    );
    expect(partial().lengthSync(), greaterThan(0));

    origin.cutAfterBytes = null;
    origin.ignoreRange = true;
    final outcome = await downloader.fetch(
      url: origin.url,
      destination: dest(),
      expectedSha256: goodHash,
    );

    expect(outcome, isA<DownloadCompleted>());
    expect(dest().lengthSync(), payload.length);
  });

  test('parcial maior que o recurso (416) é descartado, não travado', () async {
    partial().writeAsBytesSync(List<int>.filled(payload.length + 10, 0));

    final outcome = await downloader.fetch(
      url: origin.url,
      destination: dest(),
      expectedSha256: goodHash,
    );

    expect(outcome, isA<DownloadInterrupted>());
    expect((outcome as DownloadInterrupted).bytesSoFar, 0);
    expect(
      partial().existsSync(),
      isFalse,
      reason: 'sem descartar, o download nunca mais completaria',
    );
  });

  test('4xx é permanente; 5xx é transitório', () async {
    origin.forceStatus = HttpStatus.notFound;
    expect(
      await downloader.fetch(
        url: origin.url,
        destination: dest(),
        expectedSha256: goodHash,
      ),
      isA<DownloadRejected>(),
      reason: 'repetir um 404 nao vai fazer o recurso aparecer',
    );

    origin.forceStatus = HttpStatus.badGateway;
    expect(
      await downloader.fetch(
        url: origin.url,
        destination: dest(),
        expectedSha256: goodHash,
      ),
      isA<DownloadInterrupted>(),
      reason: 'gateway ruim volta ao normal sozinho',
    );
  });

  test('arquivo já presente e íntegro não gera requisição', () async {
    dest().writeAsBytesSync(payload);
    final before = origin.requestCount;

    final outcome = await downloader.fetch(
      url: origin.url,
      destination: dest(),
      expectedSha256: goodHash,
    );

    expect(outcome, isA<DownloadCompleted>());
    expect(
      origin.requestCount,
      before,
      reason: 'nao pode rebaixar 1,2 GB à toa',
    );
  });

  test('arquivo presente porém corrompido é rebaixado', () async {
    // Corrupção em disco acontece. O nome definitivo não é garantia eterna.
    dest().writeAsBytesSync(utf8.encode('lixo'));

    final outcome = await downloader.fetch(
      url: origin.url,
      destination: dest(),
      expectedSha256: goodHash,
    );

    expect(outcome, isA<DownloadCompleted>());
    expect(dest().readAsBytesSync(), payload);
  });

  test('servidor inalcançável vira interrupção, nunca exceção', () async {
    final url = origin.url; // capturado antes: o endereço some ao fechar
    await origin.stop();

    final outcome = await downloader.fetch(
      url: url,
      destination: dest(),
      expectedSha256: goodHash,
    );

    expect(outcome, isA<DownloadInterrupted>());
  });

  group('rastro', () {
    late List<String> lines;
    late ResumableDownloader traced;
    File destM() => File('${tmp.path}/m.gguf');

    setUp(() {
      lines = [];
      traced = ResumableDownloader(
        idleTimeout: const Duration(seconds: 5),
        connectTimeout: const Duration(seconds: 5),
        writerLabel: 't',
        trace: lines.add,
      );
    });
    tearDown(() => traced.close());

    test('retomada registra o offset de partida', () async {
      File(
        '${destM().path}.parcial',
      ).writeAsBytesSync(payload.sublist(0, 4096));
      await traced.fetch(
        url: origin.url,
        destination: destM(),
        expectedSha256: goodHash,
      );
      expect(lines, contains('gubs-dl w=t inicio off=4096 destino=m.gguf'));
      expect(lines.any((l) => l.startsWith('gubs-dl w=t sha ok')), isTrue);
      expect(
        lines,
        contains('gubs-dl w=t fim desfecho=Completed bytes=${payload.length}'),
      );
    });

    test('download solitário não acusa anomalia', () async {
      await traced.fetch(
        url: origin.url,
        destination: destM(),
        expectedSha256: goodHash,
      );
      expect(lines.any((l) => l.contains('ANOMALIA')), isFalse);
    });

    test('retomada solitária não acusa anomalia', () async {
      File(
        '${destM().path}.parcial',
      ).writeAsBytesSync(payload.sublist(0, 4096));
      await traced.fetch(
        url: origin.url,
        destination: destM(),
        expectedSha256: goodHash,
      );
      expect(lines.any((l) => l.contains('ANOMALIA')), isFalse);
    });

    test('sha registra a duração', () async {
      await traced.fetch(
        url: origin.url,
        destination: destM(),
        expectedSha256: goodHash,
      );
      expect(
        lines.any(
          (l) => RegExp(r'^gubs-dl w=t sha ok bytes=\d+ ms=\d+$').hasMatch(l),
        ),
        isTrue,
      );
    });

    test('hash divergente aparece no rastro', () async {
      await traced.fetch(
        url: origin.url,
        destination: destM(),
        expectedSha256: '00' * 32,
      );
      expect(
        lines.any((l) => l.startsWith('gubs-dl w=t sha divergente')),
        isTrue,
      );
      expect(lines.any((l) => l.contains('fim desfecho=Rejected')), isTrue);
    });
  });

  group('dois escritores no mesmo destino', () {
    final grande = List<int>.generate(1 << 18, (i) => (i * 31) & 0xff);
    final hashGrande = sha256.convert(grande).toString();
    const semente = 65536;
    late _FakeOrigin big;
    late List<String> lines;
    late File destino;
    late File parcial;

    setUp(() async {
      big = _FakeOrigin(grande)..interleave = true;
      await big.start();
      lines = [];
      destino = File('${tmp.path}/g.gguf');
      parcial = File('${destino.path}.parcial')
        ..writeAsBytesSync(grande.sublist(0, semente));
    });
    tearDown(() => big.stop());

    ResumableDownloader novo(String label) => ResumableDownloader(
      idleTimeout: const Duration(seconds: 10),
      connectTimeout: const Duration(seconds: 10),
      writerLabel: label,
      trace: lines.add,
      // OS DOIS esperam: com espera só em `b`, quem vencesse a corrida pela
      // trava decidiria o desfecho, e o teste oscilaria mesmo com a trava
      // certa. Espera zero = desistir, e isso é o grupo `escritor unico`.
      writerWait: const Duration(seconds: 30),
    );

    void garantias(List<String> desfechos) {
      expect(desfechos, everyElement('DownloadCompleted'));
      expect(sha256.convert(destino.readAsBytesSync()).toString(), hashGrande);
      expect(parcial.existsSync(), isFalse);
      expect(big.maxConcurrent, 1);
      expect(big.bytesServed, grande.length - semente);
      expect(big.ranges, isNot(contains(null)));
      expect(big.ranges, isNot(contains('bytes=0-')));
      expect(lines.any((l) => l.contains('ANOMALIA')), isFalse);
    }

    test('mesmo isolate: um baixa, o outro aceita o mesmo arquivo', () async {
      final a = novo('a');
      final b = novo('b');
      addTearDown(a.close);
      addTearDown(b.close);
      final r = await Future.wait([
        a.fetch(url: big.url, destination: destino, expectedSha256: hashGrande),
        b.fetch(url: big.url, destination: destino, expectedSha256: hashGrande),
      ]);
      garantias([for (final o in r) o.runtimeType.toString()]);
    });

    test('outro isolate (Isolate.spawn): mesmas garantias', () async {
      final a = novo('a');
      addTearDown(a.close);
      final porta = ReceivePort();
      addTearDown(porta.close);
      await Isolate.spawn(_fetchInIsolate, <Object>[
        porta.sendPort,
        big.url.toString(),
        destino.path,
        hashGrande,
      ]);
      final doB = porta.first;
      final oa = await a.fetch(
        url: big.url,
        destination: destino,
        expectedSha256: hashGrande,
      );
      final rb = await doB as List<Object?>;
      if (rb[0] == 'erro') fail('isolate b falhou: ${rb[1]}');
      lines.addAll((rb[1] as List).cast<String>());
      garantias([oa.runtimeType.toString(), rb[0] as String]);
    });
  });

  group('escritor unico', () {
    final grande = List<int>.generate(1 << 18, (i) => (i * 31) & 0xff);
    final hashGrande = sha256.convert(grande).toString();
    const semente = 65536;
    late _FakeOrigin big;
    late List<String> lines;
    late File destino;
    late File parcial;

    setUp(() async {
      big = _FakeOrigin(grande);
      await big.start();
      lines = [];
      destino = File('${tmp.path}/g.gguf');
      parcial = File('${destino.path}.parcial')
        ..writeAsBytesSync(grande.sublist(0, semente));
    });
    tearDown(() => big.stop());

    ResumableDownloader novo(
      String label, {
      Duration writerWait = Duration.zero,
      LockTiming lockTiming = const LockTiming(),
      Future<String> Function(File file)? digestOf,
    }) {
      final d = ResumableDownloader(
        idleTimeout: const Duration(seconds: 10),
        connectTimeout: const Duration(seconds: 10),
        writerLabel: label,
        trace: lines.add,
        writerWait: writerWait,
        lockTiming: lockTiming,
        digestOf: digestOf,
      );
      addTearDown(d.close);
      return d;
    }

    Future<DestinationLock> segura() async {
      final lock = (await DestinationLock.acquire(destino))!;
      addTearDown(lock.release);
      return lock;
    }

    void usurpa() =>
        DestinationLock.fileFor(destino).writeAsStringSync('1:alheio');

    test('quem desiste não toca no parcial', () async {
      await segura();
      final antes = parcial.statSync();

      final outcome = await novo(
        'w',
      ).fetch(url: big.url, destination: destino, expectedSha256: hashGrande);

      expect(outcome, isA<DownloadInterrupted>());
      outcome as DownloadInterrupted;
      expect(outcome.reason, contains('outro escritor'));
      expect(outcome.bytesSoFar, semente);
      final depois = parcial.statSync();
      expect(depois.size, antes.size);
      expect(depois.modified, antes.modified);
      expect(big.requestCount, 0);
      expect(lines, contains('gubs-dl w=w trava ocupada desiste'));
    });

    test('quem espera retoma do offset em disco', () async {
      big
        ..cutAfterBytes = 32768
        ..cutFirstRequestOnly = true;
      final aComecou = Completer<void>();
      final fa = novo('a').fetch(
        url: big.url,
        destination: destino,
        expectedSha256: hashGrande,
        onProgress: (_, _) {
          if (!aComecou.isCompleted) aComecou.complete();
        },
      );
      // Só depois do 1º progresso de A: aí A certamente detém a trava.
      await aComecou.future;
      final fb = novo(
        'b',
        writerWait: const Duration(seconds: 5),
      ).fetch(url: big.url, destination: destino, expectedSha256: hashGrande);

      expect(await fa, isA<DownloadInterrupted>());
      expect(await fb, isA<DownloadCompleted>());
      expect(big.ranges, ['bytes=65536-', 'bytes=98304-']);
      expect(sha256.convert(destino.readAsBytesSync()).toString(), hashGrande);
    });

    test('espera reporta progresso do parcial alheio', () async {
      final lock = await segura();
      // Só conta o que chegou ANTES de a trava ser solta: depois dela, o
      // próprio `_download` reporta (65536, total) ao começar, e o teste
      // passaria mesmo sem `onWaiting`.
      final antesDeSoltar = <(int, int)>[];
      final calls = <(int, int)>[];
      var solta = false;
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 100), () async {
          solta = true;
          await lock.release();
        }),
      );

      final outcome = await novo('w', writerWait: const Duration(seconds: 1))
          .fetch(
            url: big.url,
            destination: destino,
            expectedSha256: hashGrande,
            fallbackTotalBytes: grande.length,
            onProgress: (r, t) {
              calls.add((r, t));
              if (!solta) antesDeSoltar.add((r, t));
            },
          );

      expect(outcome, isA<DownloadCompleted>());
      expect(
        antesDeSoltar,
        contains((semente, grande.length)),
        reason: 'a espera precisa mostrar o disco do outro escritor',
      );
      expect(big.requestCount, 1);
      final alheio = calls.indexOf((semente, grande.length));
      final primeiroMaior = calls.indexWhere((c) => c.$1 > semente);
      expect(alheio, greaterThanOrEqualTo(0), reason: '$calls');
      expect(primeiroMaior, greaterThan(alheio), reason: '$calls');
    });

    final naoLinux = !Platform.isLinux;
    final root =
        !naoLinux &&
        Process.runSync('id', ['-u']).stdout.toString().trim() == '0';
    test(
      'sem trava, nada é escrito',
      () async {
        final ro = Directory('${tmp.path}/ro')..createSync();
        Process.runSync('chmod', ['0555', ro.path]);
        addTearDown(() => Process.runSync('chmod', ['0755', ro.path]));
        final alvo = File('${ro.path}/m.gguf');

        final outcome = await novo(
          'w',
        ).fetch(url: big.url, destination: alvo, expectedSha256: hashGrande);

        expect(outcome, isA<DownloadInterrupted>());
        expect(File('${alvo.path}.parcial').existsSync(), isFalse);
        expect(big.requestCount, 0);
      },
      skip: naoLinux
          ? 'chmod/0555 só no Linux'
          : root
          ? 'root ignora 0555'
          : false,
    );

    test('cerca: trava perdida no meio interrompe sem renomear', () async {
      big
        ..interleave = true
        ..blockDelay = const Duration(milliseconds: 5);
      var usurpada = false;

      final outcome =
          await novo(
            'w',
            lockTiming: const LockTiming(heartbeat: Duration(milliseconds: 20)),
          ).fetch(
            url: big.url,
            destination: destino,
            expectedSha256: hashGrande,
            onProgress: (_, _) {
              if (!usurpada) {
                usurpada = true;
                usurpa();
              }
            },
          );

      expect(outcome, isA<DownloadInterrupted>());
      // A cerca do laço, não a conferência antes do rename: a escrita parou
      // no meio do corpo.
      expect(
        (outcome as DownloadInterrupted).reason,
        contains('trava perdida'),
      );
      expect(destino.existsSync(), isFalse);
    });

    test('trava usurpada durante o hash: não renomeia', () async {
      parcial.deleteSync();
      final outcome = await novo(
        'w',
        // Batimento lento: só o `confirmHeld()` antes do rename pode pegar.
        lockTiming: const LockTiming(heartbeat: Duration(seconds: 10)),
        digestOf: (f) async {
          usurpa();
          return sha256.convert(f.readAsBytesSync()).toString();
        },
      ).fetch(url: big.url, destination: destino, expectedSha256: hashGrande);

      expect(outcome, isA<DownloadInterrupted>());
      expect(destino.existsSync(), isFalse);
      expect(parcial.readAsBytesSync(), grande, reason: 'parcial intacto');
    });

    test(
      'trava usurpada durante o hash do atalho sem rede: não renomeia',
      () async {
        // Parcial completo (pendrive, ou app morto antes do rename): o atalho
        // confere o hash sem rede. A conferência antes do rename vale aqui
        // também.
        parcial.writeAsBytesSync(grande);
        final outcome =
            await novo(
              'w',
              lockTiming: const LockTiming(heartbeat: Duration(seconds: 10)),
              digestOf: (f) async {
                usurpa();
                return sha256.convert(f.readAsBytesSync()).toString();
              },
            ).fetch(
              url: big.url,
              destination: destino,
              expectedSha256: hashGrande,
              fallbackTotalBytes: grande.length,
            );

        expect(outcome, isA<DownloadInterrupted>());
        expect(destino.existsSync(), isFalse);
        expect(parcial.readAsBytesSync(), grande, reason: 'parcial intacto');
        expect(big.requestCount, 0);
      },
    );

    test('dono com hash mais lento que staleAfter mantém a trava', () async {
      const timing = LockTiming(
        staleAfter: Duration(milliseconds: 300),
        heartbeat: Duration(milliseconds: 50),
        // `acquire` só confere o prazo entre tentativas: com o `poll` padrão
        // (500 ms) o intruso tentaria de novo em 1 s, já depois do dono.
        poll: Duration(milliseconds: 50),
      );
      final hashing = Completer<void>();
      final fa = novo(
        'a',
        lockTiming: timing,
        digestOf: (f) async {
          if (!hashing.isCompleted) hashing.complete();
          // 3× staleAfter, cedendo o laço de eventos como o hash real cede.
          await Future<void>.delayed(const Duration(milliseconds: 900));
          return sha256.convert(f.readAsBytesSync()).toString();
        },
      ).fetch(url: big.url, destination: destino, expectedSha256: hashGrande);

      await hashing.future;
      final intruso = await DestinationLock.acquire(
        destino,
        wait: const Duration(milliseconds: 600),
        timing: timing,
      );
      await intruso?.release();

      expect(intruso, isNull, reason: 'o dono está vivo, só calculando hash');
      expect(await fa, isA<DownloadCompleted>());
    });

    // Cerca antes dos ramos DESTRUTIVOS: quem perdeu a trava não apaga o
    // `.parcial` nem devolve `Rejected` — o hash divergente pode ser o do
    // arquivo que o novo dono ainda escreve, e no pack o `Rejected` poria um
    // artefato legítimo na lista negra.
    const hashErrado =
        '0000000000000000000000000000000000000000000000000000000000000000';

    test(
      'trava usurpada antes de recusar hash divergente: não apaga',
      () async {
        final outcome = await novo(
          'w',
          lockTiming: const LockTiming(heartbeat: Duration(seconds: 10)),
          digestOf: (f) async {
            usurpa();
            return sha256.convert(f.readAsBytesSync()).toString();
          },
        ).fetch(url: big.url, destination: destino, expectedSha256: hashErrado);

        expect(outcome, isA<DownloadInterrupted>());
        expect((outcome as DownloadInterrupted).reason, contains('usurpada'));
        expect(parcial.readAsBytesSync(), grande, reason: 'parcial intacto');
        expect(destino.existsSync(), isFalse);
      },
    );

    test(
      'trava usurpada antes de recusar no atalho sem rede: não apaga',
      () async {
        parcial.writeAsBytesSync(grande);
        final outcome =
            await novo(
              'w',
              lockTiming: const LockTiming(heartbeat: Duration(seconds: 10)),
              digestOf: (f) async {
                usurpa();
                return sha256.convert(f.readAsBytesSync()).toString();
              },
            ).fetch(
              url: big.url,
              destination: destino,
              expectedSha256: hashErrado,
              fallbackTotalBytes: grande.length,
            );

        expect(outcome, isA<DownloadInterrupted>());
        expect((outcome as DownloadInterrupted).reason, contains('usurpada'));
        expect(parcial.readAsBytesSync(), grande, reason: 'parcial intacto');
        expect(big.requestCount, 0);
      },
    );

    test('trava usurpada antes do 416: não apaga o parcial', () async {
      final maior = List<int>.filled(grande.length + 10, 7);
      parcial.writeAsBytesSync(maior);
      big.onRequest = usurpa;

      final outcome = await novo(
        'w',
        lockTiming: const LockTiming(heartbeat: Duration(seconds: 10)),
      ).fetch(url: big.url, destination: destino, expectedSha256: hashGrande);

      expect(outcome, isA<DownloadInterrupted>());
      expect((outcome as DownloadInterrupted).reason, contains('usurpada'));
      expect(parcial.readAsBytesSync(), maior, reason: 'parcial intacto');
      expect(big.ranges, ['bytes=${maior.length}-']);
    });

    test('destino já verificado: worker conclui sem rede', () async {
      destino.writeAsBytesSync(grande);

      final outcome = await novo(
        'worker',
      ).fetch(url: big.url, destination: destino, expectedSha256: hashGrande);

      expect(outcome, isA<DownloadCompleted>());
      expect(big.requestCount, 0);
    });
  });
}
