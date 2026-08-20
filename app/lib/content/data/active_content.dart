/// Mantém aberta a conexão com o pack ativo, e a reabre depois do swap.
///
/// Fecha o laço com o `sync/`: o [PackStore] diz qual arquivo está ativo e já
/// verificado (INV-3); este objeto o abre somente-leitura e entrega um
/// [ContentRepository] às telas.
///
/// ## Por que a troca não corrompe uma leitura em curso
///
/// A FSM-B só troca com a FSM-A em `S0_IDLE` (guard de quiescência) — mas o
/// desenho não depende só disso. Packs vivem nomeados pelo próprio hash, e o
/// commit é um rename do `manifest.json`: o arquivo antigo continua existindo
/// até ser removido, e no POSIX um `unlink` não invalida descritor já aberto.
/// Uma leitura em voo termina lendo o pack antigo, íntegro, em vez de ver um
/// arquivo trocado por baixo. A reabertura acontece por [reload], depois.
///
/// ## Ausência de pack não é erro
///
/// Um aparelho recém-instalado, ou um cujo primeiro sync ainda não completou,
/// não tem pack. [repository] devolve `null`, e a tela mostra "conteúdo ainda
/// não disponível" em vez de quebrar (INV-8).
library;

import 'package:sqlite3/sqlite3.dart';

import '../../sync/pack_store.dart';
import 'content_repository.dart';
import 'pack_rule_source.dart';

class ActiveContent {
  ActiveContent(this.store);

  final PackStore store;

  Database? _db;
  ContentRepository? _repository;
  int? _version;

  /// Leitura do pack ativo, ou `null` se ainda não há pack utilizável.
  ContentRepository? get repository => _repository;

  /// Versão do pack aberto agora. Útil para telemetria agregada e diagnóstico.
  int? get packVersion => _version;

  bool get hasContent => _repository != null;

  /// Abre (ou reabre) o pack ativo.
  ///
  /// **Nunca lança.** Pack ausente, ilegível ou com assinatura que não confere
  /// resulta em `hasContent == false`, nunca em exceção: conteúdo indisponível
  /// degrada a tela, não derruba o app.
  Future<void> reload() async {
    await close();
    try {
      final active = await store.loadActive();
      if (active == null) return;

      final db = openPack(active.file.path);
      final repository = ContentRepository(db);
      // Lê o cabeçalho já: um arquivo que passou no SHA-256 mas não é um pack
      // válido (schema truncado) precisa ser recusado agora, e não na primeira
      // tela que o usuário abrir.
      final info = repository.readPackInfo();

      _db = db;
      _repository = repository;
      _version = info.packVersion;
    } on Object {
      await close();
    }
  }

  Future<void> close() async {
    _db?.dispose();
    _db = null;
    _repository = null;
    _version = null;
  }
}
