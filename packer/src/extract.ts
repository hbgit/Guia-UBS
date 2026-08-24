/**
 * Banco de autoria -> linhas do pack.
 *
 * O CMS edita conteudo num banco mutavel, com colunas que o pack nao tem
 * (`version`, `updated_by`, `updated_at`, `status`, `storage_key`) e com regras
 * em rascunho convivendo com regras aprovadas. O pack e um snapshot imutavel de
 * um municipio, com apenas o que foi revisado.
 *
 * Este modulo faz a projecao, e ela tem tres responsabilidades que nao podem
 * falhar em silencio:
 *
 *   1. **So regras `approved` entram.** Rascunho no pack e conteudo nao revisado
 *      chegando a um aparelho sem internet — a INV-4 e o risco R5 do PRD.
 *   2. **So o municipio da release.** As tabelas municipais guardam varios; vazar
 *      o conteudo de outro seria orientacao de uma cidade exibida em outra.
 *   3. **Nenhuma coluna de autoria atravessa.** O pack nao tem onde guarda-las.
 *
 * A saida e SQL, na mesma forma de `seed/*.sql`, para entrar pelo MESMO
 * `buildPack()` e passar pelos MESMOS portoes. Um segundo construtor para o
 * caminho do banco seria um caminho cujos portoes ninguem exercita em toda PR.
 */
import type { Client } from '@libsql/client';

/** Como cada tabela do pack e projetada a partir da autoria. */
interface Projecao {
  /** Tabela, igual nos dois lados. */
  tabela: string;
  /** Colunas do PACK, na ordem do INSERT. */
  colunas: readonly string[];
  /** `true` quando a tabela guarda varios municipios. */
  municipal: boolean;
  /** Condicao extra, alem do municipio. */
  filtro?: string;
}

/**
 * A projecao completa, como dado.
 *
 * A ordem importa: as FKs sao verificadas durante a carga (`PRAGMA foreign_keys`
 * fica ON em `buildPack`), entao alvo antes de quem aponta.
 */
export const PROJECOES: readonly Projecao[] = [
  { tabela: 'asset', colunas: ['ref', 'kind', 'path', 'sha256', 'bytes'], municipal: false },
  {
    tabela: 'symptom_token',
    colunas: ['id', 'kind', 'icon_ref', 'sort_order', 'deprecated'],
    municipal: false,
  },
  {
    tabela: 'token_translation',
    colunas: ['token_id', 'lang', 'label', 'audio_ref'],
    municipal: false,
  },
  { tabela: 'venue', colunas: ['id', 'icon_ref', 'color_token', 'sort_order'], municipal: false },
  {
    tabela: 'venue_translation',
    colunas: ['venue_id', 'lang', 'label', 'audio_ref'],
    municipal: false,
  },
  {
    tabela: 'card',
    colunas: ['id', 'kind', 'icon_ref', 'color_token', 'sort_order'],
    municipal: false,
  },
  {
    tabela: 'card_translation',
    colunas: ['card_id', 'lang', 'title', 'body', 'audio_ref'],
    municipal: false,
  },
  {
    tabela: 'routing_outcome',
    colunas: ['id', 'severity_level', 'card_id', 'venue_id'],
    municipal: false,
  },
  {
    tabela: 'routing_rule',
    colunas: ['id', 'priority', 'outcome_id', 'rationale', 'clinical_source'],
    municipal: false,
    // A linha mais importante do arquivo.
    filtro: "status = 'approved'",
  },
  {
    tabela: 'routing_rule_term',
    colunas: ['rule_id', 'group_no', 'token_id', 'negated'],
    municipal: false,
    // Termo de regra em rascunho nao entra: entraria orfao, e a FK derrubaria o
    // build — mas com mensagem de banco em vez de "a regra nao esta aprovada".
    filtro: "rule_id IN (SELECT id FROM routing_rule WHERE status = 'approved')",
  },
  { tabela: 'service', colunas: ['id', 'venue_id', 'icon_ref', 'sort_order'], municipal: true },
  {
    tabela: 'service_translation',
    colunas: ['service_id', 'lang', 'label', 'audio_ref'],
    municipal: true,
  },
  { tabela: 'document', colunas: ['id', 'icon_ref', 'image_ref'], municipal: true },
  {
    tabela: 'document_translation',
    colunas: ['document_id', 'lang', 'label', 'hint', 'audio_ref'],
    municipal: true,
  },
  {
    tabela: 'service_document',
    colunas: ['service_id', 'document_id', 'required'],
    municipal: true,
  },
  { tabela: 'flow_step', colunas: ['id', 'venue_id', 'step_order', 'icon_ref'], municipal: true },
  {
    tabela: 'flow_step_translation',
    colunas: ['step_id', 'lang', 'title', 'body', 'audio_ref'],
    municipal: true,
  },
];

