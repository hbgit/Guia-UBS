/// Ligação `dart:ffi` com `libgubs_llama` (ver `native/llama_shim/`).
///
/// Este é o ÚNICO arquivo Dart que conhece a fronteira nativa. Tudo acima dele
/// trabalha com `String` e `Duration`.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Deve casar com `GUBS_LLAMA_ABI_VERSION` em `gubs_llama.h`.
///
/// Divergência aqui significa que o APK embarcou um `.so` de outra geração do
/// shim. Nesse caso o motor se desqualifica — chamar com layout de argumentos
/// diferente não daria erro, daria memória lixo interpretada como diagnóstico
/// clínico.
const int expectedAbiVersion = 1;

// Códigos de erro espelhados de gubs_llama.h.
const int gubsErrArgs = -1;
const int gubsErrTokenize = -2;
const int gubsErrDecode = -3;
const int gubsErrTimeout = -4;
const int gubsErrOverflow = -5;

typedef _AbiVersionC = Int32 Function();
typedef _AbiVersionDart = int Function();

typedef _OpenC = Pointer<Void> Function(Pointer<Utf8>, Int32, Int32);
typedef _OpenDart = Pointer<Void> Function(Pointer<Utf8>, int, int);

typedef _GenerateC = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Int32, Int64, Pointer<Utf8>, Int32);
typedef _GenerateDart = int Function(
    Pointer<Void>, Pointer<Utf8>, int, int, Pointer<Utf8>, int);

typedef _CloseC = Void Function(Pointer<Void>);
typedef _CloseDart = void Function(Pointer<Void>);

/// Nomes procurados, em ordem. No Android o `.so` vem dentro do APK e é
/// resolvido pelo linker do sistema; no host de desenvolvimento e no CI ele
/// costuma estar no diretório de build.
const List<String> shimLibraryCandidates = <String>[
  'libgubs_llama.so',
  'build/shim/libgubs_llama.so',
];

/// Abre a biblioteca do shim, ou `null` se nenhum candidato carregar.
///
/// `null` não é erro: é o caso normal de um build sem suporte a SLM, e leva o
/// app a degradar para o `RuleOnlyEngine` (RF-12).
DynamicLibrary? openShimLibrary({List<String>? candidates}) {
  if (Platform.isIOS || Platform.isMacOS) {
    // Ligação estática dentro do processo no build Apple.
    try {
      return DynamicLibrary.process();
    } on ArgumentError {
      return null;
    }
  }
  for (final name in candidates ?? shimLibraryCandidates) {
    try {
      return DynamicLibrary.open(name);
    } on ArgumentError {
      continue;
    }
  }
  return null;
}

/// Envelope tipado das 4 funções do shim.
final class GubsLlamaShim {
  GubsLlamaShim(DynamicLibrary lib)
      : _abiVersion = lib
            .lookupFunction<_AbiVersionC, _AbiVersionDart>('gubs_llama_abi_version'),
        _open = lib.lookupFunction<_OpenC, _OpenDart>('gubs_llama_open'),
        _generate = lib.lookupFunction<_GenerateC, _GenerateDart>('gubs_llama_generate'),
        _close = lib.lookupFunction<_CloseC, _CloseDart>('gubs_llama_close');

  final _AbiVersionDart _abiVersion;
  final _OpenDart _open;
  final _GenerateDart _generate;
  final _CloseDart _close;

  int abiVersion() => _abiVersion();

  /// `nullptr` quando o modelo não carrega (ausente, corrompido, sem RAM).
  Pointer<Void> open(
    String modelPath, {
    required int contextTokens,
    required int threads,
  }) {
    final path = modelPath.toNativeUtf8();
    try {
      return _open(path, contextTokens, threads);
    } finally {
      calloc.free(path);
    }
  }

  /// Retorna o texto gerado, ou lança [LlamaShimException] com o código do erro.
  String generate(
    Pointer<Void> handle,
    String prompt, {
    required int maxTokens,
    required Duration timeout,
    int outputCapacity = 2048,
  }) {
    final promptPtr = prompt.toNativeUtf8();
    final out = calloc<Uint8>(outputCapacity + 1).cast<Utf8>();
    try {
      final written = _generate(
        handle,
        promptPtr,
        maxTokens,
        timeout.inMilliseconds,
        out,
        outputCapacity,
      );
      if (written < 0) throw LlamaShimException(written);
      // O shim não escreve terminador; o buffer veio zerado de `calloc`, então
      // o byte na posição `written` já é 0.
      return out.toDartString(length: written);
    } finally {
      calloc.free(promptPtr);
      calloc.free(out);
    }
  }

  void close(Pointer<Void> handle) => _close(handle);
}

/// Falha reportada pelo shim, com o código negativo original.
class LlamaShimException implements Exception {
  const LlamaShimException(this.code);

  final int code;

  bool get isTimeout => code == gubsErrTimeout;

  @override
  String toString() => 'LlamaShimException($code)';
}
