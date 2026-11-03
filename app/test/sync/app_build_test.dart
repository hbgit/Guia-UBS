/// A regra do build ilegível da guarda B5b (ADR-009).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/app_build.dart';

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
}
