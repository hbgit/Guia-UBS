/// O que conta como origem de rede utilizável — uma regra só, para o app e
/// para o guarda de build (#45).
///
/// ===========================================================================
/// O SISTEMA NÃO BLOQUEIA `http` POR NÓS
/// ===========================================================================
///
/// Medido em 2026-10-29 (Task 0 da #45, `spec/arquitetura.md` §5): um APK
/// release deste projeto, com `PACK_MANIFEST_URL` em `http://`, fez a
/// requisição e gravou o ETag do servidor. O `HttpClient` do `dart:io` não
/// passa pela política de cleartext do Android. A exigência de `https` abaixo
/// é, portanto, a única proteção da LGPD-RF17(c) dentro do app — e vale para
/// qualquer build, inclusive o que não passou por `tool/build_apk.sh`.
library;

import 'dart:io';

/// O mesmo que o `kDebugMode` do Flutter, sem importar o Flutter: este
/// arquivo também roda no guarda de build (`dart run tool/...`), onde
/// `package:flutter/foundation` não carrega (precisa de `dart:ui`).
const bool _debugBuild = !bool.fromEnvironment('dart.vm.product') &&
    !bool.fromEnvironment('dart.vm.profile');

/// [url] como `Uri`, ou um `Uri` vazio quando ela é malformada. **Nunca
/// lança.** `Uri.parse` lança para `" https://h/x"` ou `https://h:abc/x`, e
/// num build feito sem o guarda a exceção subia do setup do modelo e deixava o
/// onboarding num spinner eterno (revisão final da #45). Vazio = não
/// configurado, pelo mesmo caminho de uma URL ausente.
Uri parseEndpoint(String url) => Uri.tryParse(url) ?? Uri();

/// `true` quando [url] é absoluta, `http`/`https` e com host; com
/// [requireHttps] (padrão: fora do debug, isto é, release E profile), só
/// `https`. O debug aceita `http` porque o emulador fala com o edge de dev em
/// `http://10.0.2.2`.
bool isUsableEndpoint(Uri url, {bool requireHttps = !_debugBuild}) {
  if (!url.isAbsolute || url.host.isEmpty) return false;
  if (url.scheme == 'https') return true;
  return url.scheme == 'http' && !requireHttps;
}

/// Hosts que não podem ser a origem de um release: loopback, rede local,
/// link-local, `.local` e os nomes reservados para exemplo e teste
/// (RFC 2606, RFC 6761). Um APK "configurado" com um deles não baixa nada no
/// aparelho de ninguém — é o mesmo defeito da #45 com outro nome.
///
/// Usada pelo guarda de build, não pelo runtime: em debug o emulador precisa
/// de `10.0.2.2`.
bool isLocalOrReservedHost(String host) {
  var h = host.toLowerCase().trim();
  if (h.startsWith('[') && h.endsWith(']')) h = h.substring(1, h.length - 1);
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);

  final ip = InternetAddress.tryParse(h);
  if (ip != null) return _isLocalAddress(ip);

  if (h == 'localhost') return true;
  for (final tld in const ['.local', '.localhost', '.test', '.invalid', '.example']) {
    if (h.endsWith(tld)) return true;
  }
  for (final name in const ['example.com', 'example.org', 'example.net']) {
    if (h == name || h.endsWith('.$name')) return true;
  }
  return false;
}

bool _isLocalAddress(InternetAddress ip) {
  if (ip.isLoopback || ip.isLinkLocal) return true;
  final b = ip.rawAddress;
  if (ip.type == InternetAddressType.IPv6) {
    return b.every((x) => x == 0); // `::`
  }
  return b[0] == 0 || // 0.0.0.0/8
      b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168);
}
