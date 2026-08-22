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
/// `theme_mode` e `font_scale` entraram com a tela de ajustes e passaram pela
/// mesma pergunta: descrevem **como a interface é desenhada**, não quem a usa.
/// Não identificam ninguém, não dizem nada sobre saúde e nunca saem do
/// aparelho. Persistir as duas é o ponto delas — quem amplia a fonte costuma
/// fazê-lo por não enxergar, e obrigar a reescolher a cada abertura seria
/// acessibilidade pior sem nenhum ganho de privacidade, exatamente como já
/// vale para o idioma.
const Set<String> allowedUserDataColumns = {
  'id',
  'locale_code',
  'telemetry_enabled',
  'allow_metered_download',
  'setup_completed',
  'theme_mode',
  'font_scale',
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
      // Compara a linha apagada com a de um banco RECÉM-CRIADO, coluna por
      // coluna, em SQL cru. Assim o teste não precisa saber o que cada default
      // é — e continua encontrando a preferência que alguém acrescentar e
      // esquecer de zerar no `wipe`, sem nunca precisar ser atualizado.
      //
      // A versão anterior exigia que todo valor fosse `null`, `0` ou `1`, o
      // que só era verdade enquanto todas as colunas eram booleanas. A
      // primeira coluna de texto (`theme_mode`, default `system`) reprovou o
      // teste sem que nada estivesse errado — heurística de tipo no lugar de
      // comparação com o padrão.
      final repo = PreferencesRepository(db);
      await repo.write(AppLocale.es);
      await repo.setTelemetryEnabled(enabled: false);
      await repo.setAllowMeteredDownload(allowed: true);
      await repo.setSetupCompleted(completed: true);
      await repo.setThemeMode(GubsThemeMode.dark);
      await repo.setFontScale(1.6);

      await repo.wipe();

      final pristine = inMemoryUserDatabase();
      addTearDown(pristine.close);
      await pristine.readPreferences();

      final apagado =
          (await db.customSelect('SELECT * FROM preferences').getSingle()).data;
      final novo = (await pristine
              .customSelect('SELECT * FROM preferences')
              .getSingle())
          .data;

      for (final key in novo.keys) {
        expect(
          apagado[key],
          novo[key],
          reason: 'coluna $key reteve "${apagado[key]}" depois do apagamento',
        );
      }
      // Âncoras explícitas: se o default de alguma destas mudar, a comparação
      // acima continuaria passando e o significado teria mudado em silêncio.
      expect(apagado['locale_code'], isNull, reason: 'precisa perguntar de novo');
      expect(apagado['telemetry_enabled'], 1);
      expect(apagado['setup_completed'], 0);
      expect(apagado['theme_mode'], 'system');
      expect(apagado['font_scale'], 1.0);
    });

    test('apagar é idempotente — a tela pode ser tocada duas vezes', () async {
      final repo = PreferencesRepository(db);

      await repo.wipe();
      await expectLater(repo.wipe(), completes);

      expect((await repo.readAll()).locale, isNull);
    });
  });
}
