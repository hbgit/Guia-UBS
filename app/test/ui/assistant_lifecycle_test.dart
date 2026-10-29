/// A fiação que sobe e desce o motor conforme o aceite dos termos (ADR-004).
///
/// Morava em `main.dart`, sem teste, e a revisão final achou nela três
/// defeitos: dois motores carregados a cada boot de quem aceitou (o `restore`
/// e o listener chamavam o carregamento ao mesmo tempo), recusa durante o
/// carregamento que não impedia o motor de subir, e o download agendado por
/// uma versão anterior que nunca era cancelado.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/triage/engine/triage_engine.dart';
import 'package:guia_ubs/ui/assistant_lifecycle.dart';

class _Motor implements TriageEngine {
  bool descartado = false;
  @override
  Future<void> dispose() async => descartado = true;
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late bool permitido;
  late TriageEngine? instalado;
  late int carregamentos;
  late int cancelamentos;
  late Completer<TriageEngine?> carga;

  AssistantLifecycle novo() => AssistantLifecycle(
        isAllowed: () => permitido,
        current: () => instalado,
        install: (e) => instalado = e,
        load: () {
          carregamentos++;
          return carga.future;
        },
        cancelSync: () async => cancelamentos++,
      );

  setUp(() {
    permitido = true;
    instalado = null;
    carregamentos = 0;
    cancelamentos = 0;
    carga = Completer<TriageEngine?>();
  });

  test('dois pedidos ao mesmo tempo carregam UM motor', () async {
    final l = novo();
    final a = l.onAllowed(true);
    final b = l.onAllowed(true);
    final motor = _Motor();
    carga.complete(motor);
    await Future.wait([a, b]);

    expect(carregamentos, 1, reason: 'dois isolates de 800 MB no boot');
    expect(instalado, same(motor));
  });

  test('recusa durante o carregamento descarta o motor que chegou', () async {
    final l = novo();
    final subindo = l.onAllowed(true);
    permitido = false;
    await l.onAllowed(false);
    final motor = _Motor();
    carga.complete(motor);
    await subindo;

    expect(instalado, isNull);
    expect(motor.descartado, isTrue);
  });

  test('sem aceite, cancela o download agendado e descarta o motor', () async {
    final motor = _Motor();
    instalado = motor;
    permitido = false;
    await novo().onAllowed(false);

    expect(cancelamentos, 1,
        reason: 'job registrado por versao anterior baixaria sem aceite');
    expect(instalado, isNull);
    expect(motor.descartado, isTrue);
  });

  test('com motor ja instalado, nao carrega outro', () async {
    instalado = _Motor();
    await novo().onAllowed(true);
    expect(carregamentos, 0);
  });
}
