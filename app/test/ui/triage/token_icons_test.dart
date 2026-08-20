/// O mapeamento `icon_ref` → ícone desenhável.
///
/// Numa interface iconográfica, ícone ausente não é degradação de estilo: é a
/// opção inteira desaparecendo para quem não lê o rótulo. Estes testes existem
/// porque uma sabotagem mostrou que nada cobria esse caminho.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/content/data/content_repository.dart';
import 'package:guia_ubs/content/data/pack_rule_source.dart';
import 'package:guia_ubs/ui/triage/widgets/token_icons.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/sqlite_test_libs.dart';

void main() {
  late Database db;
  late ContentRepository content;

  setUpAll(configureSqliteForTests);
  setUp(() {
    db = openPack('test/fixtures/sync/pack-v1.db');
    content = ContentRepository(db);
  });
  tearDown(() => db.dispose());

  test('TODO icon_ref do pack tem ícone — não só os de sintoma', () {
    // A primeira versão deste teste percorria apenas `symptomTokens`, e por
    // isso passou enquanto a tela "Onde ir" mostrava um ponto de interrogação
    // em CADA serviço no aparelho. A pergunta certa não é "os tokens têm
    // ícone?", é "tudo que o pack manda desenhar tem ícone?".
    final refs = db
        .select("SELECT ref FROM asset WHERE ref LIKE 'icon.%' ORDER BY ref")
        .map((row) => row['ref'] as String);

    final missing = refs.where((ref) => iconForRef(ref) == unknownIcon);

    expect(
      missing,
      isEmpty,
      reason: 'sem mapeamento, estes viram interrogação na frente de quem '
          'depende do ícone por não ler o rótulo',
    );
  });

  test('todo token de sintoma tem ícone próprio', () {
    final missing = [
      for (final token in content.symptomTokens())
        if (iconForToken(token) == unknownIcon) token.iconRef,
    ];

    expect(missing, isEmpty);
  });

  test('ref desconhecida devolve um ícone VISÍVEL, nunca vazio', () {
    final icon = iconForRef('icon.que.o.binario.nao.conhece');

    expect(icon, unknownIcon);
    expect(
      icon,
      isNot(anyOf(null, Icons.abc)),
      reason: 'a opção precisa continuar tocável e visível',
    );
  });

  test('os ícones dos cartões de resultado existem', () {
    // O cartão de emergência sem ícone seria a pior omissão do app.
    for (final card in content.cardsOfKind('result')) {
      expect(
        iconForRef(card.iconRef),
        isNot(unknownIcon),
        reason: 'cartão ${card.id} sem ícone',
      );
    }
  });

  test('serviços, documentos e passos do fluxo têm ícones distintos', () {
    // Dois serviços com o mesmo desenho sao, para quem nao le, o mesmo botao.
    for (final (name, refs) in [
      ('serviços', _refsLike(db, 'icon.svc.%')),
      ('documentos', _refsLike(db, 'icon.doc.%')),
      ('passos do fluxo', _refsLike(db, 'icon.step.%')),
    ]) {
      final icons = refs.map(iconForRef).toList();
      expect(
        icons.toSet(),
        hasLength(icons.length),
        reason: 'ícones repetidos em $name são botões indistinguíveis',
      );
    }
  });

  test('cada família da ontologia tem ícones distintos entre si', () {
    // Dois sintomas com o mesmo desenho são, para quem não lê, o mesmo botão.
    for (final kind in ['body_part', 'symptom', 'modifier']) {
      final icons =
          content.symptomTokens(kind: kind).map(iconForToken).toList();

      expect(
        icons.toSet(),
        hasLength(icons.length),
        reason: 'ícones repetidos em "$kind" são botões indistinguíveis',
      );
    }
  });
}

List<String> _refsLike(Database db, String pattern) => db
    .select('SELECT ref FROM asset WHERE ref LIKE ? ORDER BY ref', [pattern])
    .map((row) => row['ref'] as String)
    .toList();
