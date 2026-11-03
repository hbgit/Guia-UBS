/// Guarda de versão do release (ADR-009, itens 2 e 3; item 31).
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/release_version.dart';

void main() {
  group('versionCodeFor', () {
    test('MAJOR*10000 + MINOR*100 + PATCH', () {
      expect(versionCodeFor('0.1.0'), 100);
      expect(versionCodeFor('1.2.3'), 10203);
      expect(versionCodeFor('210.99.99'), 2109999);
    });

    test('fora dos limites lança', () {
      // MINOR e PATCH andam de 100 em 100; MAJOR até 210 cabe no teto de
      // versionCode da Play (2 100 000 000).
      expect(() => versionCodeFor('1.100.0'), throwsFormatException);
      expect(() => versionCodeFor('1.0.100'), throwsFormatException);
      expect(() => versionCodeFor('211.0.0'), throwsFormatException);
      expect(() => versionCodeFor('1.2'), throwsFormatException);
      expect(() => versionCodeFor('1.2.3-rc1'), throwsFormatException);
    });
  });

  group('checkRelease', () {
    ReleaseCheck check(String tag, String pubspec, List<String> tags) =>
        checkRelease(tag: tag, pubspecVersion: pubspec, existingTags: tags);

    test('tag e pubspec coerentes, sem tag anterior: passa', () {
      final r = check('v1.2.3', '1.2.3+10203', const []);
      expect(r.problems, isEmpty);
      expect(r.versionCode, 10203);
    });

    test('tag que nao e vX.Y.Z reprova', () {
      expect(check('1.2.3', '1.2.3+10203', const []).problems, isNotEmpty);
      expect(check('v1.2', '1.2.0+10200', const []).problems, isNotEmpty);
    });

    test('pubspec com o +N fora da formula reprova', () {
      // O caso real de hoje: 0.1.0+1. O +N e o versionCode, e precisa ser a
      // formula, senao dois artefatos da mesma versao saem com codigos
      // diferentes conforme quem editou o pubspec.
      expect(check('v1.2.3', '1.2.3+1', const []).problems, isNotEmpty);
      expect(check('v1.2.3', '1.2.4+10204', const []).problems, isNotEmpty);
    });

    test('a propria tag ja existente nao conta contra ela', () {
      // O workflow roda DEPOIS do push da tag: ela ja esta na lista.
      expect(check('v1.2.3', '1.2.3+10203', const ['v1.2.3']).problems,
          isEmpty);
    });

    test('menor ou igual a maior tag existente reprova', () {
      expect(check('v1.2.9', '1.2.9+10209', const ['v1.3.0']).problems,
          isNotEmpty);
      expect(
          check('v1.2.3', '1.2.3+10203', const ['v1.2.4', 'v1.2.3']).problems,
          isNotEmpty);
    });

    test('pre-release conta: tem tag', () {
      expect(check('v1.2.5', '1.2.5+10205', const ['v1.2.4']).problems,
          isEmpty);
    });

    test('tags que nao sao vX.Y.Z sao ignoradas', () {
      expect(
          check('v0.1.0', '0.1.0+100', const ['experimento', 'v9.9']).problems,
          isEmpty);
    });
  });
}
