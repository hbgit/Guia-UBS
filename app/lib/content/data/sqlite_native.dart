/// Resolve a biblioteca nativa do SQLite fora do Android.
///
/// No aparelho, `sqlite3_flutter_libs` empacota a lib dentro do APK e nada
/// disto roda — não dependemos da versão que o fabricante da ROM enviou. Já em
/// host (desenvolvimento, CI, bench) cada distribuição instala um nome
/// diferente, e muitas só criam o symlink `libsqlite3.so` no pacote `-dev`.
///
/// Existe para que rodar testes e o bench não exija instalar pacote de
/// desenvolvimento algum.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';

const List<String> sqliteCandidates = <String>[
  'libsqlite3.so',
  'libsqlite3.so.0',
  '/lib64/libsqlite3.so.0',
  '/usr/lib64/libsqlite3.so.0',
  '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
  '/usr/lib/aarch64-linux-gnu/libsqlite3.so.0',
];

bool _configured = false;

/// Idempotente. Sem efeito no Android, onde o carregamento já está resolvido.
void configureSqliteForHost() {
  if (_configured || Platform.isAndroid) return;
  _configured = true;

  if (Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux, _openFirstAvailable);
  } else if (Platform.isMacOS) {
    open.overrideFor(OperatingSystem.macOS, _openFirstAvailable);
  }
}

DynamicLibrary _openFirstAvailable() {
  final failures = <String>[];
  for (final candidate in sqliteCandidates) {
    try {
      return DynamicLibrary.open(candidate);
    } on ArgumentError catch (error) {
      failures.add('$candidate (${error.message})');
    }
  }
  throw StateError(
    'Nenhuma biblioteca SQLite encontrada no host. Tentativas:\n'
    '${failures.join('\n')}\n'
    'Instale o SQLite do sistema (ex.: libsqlite3-0 / sqlite-libs).',
  );
}
