/// Onde o `user.db` vive e como ele é aberto.
///
/// Separado do esquema porque o esquema precisa rodar em teste de host, sem
/// `path_provider` e sem plugin nenhum. Aqui mora a única parte que depende do
/// aparelho.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../core/app_paths.dart';
import 'user_database.dart';

/// Abre o `user.db` no armazenamento interno do app.
///
/// Fica ao lado do `packs/` e do `models/`: mesmo sandbox, removido junto com
/// o app na desinstalação — que é o que a LGPD-RT10 pede para o device.
Future<UserDatabase> openUserDatabase() async {
  final dir = await appSupportDirectory();
  return UserDatabase(
    LazyDatabase(() async => NativeDatabase.createInBackground(
          // `File` do dart:io via caminho: o Drift resolve o resto.
          _userDbFile(dir.path),
        )),
  );
}

File _userDbFile(String supportPath) => File('$supportPath/user.db');

/// Banco em memória, para testes.
UserDatabase inMemoryUserDatabase() => UserDatabase(NativeDatabase.memory());
