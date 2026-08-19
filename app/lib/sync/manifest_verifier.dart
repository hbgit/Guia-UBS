/// Verificação Ed25519 do manifest.
///
/// Uma função e um resultado: bytes que chegaram do servidor entram, e ou sai
/// um [PackManifest] (que por construção já teve a assinatura conferida), ou
/// sai um motivo de recusa. Não há terceira saída, e não há como pedir a este
/// componente que "pule a verificação" — o caminho não existe.
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

import 'pack_manifest.dart';
import 'pack_signing_keys.dart';

/// Por que um manifest foi recusado. Todos são permanentes para *aqueles
/// bytes* — nenhum é resolvido tentando de novo (FSM-B → F2_REJECTED).
enum ManifestRejection {
  /// Não é JSON, ou não é um objeto JSON.
  malformed,

  /// Bloco `signature` ausente ou incompleto.
  missingSignature,

  /// `keyId` que este binário não conhece — ou chave rotacionada e aposentada,
  /// ou emissor que não é nosso.
  unknownKey,

  /// Assinatura não fecha sobre os bytes canônicos. Manifest adulterado em
  /// trânsito, espelho comprometido, ou divergência de serialização.
  badSignature,

  /// Assinatura válida, mas o conteúdo viola o contrato de formato.
  schemaViolation,
}

@immutable
sealed class ManifestOutcome {
  const ManifestOutcome();
}

/// Assinatura conferida e formato válido.
@immutable
final class ManifestAccepted extends ManifestOutcome {
  const ManifestAccepted(this.manifest);

  final PackManifest manifest;
}

@immutable
final class ManifestRejected extends ManifestOutcome {
  const ManifestRejected(this.reason, this.detail);

  final ManifestRejection reason;
  final String detail;
}

class ManifestVerifier {
  const ManifestVerifier({this.keys = packSigningKeys});

  /// `keyId` → chave pública em hex de 32 bytes. Injetável para os testes
  /// poderem assinar com par descartável sem tocar na chave de produção.
  final Map<String, String> keys;

  /// **Nunca lança.** Toda falha vira um [ManifestRejected].
  Future<ManifestOutcome> verify(List<int> bytes) async {
    final Map<String, Object?> json;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, Object?>) {
        return const ManifestRejected(
          ManifestRejection.malformed,
          'raiz do JSON não é objeto',
        );
      }
      json = decoded;
    } on Object catch (error) {
      return ManifestRejected(ManifestRejection.malformed, '$error');
    }

    final signature = json['signature'];
    if (signature is! Map<String, Object?>) {
      return const ManifestRejected(
        ManifestRejection.missingSignature,
        'campo signature ausente',
      );
    }
    final alg = signature['alg'];
    final keyId = signature['keyId'];
    final value = signature['value'];
    if (alg != 'Ed25519' || keyId is! String || value is! String) {
      return const ManifestRejected(
        ManifestRejection.missingSignature,
        'bloco signature incompleto ou algoritmo não suportado',
      );
    }

    // Chave vazia = posição de rotação não preenchida. Tratar como
    // desconhecida, e não como "aceita tudo".
    final publicKeyHex = keys[keyId];
    if (publicKeyHex == null || publicKeyHex.isEmpty) {
      return ManifestRejected(
        ManifestRejection.unknownKey,
        'keyId "$keyId" não está entre as chaves embarcadas',
      );
    }

    final List<int> publicKey;
    final List<int> signatureBytes;
    try {
      publicKey = _decodeHex(publicKeyHex);
      signatureBytes = base64Decode(value);
    } on Object catch (error) {
      return ManifestRejected(ManifestRejection.badSignature, '$error');
    }
    if (publicKey.length != 32 || signatureBytes.length != 64) {
      return const ManifestRejected(
        ManifestRejection.badSignature,
        'tamanho de chave ou de assinatura fora do padrão Ed25519',
      );
    }

    final payload = utf8.encode(canonicalPayload(json));
    final ok = await Ed25519().verify(
      payload,
      signature: Signature(
        signatureBytes,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!ok) {
      return const ManifestRejected(
        ManifestRejection.badSignature,
        'assinatura não confere com o payload canônico',
      );
    }

    // Só agora tipamos. Antes disso, tipar seria opinar sobre bytes que ainda
    // não sabíamos de quem eram.
    try {
      return ManifestAccepted(parseVerifiedManifest(json, bytes, keyId));
    } on ManifestFormatException catch (error) {
      return ManifestRejected(ManifestRejection.schemaViolation, error.message);
    }
  }
}

List<int> _decodeHex(String hex) {
  if (hex.length.isOdd) throw const FormatException('hex de comprimento ímpar');
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}
