/// Leitura do `content.db` ativo.
///
/// ## Somente leitura, e isso é estrutural
///
/// O pacote é aberto em `OpenMode.readOnly`. O app **nunca** escreve conteúdo:
/// conteúdo clínico só entra por pack assinado com dupla revisão (INV-4), e um
/// caminho de escrita aqui seria um caminho para orientação não revisada
/// chegar ao usuário sem passar pela assinatura.
///
/// Este arquivo **não valida procedência**. Quando ele abre um pack, a
/// assinatura Ed25519 e o SHA-256 já foram conferidos pelo `sync/` (INV-3).
///
/// ## Idioma: recuar, não sumir
///
/// O packer bloqueia a publicação de pack com tradução faltando, então falta de
/// tradução no aparelho é defeito. Ainda assim recuamos para o idioma base em
/// vez de omitir o item: sumir com "Onde ir" de quem precisa é pior que
/// mostrá-lo em português para um hispanofalante — o ícone segue correto, e as
/// duas línguas são próximas. O recuo é sinalizado em [Localized.isFallback].
library;

import 'package:sqlite3/sqlite3.dart';

import '../../triage/domain/routing_rule.dart';
import '../domain/content_models.dart';
import 'pack_rule_source.dart';

/// Idioma base do pack. É o que sempre existe.
const String basePackLanguage = 'pt';

/// Consultas de leitura sobre um pack já verificado e aberto.
class ContentRepository {
  ContentRepository(this._db);

  final Database _db;

  // -------------------------------------------------------------------------
  // Identidade do pack
  // -------------------------------------------------------------------------

  PackInfo readPackInfo() {
    final rows = _db.select(
      'SELECT pack_version, schema_version, municipality_code, built_at, '
      'default_outcome_id, source_commit FROM pack_meta WHERE id = 1',
    );
    if (rows.isEmpty) {
      throw StateError('pack_meta ausente — pacote inválido');
    }
    final row = rows.first;
    return PackInfo(
      packVersion: row['pack_version'] as int,
      schemaVersion: row['schema_version'] as String,
      builtAt: row['built_at'] as String,
      defaultOutcomeId: row['default_outcome_id'] as String,
      municipalityCode: row['municipality_code'] as String?,
      sourceCommit: row['source_commit'] as String?,
    );
  }

  // -------------------------------------------------------------------------
  // Ontologia de sintomas (CAP-03)
  // -------------------------------------------------------------------------

  /// Tokens ativos, na ordem de exibição.
  ///
  /// Tokens `deprecated` ficam de fora da COMPOSIÇÃO mas continuam legíveis
  /// por id ([tokenById]): uma regra publicada pode referenciá-los, e uma
  /// regra que aponta para token invisível ainda precisa ser explicável.
  List<SymptomToken> symptomTokens({String lang = basePackLanguage, String? kind}) {
    final where = StringBuffer('t.deprecated = 0');
    final params = <Object?>[lang, basePackLanguage];
    if (kind != null) {
      where.write(' AND t.kind = ?');
      params.add(kind);
    }
    return _db
        .select(
          '''
          SELECT t.id, t.kind, t.icon_ref, t.sort_order,
                 tr.label AS label, tr.audio_ref AS audio_ref,
                 base.label AS base_label
          FROM symptom_token t
          LEFT JOIN token_translation tr ON tr.token_id = t.id AND tr.lang = ?
          LEFT JOIN token_translation base
                 ON base.token_id = t.id AND base.lang = ?
          WHERE $where
          ORDER BY t.sort_order, t.id
          ''',
          params,
        )
        .map(_toToken)
        .toList();
  }

  SymptomToken? tokenById(String id, {String lang = basePackLanguage}) {
    final rows = _db.select(
      '''
      SELECT t.id, t.kind, t.icon_ref, t.sort_order,
             tr.label AS label, tr.audio_ref AS audio_ref,
             base.label AS base_label
      FROM symptom_token t
      LEFT JOIN token_translation tr ON tr.token_id = t.id AND tr.lang = ?
      LEFT JOIN token_translation base ON base.token_id = t.id AND base.lang = ?
      WHERE t.id = ?
      ''',
      [lang, basePackLanguage, id],
    );
    return rows.isEmpty ? null : _toToken(rows.first);
  }

