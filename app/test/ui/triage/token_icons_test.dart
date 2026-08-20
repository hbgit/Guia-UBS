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

  test('todo token do pack real tem ícone próprio', () {
    // Se o conteúdo publicar um sintoma novo e o binário não conhecer o ícone,
    // este teste avisa antes de a opção virar um ponto de interrogação na
    // frente de quem precisa dela.
    final missing = <String>[];
    for (final token in content.symptomTokens()) {
      if (iconForToken(token) == unknownIcon) missing.add(token.iconRef);
    }

    expect(
      missing,
      isEmpty,
      reason: 'sem mapeamento, estes ícones viram interrogação na triagem',
    );
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
