/// O `versionCode` do binário em execução, para a guarda B5b (ADR-009).
///
/// Existe como função, e não como valor guardado, porque o ciclo de sync roda
/// em dois isolates — o da UI e o do WorkManager — e nenhum dos dois pode
/// confiar em estado de memória do outro. Cada um pergunta à plataforma.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:package_info_plus/package_info_plus.dart';

/// Devolve o build do binário, ou `null` quando ele não pode ser lido.
typedef AppBuildProbe = Future<int?> Function();

/// Lê o `versionCode` pelo `PackageInfo.buildNumber`.
///
/// **Nunca lança.** Falha de plataforma ou `buildNumber` não inteiro viram
/// `null`, e quem decide o que fazer com isso é o `SyncService` (ver
/// [appBuildSatisfies]).
///
/// Quando vira `null`, deixa **uma linha explícita** no log ([log]; por
/// padrão o `debugPrint`, que também sai no logcat do release). O efeito é recusar todo
/// pack com `minAppBuild > 0`, e "não recebe pack e não diz por quê" é o pior
/// sintoma para diagnosticar à distância. A linha não leva dado da pessoa.
///
/// [info] existe para o teste; em produção é a plataforma.
Future<int?> readAppBuild({
  Future<PackageInfo> Function() info = PackageInfo.fromPlatform,
  void Function(String)? log,
}) async {
  final escreve = log ?? debugPrint;
  const prefixo = 'gubs-sync ERRO: build do app ilegivel; pack com '
      'minAppBuild > 0 sera recusado ate o app atualizar (B5b, ADR-009)';
  try {
    final buildNumber = (await info()).buildNumber.trim();
    final build = int.tryParse(buildNumber);
    if (build == null) escreve('$prefixo: buildNumber "$buildNumber"');
    return build;
  } on Object catch (e) {
    escreve('$prefixo: $e');
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
