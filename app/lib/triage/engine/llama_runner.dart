/// Execução da inferência fora da thread de UI.
///
/// O contexto nativo é caro (centenas de MB mapeados) e precisa ser criado uma
/// vez e reutilizado. Ele vive num isolate dedicado que nasce no boot e morre
/// no `dispose` — nunca por sessão de triagem.
///
/// [LlamaRunner] é uma interface porque a POLÍTICA de segurança do motor
/// (timeout vira "sem opinião", erro vira "sem opinião") precisa ser testável
/// sem biblioteca nativa, sem modelo GGUF e sem device.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'llama_bindings.dart';

/// Executa uma geração. Retorna `null` para QUALQUER falha.
abstract interface class LlamaRunner {
  /// `false` depois de um `dispose` ou de um travamento irrecuperável.
  bool get isAlive;

  Future<String?> generate(
    String prompt, {
    required int maxTokens,
    required Duration timeout,
  });

  Future<void> dispose();
}

// Códigos do protocolo com o isolate.
const int _cmdGenerate = 0;
const int _cmdClose = 1;

/// Runner real: isolate dedicado + FFI.
class IsolateLlamaRunner implements LlamaRunner {
  IsolateLlamaRunner._(this._isolate, this._toWorker, this._fromWorker);

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;

  final Map<int, Completer<String?>> _pending = <int, Completer<String?>>{};
  int _nextRequestId = 0;
  bool _busy = false;
  bool _alive = true;

  /// Margem sobre o prazo nativo antes de considerar o isolate travado.
  ///
  /// Em operação normal o C devolve GUBS_ERR_TIMEOUT sozinho e esta margem
  /// nunca é atingida. Se for, o `abort_callback` não funcionou e o isolate
  /// está bloqueado dentro de uma chamada FFI — situação que o Dart não
  /// consegue interromper.
  static const Duration wedgeGrace = Duration(seconds: 3);

