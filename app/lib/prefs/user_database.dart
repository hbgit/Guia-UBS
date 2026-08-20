/// `user.db` — as preferências do aparelho, e **nada além disso**.
///
/// ===========================================================================
/// ESTE ARQUIVO É A SUPERFÍCIE AUDITÁVEL DA LGPD NO DEVICE
/// ===========================================================================
///
/// A INV-2 e a LGPD-RF13 dizem a mesma coisa por caminhos diferentes: nenhum
/// dado do usuário final vai para disco. A sequência de sintomas — que é dado
/// de saúde, art. 5º II — vive em memória durante a triagem e morre com ela.
/// O que sobra para persistir são escolhas de operação do app.
///
/// ## Por que colunas tipadas e não chave-valor
///
/// Uma tabela `(chave, valor)` aceitaria qualquer coisa que qualquer código
/// futuro resolvesse gravar, e "o que este app guarda sobre a pessoa?" deixaria
/// de ter resposta estática — só auditoria de runtime responderia. Com colunas
/// declaradas, **as colunas SÃO a resposta**, e
/// `test/prefs/lgpd_surface_test.dart` as enumera e reprova qualquer acréscimo
/// não revisado. Custa uma migração por preferência nova; compra a capacidade
/// de provar o que não guardamos.
///
/// ## Linha única
///
/// Não há conta, cadastro nem perfil: um aparelho, um conjunto de preferências.
/// A chave primária é fixa em 1 — não existe "outro usuário" a distinguir, e é
/// bom que o esquema torne isso impossível de expressar.
library;

import 'package:drift/drift.dart';

part 'user_database.g.dart';

/// Preferências do aparelho. **Linha única** (`id = 1`).
///
/// Antes de acrescentar coluna aqui, responda: isto é uma escolha de operação
/// do app, ou é um dado sobre a pessoa? Se for a segunda, não entra.
class Preferences extends Table {
  /// Sempre 1. Ver o comentário da biblioteca.
  IntColumn get id => integer().withDefault(const Constant(1))();

  /// Idioma da interface e da voz (RF-01). `null` = ainda não escolheu, o que
  /// é o que faz a tela de seleção aparecer no primeiro acesso.
  TextColumn get localeCode => text().nullable()();

  /// Opt-out de telemetria agregada (LGPD-RF03).
  ///
  /// Começa **habilitada** porque a telemetria já nasce agregada por coorte,
  /// sem identificador de aparelho e com k-anonimato ≥ 20 (LGPD-RF14) — não há
  /// dado pessoal a consentir. O opt-out existe mesmo assim, por livre acesso
  /// (art. 18): a pessoa pode não querer contribuir, e isso basta.
  BoolColumn get telemetryEnabled =>
      boolean().withDefault(const Constant(true))();

  /// Administrador autorizou baixar o modelo por dados móveis (ADR-003).
  ///
  /// É configuração de operação em campo, não preferência do paciente: quem a
  /// liga é o agente de saúde num posto sem Wi-Fi.
  BoolColumn get allowMeteredDownload =>
      boolean().withDefault(const Constant(false))();

  /// O usuário já passou pelo First-Time Setup.
  ///
  /// Persistir isto é o que impede a apresentação de valor de reaparecer a
  /// cada abertura para quem escolheu seguir sem o modelo — antes do item 11 a
  /// decisão vivia só em memória e se perdia no fechamento do app.
  BoolColumn get setupCompleted =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Preferences])
class UserDatabase extends _$UserDatabase {
  UserDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await into(preferences).insert(
            const PreferencesCompanion(id: Value(1)),
            mode: InsertMode.insertOrIgnore,
          );
        },
      );

  /// A linha única, criada sob demanda.
  ///
  /// `onCreate` já a insere, mas um `user.db` que sobreviveu a uma falha de
  /// gravação pode não tê-la. Preferência ausente não pode virar exceção no
  /// boot, então lemos com padrão em vez de exigir presença.
  Future<Preference> readPreferences() async {
    final row = await (select(preferences)..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    if (row != null) return row;

    await into(preferences).insert(
      const PreferencesCompanion(id: Value(1)),
      mode: InsertMode.insertOrIgnore,
    );
    return (select(preferences)..where((t) => t.id.equals(1))).getSingle();
  }

  Future<void> updatePreferences(PreferencesCompanion patch) async {
    await readPreferences();
    await (update(preferences)..where((t) => t.id.equals(1))).write(patch);
  }

  /// "Apagar meus dados" (LGPD-RF03, LGPD-RT10).
  ///
  /// Zera **tudo**, inclusive o idioma: a operação é irreversível por
  /// definição, e devolver o aparelho ao estado de fábrica é o que a tela
  /// promete. O app volta a perguntar o idioma na próxima abertura, e isso é o
  /// sinal visível de que o apagamento aconteceu de fato.
  Future<void> wipe() async {
    await delete(preferences).go();
    await into(preferences).insert(const PreferencesCompanion(id: Value(1)));
  }
}
