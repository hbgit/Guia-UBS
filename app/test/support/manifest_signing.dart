/// Assina manifests dentro do teste, com par Ed25519 descartável.
///
/// Existe para que os testes de guarda (versão, schema, formato) possam variar
/// o conteúdo livremente sem precisar da chave do packer. Note que ele usa o
/// MESMO `canonicalPayload` que o verificador — o que torna esses testes
/// consistentes consigo mesmos, mas incapazes de detectar divergência de
/// serialização com o TypeScript. Quem cobre isso é o teste do manifest real
/// assinado pelo packer, e é por isso que aquele teste não pode ser removido.
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:guia_ubs/sync/pack_manifest.dart';

class TestSigner {
  TestSigner._(this._keyPair, this.publicKeyHex);

  final SimpleKeyPair _keyPair;

  /// Hex dos 32 bytes crus, no formato que `packSigningKeys` espera.
  final String publicKeyHex;

  static Future<TestSigner> generate() async {
    final keyPair = await Ed25519().newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final hex = publicKey.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return TestSigner._(keyPair, hex);
  }

  /// Devolve os bytes do manifest com o bloco `signature` preenchido.
  Future<List<int>> sign(Map<String, Object?> manifest, {String keyId = 'k1'}) async {
    final payload = utf8.encode(canonicalPayload(manifest));
    final signature = await Ed25519().sign(payload, keyPair: _keyPair);
    return utf8.encode(
      jsonEncode({
        ...manifest,
        'signature': {
          'alg': 'Ed25519',
          'keyId': keyId,
          'value': base64Encode(signature.bytes),
        },
      }),
    );
  }
}

/// Manifest mínimo e válido, para ser modificado pelos testes.
Map<String, Object?> manifestTemplate({
  int packVersion = 2,
  String schemaVersion = '1.0',
  String packSha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  int packBytes = 1024,
  String packUrl = 'packs/pack-aaaaaaaaaaaa.db',
}) =>
    <String, Object?>{
      'schemaVersion': schemaVersion,
      'packVersion': packVersion,
      'municipality': '0000000',
      'pack': {'url': packUrl, 'sha256': packSha256, 'bytes': packBytes},
      'assets': <Object?>[],
      'minAppBuild': 1,
      'publishedAt': '2026-08-19',
    };
