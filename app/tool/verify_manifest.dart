/// Confere, fora do `flutter test`, que um manifest assinado pelo packer é
/// aceito pelo verificador do app.
///
/// Existe por causa de um modo de falha silencioso: a serialização canônica
/// vive duas vezes, em `contract/src/manifest.ts` e em
/// `lib/sync/pack_manifest.dart`. Se alguém mudar uma e não a outra, os
/// fixtures versionados continuam passando — eles foram assinados pela versão
/// antiga e verificados pela versão antiga. A divergência só apareceria em
/// produção, como frota inteira parando de receber conteúdo sem erro visível.
///
/// Este script fecha essa janela assinando **agora** e verificando **agora**:
///
/// ```sh
/// openssl genpkey -algorithm ed25519 -out /tmp/ci.pem
/// openssl pkey -in /tmp/ci.pem -pubout -outform DER | tail -c 32 | xxd -p -c 32
/// PACK_SIGNING_KEY_PATH=/tmp/ci.pem npm run pack:build
/// dart run tool/verify_manifest.dart ../packer/out/manifest.json <hex>
/// ```
library;

import 'dart:io';

import 'package:guia_ubs/sync/manifest_verifier.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('uso: verify_manifest.dart <manifest.json> <chave-publica-hex>');
    exit(64);
  }

  final bytes = File(args[0]).readAsBytesSync();
  final verifier = ManifestVerifier(keys: {'k1': args[1].trim()});
  final outcome = await verifier.verify(bytes);

  switch (outcome) {
    case ManifestAccepted(:final manifest):
      stdout.writeln(
        'ok  manifest v${manifest.packVersion} aceito '
        '(${manifest.assets.length} assets, schema ${manifest.schemaVersion})',
      );
    case ManifestRejected(:final reason, :final detail):
      stderr.writeln('FALHA  ${reason.name}: $detail');
      if (reason == ManifestRejection.badSignature) {
        stderr.writeln(
          '       Serialização canônica divergiu entre '
          'contract/src/manifest.ts e lib/sync/pack_manifest.dart.',
        );
      }
      exit(1);
  }
}
