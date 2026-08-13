/// Monta um `content.db` em memória a partir das MESMAS fontes que o packer usa.
///
/// Nenhum teste depende de o packer ter rodado antes, e nenhum teste tem sua
/// própria cópia das regras: o DDL vem de `contract/ddl/` (gerado do schema
/// Drizzle) e os dados de `seed/`. Se as regras clínicas mudarem, os testes
/// enxergam a mudança no mesmo instante que o dispositivo enxergaria.
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'sqlite_test_libs.dart';

/// Raiz do repositório a partir do diretório do pacote Flutter (`app/`).
final Directory repoRoot = Directory.current.parent;

const String _statementBreak = '--> statement-breakpoint';

List<File> _sqlFilesIn(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) {
    throw StateError('diretório ausente: $path');
  }
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Constrói o pacote em memória. O chamador é responsável por `dispose()`.
Database buildInMemoryPack() {
  configureSqliteForTests();
  final db = sqlite3.openInMemory();
  // Chaves estrangeiras ligadas: é a primeira barreira contra uma regra que
  // aponta para um token ou desfecho inexistente.
  db.execute('PRAGMA foreign_keys = ON');

  final ddlFiles = _sqlFilesIn('${repoRoot.path}/contract/ddl');
  if (ddlFiles.isEmpty) {
    throw StateError('contract/ddl vazio — rode drizzle-kit generate');
  }
  for (final file in ddlFiles) {
    for (final statement in file.readAsStringSync().split(_statementBreak)) {
      if (statement.trim().isEmpty) continue;
      db.execute(statement);
    }
  }

  for (final file in _sqlFilesIn('${repoRoot.path}/seed')) {
    db.execute(file.readAsStringSync());
  }

  // `pack_meta` normalmente é escrito pelo packer no momento da assinatura;
  // aqui só o desfecho padrão importa para avaliar regras.
  db.execute('''
    INSERT INTO pack_meta
      (id, pack_version, schema_version, municipality_code, built_at,
       default_outcome_id, source_commit)
    VALUES (1, 0, '1.0', '0000000', '1970-01-01T00:00:00Z', 'ROUTINE_UBS', 'test')
  ''');

  return db;
}

/// Casos golden clínicos — o mesmo arquivo que o packer valida.
File get goldenCasesFile => File('${repoRoot.path}/seed/golden/clinical_cases.yaml');
