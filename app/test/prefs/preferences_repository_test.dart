/// Persistência das preferências e a migração vinda do item 10.
///
/// O foco não é o Drift funcionar — é o que acontece quando ele não funciona.
/// Preferência é a coisa menos importante do app; ela nunca pode ser o motivo
/// de uma tela de erro ou de um boot travado.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/prefs/preferences_repository.dart';
import 'package:guia_ubs/prefs/user_database.dart';
import 'package:guia_ubs/prefs/user_database_connection.dart';

import '../support/sqlite_test_libs.dart';

void main() {
  late UserDatabase db;
  late PreferencesRepository repo;
  late Directory tmp;

  setUpAll(configureSqliteForTests);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gubs_prefs_repo_');
    db = inMemoryUserDatabase();
    repo = PreferencesRepository(db);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  group('padrões', () {
    test('aparelho novo não tem idioma escolhido', () async {
      expect(await repo.read(), isNull);
    });

    test('telemetria começa habilitada, override de dados móveis não', () async {
      final prefs = await repo.readAll();

      // A telemetria já nasce agregada por coorte, com k-anonimato >= 20 e sem
      // identificador de aparelho (LGPD-RF14) — não há dado pessoal a
      // consentir. O opt-out existe por livre acesso (art. 18), não porque o
      // padrão seja invasivo.
      expect(prefs.telemetryEnabled, isTrue);
      // Já o download por dados móveis gasta o plano de alguém: só com decisão
      // explícita.
      expect(prefs.allowMeteredDownload, isFalse);
      expect(prefs.setupCompleted, isFalse);
    });
  });

  group('gravação', () {
    test('cada preferência sobrevive à releitura', () async {
      await repo.write(AppLocale.es);
      await repo.setTelemetryEnabled(enabled: false);
      await repo.setAllowMeteredDownload(allowed: true);
      await repo.setSetupCompleted(completed: true);

      final prefs = await repo.readAll();

      expect(prefs.locale, AppLocale.es);
      expect(prefs.telemetryEnabled, isFalse);
      expect(prefs.allowMeteredDownload, isTrue);
      expect(prefs.setupCompleted, isTrue);
    });

    test('gravar uma preferência não mexe nas outras', () async {
      await repo.setTelemetryEnabled(enabled: false);

      await repo.write(AppLocale.pt);

      expect((await repo.readAll()).telemetryEnabled, isFalse);
    });
  });

  group('banco indisponível', () {
    late PreferencesRepository broken;

    setUp(() async {
      final closed = inMemoryUserDatabase();
      await closed.close();
      broken = PreferencesRepository(closed);
    });

    test('leitura devolve os padrões, e o app abre', () async {
      // Um app que não abre porque não conseguiu ler a preferência de idioma é
      // pior que um app que pergunta o idioma de novo.
      expect((await broken.readAll()).locale, isNull);
    });

    test('gravação falha em silêncio, sem propagar', () async {
      await expectLater(broken.write(AppLocale.es), completes);
      await expectLater(
        broken.setTelemetryEnabled(enabled: false),
        completes,
      );
    });

    test('apagar dados não vira tela de erro nem com o banco quebrado', () async {
      // Se o banco já está inacessível, o efeito prático — nada legível em
      // disco — é o que a tela promete de qualquer forma.
      await expectLater(broken.wipe(), completes);
    });
  });

  group('migração do locale.json (item 10 → item 11)', () {
    File legacy() => File('${tmp.path}/locale.json');

    test('traz o idioma já escolhido', () async {
      await FileLocaleStore(legacy()).write(AppLocale.es);

      await repo.migrateFromFile(legacy());

      expect(await repo.read(), AppLocale.es);
      expect(
        legacy().existsSync(),
        isFalse,
        reason: 'duas fontes de verdade para a mesma preferência',
      );
    });

    test('não sobrescreve escolha mais recente do banco', () async {
      // O arquivo é a fonte antiga. Se o banco já tem idioma, ele é o que
      // vale — trocar por um valor mais velho seria regressão silenciosa.
      await FileLocaleStore(legacy()).write(AppLocale.es);
      await repo.write(AppLocale.pt);

      await repo.migrateFromFile(legacy());

      expect(await repo.read(), AppLocale.pt);
    });

    test('sem arquivo antigo, não faz nada', () async {
      await expectLater(repo.migrateFromFile(legacy()), completes);

      expect(await repo.read(), isNull);
    });

    test('arquivo antigo corrompido não impede o boot', () async {
      legacy().writeAsStringSync('{isto nao e json');

      await expectLater(repo.migrateFromFile(legacy()), completes);

      expect(await repo.read(), isNull);
    });

    test('rodar a migração duas vezes é seguro', () async {
      await FileLocaleStore(legacy()).write(AppLocale.es);

      await repo.migrateFromFile(legacy());
      await repo.migrateFromFile(legacy());

      expect(await repo.read(), AppLocale.es);
    });
  });
}
