/// A regra do build ilegível da guarda B5b (ADR-009).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/app_build.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test('build legível: minAppBuild <= appBuild, com a igualdade aceita', () {
    expect(appBuildSatisfies(minAppBuild: 10000, appBuild: 10000), isTrue);
    expect(appBuildSatisfies(minAppBuild: 9999, appBuild: 10000), isTrue);
    expect(appBuildSatisfies(minAppBuild: 999999, appBuild: 10000), isFalse);
  });

  test('build ilegível: só aceita o manifest que não exige build nenhum', () {
    expect(appBuildSatisfies(minAppBuild: 0, appBuild: null), isTrue);
    expect(appBuildSatisfies(minAppBuild: 1, appBuild: null), isFalse);
  });

  // "Nao recebe pack e nao diz por que" e o pior sintoma para diagnosticar a
  // distancia: o build ilegivel deixa uma linha explicita no logcat.
  test('build ilegivel por erro de plataforma: null e uma linha de log', () async {
    final linhas = <String>[];
    final build = await readAppBuild(
      info: () async => throw StateError('sem plataforma'),
      log: linhas.add,
    );
    expect(build, isNull);
    expect(linhas, hasLength(1));
    expect(linhas.single, contains('B5b'));
    expect(linhas.single, contains('sem plataforma'));
  });

  test('build ilegivel por buildNumber nao inteiro: null e uma linha de log',
      () async {
    final linhas = <String>[];
    final build = await readAppBuild(
      info: () async => PackageInfo(
          appName: 'x', packageName: 'x', version: '0.1.0', buildNumber: 'abc'),
      log: linhas.add,
    );
    expect(build, isNull);
    expect(linhas.single, contains('"abc"'));
  });

  test('build legivel: o numero, sem log', () async {
    final linhas = <String>[];
    final build = await readAppBuild(
      info: () async => PackageInfo(
          appName: 'x', packageName: 'x', version: '0.1.0', buildNumber: '100'),
      log: linhas.add,
    );
    expect(build, 100);
    expect(linhas, isEmpty);
  });
}
