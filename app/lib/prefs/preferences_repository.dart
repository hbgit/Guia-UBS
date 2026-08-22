/// Acesso às preferências, e a migração do arquivo JSON que as guardava antes.
///
/// O item 10 gravava o idioma num `locale.json` porque o banco ainda não
/// existia. Trocar de armazenamento sem trazer o conteúdo antigo faria todo
/// aparelho já em uso voltar a perguntar o idioma — pequeno para nós, e um
/// susto para quem já tinha o app configurado. A migração roda uma vez, apaga
/// o arquivo e some.
library;

import 'dart:io';

import 'package:drift/drift.dart';

import 'locale_store.dart';
import 'user_database.dart';

/// Como a interface é pintada. Persistido em `preferences.theme_mode`.
///
/// Enum e não `String` pelo mesmo motivo da allowlist de telemetria: um valor
/// escrito errado no banco não pode virar um terceiro tema silencioso. Valor
/// desconhecido recua para [system], que é o padrão e nunca fica ilegível.
enum GubsThemeMode {
  system('system'),
  light('light'),
  dark('dark');

  const GubsThemeMode(this.storageKey);

  final String storageKey;

  static GubsThemeMode fromStorage(String? key) {
    for (final mode in values) {
      if (mode.storageKey == key) return mode;
    }
    return GubsThemeMode.system;
  }
}

/// Passos de ampliação de fonte oferecidos na tela de ajustes.
///
/// Três, e não um controle contínuo: o público-alvo escolhe entre opções
/// visíveis lado a lado, não arrasta um `Slider` até achar um número. Os
/// valores coincidem com escalas que `accessibility_test` já verifica.
const List<double> fontScaleSteps = [1.0, 1.3, 1.6];

/// Escala fora dos passos conhecidos recua para 1× em vez de ser aceita.
///
/// O banco pode conter qualquer `REAL` — inclusive 0 ou um número absurdo
/// gravado por uma versão futura e depois revertida. Nenhum dos dois pode
/// chegar ao `TextScaler`: 0 apagaria o texto da tela.
double normalizeFontScale(double? value) {
  if (value == null) return 1;
  for (final step in fontScaleSteps) {
    if ((value - step).abs() < 0.001) return step;
  }
  return 1;
}

/// Preferências lidas de uma vez, para a UI não consultar o banco por campo.
class UserPreferences {
  const UserPreferences({
    required this.locale,
    required this.telemetryEnabled,
    required this.allowMeteredDownload,
    required this.setupCompleted,
    required this.themeMode,
    required this.fontScale,
  });

  final AppLocale? locale;
  final bool telemetryEnabled;
  final bool allowMeteredDownload;
  final bool setupCompleted;
  final GubsThemeMode themeMode;
  final double fontScale;

  static const UserPreferences defaults = UserPreferences(
    locale: null,
    telemetryEnabled: true,
    allowMeteredDownload: false,
    setupCompleted: false,
    themeMode: GubsThemeMode.system,
    fontScale: 1,
  );
}

/// Preferências sobre o `user.db`, implementando também a porta [LocaleStore]
/// que a casca já usa.
class PreferencesRepository implements LocaleStore {
  PreferencesRepository(this.database);

  final UserDatabase database;

  /// Lê tudo de uma vez.
  Future<UserPreferences> readAll() async {
    try {
      final row = await database.readPreferences();
      return UserPreferences(
        locale: AppLocale.fromCode(row.localeCode),
        telemetryEnabled: row.telemetryEnabled,
        allowMeteredDownload: row.allowMeteredDownload,
        setupCompleted: row.setupCompleted,
        themeMode: GubsThemeMode.fromStorage(row.themeMode),
        fontScale: normalizeFontScale(row.fontScale),
      );
    } on Object {
      // Banco corrompido devolve os padrões, que é um app funcional pedindo o
      // idioma de novo. Lançar aqui travaria o boot por causa de preferências.
      return UserPreferences.defaults;
    }
  }


  @override
  Future<AppLocale?> read() async => (await readAll()).locale;

  @override
  Future<void> write(AppLocale locale) => _patch(
        PreferencesCompanion(localeCode: Value(locale.code)),
      );

  Future<void> setTelemetryEnabled({required bool enabled}) =>
      _patch(PreferencesCompanion(telemetryEnabled: Value(enabled)));

  Future<void> setAllowMeteredDownload({required bool allowed}) =>
      _patch(PreferencesCompanion(allowMeteredDownload: Value(allowed)));

  Future<void> setSetupCompleted({required bool completed}) =>
      _patch(PreferencesCompanion(setupCompleted: Value(completed)));

  Future<void> setThemeMode(GubsThemeMode mode) =>
      _patch(PreferencesCompanion(themeMode: Value(mode.storageKey)));

  /// Grava apenas passos conhecidos: normaliza ANTES de tocar o disco, para
  /// que uma escala inválida não sobreviva no banco esperando ser lida.
  Future<void> setFontScale(double scale) =>
      _patch(PreferencesCompanion(fontScale: Value(normalizeFontScale(scale))));

  /// LGPD-RF03: apaga tudo, sem confirmação de volta e sem recuperação.
  Future<void> wipe() async {
    try {
      await database.wipe();
    } on Object {
      // Nem o apagamento pode virar tela de erro. Se o banco já está
      // inacessível, o efeito prático — nada legível em disco — é o mesmo.
    }
  }

  Future<void> _patch(PreferencesCompanion patch) async {
    try {
      await database.updatePreferences(patch);
    } on Object {
      // Ver `LocaleController.select`: preferência que não grava vale para
      // esta sessão e é perguntada de novo depois. Nunca é erro na tela.
    }
  }

  /// Traz o idioma do `locale.json` do item 10 para o banco, uma única vez.
  ///
  /// Só migra se o banco ainda não tem idioma: o arquivo é a fonte antiga, e
  /// sobrescrever uma escolha mais recente com uma mais velha seria pior que
  /// não migrar. Apaga o arquivo ao terminar — deixá-lo para trás criaria duas
  /// fontes de verdade para a mesma preferência.
  Future<void> migrateFromFile(File legacy) async {
    try {
      if (!legacy.existsSync()) return;
      final fromFile = await FileLocaleStore(legacy).read();
      if (fromFile != null && (await read()) == null) {
        await write(fromFile);
      }
      await legacy.delete();
    } on Object {
      // Migração é conveniência: falhar nela custa uma pergunta de idioma.
    }
  }
}
