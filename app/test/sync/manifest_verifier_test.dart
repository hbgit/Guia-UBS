/// O verificador é a fronteira entre "bytes que alguém serviu" e "orientação
/// clínica que o app vai mostrar". Estes testes cobrem as formas de atravessar
/// essa fronteira sem autorização.
///
/// O primeiro grupo é o mais importante do arquivo: ele confere um manifest
/// assinado pelo **packer real, em Node**, contra o verificador em Dart. Se as
/// duas serializações canônicas divergirem em um byte, toda assinatura legítima
/// passa a parecer forjada e a frota inteira para de receber conteúdo — sem
/// nenhuma mensagem de erro que explique por quê.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/manifest_verifier.dart';
import 'package:guia_ubs/sync/pack_signing_keys.dart';

import '../support/manifest_signing.dart';

const Map<String, String> _devKeys = {'k1': devPackSigningKeyK1, 'k2': ''};

List<int> _fixture(String name) =>
    File('test/fixtures/sync/$name').readAsBytesSync();

void main() {
  const verifier = ManifestVerifier(keys: _devKeys);

  group('interoperabilidade com o packer (Node → Dart)', () {
    test('manifest assinado pelo packer real é aceito', () async {
      final outcome = await verifier.verify(_fixture('manifest-v1.json'));

      expect(
        outcome,
        isA<ManifestAccepted>(),
        reason: 'canonicalPayload em Dart divergiu de contract/src/manifest.ts',
      );
      final manifest = (outcome as ManifestAccepted).manifest;
      expect(manifest.packVersion, 1);
      expect(manifest.keyId, 'k1');
      expect(manifest.pack.sha256,
          '204477cedcc9a0260bc8f4dcfedc6aa52cf341e8483eef9eb5b2a0545af1b32e');
      expect(manifest.assets, hasLength(47));
      expect(manifest.isSchemaSupported, isTrue);
    });

    test('ordem das chaves no JSON não altera o veredito', () async {
      // O servidor, um proxy ou um espelho podem reserializar o JSON. Se a
      // canonicalização não fosse independente de ordem, um espelho honesto
      // quebraria a assinatura só por reescrever o arquivo.
      final original =
          jsonDecode(utf8.decode(_fixture('manifest-v1.json'))) as Map<String, Object?>;
      final reordered = Map<String, Object?>.fromEntries(
        original.entries.toList().reversed,
      );

      final outcome = await verifier.verify(utf8.encode(jsonEncode(reordered)));

      expect(outcome, isA<ManifestAccepted>());
    });

    test('os bytes guardados são os que chegaram, não uma reserialização',
        () async {
      // O cold start reconfere a assinatura (INV-3), e ela só fecha sobre os
      // bytes originais. Guardar uma versão nossa quebraria a próxima abertura.
      final bytes = _fixture('manifest-v1.json');
      final outcome = await verifier.verify(bytes);

      expect((outcome as ManifestAccepted).manifest.rawBytes, bytes);
    });
  });

  group('recusas', () {
    test('um byte alterado no conteúdo invalida a assinatura', () async {
      final json =
          jsonDecode(utf8.decode(_fixture('manifest-v1.json'))) as Map<String, Object?>;
      // Trocar o hash do pack é o ataque óbvio: aponta o app para outro arquivo
      // mantendo o resto do manifest intacto.
      (json['pack']! as Map<String, Object?>)['sha256'] = 'b' * 64;

      final outcome = await verifier.verify(utf8.encode(jsonEncode(json)));

      expect(outcome, isA<ManifestRejected>());
      expect((outcome as ManifestRejected).reason, ManifestRejection.badSignature);
    });

    test('campo extra não assinado é recusado', () async {
      // Prova que a verificação roda sobre o JSON cru: se tipássemos antes de
      // verificar, este campo sumiria dos bytes conferidos e passaria livre.
      final json =
          jsonDecode(utf8.decode(_fixture('manifest-v1.json'))) as Map<String, Object?>;
      json['mirrorHint'] = 'http://espelho-do-atacante.invalido';

      final outcome = await verifier.verify(utf8.encode(jsonEncode(json)));

      expect((outcome as ManifestRejected).reason, ManifestRejection.badSignature);
    });

    test('keyId desconhecido é recusado antes de qualquer criptografia',
        () async {
      final json =
          jsonDecode(utf8.decode(_fixture('manifest-v1.json'))) as Map<String, Object?>;
      (json['signature']! as Map<String, Object?>)['keyId'] = 'k9';

      final outcome = await verifier.verify(utf8.encode(jsonEncode(json)));

      expect((outcome as ManifestRejected).reason, ManifestRejection.unknownKey);
    });

    test('posição de rotação vazia não aceita qualquer assinatura', () async {
      // `k2` existe no mapa com valor vazio até a primeira rotação. Uma chave
      // vazia que "verifica" tudo seria um bypass completo da raiz de confiança.
      final signer = await TestSigner.generate();
      final bytes = await signer.sign(manifestTemplate(), keyId: 'k2');

      final outcome = await verifier.verify(bytes);

      expect((outcome as ManifestRejected).reason, ManifestRejection.unknownKey);
    });

    test('manifest sem bloco signature é recusado', () async {
      final outcome = await verifier.verify(utf8.encode(jsonEncode(manifestTemplate())));

      expect((outcome as ManifestRejected).reason, ManifestRejection.missingSignature);
    });

    test('algoritmo diferente de Ed25519 é recusado', () async {
      final outcome = await verifier.verify(
        utf8.encode(
          jsonEncode({
            ...manifestTemplate(),
            'signature': {'alg': 'RS256', 'keyId': 'k1', 'value': 'x'},
          }),
        ),
      );

      expect((outcome as ManifestRejected).reason, ManifestRejection.missingSignature);
    });

    test('JSON malformado não derruba o verificador', () async {
      final outcome = await verifier.verify(utf8.encode('{"schemaVersion":'));

      expect((outcome as ManifestRejected).reason, ManifestRejection.malformed);
    });
  });

  group('formato conferido depois da assinatura', () {
    late TestSigner signer;
    late ManifestVerifier own;

    setUp(() async {
      signer = await TestSigner.generate();
      own = ManifestVerifier(keys: {'k1': signer.publicKeyHex});
    });

    test('assinatura válida com sha256 fora do padrão é recusada', () async {
      final bytes = await signer.sign(
        manifestTemplate(packSha256: 'NAO-EH-HEX'),
      );

      final outcome = await own.verify(bytes);

      expect((outcome as ManifestRejected).reason, ManifestRejection.schemaViolation);
    });

    test('packVersion zero é recusado — o contrato exige positivo', () async {
      final bytes = await signer.sign(manifestTemplate(packVersion: 0));

      final outcome = await own.verify(bytes);

      expect((outcome as ManifestRejected).reason, ManifestRejection.schemaViolation);
    });

    test('schemaVersion de major não suportado é aceito e sinalizado', () async {
      // Recusar aqui perderia informação: a máquina precisa distinguir
      // "manifest de outro emissor" (recusa) de "manifest nosso, formato
      // futuro" (espera atualização do binário). A guarda é da FSM, não daqui.
      final bytes = await signer.sign(manifestTemplate(schemaVersion: '2.0'));

      final outcome = await own.verify(bytes);

      expect(outcome, isA<ManifestAccepted>());
      expect((outcome as ManifestAccepted).manifest.isSchemaSupported, isFalse);
    });
  });
}
