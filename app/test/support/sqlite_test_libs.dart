/// Resolução da lib nativa do SQLite nos testes de host.
///
/// A lógica vive em `lib/content/data/sqlite_native.dart` porque o bench
/// (`tool/bench_inference.dart`) precisa exatamente da mesma coisa, e uma
/// segunda cópia sairia de sincronia na primeira distribuição nova.
library;

import 'package:guia_ubs/content/data/sqlite_native.dart';

void configureSqliteForTests() => configureSqliteForHost();
