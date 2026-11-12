/// `tool/verify_published.dart` (plano B): o mantenedor B confere o que foi
/// PUBLICADO, pela rede, com o MESMO verificador do app — e não com uma
/// reimplementação que poderia concordar com um erro do assinador.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/model_catalog.dart';
import 'package:guia_ubs/sync/pack_signing_keys.dart';

import '../../tool/verify_published.dart';
import '../support/manifest_signing.dart';

/// Host de conteúdo de mentira: serve arquivos de [files] com os cabeçalhos
/// de cache do `Caddyfile.content`.
class _Host {
  final Map<String, List<int>> files = {};
  final Map<String, String> cacheControl = {};
  final Map<String, int> headLength = {};
  late HttpServer server;

  Uri url(String path) =>
      Uri.parse('http://${server.address.host}:${server.port}/$path');

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(server.forEach((r) async {
      final path = r.uri.path.substring(1);
      final cc = cacheControl[path] ??
          (path.endsWith('manifest.json')
              ? 'public, max-age=60, must-revalidate'
              : 'public, max-age=31536000, immutable');
      if (r.method == 'HEAD' && headLength.containsKey(path)) {
        r.response
          ..headers.set('cache-control', cc)
          ..contentLength = headLength[path]!;
        await r.response.close();
        return;
      }
      final body = files[path];
      if (body == null) {
        r.response.statusCode = 404;
      } else {
        r.response
          ..headers.set('cache-control', cc)
          ..contentLength = body.length;
        if (r.method != 'HEAD') r.response.add(body);
      }
      await r.response.close();
    }));
  }
}

void main() {
  late _Host host;
  setUp(() async {
    host = _Host();
    await host.start();
  });
  tearDown(() => host.server.close(force: true));

  const base = 'content-packs/0000000';
  Uri manifestUrl() => host.url('$base/manifest.json');

  void serveFixtureV1() {
    final manifest = File('test/fixtures/sync/manifest-v1.json').readAsBytesSync();
    final url = (jsonDecode(utf8.decode(manifest)) as Map)['pack']['url'] as String;
    host.files['$base/manifest.json'] = manifest;
    host.files['$base/$url'] = File('test/fixtures/sync/pack-v1.db').readAsBytesSync();
  }

  test('ok com a fixture e a chave de dev', () async {
    serveFixtureV1();
    expect(await verifyPublished(manifestUrl(), devPackSigningKeyK1), isEmpty);
  });

  test('pack adulterado reprova', () async {
    serveFixtureV1();
    final key = host.files.keys.firstWhere((k) => k.contains('0000000/packs/'));
    host.files[key] = [...host.files[key]!]..[0] ^= 0xff;
    final p = await verifyPublished(manifestUrl(), devPackSigningKeyK1);
    expect(p.join('\n'), contains('sha256'));
  });

  test('chave errada reprova', () async {
    serveFixtureV1();
    final p = await verifyPublished(manifestUrl(), 'a' * 64);
    expect(p.join('\n'), contains('assinatura'));
  });

  test('404 no pack reprova', () async {
    serveFixtureV1();
    host.files.removeWhere((k, _) => k.contains('0000000/packs/'));
    final p = await verifyPublished(manifestUrl(), devPackSigningKeyK1);
    expect(p.join('\n'), contains('404'));
  });

  test('manifest sem max-age=60 reprova', () async {
    serveFixtureV1();
    host.cacheControl['$base/manifest.json'] = 'public, max-age=31536000, immutable';
    final p = await verifyPublished(manifestUrl(), devPackSigningKeyK1);
    expect(p.join('\n'), contains('max-age=60'));
  });

  group('model', () {
    late TestSigner signer;
    final packBytes = utf8.encode('pack de teste');
    final packSha = sha256.convert(packBytes).toString();
    const packUrl = 'packs/pack-teste.db';

    Future<void> serveWithModel(String modelUrl) async {
      signer = await TestSigner.generate();
      host.files['$base/$packUrl'] = packBytes;
      host.files['$base/manifest.json'] = await signer.sign({
        ...manifestTemplate(
          packSha256: packSha,
          packBytes: packBytes.length,
          packUrl: packUrl,
        ),
        'model': {'url': modelUrl, 'sha256': activeModel.sha256},
      });
    }

    test('model na mesma origem com HEAD do tamanho certo passa', () async {
      await serveWithModel('../models/m.gguf');
      host.headLength['content-packs/models/m.gguf'] = activeModel.sizeBytes;
      expect(await verifyPublished(manifestUrl(), signer.publicKeyHex), isEmpty);
    });

    test('model em outra origem reprova', () async {
      await serveWithModel('https://terceiro.org/m.gguf');
      final p = await verifyPublished(manifestUrl(), signer.publicKeyHex);
      expect(p.join('\n'), contains('origem'));
    });

    test('model com tamanho errado reprova', () async {
      await serveWithModel('../models/m.gguf');
      host.headLength['content-packs/models/m.gguf'] = 10;
      final p = await verifyPublished(manifestUrl(), signer.publicKeyHex);
      expect(p.join('\n'), contains('Content-Length'));
    });
  });
}
