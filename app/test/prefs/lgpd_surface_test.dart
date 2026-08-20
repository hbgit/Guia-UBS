/// A superfície de dados persistidos no aparelho, enumerada.
///
/// ===========================================================================
/// ESTE TESTE É UM CONTROLE DE CONFORMIDADE, NÃO UM TESTE DE UNIDADE
/// ===========================================================================
///
/// A LGPD-RF13 classifica sintoma como **dado sensível de saúde** (art. 5º II)
/// e proíbe persistir ou transmitir; a INV-2 diz o mesmo. Um `INSERT` a mais
/// num commit distraído basta para violar as duas, e nada no compilador
/// reclamaria.
///
/// A lista abaixo é a declaração explícita do que o app guarda. Acrescentar
/// coluna sem alterá-la reprova o build — e alterá-la é um ato deliberado, que
/// aparece no diff e exige justificar por que aquele dado precisa sobreviver
/// ao fechamento do app.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/prefs/preferences_repository.dart';
import 'package:guia_ubs/prefs/user_database.dart';
import 'package:guia_ubs/prefs/user_database_connection.dart';
import 'package:guia_ubs/prefs/locale_store.dart';

import '../support/sqlite_test_libs.dart';

/// Tudo que o `user.db` pode conter, revisado contra a LGPD.
///
/// Cada entrada é uma **escolha de operação do app**, nunca um atributo da
/// pessoa: idioma da interface, se contribui com telemetria agregada, se o
/// administrador liberou dados móveis, e se já passou pela configuração
/// inicial. Nenhuma delas identifica ninguém nem descreve saúde.
const Set<String> allowedUserDataColumns = {
  'id',
  'locale_code',
  'telemetry_enabled',
  'allow_metered_download',
  'setup_completed',
};

/// Tabelas que o `user.db` pode ter.
const Set<String> allowedUserDataTables = {'preferences'};

void main() {
  late UserDatabase db;

  setUpAll(configureSqliteForTests);
  setUp(() => db = inMemoryUserDatabase());
  tearDown(() => db.close());

  group('superfície de dados no aparelho', () {
    test('o user.db não tem nenhuma tabela além das revisadas', () async {
      final names = db.allTables.map((t) => t.actualTableName).toSet();

      expect(
        names,
        allowedUserDataTables,
        reason: 'tabela nova no user.db precisa de revisão de privacidade '
            '(LGPD-RF13) antes de existir',
      );
    });

    test('nenhuma coluna além das revisadas', () async {
      final columns = <String>{
        for (final table in db.allTables)
          for (final column in table.$columns) column.name,
      };

      expect(
        columns,
        allowedUserDataColumns,
        reason: 'coluna nova no user.db é dado novo persistido no aparelho — '
            'justifique-a contra a INV-2 e a LGPD-RF13',
      );
    });

    test('nenhum nome de coluna sugere dado clínico ou identificador', () async {
      // Rede de segurança para o caso de alguém atualizar a lista permitida
      // sem pensar. Não substitui a revisão; torna o descuido barulhento.
      const forbidden = [
        'symptom', 'sintoma', 'token', 'triage', 'triagem', 'severity',
        'outcome', 'diagnos', 'patient', 'paciente', 'cpf', 'sus', 'name',
        'nome', 'birth', 'nascimento', 'phone', 'telefone', 'email',
        'address', 'endereco', 'lat', 'lon', 'device_id', 'uuid',
      ];

      for (final table in db.allTables) {
        for (final column in table.$columns) {
          for (final word in forbidden) {
            expect(
              column.name.toLowerCase(),
              isNot(contains(word)),
              reason: '"${column.name}" parece dado pessoal ou clínico',
            );
          }
        }
      }
    });

    test('o esquema não expressa "vários usuários" — é um aparelho', () async {
      // Não há cadastro nem perfil. Um esquema capaz de distinguir pessoas
      // seria um esquema capaz de acumular histórico por pessoa.
      final prefs = db.preferences;
      expect(prefs.primaryKey, {prefs.id});

      await PreferencesRepository(db).write(AppLocale.pt);
      await PreferencesRepository(db).write(AppLocale.es);

      expect(
        await db.select(prefs).get(),
        hasLength(1),
        reason: 'gravar duas vezes criou uma segunda linha',
      );
    });
  });

  group('apagar meus dados (LGPD-RF03)', () {
    test('o apagamento devolve o aparelho ao estado inicial', () async {
      final repo = PreferencesRepository(db);
      await repo.write(AppLocale.es);
      await repo.setTelemetryEnabled(enabled: false);
      await repo.setAllowMeteredDownload(allowed: true);
      await repo.setSetupCompleted(completed: true);

      await repo.wipe();

      final after = await repo.readAll();
      expect(after.locale, isNull, reason: 'o app precisa perguntar de novo');
      expect(after.telemetryEnabled, isTrue);
      expect(after.allowMeteredDownload, isFalse);
      expect(after.setupCompleted, isFalse);
    });

    test('nenhum valor gravado pelo usuário sobrevive ao apagamento', () async {
      // Percorre as colunas de verdade, em SQL cru: se alguém acrescentar uma
      // preferência e esquecer de zerá-la no `wipe`, este teste a encontra sem
      // precisar ser atualizado.
      final repo = PreferencesRepository(db);
      await repo.write(AppLocale.es);
      await repo.setTelemetryEnabled(enabled: false);
      await repo.setAllowMeteredDownload(allowed: true);
      await repo.setSetupCompleted(completed: true);

      await repo.wipe();

      final row = await db.customSelect('SELECT * FROM preferences').getSingle();
      for (final entry in row.data.entries) {
        if (entry.key == 'id') continue;
        expect(
          entry.value,
          anyOf(isNull, 0, 1),
          reason: 'coluna ${entry.key} reteve "${entry.value}"',
        );
      }
      expect(row.data['locale_code'], isNull);
      expect(row.data['telemetry_enabled'], 1);
      expect(row.data['allow_metered_download'], 0);
      expect(row.data['setup_completed'], 0);
    });

    test('apagar é idempotente — a tela pode ser tocada duas vezes', () async {
      final repo = PreferencesRepository(db);

      await repo.wipe();
      await expectLater(repo.wipe(), completes);

      expect((await repo.readAll()).locale, isNull);
    });
  });
}