/** Literal SQL de um valor. Numeros e nulos sem aspas; texto com escape de aspa. */
function literal(valor: unknown): string {
  if (valor === null || valor === undefined) return 'NULL';
  if (typeof valor === 'number' || typeof valor === 'bigint') return String(valor);
  return `'${String(valor).replaceAll("'", "''")}'`;
}

export interface ExtracaoOptions {
  client: Client;
  /** `municipality.id` da release — nao o codigo IBGE. */
  municipalityId: string;
}

/**
 * Devolve as sentencas de dados do pack, na forma que `buildPack` consome.
 *
 * Somente leitura: o extrator nunca escreve no banco de autoria. Um packer que
 * escrevesse ali seria um segundo autor de conteudo, fora da trilha e fora do
 * travamento otimista.
 */
export async function extrairConteudo({
  client,
  municipalityId,
}: ExtracaoOptions): Promise<{ name: string; sql: string }[]> {
  const saida: { name: string; sql: string }[] = [];

  for (const [indice, projecao] of PROJECOES.entries()) {
    const condicoes: string[] = [];
    if (projecao.municipal) condicoes.push('municipality_id = ?');
    if (projecao.filtro) condicoes.push(projecao.filtro);
    const onde = condicoes.length > 0 ? ` WHERE ${condicoes.join(' AND ')}` : '';

    const resultado = await client.execute({
      sql: `SELECT ${projecao.colunas.join(', ')} FROM ${projecao.tabela}${onde}`,
      args: projecao.municipal ? [municipalityId] : [],
    });

    if (resultado.rows.length === 0) continue;

    const valores = resultado.rows
      .map((linha) => `  (${projecao.colunas.map((c) => literal(linha[c])).join(', ')})`)
      .join(',\n');

    saida.push({
      name: `${String(indice).padStart(3, '0')}_${projecao.tabela}.sql`,
      sql: `INSERT INTO ${projecao.tabela} (${projecao.colunas.join(', ')}) VALUES\n${valores};`,
    });
  }

  return saida;
}

/**
 * Casos golden do banco, na forma que `validateGolden` consome.
 *
 * A suite e GLOBAL: as regras que ela protege tambem sao, e um caso clinico que
 * so valesse para um municipio seria um caso que outro municipio publica sem
 * passar por ele.
 */
export async function lerGoldenDoBanco(
  client: Client,
): Promise<{ id: string; tokens: string[]; expect: string; reviewed_by?: string | null }[]> {
  const resultado = await client.execute(
    'SELECT id, tokens_json, expected_outcome_id, reviewed_by FROM golden_case WHERE active = 1',
  );
  return resultado.rows.map((linha) => ({
    id: String(linha.id),
    tokens: JSON.parse(String(linha.tokens_json)) as string[],
    expect: String(linha.expected_outcome_id),
    reviewed_by: linha.reviewed_by === null ? null : String(linha.reviewed_by),
  }));
}
