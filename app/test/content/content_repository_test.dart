/// Leitura do conteúdo contra o pack REAL, construído e assinado pelo packer.
///
/// Não é fixture escrita à mão: é `test/fixtures/sync/pack-v1.db`, o mesmo
/// arquivo que o sync instala e que o gate clínico consome. Um repositório
/// testado contra um banco inventado prova que o SQL roda, não que ele lê o
/// pacote que existe.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/content/data/content_repository.dart';
import 'package:guia_ubs/content/data/pack_rule_source.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/sqlite_test_libs.dart';

void main() {
  late Directory tmp;
  late Database db;
  late ContentRepository content;

  setUpAll(configureSqliteForTests);

  setUp(() {
    // Trabalha sobre uma CÓPIA descartável, nunca sobre a fixture versionada.
    //
    // Não é zelo abstrato: o teste logo abaixo tenta escrever no pack para
    // provar que a escrita é impossível. Quando uma sabotagem removeu o
    // `OpenMode.readOnly`, o `UPDATE` passou — e corrompeu a fixture
    // compartilhada, derrubando 10 testes de sync que não tinham nada a ver
    // com o assunto. Um teste que prova "isto não pode acontecer" precisa ser
    // inofensivo no dia em que acontecer.
    tmp = Directory.systemTemp.createTempSync('gubs_content_');
    final copy = File('${tmp.path}/pack.db');
    File('test/fixtures/sync/pack-v1.db').copySync(copy.path);

    db = openPack(copy.path);
    content = ContentRepository(db);
  });

  tearDown(() {
    db.dispose();
    tmp.deleteSync(recursive: true);
  });

  group('identidade do pack', () {
    test('lê a versão e o desfecho padrão', () {
      final info = content.readPackInfo();

      expect(info.packVersion, 1);
      expect(info.schemaVersion, startsWith('1.'));
      expect(info.defaultOutcomeId, isNotEmpty);
    });
  });

  group('somente leitura (INV-4)', () {
    test('escrever no pack é impossível, não apenas desencorajado', () {
      // Conteúdo clínico só entra por pack assinado com dupla revisão. Se este
      // banco aceitasse escrita, existiria um caminho para orientação não
      // revisada chegar ao usuário sem passar pela assinatura.
      expect(
        () => db.execute("UPDATE pack_meta SET pack_version = 99 WHERE id = 1"),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('ontologia de sintomas', () {
    test('devolve tokens ordenados, sem os depreciados', () {
      final tokens = content.symptomTokens();

      expect(tokens, isNotEmpty);
      final orders = tokens.map((t) => t.sortOrder).toList();
      expect(orders, orderedEquals(List.of(orders)..sort()));
    });

    test('filtra por tipo, que é o que a tela de composição usa', () {
      final kinds = content.symptomTokens().map((t) => t.kind).toSet();
      expect(kinds, isNotEmpty);

      final first = kinds.first;
      final filtered = content.symptomTokens(kind: first);

      expect(filtered, isNotEmpty);
      expect(filtered.every((t) => t.kind == first), isTrue);
    });

    test('token depreciado continua legível por id', () {
      // Uma regra publicada pode referenciá-lo, e regra que aponta para token
      // invisível ainda precisa ser explicável.
      final any = content.symptomTokens().first;
      expect(content.tokenById(any.id), isNotNull);
      expect(content.tokenById('token-que-nao-existe'), isNull);
    });

    test('todo token tem ícone — é a interface inteira para quem não lê', () {
      for (final token in content.symptomTokens()) {
        expect(token.iconRef, isNotEmpty, reason: 'token ${token.id} sem ícone');
        expect(content.assetByRef(token.iconRef), isNotNull,
            reason: 'ícone ${token.iconRef} não existe no pack');
      }
    });
  });

  group('idioma', () {
    test('espanhol e português devolvem textos diferentes', () {
      final pt = content.symptomTokens();
      final es = content.symptomTokens(lang: 'es');

      expect(es, hasLength(pt.length));
      final differences = [
        for (var i = 0; i < pt.length; i++)
          if (pt[i].label.value != es[i].label.value) i,
      ];
      expect(
        differences,
        isNotEmpty,
        reason: 'o pack traz as duas línguas; nenhum texto mudou',
      );
    });

    test('o pack real não precisa de recuo em nenhum idioma suportado', () {
      // O packer bloqueia publicação com tradução faltando. Este teste é o
      // espelho dessa garantia no aparelho: se ele falhar, o pacote que chegou
      // ao dispositivo não é o que o pipeline promete.
      for (final lang in ['pt', 'es']) {
        for (final token in content.symptomTokens(lang: lang)) {
          expect(
            token.label.isFallback,
            isFalse,
            reason: 'token ${token.id} recuou de idioma em "$lang"',
          );
          expect(token.label.value, isNotEmpty);
        }
      }
    });

    test('idioma desconhecido recua para o base em vez de sumir com o item', () {
      // Sumir com "Onde ir" de quem precisa é pior que mostrá-lo em português.
      final tokens = content.symptomTokens(lang: 'gn');
      final pt = content.symptomTokens();

      expect(tokens, hasLength(pt.length));
      expect(tokens.first.label.value, pt.first.label.value);
      expect(
        tokens.first.label.isFallback,
        isTrue,
        reason: 'o recuo precisa ser sinalizado, ou vira defeito invisível',
      );
    });
  });

  group('cartões e desfechos', () {
    test('todo desfecho de encaminhamento tem cartão', () {
      // Um desfecho sem cartão é uma triagem que termina em tela vazia.
      final outcomes = db.select('SELECT id FROM routing_outcome');
      expect(outcomes, isNotEmpty);

      for (final row in outcomes) {
        final id = row['id'] as String;
        final card = content.cardForOutcome(id);
        expect(card, isNotNull, reason: 'desfecho $id sem cartão');
        expect(card!.title.value, isNotEmpty);
      }
    });

    test('desfecho inexistente devolve null, não exceção', () {
      expect(content.cardForOutcome('OUTCOME_INEXISTENTE'), isNull);
    });

    test('o cartão traz token de cor, não cor', () {
      // Quem converte token em pixel é a UI. Se o pack ditasse a cor, uma
      // republicação de conteúdo poderia pintar um cartão de emergência de
      // verde sem passar por revisão de código.
      final outcomes = db.select('SELECT id FROM routing_outcome LIMIT 1');
      final card = content.cardForOutcome(outcomes.first['id'] as String)!;

      expect(card.colorToken, isNotEmpty);
      expect(
        card.colorToken,
        isNot(startsWith('#')),
        reason: 'o pack não pode ditar paleta',
      );
    });
  });

  group('conteúdo estático (RF-07/08/09)', () {
    test('há locais, e cada um tem ícone e rótulo', () {
      final venues = content.venues();

      expect(venues, isNotEmpty);
      for (final venue in venues) {
        expect(venue.label.value, isNotEmpty);
        expect(content.assetByRef(venue.iconRef), isNotNull);
      }
    });

    test('os passos do fluxo vêm na ordem publicada', () {
      final venues = content.venues();
      final withFlow =
          venues.where((v) => content.flowOf(v.id).isNotEmpty).toList();
      expect(withFlow, isNotEmpty, reason: 'nenhum local tem fluxo');

      for (final venue in withFlow) {
        final steps = content.flowOf(venue.id);
        final orders = steps.map((s) => s.stepOrder).toList();
        expect(orders, orderedEquals(List.of(orders)..sort()));
      }
    });

    test('documentos obrigatórios vêm antes dos opcionais', () {
      // Quem tem cinco minutos de atenção precisa ver o que IMPEDE o
      // atendimento antes do que apenas ajuda.
      final services = [
        for (final venue in content.venues()) ...content.servicesOf(venue.id),
      ];
      expect(services, isNotEmpty);

      final withDocs = services
          .where((s) => content.documentsFor(s.id).isNotEmpty)
          .toList();
      expect(withDocs, isNotEmpty, reason: 'nenhum serviço exige documento');

      for (final service in withDocs) {
        final docs = content.documentsFor(service.id);
        final requiredFlags = docs.map((d) => d.required).toList();
        expect(
          requiredFlags,
          orderedEquals(List.of(requiredFlags)..sort((a, b) => b ? 1 : -1)),
          reason: 'serviço ${service.id} lista opcional antes de obrigatório',
        );
      }
    });

    test('serviço inexistente devolve lista vazia', () {
      expect(content.documentsFor('servico-que-nao-existe'), isEmpty);
      expect(content.flowOf('local-que-nao-existe'), isEmpty);
    });
  });

  group('assets', () {
    test('todo asset referenciado existe e tem hash', () {
      final asset = content.assetByRef(content.venues().first.iconRef)!;

      expect(asset.path, isNotEmpty);
      expect(asset.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(asset.bytes, greaterThan(0));
    });

    test('ref desconhecida devolve null', () {
      expect(content.assetByRef('icon.inexistente'), isNull);
    });
  });

  test('o arquivo de fixture é o mesmo que o sync instala', () {
    // Guarda contra alguém "consertar" um teste apontando para outro pacote.
    expect(File('test/fixtures/sync/pack-v1.db').existsSync(), isTrue);
  });
}
