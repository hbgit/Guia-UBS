/// Plano B (Q-B2): a URL do modelo pode vir do manifest ASSINADO, mas só vale
/// se for do MESMO modelo que este binário compilou e se ficar na origem do
/// manifest (ou no host do `MODEL_URL` embarcado). Sem a regra de origem, um
/// manifest assinado mandaria o IP do usuário a um terceiro host — e o
/// `docs/dados-do-usuario.md` §3 prometeria algo que o código não garante.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/model_catalog.dart';
import 'package:guia_ubs/sync/model_downloader.dart';
import 'package:guia_ubs/sync/model_source.dart';
import 'package:guia_ubs/sync/pack_manifest.dart';
import 'package:guia_ubs/sync/pack_store.dart';

void main() {
  final sha = activeModel.sha256;
  final manifestUrl =
      Uri.parse('https://h.org/content-packs/0000000/manifest.json');
  ModelArtifact compiled(String url) => ModelArtifact(
        url: url,
        sha256: sha,
        sizeBytes: activeModel.sizeBytes,
        fileName: activeModel.fileName,
      );
  const hf = 'https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/'
      'f9c28bcd85737ffc5aef028638d3341d49869c27/gemma-3-1b-it-Q4_K_M.gguf';

  Uri? resolve({
    String compiledUrl = hf,
    ManifestModel? model,
    bool requireHttps = true,
  }) =>
      resolveModelUri(
        compiled: compiled(compiledUrl),
        fromManifest: model,
        manifestUrl: manifestUrl,
        requireHttps: requireHttps,
      );

  test('sem manifest, usa o compilado', () {
    expect(resolve(), Uri.parse(hf));
  });

  test('usa a url do manifest quando o sha confere', () {
    final url = 'https://h.org/content-packs/models/m-$sha.gguf';
    expect(resolve(model: ManifestModel(url: url, sha256: sha)), Uri.parse(url));
  });

  test('ignora url de outro modelo', () {
    final outro = ManifestModel(
      url: 'https://h.org/content-packs/models/m.gguf',
      sha256: 'f' * 64,
    );
    expect(resolve(model: outro), Uri.parse(hf));
  });

  test('resolve url relativa contra o manifest', () {
    final rel = ManifestModel(url: '../models/x-$sha.gguf', sha256: sha);
    expect(
      resolve(model: rel),
      Uri.parse('https://h.org/content-packs/models/x-$sha.gguf'),
    );
  });

  test('recusa url insegura em release', () {
    final http = ManifestModel(url: 'http://h.org/m.gguf', sha256: sha);
    expect(resolve(model: http), Uri.parse(hf));
  });

  test('recusa url de outra origem', () {
    final terceiro =
        ManifestModel(url: 'https://terceiro.org/m-$sha.gguf', sha256: sha);
    expect(resolve(model: terceiro), Uri.parse(hf));
  });

  test('outra porta no mesmo host é outra origem', () {
    final porta =
        ManifestModel(url: 'https://h.org:8443/m-$sha.gguf', sha256: sha);
    expect(resolve(model: porta), Uri.parse(hf));
  });

  test('aceita o host do MODEL_URL compilado', () {
    const outroCaminho =
        'https://huggingface.co/ggml-org/outro-repo/resolve/abc/m.gguf';
    expect(
      resolve(model: ManifestModel(url: outroCaminho, sha256: sha)),
      Uri.parse(outroCaminho),
    );
  });

  test('sem manifest e sem MODEL_URL, devolve null', () {
    expect(resolve(compiledUrl: ''), isNull);
  });

  test('sem MODEL_URL, a url do manifest na mesma origem vale', () {
    final rel = ManifestModel(url: '../models/x-$sha.gguf', sha256: sha);
    expect(resolve(compiledUrl: '', model: rel), isNotNull);
  });

  group('effectiveModel', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('gubs_ms_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('effectiveModel não lança com store ilegível', () async {
      File('${tmp.path}/manifest.json').writeAsStringSync('{corrompido');

      final model = await effectiveModel(
        store: PackStore(tmp),
        manifestUrl: manifestUrl,
        compiled: compiled(hf),
      );

      expect(model.url, hf);
    });

    test('com o manifest ativo v3, usa a url dele e preserva a identidade',
        () async {
      // A fixture v3 referencia o "pack" sintético do job interop: os bytes
      // abaixo são exatamente os que o manifest declara.
      File('test/fixtures/sync/manifest-v3-model.json')
          .copySync('${tmp.path}/manifest.json');
      File('${tmp.path}/pack-ae18ca20d2650c79107692246d4989a9d33a82a13706c2bea18a81e2f2e03806.db')
          .writeAsStringSync(
              'guia-ubs: pack sintetico do job interop - NAO E CONTEUDO\n');

      final model = await effectiveModel(
        store: PackStore(tmp),
        manifestUrl: manifestUrl,
        compiled: compiled(hf),
      );

      expect(model.url,
          'https://h.org/content-packs/models/gemma-3-1b-it-Q4_K_M-$sha.gguf');
      expect(model.sha256, sha);
      expect(model.fileName, activeModel.fileName);
      expect(model.sizeBytes, activeModel.sizeBytes);
    });
  });
}
