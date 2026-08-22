/// A atualização do `user.db` por cima de uma instalação existente.
///
/// ===========================================================================
/// ESTE TESTE EXISTE POR UM MODO DE FALHA QUE INSTALAÇÃO LIMPA NÃO MOSTRA
/// ===========================================================================
///
/// A v2 acrescentou `theme_mode` e `font_scale`. Em aparelho novo, `onCreate`
/// cria o esquema completo e nada disso aparece. Em aparelho que JÁ TEM o app
/// — que é o caminho de todo mundo que usa —, o arquivo em disco continua na
/// v1, e sem `onUpgrade` a primeira leitura lança **no boot**, antes de
/// qualquer tela. O sintoma é o app não abrir mais.
///
/// Por isso o teste monta o banco v1 em SQL cru, exatamente como ele existe no
/// aparelho de alguém, e só então deixa o Drift abri-lo.
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/prefs/preferences_repository.dart';
import 'package:guia_ubs/prefs/user_database.dart';

import '../support/sqlite_test_libs.dart';

/// O esquema da v1, transcrito. Não é derivado do código atual de propósito:
/// se fosse, mudaria junto com o esquema e o teste deixaria de representar o
/// que está instalado no aparelho de alguém.
const String _v1Schema = '''
CREATE TABLE preferences (
  id INTEGER NOT NULL DEFAULT 1,
  locale_code TEXT NULL,
  telemetry_enabled INTEGER NOT NULL DEFAULT 1
    CHECK (telemetry_enabled IN (0, 1)),
  allow_metered_download INTEGER NOT NULL DEFAULT 0
    CHECK (allow_metered_download IN (0, 1)),
  setup_completed INTEGER NOT NULL DEFAULT 0
    CHECK (setup_completed IN (0, 1)),
  PRIMARY KEY (id)
);
''';

/// Um `user.db` na v1, com escolhas que uma pessoa real já teria feito.
QueryExecutor _databaseOnV1({
  String localeCode = 'es',
  bool telemetryEnabled = false,
  bool setupCompleted = true,
}) =>
    NativeDatabase.memory(setup: (raw) {
      raw
        ..execute(_v1Schema)
        ..execute(
          'INSERT INTO preferences '
          '(id, locale_code, telemetry_enabled, allow_metered_download, '
          'setup_completed) VALUES (1, ?, ?, 0, ?)',
          [localeCode, telemetryEnabled ? 1 : 0, setupCompleted ? 1 : 0],
        )
        // O Drift decide se migra pelo `user_version` do arquivo. Sem esta
        // linha o banco pareceria novo, `onUpgrade` nunca rodaria, e o teste
        // passaria sem testar nada.
        ..execute('PRAGMA user_version = 1');
    });

void main() {
  setUpAll(configureSqliteForTests);

  test('o app abre um user.db da v1 sem lançar', () async {
    final db = UserDatabase(_databaseOnV1());
    addTearDown(db.close);

    await expectLater(db.readPreferences(), completes);
  });

  test('a migração não perde o idioma já escolhido', () async {
    // O pior defeito aqui não é o app quebrar, é ele abrir mudo: um aparelho
    // configurado em espanhol voltando a perguntar o idioma, para alguém que
    // talvez não leia nenhum dos dois nomes.
    final db = UserDatabase(_databaseOnV1(localeCode: 'es'));
    addTearDown(db.close);

    expect((await PreferencesRepository(db).readAll()).locale, AppLocale.es);
  });

  test('as demais preferências da v1 atravessam intactas', () async {
    final db = UserDatabase(
      _databaseOnV1(telemetryEnabled: false, setupCompleted: true),
    );
    addTearDown(db.close);

    final prefs = await PreferencesRepository(db).readAll();

    expect(
      prefs.telemetryEnabled,
      isFalse,
      reason: 'um opt-out revogado pela atualização seria a LGPD-RF03 '
          'desfeita sem a pessoa saber',
    );
    expect(prefs.setupCompleted, isTrue, reason: 'reveria o First-Time Setup');
    expect(prefs.allowMeteredDownload, isFalse);
  });

  test('as colunas novas chegam com o padrão, não nulas', () async {
    // `addColumn` preenche as linhas existentes com o default declarado. Se
    // chegassem nulas, o tema viria ilegível e a escala de fonte iria a zero —
    // texto invisível numa tela para quem já tem dificuldade de ler.
    final db = UserDatabase(_databaseOnV1());
    addTearDown(db.close);

    final prefs = await PreferencesRepository(db).readAll();

    expect(prefs.themeMode, GubsThemeMode.system);
    expect(prefs.fontScale, 1.0);
  });

  test('depois de migrar, gravar as preferências novas funciona', () async {
    final db = UserDatabase(_databaseOnV1());
    addTearDown(db.close);
    final repo = PreferencesRepository(db);

    await repo.setThemeMode(GubsThemeMode.dark);
    await repo.setFontScale(1.6);

    final prefs = await repo.readAll();
    expect(prefs.themeMode, GubsThemeMode.dark);
    expect(prefs.fontScale, 1.6);
  });

  group('valores que o banco pode conter e a UI não pode aceitar', () {
    test('tema desconhecido recua para o do sistema', () {
      // Acontece de verdade num downgrade: uma versão futura grava um tema
      // novo, a pessoa volta para esta, e o valor continua no disco.
      expect(GubsThemeMode.fromStorage('sepia'), GubsThemeMode.system);
      expect(GubsThemeMode.fromStorage(null), GubsThemeMode.system);
      expect(GubsThemeMode.fromStorage('dark'), GubsThemeMode.dark);
    });

    test('escala fora dos passos recua para 1x', () {
      // Zero é o caso que importa: chegaria ao `TextScaler` e apagaria o texto
      // da tela inteira.
      expect(normalizeFontScale(0), 1.0);
      expect(normalizeFontScale(99), 1.0);
      expect(normalizeFontScale(null), 1.0);
      expect(normalizeFontScale(1.3), 1.3);
    });
  });
}
