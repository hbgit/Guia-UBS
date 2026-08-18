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

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
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

  /// Quantas requisições recebeu — prova que a retomada não rebaixou.
  int requestCount = 0;

  /// Último cabeçalho Range recebido.
  String? lastRange;

  Uri get url => Uri.parse('http://${_server.address.host}:${_server.port}/m');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server.forEach(_handle));
  }

  Future<void> _handle(HttpRequest request) async {
    requestCount++;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    lastRange = range;

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
    if (cutAfterBytes != null && cutAfterBytes! < body.length) {
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
        ..add(utf8.encode('HTTP/1.1 $status\r\n'
            'Content-Length: ${body.length}\r\n'
            '${contentRange}Accept-Ranges: bytes\r\n\r\n'))
        ..add(body.sublist(0, cutAfterBytes!));
      await socket.flush();
      // Dá tempo de os bytes chegarem antes do RST.
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
    expect(dest().existsSync(), isFalse,
        reason: 'nao pode assumir o nome definitivo');
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
    expect(origin.lastRange, 'bytes=$saved-',
        reason: 'a segunda tentativa precisa pedir só o que falta');
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
    expect(partial().existsSync(), isFalse,
        reason: 'sem descartar, o download nunca mais completaria');
  });

  test('4xx é permanente; 5xx é transitório', () async {
    origin.forceStatus = HttpStatus.notFound;
    expect(
      await downloader.fetch(
          url: origin.url, destination: dest(), expectedSha256: goodHash),
      isA<DownloadRejected>(),
      reason: 'repetir um 404 nao vai fazer o recurso aparecer',
    );

    origin.forceStatus = HttpStatus.badGateway;
    expect(
      await downloader.fetch(
          url: origin.url, destination: dest(), expectedSha256: goodHash),
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
    expect(origin.requestCount, before,
        reason: 'nao pode rebaixar 1,2 GB à toa');
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
}
