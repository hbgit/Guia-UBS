/// Espaço livre em disco — pré-requisito do RNF-03 (ADR-003).
///
/// O app precisa de **3 GB livres** antes de iniciar o download do modelo. A
/// razão não é conforto: começar a baixar 1,2 GB num aparelho sem espaço deixa
/// o usuário PIOR do que não baixar nada — enche o armazenamento, falha no
/// meio e ainda deixa lixo para trás.
///
/// `dart:io` não expõe espaço livre, então isto vai direto ao `statvfs(3)` da
/// libc. O layout da struct é estável em LP64 (aarch64 e x86_64), as únicas
/// ABIs que empacotamos (ver `android/app/build.gradle.kts`). Ainda assim o
/// resultado é conferido: um layout errado devolveria números absurdos, e é
/// melhor responder "não sei" do que responder um número falso sobre o qual
/// alguém vai decidir baixar 1,2 GB.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Campos de `struct statvfs` em LP64, em índices de palavras de 8 bytes.
///
/// ```c
/// unsigned long f_bsize;   // 0
/// unsigned long f_frsize;  // 1  <- tamanho do bloco de f_blocks/f_bavail
/// fsblkcnt_t    f_blocks;  // 2  <- total de blocos
/// fsblkcnt_t    f_bfree;   // 3
/// fsblkcnt_t    f_bavail;  // 4  <- livres para processo SEM privilégio
/// ```
const int _idxFrsize = 1;
const int _idxBlocks = 2;
const int _idxBavail = 4;

/// A struct tem ~14 campos em LP64; 32 palavras cobrem com folga qualquer
/// variação de padding entre libcs.
const int _statvfsWords = 32;

typedef _StatvfsC = Int32 Function(Pointer<Utf8>, Pointer<Uint64>);
typedef _StatvfsDart = int Function(Pointer<Utf8>, Pointer<Uint64>);

_StatvfsDart? _statvfs;
bool _resolved = false;

_StatvfsDart? _resolveStatvfs() {
  if (_resolved) return _statvfs;
  _resolved = true;
  if (!Platform.isAndroid && !Platform.isLinux) return null;
  try {
    _statvfs = DynamicLibrary.process()
        .lookupFunction<_StatvfsC, _StatvfsDart>('statvfs');
  } on ArgumentError {
    _statvfs = null;
  }
  return _statvfs;
}

/// Bytes livres em [path] para um processo comum, ou `null` se indeterminável.
///
/// Usa `f_bavail`, não `f_bfree`: o segundo inclui os blocos reservados ao
/// root, que o app não pode usar. Contá-los superestimaria o espaço disponível
/// justamente no caso apertado, que é o que importa.
int? freeDiskBytes(String path) {
  final statvfs = _resolveStatvfs();
  if (statvfs == null) return null;

  final pathPtr = path.toNativeUtf8();
  final buf = calloc<Uint64>(_statvfsWords);
  try {
    if (statvfs(pathPtr, buf) != 0) return null;

    final frsize = buf[_idxFrsize];
    final blocks = buf[_idxBlocks];
    final avail = buf[_idxBavail];

    // Conferência de sanidade: com layout errado estes valores seriam lixo, e
    // um "não sei" é infinitamente melhor que um número falso.
    final plausibleBlockSize = frsize >= 512 && frsize <= 1 << 20;
    final plausibleTotals = blocks > 0 && avail <= blocks;
    if (!plausibleBlockSize || !plausibleTotals) return null;

    return avail * frsize;
  } on Object {
    return null;
  } finally {
    calloc.free(pathPtr);
    calloc.free(buf);
  }
}

/// Exigência do RNF-03 antes de baixar o modelo SLM.
const int requiredFreeBytesForModel = 3 * 1024 * 1024 * 1024;

/// Resultado da checagem de espaço, com o motivo explícito.
enum DiskSpaceVerdict {
  /// Há espaço suficiente.
  sufficient,

  /// Espaço insuficiente — não iniciar o download.
  insufficient,

  /// Indeterminável (plataforma sem `statvfs`, caminho inválido).
  unknown,
}

/// Decide se vale iniciar um download que precisa de [requiredBytes].
///
/// `unknown` **não** bloqueia: onde não conseguimos medir, seguir em frente e
/// deixar o download falhar por falta de espaço é melhor do que nunca baixar.
/// O caso que precisamos evitar é o que sabemos ser ruim.
DiskSpaceVerdict checkDiskSpace(
  String path, {
  int requiredBytes = requiredFreeBytesForModel,
}) {
  final free = freeDiskBytes(path);
  if (free == null) return DiskSpaceVerdict.unknown;
  return free >= requiredBytes
      ? DiskSpaceVerdict.sufficient
      : DiskSpaceVerdict.insufficient;
}
