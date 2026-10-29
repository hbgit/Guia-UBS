/// Sobe e desce o motor SLM conforme o aceite dos termos (ADR-004).
///
/// Morava em `main.dart`, sem teste, e a revisão final achou nela três
/// defeitos, todos de concorrência ou de estado herdado:
///
/// * **dois motores no boot:** o `restore()` dos termos notifica o listener de
///   forma síncrona, e o listener e a continuação do `restore` pediam o
///   carregamento ao mesmo tempo. Os dois passavam pela guarda "já há motor?"
///   antes do primeiro `await`. Carregar é single-flight agora;
/// * **recusa durante o carregamento:** o aceite era conferido só no início.
///   Agora é conferido de novo quando o motor chega, e o motor que chegou
///   tarde é descartado;
/// * **job de versão anterior:** o download periódico registrado por um build
///   antigo sobrevive à atualização e baixaria sem aceite. Sem aceite, ele é
///   cancelado — inclusive no boot.
///
/// Nunca lança: o motor é o componente que a INV-8 declara opcional.
library;

import 'dart:async';

import '../triage/engine/triage_engine.dart';

class AssistantLifecycle {
  AssistantLifecycle({
    required this.isAllowed,
    required this.current,
    required this.install,
    required this.load,
    required this.cancelSync,
  });

  /// Aceite da versão vigente, lido NA HORA (não guardado aqui).
  final bool Function() isAllowed;
  final TriageEngine? Function() current;
  final void Function(TriageEngine? engine) install;

  /// Carrega o modelo verificado; `null` = não há o que carregar.
  final Future<TriageEngine?> Function() load;
  final Future<void> Function() cancelSync;

  Future<void>? _starting;

  /// Reage a uma mudança (ou ao valor inicial) do aceite.
  Future<void> onAllowed(bool allowed) => allowed ? _start() : _stop();

  Future<void> _start() => _starting ??= _load().whenComplete(() {
    _starting = null;
  });

  Future<void> _load() async {
    try {
      if (!isAllowed() || current() != null) return;
      final engine = await load();
      if (engine == null) return;
      // Recusou, ou outro carregamento ganhou, enquanto este esperava.
      if (!isAllowed() || current() != null) {
        await engine.dispose();
        return;
      }
      install(engine);
    } on Object {
      // Segue sem motor: degradação prevista (RF-12).
    }
  }

  Future<void> _stop() async {
    try {
      final engine = current();
      install(null);
      await engine?.dispose();
    } on Object {
      // Idem.
    }
    try {
      await cancelSync();
    } on Object {
      // O job cancelado na próxima abertura custa uma tentativa a mais.
    }
  }
}
