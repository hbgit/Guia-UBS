/// Guarda de versão do release do app (ADR-009, itens 2 e 3; item 31 do
/// roadmap).
///
/// O `versionCode` é função do SemVer: `MAJOR*10000 + MINOR*100 + PATCH`, o
/// MESMO número em todo artefato da tag (APK por ABI e AAB). Este guarda roda
/// no workflow de release, antes do build:
///
/// ```sh
/// dart run tool/release_version.dart --tag v1.2.3
/// ```
///
/// Reprova se a tag não é `vX.Y.Z`, se o `version:` do `pubspec.yaml` não é
/// `X.Y.Z+<código da fórmula>`, ou se o código não é MAIOR que o da maior tag
/// `vX.Y.Z` já existente no repositório. A fonte é a tag, e não a Play nem o
/// GitHub Releases: é determinística, funciona offline, não depende de conta
/// nem de API, e as pre-releases contam, porque também têm tag.
///
/// Saída: 0 ok (imprime `versionCode=<n>`); 1 reprovado; 64 uso.
library;

import 'dart:io';

final RegExp _semver = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');
final RegExp _tag = RegExp(r'^v(\d+\.\d+\.\d+)$');

/// `MAJOR*10000 + MINOR*100 + PATCH`, ou [FormatException] fora dos limites.
///
/// MINOR e PATCH ≤ 99, porque a fórmula anda de 100 em 100. MAJOR ≤ 210,
/// porque a Play aceita `versionCode` até 2 100 000 000 (conferir no Play
/// Console na data da publicação). Sufixo (`-rc1`) não existe: pre-release é
/// uma tag como as outras, promovida sem rebuild (ADR-009, item 4).
int versionCodeFor(String semver) {
  final m = _semver.firstMatch(semver);
  if (m == null) {
    throw FormatException('versao "$semver" nao e MAJOR.MINOR.PATCH');
  }
  final [major, minor, patch] = [for (var i = 1; i <= 3; i++) int.parse(m[i]!)];
  if (minor > 99 || patch > 99) {
    throw FormatException(
        'versao "$semver": MINOR e PATCH vao ate 99 (ADR-009, item 3)');
  }
  if (major > 210) {
    throw FormatException(
        'versao "$semver": MAJOR vai ate 210 (teto do versionCode da Play)');
  }
  return major * 10000 + minor * 100 + patch;
}

/// Resultado de [checkRelease]: vazio em [problems] quer dizer que passou.
class ReleaseCheck {
  const ReleaseCheck({required this.problems, this.versionCode});

  final List<String> problems;
  final int? versionCode;
}

/// Confere a tag contra o `pubspec.yaml` e contra as tags existentes.
///
/// [existingTags] inclui a própria [tag], porque o workflow roda depois do
/// push dela; a comparação a exclui.
ReleaseCheck checkRelease({
  required String tag,
  required String pubspecVersion,
  required List<String> existingTags,
}) {
  final problems = <String>[];
  final t = _tag.firstMatch(tag);
  if (t == null) {
    return ReleaseCheck(problems: ['tag "$tag" nao e vX.Y.Z']);
  }
  final semver = t[1]!;
  final int code;
  try {
    code = versionCodeFor(semver);
  } on FormatException catch (e) {
    return ReleaseCheck(problems: [e.message]);
  }

  final esperado = '$semver+$code';
  if (pubspecVersion != esperado) {
    problems.add('pubspec.yaml tem version: $pubspecVersion; para a tag $tag '
        'precisa ser $esperado');
  }

  int? maior;
  String? maiorTag;
  for (final outra in existingTags) {
    if (outra == tag) continue;
    final m = _tag.firstMatch(outra);
    if (m == null) continue;
    final int c;
    try {
      c = versionCodeFor(m[1]!);
    } on FormatException {
      continue;
    }
    if (maior == null || c > maior) {
      maior = c;
      maiorTag = outra;
    }
  }
  if (maior != null && code <= maior) {
    problems.add('versionCode $code de $tag nao e maior que $maior, da tag '
        '$maiorTag ja existente');
  }
  return ReleaseCheck(problems: problems, versionCode: code);
}

String _pubspecVersion(String pubspec) {
  final m = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);
  return m?[1] ?? '';
}

Future<void> main(List<String> args) async {
  final i = args.indexOf('--tag');
  if (i < 0 || i + 1 >= args.length) {
    stderr.writeln('uso: dart run tool/release_version.dart --tag vX.Y.Z');
    exit(64);
  }
  final tag = args[i + 1];
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final tags = await Process.run('git', ['tag', '--list', 'v*']);
  if (tags.exitCode != 0) {
    stderr.writeln('FALHOU  git tag: ${tags.stderr}');
    exit(1);
  }
  final r = checkRelease(
    tag: tag,
    pubspecVersion: _pubspecVersion(pubspec),
    existingTags: '${tags.stdout}'
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList(),
  );
  if (r.problems.isNotEmpty) {
    for (final p in r.problems) {
      stderr.writeln('FALHOU  $p');
    }
    exit(1);
  }
  stdout.writeln('versionCode=${r.versionCode}');
}
