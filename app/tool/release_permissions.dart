/// Lista fechada das permissões do APK release (LGPD-RF01, "permissões
/// mínimas").
///
/// Existe por causa da P0-1: `INTERNET` só estava em `src/debug` e
/// `src/profile`, e o release saía sem rede — sem pack e sem modelo — sem que
/// nada reprovasse. Quem olhava o build de debug via a permissão lá.
///
/// "Exatamente" vale nos dois sentidos: permissão a mais (um plugin novo, uma
/// linha no manifest) reprova, e permissão que some também. A justificativa de
/// cada uma das herdadas de plugins é mantida pela #28 (P3-3); aqui só se fecha
/// a lista.
///
/// Mora em `tool/`, e não em `lib/`, porque não vai para o APK. A lógica é pura
/// e testada em `test/tool/` sem build; quem a aplica ao manifest mesclado de
/// verdade é `check_release_permissions.dart`, que exige o build de release.
library;

import 'package:xml/xml.dart';

/// As oito permissões que o APK release pode pedir. Nenhuma a mais, nenhuma a
/// menos.
const Set<String> releasePermissionAllowlist = {
  // As duas únicas chamadas de rede: manifest/pack e modelo SLM (ADR-003).
  'android.permission.INTERNET',
  // connectivity_plus.
  'android.permission.ACCESS_NETWORK_STATE',
  // workmanager (androidx.work).
  'android.permission.POST_NOTIFICATIONS',
  'android.permission.FOREGROUND_SERVICE',
  'android.permission.FOREGROUND_SERVICE_SHORT_SERVICE',
  'android.permission.WAKE_LOCK',
  'android.permission.RECEIVE_BOOT_COMPLETED',
  // androidx.core, para receivers dinâmicos não exportados (API 33+).
  'br.gov.exemplo.guia_ubs.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION',
};

/// Manifest mesclado de release no AGP 9.0.1, relativo a `app/`.
///
/// É caminho INTERNO do AGP (mudou entre o 7 e o 8). Nunca o de debug: ele tem
/// `INTERNET` via `src/debug` e passaria com o release quebrado — a armadilha
/// que criou a P0-1.
const String defaultReleaseManifestPath = 'build/app/intermediates/'
    'merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml';

/// Fonte do manifest principal, relativa a `app/`.
const String mainManifestSourcePath = 'android/app/src/main/AndroidManifest.xml';

const String _androidNamespace = 'http://schemas.android.com/apk/res/android';
const String _toolsNamespace = 'http://schemas.android.com/tools';

/// Marcadores do merger que TIRAM a permissão do mesclado. É assim que se
/// remove uma herdada de plugin; contá-la como pedido faria o guarda de build
/// velho acusar, para sempre, um build novo.
const Set<String> _removalNodes = {'remove', 'removeAll'};

/// Elementos que PEDEM permissão. `uses-permission-sdk-23` concede em API 23+
/// e escaparia de um filtro só por `uses-permission`. `<permission>` declara,
/// não pede, e `android:permission` em componente protege o componente: nenhum
/// dos dois entra.
const Set<String> _requestElements = {
  'uses-permission',
  'uses-permission-sdk-23',
};

/// Permissões pedidas por um manifest Android.
///
/// Elementos com `tools:node="remove"` ou `"removeAll"` não são pedidos: na
/// fonte, eles dizem ao merger para tirar a permissão.
///
/// Lança [FormatException] em pedido sem `android:name`: manifest malformado
/// não pode virar "zero permissões, tudo certo".
Set<String> declaredPermissions(String manifestXml) {
  final document = XmlDocument.parse(manifestXml);
  final declared = <String>{};
  for (final element in document.descendantElements) {
    if (!_requestElements.contains(element.name.local)) continue;
    final node = element.getAttribute('node', namespace: _toolsNamespace);
    if (_removalNodes.contains(node)) continue;
    final name = element.getAttribute('name', namespace: _androidNamespace);
    if (name == null || name.isEmpty) {
      throw FormatException(
        '<${element.name.local}> sem android:name: ${element.toXmlString()}',
      );
    }
    declared.add(name);
  }
  return declared;
}

class PermissionDiff {
  const PermissionDiff({required this.unexpected, required this.missing});

  /// Pedidas e fora da lista.
  final Set<String> unexpected;

  /// Na lista e não pedidas.
  final Set<String> missing;

  bool get isClean => unexpected.isEmpty && missing.isEmpty;
}

PermissionDiff diffPermissions(
  Set<String> declared, {
  Set<String> allowed = releasePermissionAllowlist,
}) =>
    PermissionDiff(
      unexpected: declared.difference(allowed),
      missing: allowed.difference(declared),
    );

/// O manifest mesclado não reflete a fonte: ela pede algo que ele não tem, ou
/// seja, o build não foi refeito depois da edição.
///
/// Compara CONTEÚDO, não data. O Gradle decide se a tarefa está atualizada
/// pelo conteúdo dos insumos, e não reescreve a saída quando a fonte só foi
/// tocada (um checkout, por exemplo): por `mtime`, o guarda acusaria build
/// velho para sempre. Fora as marcadas com `tools:node="remove"` (que
/// [declaredPermissions] já ignora), o merger só ACRESCENTA permissões dos
/// plugins, então o mesclado sempre contém as da fonte; faltar alguma é build
/// por refazer.
///
/// Limite conhecido: REMOVER uma permissão da fonte sem refazer o build passa
/// despercebido, porque o mesclado antigo ainda a contém.
bool isStale({
  required Set<String> source,
  required Set<String> merged,
}) =>
    !merged.containsAll(source);
