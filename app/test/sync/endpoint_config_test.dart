/// A regra única de "origem utilizável" do app e do guarda de build (#45).
///
/// Medido em 2026-10-29 (Task 0 da #45): o `dart:io` NÃO respeita a política de
/// cleartext do Android neste projeto — um release com URL `http` faz a
/// requisição. A exigência de `https` fora do debug é, portanto, a única
/// proteção da LGPD-RF17(c) dentro do app.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/endpoint_config.dart';

void main() {
  group('isUsableEndpoint', () {
    bool usavel(String url, {required bool https}) =>
        isUsableEndpoint(Uri.parse(url), requireHttps: https);

    test('vazia, relativa ou de outro esquema nunca e utilizavel', () {
      for (final url in ['', 'models/x.gguf', 'ftp://h/x', 'https:///x']) {
        expect(usavel(url, https: false), isFalse, reason: url);
      }
    });

    test('http so fora do release', () {
      expect(usavel('http://10.0.2.2:8081/x', https: false), isTrue);
      expect(usavel('http://10.0.2.2:8081/x', https: true), isFalse);
    });

    test('https passa; a lista de hosts e do guarda, nao do runtime', () {
      expect(usavel('https://h.example.invalid/x', https: true), isTrue);
    });
  });

  group('isLocalOrReservedHost', () {
    const reservados = [
      'localhost', '127.0.0.1', '127.8.9.1', '::1', '[::1]', '0.0.0.0',
      '10.0.2.2', '172.16.0.1', '172.31.255.255', '192.168.1.10',
      '169.254.1.1', 'srv.local', 'a.localhost', 'x.test', 'x.invalid',
      'x.example', 'example.com', 'EXAMPLE.ORG', 'www.example.net',
    ];
    for (final host in reservados) {
      test('$host e local ou reservado', () {
        expect(isLocalOrReservedHost(host), isTrue);
      });
    }

    const publicos = [
      '172.15.0.1', '172.32.0.1', '11.0.0.1', 'huggingface.co',
      // Fictício; o teste não faz rede. Trocar pelo domínio real quando a #55
      // decidir.
      'edge.dominio-do-projeto-a-definir.org',
    ];
    for (final host in publicos) {
      test('$host nao e reservado', () {
        expect(isLocalOrReservedHost(host), isFalse);
      });
    }
  });
}
