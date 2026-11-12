/// Guarda de build do `MODEL_URL` (P1-1, ADR-004).
///
/// O app não tem host padrão para o modelo. Isso só é seguro se o build que
/// esqueceu o `--dart-define`, ou que aponta para o lugar errado, falhar ANTES
/// de compilar — e não no aparelho de alguém.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/model_catalog.dart';
import 'package:guia_ubs/sync/pack_signing_keys.dart';

import '../../tool/model_url_check.dart';

void main() {
  final sha = activeModel.sha256;
  String problem(String? url, {bool release = true}) =>
      modelUrlProblem(url, release: release, expectedSha256: sha) ?? 'ok';

  test('ausente reprova', () {
    expect(problem(null, release: false), contains('MODEL_URL'));
    expect(problem('', release: false), contains('MODEL_URL'));
  });

  test('relativa reprova', () {
    expect(problem('models/x.gguf', release: false), contains('absoluta'));
  });

  test('http reprova no release', () {
    expect(
      problem('http://10.0.2.2:8081/content-packs/models/gemma-3-1b-it-Q4_K_M-$sha.gguf'),
      contains('https'),
    );
  });

  test('huggingface reprova: o modelo vem do storage proprio', () {
    expect(
      problem('https://huggingface.co/ggml-org/x/gemma-3-1b-it-Q4_K_M-$sha.gguf'),
      contains('storage proprio'),
    );
  });

  test('URL de outro modelo reprova e cita o hash esperado', () {
    expect(
      problem('https://edge.dominio-do-projeto-a-definir.org/content-packs/models/'
          'gemma-3-1b-it-Q4_K_M-${'0' * 64}.gguf'),
      contains(sha),
    );
  });

  // Fictício; o teste não faz rede. Trocar pelo domínio real quando a #55
  // decidir.
  test('https no storage proprio, com o hash do catalogo, passa', () {
    expect(
      problem('https://edge.dominio-do-projeto-a-definir.org/content-packs/models/'
          'gemma-3-1b-it-Q4_K_M-$sha.gguf'),
      'ok',
    );
  });

  group('excecao do huggingface.co (ADR-004)', () {
    test('a URL da excecao passa, no release', () {
      expect(problem(huggingFaceExceptionUrl), 'ok');
    });

    test('huggingface em resolve/main reprova: a excecao e uma revisao fixa', () {
      final main = huggingFaceExceptionUrl.replaceFirst(
          RegExp('resolve/[0-9a-f]{40}'), 'resolve/main');
      expect(main, isNot(huggingFaceExceptionUrl));
      expect(problem(main), contains('revisao fixa'));
    });

    test('outro repositorio do huggingface reprova', () {
      expect(problem(huggingFaceExceptionUrl.replaceFirst('ggml-org', 'outra-org')),
          contains('ADR-004'));
    });

    test('a excecao nao vale para outro modelo', () {
      expect(
        modelUrlProblem(huggingFaceExceptionUrl,
            release: true, expectedSha256: '0' * 64),
        contains('ADR-004'),
      );
    });

    test('a excecao e do modelo ativo', () {
      expect(huggingFaceExceptionSha256, activeModel.sha256);
    });
  });

  test('http passa fora do release (emulador em dev)', () {
    expect(
      problem('http://10.0.2.2:8081/content-packs/models/gemma-3-1b-it-Q4_K_M-$sha.gguf',
          release: false),
      'ok',
    );
  });

  // Fictício; o teste não faz rede. Trocar pelo domínio real quando a #55
  // decidir.
  const edge = 'edge.dominio-do-projeto-a-definir.org';
  const manifest = 'https://$edge/content-packs/0000000/manifest.json';

  group('PACK_MANIFEST_URL (#45)', () {
    String pack(String? url, {bool release = true}) =>
        packManifestUrlProblem(url, release: release) ?? 'ok';

    test('ausente reprova', () {
      expect(pack(null), contains('PACK_MANIFEST_URL'));
      expect(pack('', release: false), contains('PACK_MANIFEST_URL'));
    });

    test('relativa reprova', () {
      expect(pack('content-packs/0000000/manifest.json', release: false),
          contains('absoluta'));
    });

    test('http reprova no release', () {
      expect(pack('http://$edge/content-packs/0000000/manifest.json'),
          contains('https'));
    });

    test('host de exemplo reprova no release', () {
      expect(pack('https://conteudo.exemplo.invalid/content-packs/0000000/manifest.json'),
          contains('local ou reservado'));
    });

    test('servidor da rede local: passa em dev, reprova no release', () {
      const lan = 'http://192.168.0.10:8081/content-packs/0000000/manifest.json';
      expect(pack(lan, release: false), 'ok');
      expect(pack(lan), isNot('ok'));
    });

    test('https num host publico passa', () {
      expect(pack(manifest), 'ok');
    });

    test('caminho que nao e manifest.json reprova', () {
      expect(pack('https://$edge/content-packs/0000000/'), contains('manifest.json'));
    });
  });

  group('MODEL_URL em host reservado (#45)', () {
    test('o host do exemplo reprova no release', () {
      expect(
        problem('https://conteudo.exemplo.invalid/content-packs/models/'
            'gemma-3-1b-it-Q4_K_M-$sha.gguf'),
        contains('local ou reservado'),
      );
    });
  });

  group('mesmo host no release (#45)', () {
    const modelo = 'https://$edge/content-packs/models/gemma-3-1b-it-Q4_K_M-x.gguf';

    test('hosts diferentes reprovam citando os dois', () {
      final p = sameHostProblem(
          modelo, 'https://outro.dominio-do-projeto-a-definir.org/m/manifest.json',
          release: true);
      expect(p, contains(edge));
      expect(p, contains('outro.dominio-do-projeto-a-definir.org'));
    });

    test('mesmo host passa', () {
      expect(sameHostProblem(modelo, manifest, release: true), isNull);
    });

    test('a excecao do Hugging Face (ADR-004) nao exige mesmo host', () {
      expect(sameHostProblem(huggingFaceExceptionUrl, manifest, release: true),
          isNull);
    });

    test('fora do release, host nunca reprova', () {
      expect(
          sameHostProblem(modelo, 'http://10.0.2.2:8081/manifest.json',
              release: false),
          isNull);
    });
  });

  // Plano B, Task 1: sem PACK_SIGNING_KEY_K1, o release embarca a chave de
  // desenvolvimento — versionada no repositório — e aceitaria pack assinado
  // por qualquer pessoa que clonasse o projeto.
  group('packSigningKeyProblem', () {
    test('reprova ausente em release', () {
      expect(packSigningKeyProblem(null, release: true), isNotNull);
      expect(packSigningKeyProblem('', release: true), isNotNull);
    });

    test('reprova a chave de desenvolvimento em release', () {
      expect(
        packSigningKeyProblem(devPackSigningKeyK1, release: true),
        contains('desenvolvimento'),
      );
    });

    test('reprova formato', () {
      expect(packSigningKeyProblem('abc', release: true), isNotNull);
      expect(packSigningKeyProblem('a' * 63, release: true), isNotNull);
      expect(packSigningKeyProblem('${'a' * 63}g', release: true), isNotNull);
    });

    test('aceita hex de 64 que nao e a de dev', () {
      expect(packSigningKeyProblem('a' * 64, release: true), isNull);
    });

    test('debug aceita ausente', () {
      expect(packSigningKeyProblem(null, release: false), isNull);
    });

    test('o main reprova defines de release sem a chave', () {
      final tmp = Directory.systemTemp.createTempSync('gubs_k1_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final config = File('${tmp.path}/defines.release.json')
        ..writeAsStringSync(jsonEncode({
          'MODEL_URL': huggingFaceExceptionUrl,
          'PACK_MANIFEST_URL': 'https://edge.dominio-do-projeto-a-definir.org/'
              'content-packs/0000000/manifest.json',
        }));
      final r = Process.runSync('dart', [
        'run',
        'tool/model_url_check.dart',
        '--config',
        config.path,
        '--mode',
        'release',
      ]);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect('${r.stderr}', contains('PACK_SIGNING_KEY_K1'));
    });
  });
}
