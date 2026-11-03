/// O `versionCode` do binário em execução, para a guarda B5b (ADR-009).
///
/// Existe como função, e não como valor guardado, porque o ciclo de sync roda
/// em dois isolates — o da UI e o do WorkManager — e nenhum dos dois pode
/// confiar em estado de memória do outro. Cada um pergunta à plataforma.
library;

import 'package:package_info_plus/package_info_plus.dart';

/// Devolve o build do binário, ou `null` quando ele não pode ser lido.
typedef AppBuildProbe = Future<int?> Function();

/// Lê o `versionCode` pelo `PackageInfo.buildNumber`.
///
/// **Nunca lança.** Falha de plataforma ou `buildNumber` não inteiro viram
/// `null`, e quem decide o que fazer com isso é o `SyncService` (ver
/// [appBuildSatisfies]).
Future<int?> readAppBuild() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber.trim());
  } on Object {
    return null;
  }
}

/// `minAppBuild <= appBuild`, com a regra para o build ilegível.
///
/// Sem saber o próprio build, o app só aceita o manifest que não exige build
/// nenhum (`minAppBuild <= 0`). Aceitar qualquer um poderia ativar um pack
/// que este binário não sabe ler; recusar todos, inclusive o que não impõe
/// mínimo, seria recusar sem motivo. A recusa é a da B5b — espera o binário,
/// sem blacklist e sem circuito —, então o pack ativo continua servindo.
bool appBuildSatisfies({required int minAppBuild, required int? appBuild}) =>
    appBuild == null ? minAppBuild <= 0 : minAppBuild <= appBuild;