  SymptomToken _toToken(Row row) => SymptomToken(
        id: row['id'] as String,
        kind: row['kind'] as String,
        iconRef: row['icon_ref'] as String,
        sortOrder: row['sort_order'] as int,
        label: _localized(row, 'label'),
        audioRef: row['audio_ref'] as String?,
      );

  // -------------------------------------------------------------------------
  // Cartões
  // -------------------------------------------------------------------------

  ContentCard? cardById(String id, {String lang = basePackLanguage}) {
    final rows = _db.select(
      '''
      SELECT c.id, c.kind, c.icon_ref, c.color_token,
             tr.title AS title, tr.body AS body, tr.audio_ref AS audio_ref,
             base.title AS base_title, base.body AS base_body
      FROM card c
      LEFT JOIN card_translation tr ON tr.card_id = c.id AND tr.lang = ?
      LEFT JOIN card_translation base ON base.card_id = c.id AND base.lang = ?
      WHERE c.id = ?
      ''',
      [lang, basePackLanguage, id],
    );
    return rows.isEmpty ? null : _toCard(rows.first);
  }

  /// Cartão do desfecho de uma triagem — é o que a tela de resultado mostra.
  ContentCard? cardForOutcome(String outcomeId, {String lang = basePackLanguage}) {
    final rows = _db.select(
      'SELECT card_id FROM routing_outcome WHERE id = ?',
      [outcomeId],
    );
    if (rows.isEmpty) return null;
    return cardById(rows.first['card_id'] as String, lang: lang);
  }

  List<ContentCard> cardsOfKind(String kind, {String lang = basePackLanguage}) =>
      _db
          .select(
            '''
            SELECT c.id, c.kind, c.icon_ref, c.color_token,
                   tr.title AS title, tr.body AS body, tr.audio_ref AS audio_ref,
                   base.title AS base_title, base.body AS base_body
            FROM card c
            LEFT JOIN card_translation tr ON tr.card_id = c.id AND tr.lang = ?
            LEFT JOIN card_translation base
                   ON base.card_id = c.id AND base.lang = ?
            WHERE c.kind = ?
            ORDER BY c.sort_order, c.id
            ''',
            [lang, basePackLanguage, kind],
          )
          .map(_toCard)
          .toList();

  ContentCard _toCard(Row row) => ContentCard(
        id: row['id'] as String,
        kind: row['kind'] as String,
        iconRef: row['icon_ref'] as String,
        colorToken: row['color_token'] as String,
        title: _localized(row, 'title'),
        body: _localizedOrNull(row, 'body'),
        audioRef: row['audio_ref'] as String?,
      );

  // -------------------------------------------------------------------------
  // Locais, serviços, documentos, fluxo (RF-07/08/09)
  // -------------------------------------------------------------------------

  List<Venue> venues({String lang = basePackLanguage}) => _db
      .select(
        '''
        SELECT v.id, v.icon_ref, v.color_token,
               tr.label AS label, tr.audio_ref AS audio_ref,
               base.label AS base_label
        FROM venue v
        LEFT JOIN venue_translation tr ON tr.venue_id = v.id AND tr.lang = ?
        LEFT JOIN venue_translation base ON base.venue_id = v.id AND base.lang = ?
        ORDER BY v.id
        ''',
        [lang, basePackLanguage],
      )
      .map(
        (row) => Venue(
          id: row['id'] as String,
          iconRef: row['icon_ref'] as String,
          colorToken: row['color_token'] as String,
          label: _localized(row, 'label'),
          audioRef: row['audio_ref'] as String?,
        ),
      )
      .toList();

  List<Service> servicesOf(String venueId, {String lang = basePackLanguage}) => _db
      .select(
        '''
        SELECT s.id, s.venue_id, s.icon_ref, s.sort_order,
               tr.label AS label, tr.audio_ref AS audio_ref,
               base.label AS base_label
        FROM service s
        LEFT JOIN service_translation tr
               ON tr.service_id = s.id AND tr.lang = ?
        LEFT JOIN service_translation base
               ON base.service_id = s.id AND base.lang = ?
        WHERE s.venue_id = ?
        ORDER BY s.sort_order, s.id
        ''',
        [lang, basePackLanguage, venueId],
      )
      .map(
        (row) => Service(
          id: row['id'] as String,
          venueId: row['venue_id'] as String,
          iconRef: row['icon_ref'] as String,
          sortOrder: row['sort_order'] as int,
          label: _localized(row, 'label'),
          audioRef: row['audio_ref'] as String?,
        ),
      )
      .toList();