  /// Sobe o isolate e carrega o modelo. `null` se qualquer etapa falhar:
  /// biblioteca ausente, ABI divergente, GGUF ausente/corrompido, RAM curta.
  static Future<IsolateLlamaRunner?> start({
    required String modelPath,
    int contextTokens = 512,
    int threads = 2,
    List<String>? libraryCandidates,
    Duration startupTimeout = const Duration(seconds: 30),
  }) async {
    final fromWorker = ReceivePort();
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _workerMain,
        <Object?>[
          fromWorker.sendPort,
          modelPath,
          contextTokens,
          threads,
          libraryCandidates,
        ],
        errorsAreFatal: true,
      );
    } on Object {
      fromWorker.close();
      return null;
    }

    final events = PortQueue<Object?>(fromWorker);
    Object? handshake;
    try {
      handshake = await events.next.timeout(startupTimeout);
    } on Object {
      await events.cancel();
      isolate.kill(priority: Isolate.immediate);
      fromWorker.close();
      return null;
    }

    if (handshake is! SendPort) {
      await events.cancel();
      isolate.kill(priority: Isolate.immediate);
      fromWorker.close();
      return null;
    }

    final runner = IsolateLlamaRunner._(isolate, handshake, fromWorker);
    runner._listen(events);
    return runner;
  }

  void _listen(PortQueue<Object?> events) {
    unawaited(() async {
      while (await events.hasNext) {
        final Object? message;
        try {
          message = await events.next;
        } on Object {
          break;
        }
        if (message is! List || message.length != 2) continue;
        final completer = _pending.remove(message[0] as int);
        if (completer != null && !completer.isCompleted) {
          completer.complete(message[1] as String?);
        }
      }
    }());
  }

  @override
  bool get isAlive => _alive;

  @override
  Future<String?> generate(
    String prompt, {
    required int maxTokens,
    required Duration timeout,
  }) async {
    // Uma sessão de triagem por vez (FSM-A). Chamada concorrente é bug de
    // chamador; responder "sem opinião" degrada em vez de corromper o contexto
    // nativo, que não é reentrante.
    if (!_alive || _busy) return null;
    _busy = true;

    final id = _nextRequestId++;
    final completer = Completer<String?>();
    _pending[id] = completer;

    try {
      _toWorker
          .send(<Object?>[_cmdGenerate, id, prompt, maxTokens, timeout.inMilliseconds]);
      return await completer.future.timeout(
        timeout + wedgeGrace,
        onTimeout: () {
          // O prazo nativo não foi honrado: o isolate está preso em FFI e não
          // volta. Derruba tudo e marca o motor como morto — para o resto do
          // processo a triagem roda em modo degradado (RF-12), o que é
          // conservador e visível na telemetria agregada.
          _pending.remove(id);
          _alive = false;
          _isolate.kill(priority: Isolate.immediate);
          _fromWorker.close();
          return null;
        },
      );
    } on Object {
      return null;
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> dispose() async {
    if (!_alive) return;
    _alive = false;
    _toWorker.send(<Object?>[_cmdClose]);
    // Sem espera de confirmação: o isolate fecha o contexto e encerra sozinho.
    _fromWorker.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }
}

/// Corpo do isolate. Tudo que toca ponteiro nativo mora aqui.
void _workerMain(List<Object?> args) {
  final reply = args[0] as SendPort;
  final modelPath = args[1] as String;
  final contextTokens = args[2] as int;
  final threads = args[3] as int;
  final candidates = (args[4] as List?)?.cast<String>();

  final lib = openShimLibrary(candidates: candidates);
  if (lib == null) {
    reply.send(null);
    return;
  }

  final GubsLlamaShim shim;
  try {
    shim = GubsLlamaShim(lib);
  } on Object {
    // Símbolo ausente: o `.so` carregado não é o nosso shim.
    reply.send(null);
    return;
  }

  if (shim.abiVersion() != expectedAbiVersion) {
    reply.send(null);
    return;
  }

  final handle = shim.open(modelPath, contextTokens: contextTokens, threads: threads);
  if (handle == nullptr) {
    reply.send(null);
    return;
  }

  final commands = ReceivePort();
  reply.send(commands.sendPort);

  commands.listen((Object? message) {
    if (message is! List || message.isEmpty) return;

    if (message[0] == _cmdClose) {
      shim.close(handle);
      commands.close();
      return;
    }

    if (message[0] != _cmdGenerate) return;

    final id = message[1] as int;
    final prompt = message[2] as String;
    final maxTokens = message[3] as int;
    final timeoutMs = message[4] as int;

    String? text;
    try {
      text = shim.generate(
        handle,
        prompt,
        maxTokens: maxTokens,
        timeout: Duration(milliseconds: timeoutMs),
      );
    } on Object {
      // Timeout, falha de decode, OOM do backend: todos viram "sem opinião".
      // O motor não tem autoridade para transformar a própria falha em um
      // desfecho clínico.
      text = null;
    }
    reply.send(<Object?>[id, text]);
  });
}

/// Fila mínima sobre um `ReceivePort`.
///
/// Existe para evitar a dependência `package:async` por causa de uma única
/// classe — o app roda offline em device de entrada e cada dependência a mais
/// é superfície a auditar (stack.md §9).
class PortQueue<T> {
  PortQueue(Stream<T> stream) {
    _subscription = stream.listen(
      (event) {
        if (_waiting.isNotEmpty) {
          _waiting.removeAt(0).complete(event);
        } else {
          _buffer.add(event);
        }
      },
      onDone: () {
        _done = true;
        for (final completer in _waiting) {
          if (!completer.isCompleted) {
            completer.completeError(StateError('canal encerrado'));
          }
        }
        _waiting.clear();
      },
    );
  }

  late final StreamSubscription<T> _subscription;
  final List<T> _buffer = <T>[];
  final List<Completer<T>> _waiting = <Completer<T>>[];
  bool _done = false;

  Future<bool> get hasNext async => _buffer.isNotEmpty || !_done;

  Future<T> get next {
    if (_buffer.isNotEmpty) return Future<T>.value(_buffer.removeAt(0));
    final completer = Completer<T>();
    _waiting.add(completer);
    return completer.future;
  }

  Future<void> cancel() => _subscription.cancel();
}
