import 'package:flutter_test/flutter_test.dart';

import '../../tool/release_permissions.dart';

String manifest(String body) =>
    '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
    '$body</manifest>';

String usesPermission(String name) =>
    '<uses-permission android:name="$name"/>';

/// As sete permissões herdadas de plugins, sem `INTERNET` — o release de
/// antes da P0-1.
const List<String> _herdadas = [
  'android.permission.ACCESS_NETWORK_STATE',
  'android.permission.POST_NOTIFICATIONS',
  'android.permission.FOREGROUND_SERVICE',
  'android.permission.FOREGROUND_SERVICE_SHORT_SERVICE',
  'android.permission.WAKE_LOCK',
  'android.permission.RECEIVE_BOOT_COMPLETED',
  'br.gov.exemplo.guia_ubs.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION',
];

final String _herdadasXml = _herdadas.map(usesPermission).join();
final String _listaXml =
    _herdadasXml + usesPermission('android.permission.INTERNET');

void main() {
  test('lista fechada tem exatamente as 8 permissões da issue P0-1', () {
    expect(releasePermissionAllowlist, hasLength(8));
    expect(releasePermissionAllowlist, contains('android.permission.INTERNET'));
    expect(releasePermissionAllowlist, containsAll(_herdadas));
  });

  test('manifest com exatamente a lista passa', () {
    final diff = diffPermissions(declaredPermissions(manifest(_listaXml)));
    expect(diff.isClean, isTrue);
  });

  test('falta de INTERNET reprova', () {
    final diff = diffPermissions(declaredPermissions(manifest(_herdadasXml)));
    expect(diff.isClean, isFalse);
    expect(diff.missing, {'android.permission.INTERNET'});
    expect(diff.unexpected, isEmpty);
  });

  test('permissão a mais reprova', () {
    final diff = diffPermissions(declaredPermissions(
      manifest(_listaXml + usesPermission('android.permission.CAMERA')),
    ));
    expect(diff.unexpected, {'android.permission.CAMERA'});
    expect(diff.missing, isEmpty);
  });

  test('uses-permission-sdk-23 conta como pedido', () {
    final diff = diffPermissions(declaredPermissions(manifest(
      '$_listaXml<uses-permission-sdk-23 '
      'android:name="android.permission.READ_CONTACTS"/>',
    )));
    expect(diff.unexpected, {'android.permission.READ_CONTACTS'});
  });

  test('declaração e atributo android:permission não contam', () {
    final diff = diffPermissions(declaredPermissions(manifest(
      '$_listaXml<permission android:name="x.y.Z"/>'
      '<application><service android:name=".S" '
      'android:permission="android.permission.BIND_JOB_SERVICE"/>'
      '</application>',
    )));
    expect(diff.isClean, isTrue);
  });

  test('maxSdkVersion antes do name ainda é lido', () {
    final declared = declaredPermissions(manifest(
      '<uses-permission android:maxSdkVersion="32" '
      'android:name="android.permission.WAKE_LOCK"/>',
    ));
    expect(declared, {'android.permission.WAKE_LOCK'});
  });

  test('uses-permission sem android:name lança FormatException', () {
    expect(
      () => declaredPermissions(manifest('<uses-permission/>')),
      throwsFormatException,
    );
  });

  test('caminho padrão é o de release, nunca o de debug', () {
    expect(defaultReleaseManifestPath, contains('/release/'));
    expect(defaultReleaseManifestPath, isNot(contains('debug')));
  });

  test('fonte pede o que o mesclado não tem: desatualizado', () {
    expect(
      isStale(
        source: {'android.permission.INTERNET', 'android.permission.CAMERA'},
        merged: releasePermissionAllowlist,
      ),
      isTrue,
    );
  });

  test('mesclado com a fonte mais as dos plugins: atualizado', () {
    expect(
      isStale(
        source: {'android.permission.INTERNET'},
        merged: releasePermissionAllowlist,
      ),
      isFalse,
    );
    expect(isStale(source: {}, merged: _herdadas.toSet()), isFalse);
  });
}
