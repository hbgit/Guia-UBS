/// Conferência do mantenedor B no procedimento provisório de assinatura
/// (Revisão do ADR-001; plano B): baixa o que foi PUBLICADO e confere com o
/// MESMO código do app.
///
/// ```sh
/// dart run tool/verify_published.dart \
///   https://<CONTENT_DOMAIN>/content-packs/0000000/manifest.json <pub-hex> [keyId]
/// ```
///
/// Confere:
/// - a assinatura do manifest, com `ManifestVerifier` e a pública informada;
/// - o pack em `manifestUrl.resolve(pack.url)`: sha256 e tamanho;
/// - o `Cache-Control`: manifest com `max-age=60`, pack `immutable`;
/// - quando há `model`: a URL fica na origem do manifest ou no host do
///   `MODEL_URL` da exceção do ADR-004 (a regra de `resolveModelUri`), e um
///   HEAD devolve 200 com o tamanho do catálogo. Não baixa os 806 MB.
///
/// Saída: 0 ok; 1 problemas; 64 uso.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:guia_ubs/sync/manifest_verifier.dart';
import 'package:guia_ubs/sync/model_catalog.dart';
import 'package:guia_ubs/sync/model_source.dart';

import 'model_url_check.dart' show huggingFaceExceptionUrl;

/// Lista de problemas; vazia = publicado corretamente.
Future<List<String>> verifyPublished(
  Uri manifestUrl,
  String publicKeyHex, {
  String keyId = 'k1',
  HttpClient? client,
  String compiledModelUrl = huggingFaceExceptionUrl,
}) async {
  final http = client ?? HttpClient();
  final problems = <String>[];
  try {
    final (status, headers, bytes) = await _get(http, manifestUrl);
    if (status != 200) return ['manifest: HTTP $status em $manifestUrl'];
    final cc = headers.value(HttpHeaders.cacheControlHeader) ?? '';
    if (!cc.contains('max-age=60')) {
      problems.add('manifest: Cache-Control sem max-age=60 ("$cc")');
    }

    final outcome = await ManifestVerifier(keys: {keyId: publicKeyHex.trim()})
        .verify(bytes);
    if (outcome case ManifestRejected(:final reason, :final detail)) {
      return [
        ...problems,
        'manifest: assinatura/formato recusado (${reason.name}): $detail',
      ];
    }
    final manifest = (outcome as ManifestAccepted).manifest;

    final packUrl = manifestUrl.resolve(manifest.pack.url);
    final (pStatus, pHeaders, pBytes) = await _get(http, packUrl);
    if (pStatus != 200) {
      problems.add('pack: HTTP $pStatus em $packUrl');
    } else {
      final digest = sha256.convert(pBytes).toString();
      if (digest != manifest.pack.sha256) {
        problems.add('pack: sha256 $digest difere do manifest ${manifest.pack.sha256}');
      }
      if (pBytes.length != manifest.pack.bytes) {
        problems.add('pack: ${pBytes.length} bytes, manifest diz ${manifest.pack.bytes}');
      }
      final pcc = pHeaders.value(HttpHeaders.cacheControlHeader) ?? '';
      if (!pcc.contains('immutable')) {
        problems.add('pack: Cache-Control sem immutable ("$pcc")');
      }
    }

    final model = manifest.model;
    if (model != null) {
      final wanted = manifestUrl.resolve(model.url);
      final resolved = resolveModelUri(
        compiled: activeModel.withUrl(compiledModelUrl),
        fromManifest: model,
        manifestUrl: manifestUrl,
        requireHttps: manifestUrl.scheme == 'https',
      );
      if (resolved != wanted) {
        problems.add('model: $wanted recusada pelo app (sha diferente do '
            'catálogo, ou fora da origem do manifest e do host do MODEL_URL)');
      } else {
        final req = await http.headUrl(wanted);
        final res = await req.close();
        await res.drain<void>();
        if (res.statusCode != 200) {
          problems.add('model: HEAD HTTP ${res.statusCode} em $wanted');
        } else if (res.contentLength != activeModel.sizeBytes) {
          problems.add('model: Content-Length ${res.contentLength}, catálogo '
              'diz ${activeModel.sizeBytes}');
        }
        stdout.writeln('    model $wanted (sha ${model.sha256})');
      }
    }
  } on IOException catch (e) {
    problems.add('rede: $e');
  } finally {
    if (client == null) http.close(force: true);
  }
  return problems;
}

Future<(int, HttpHeaders, List<int>)> _get(HttpClient http, Uri url) async {
  final req = await http.getUrl(url);
  final res = await req.close();
  final body = <int>[];
  await res.forEach(body.addAll);
  return (res.statusCode, res.headers, body);
}

Future<void> main(List<String> args) async {
  if (args.length < 2 || args.length > 3) {
    stderr.writeln('uso: dart run tool/verify_published.dart '
        '<manifest-url> <pubkey-hex> [keyId]');
    exit(64);
  }
  final problems = await verifyPublished(
    Uri.parse(args[0]),
    args[1],
    keyId: args.length == 3 ? args[2] : 'k1',
  );
  if (problems.isEmpty) {
    stdout.writeln('ok  publicado e conferido: ${args[0]}');
    return;
  }
  for (final p in problems) {
    stderr.writeln('FALHA  $p');
  }
  exit(1);
}
