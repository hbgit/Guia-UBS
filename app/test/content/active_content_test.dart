/// O laço entre `sync/` e `content/`: o que a FSM-B instala é o que as telas
/// leem, e a troca de versão não quebra ninguém.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/content/data/active_content.dart';
import 'package:guia_ubs/sync/manifest_verifier.dart';
import 'package:guia_ubs/sync/pack_signing_keys.dart';
import 'package:guia_ubs/sync/pack_store.dart';

import '../support/sqlite_test_libs.dart';

const Map<String, String> _devKeys = {'k1': devPackSigningKeyK1, 'k2': ''};

void main() {
  late Directory tmp;
  late PackStore store;
  late ActiveContent active;

  setUpAll(configureSqliteForTests);

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('gubs_active_');
    store = PackStore(
      Directory('${tmp.path}/packs'),
      verifier: const ManifestVerifier(keys: _devKeys),
    );
    await store.ensureDirectory();
    active = ActiveContent(store);
  });

  tearDown(() async {
    await active.close();
    tmp.deleteSync(recursive: true);
  });

  /// Instala uma versão como o sync faria: artefato no lugar, manifest ativo.
  Future<void> install(int version) async {
    final manifestBytes =
        File('test/fixtures/sync/manifest-v$version.json').readAsBytesSync();
    final outcome = await const ManifestVerifier(keys: _devKeys)
        .verify(manifestBytes);
    final manifest = (outcome as ManifestAccepted).manifest;

    File('test/fixtures/sync/pack-v$version.db')
        .copySync(store.packFile(manifest.pack.sha256).path);
    await store.commit(manifest);
  }

  test('sem pack instalado, o conteúdo simplesmente não existe', () async {
    await active.reload();

    expect(active.hasContent, isFalse);
    expect(active.repository, isNull);
    expect(active.packVersion, isNull);
  });

  test('depois do commit, as telas leem o pack instalado', () async {
    await install(1);

    await active.reload();

    expect(active.hasContent, isTrue);
    expect(active.packVersion, 1);
    expect(active.repository!.venues(), isNotEmpty);
  });

  test('reabrir depois da troca serve a versão nova', () async {
    // É a ação "reabre conexões" da linha B11 da FSM-B.
    await install(1);
    await active.reload();
    expect(active.packVersion, 1);

    await install(2);
    await active.reload();

    expect(active.packVersion, 2);
  });

  test('uma leitura em voo não vê arquivo trocado por baixo', () async {
    // Packs vivem nomeados pelo hash e o commit é um rename do manifest; no
    // POSIX, remover o arquivo antigo não invalida descritor já aberto. Uma
    // leitura que começou antes da troca termina no pack íntegro anterior —
    // é o que elimina a corrida S1 da espec, além do guard de quiescência.
    await install(1);
    await active.reload();
    final beforeSwap = active.repository!;

    await install(2);
    await store.dropUnreferenced();

    expect(beforeSwap.readPackInfo().packVersion, 1);
    expect(beforeSwap.venues(), isNotEmpty);
  });

  test('pack corrompido não derruba o app — só fica sem conteúdo', () async {
    await install(1);
    final info = await store.loadActive();
    // Trunca o arquivo mantendo o nome: simula disco com defeito.
    store.packFile(info!.manifest.pack.sha256).writeAsBytesSync([1, 2, 3]);

    await expectLater(active.reload(), completes);

    expect(active.hasContent, isFalse);
  });

  test('manifest adulterado em disco não serve conteúdo (INV-3)', () async {
    await install(1);
    File('${store.directory.path}/manifest.json')
        .writeAsStringSync('{"packVersion": 99}');

    await active.reload();

    expect(
      active.hasContent,
      isFalse,
      reason: 'conteúdo sem assinatura válida nunca chega ao usuário',
    );
  });

  test('recarregar duas vezes não vaza conexão nem quebra', () async {
    await install(1);

    await active.reload();
    await active.reload();
    await active.reload();

    expect(active.packVersion, 1);
    expect(active.repository!.venues(), isNotEmpty);
  });
}