  /// Documentos de um serviço, obrigatórios primeiro.
  ///
  /// A ordem não é estética: quem tem cinco minutos de atenção precisa ver o
  /// que impede o atendimento antes do que apenas ajuda.
  List<RequiredDocument> documentsFor(
    String serviceId, {
    String lang = basePackLanguage,
  }) =>
      _db
          .select(
            '''
            SELECT d.id, d.icon_ref, d.image_ref, sd.required,
                   tr.label AS label, tr.hint AS hint,
                   tr.audio_ref AS audio_ref,
                   base.label AS base_label, base.hint AS base_hint
            FROM service_document sd
            JOIN document d ON d.id = sd.document_id
            LEFT JOIN document_translation tr
                   ON tr.document_id = d.id AND tr.lang = ?
            LEFT JOIN document_translation base
                   ON base.document_id = d.id AND base.lang = ?
            WHERE sd.service_id = ?
            ORDER BY sd.required DESC, d.id
            ''',
            [lang, basePackLanguage, serviceId],
          )
          .map(
            (row) => RequiredDocument(
              id: row['id'] as String,
              iconRef: row['icon_ref'] as String,
              imageRef: row['image_ref'] as String?,
              required: (row['required'] as int) == 1,
              label: _localized(row, 'label'),
              hint: _localizedOrNull(row, 'hint'),
              audioRef: row['audio_ref'] as String?,
            ),
          )
          .toList();

  List<FlowStep> flowOf(String venueId, {String lang = basePackLanguage}) => _db
      .select(
        '''
        SELECT f.id, f.venue_id, f.step_order, f.icon_ref,
               tr.title AS title, tr.body AS body, tr.audio_ref AS audio_ref,
               base.title AS base_title, base.body AS base_body
        FROM flow_step f
        LEFT JOIN flow_step_translation tr
               ON tr.step_id = f.id AND tr.lang = ?
        LEFT JOIN flow_step_translation base
               ON base.step_id = f.id AND base.lang = ?
        WHERE f.venue_id = ?
        ORDER BY f.step_order
        ''',
        [lang, basePackLanguage, venueId],
      )
      .map(
        (row) => FlowStep(
          id: row['id'] as String,
          venueId: row['venue_id'] as String,
          stepOrder: row['step_order'] as int,
          iconRef: row['icon_ref'] as String,
          title: _localized(row, 'title'),
          body: _localizedOrNull(row, 'body'),
          audioRef: row['audio_ref'] as String?,
        ),
      )
      .toList();

  // -------------------------------------------------------------------------
  // Regras (gate + RuleOnlyEngine)
  // -------------------------------------------------------------------------

  /// Modelo de encaminhamento do pack ativo.
  ///
  /// Delega a `loadRuleModel`, que já existia e é usado pelo gate e pela suite
  /// golden. Expor aqui evita que a UI precise conhecer duas portas de leitura
  /// do mesmo arquivo.
  RuleModel ruleModel() => loadRuleModel(_db);

  // -------------------------------------------------------------------------
  // Assets
  // -------------------------------------------------------------------------

  AssetRef? assetByRef(String ref) {
    final rows = _db.select(
      'SELECT ref, kind, path, sha256, bytes FROM asset WHERE ref = ?',
      [ref],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return AssetRef(
      ref: row['ref'] as String,
      kind: row['kind'] as String,
      path: row['path'] as String,
      sha256: row['sha256'] as String,
      bytes: row['bytes'] as int,
    );
  }

  // -------------------------------------------------------------------------
  // Resolução de idioma
  // -------------------------------------------------------------------------

  /// Texto obrigatório: usa o idioma pedido, recua para o base, e só em último
  /// caso devolve vazio — para que a tela mostre o ícone em vez de quebrar.
  Localized _localized(Row row, String column) {
    final value = row[column] as String?;
    if (value != null) return Localized(value);
    final base = row['base_$column'] as String?;
    return base != null
        ? Localized(base, isFallback: true)
        : const Localized('', isFallback: true);
  }

  /// Texto opcional: ausente no idioma pedido E no base significa ausente.
  Localized? _localizedOrNull(Row row, String column) {
    final value = row[column] as String?;
    if (value != null) return Localized(value);
    final base = row['base_$column'] as String?;
    return base == null ? null : Localized(base, isFallback: true);
  }
}
