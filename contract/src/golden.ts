/**
 * Formato da revisao clinica dos casos golden e do registro publico de atestados.
 *
 * Fonte unica, consumida pelo `packer` (portao de assinatura) e pelo `cms`
 * (cadastro do atestado). Valida FORMATO; a existencia e a situacao do registro
 * profissional sao conferidas por pessoa no cadastro do conselho
 * (docs/revisao-golden.md).
 *
 * Duas formas de dado, de proposito:
 *  - `EntradaRegistro` (publica, vai ao repositorio): ID, conselho, UF, categoria
 *    e hash do termo. Sem nome, sem numero de registro.
 *  - `Atestado` (completa, so no CMS): acrescenta nome e numero de registro.
 */
import { z } from 'zod';

export const CONSELHOS = ['CRM', 'COREN'] as const;

/** Categorias de COREN aceitas: so enfermeiro. TE, AE, OBST e PAR nao revisam triagem. */
export const CATEGORIAS_COREN_ACEITAS = ['ENF'] as const;

export const UFS = [
  'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA',
  'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
] as const;
export type Uf = (typeof UFS)[number];

/** Quantidade minima de revisores por caso golden. */
export const MIN_REVISORES = 1;

export const ATESTADO_ID = /^AT-\d{4}$/;

/** Prefixos de acao de auditoria que mexem em conteudo e, portanto, reabrem a revisao. */
export const ACOES_QUE_REABREM = ['content_', 'rule_', 'golden_'] as const;

/**
 * Acoes de auditoria que NAO tocam conteudo. Lista exata, nao prefixo: acao nova
 * fica fora dela e, por omissao, reabre a revisao (falha para o lado seguro).
 * O middleware emite `${acao}_failed` para as de autenticacao; o worker do packer
 * emite `release_<estado>` sem ator.
 */
export const ACOES_QUE_NAO_REABREM: readonly string[] = [
  'sign_in',
  'sign_in_failed',
  'sign_in_locked',
  'sign_out',
  'sign_out_failed',
  'two_factor_enable',
  'two_factor_enable_failed',
  'two_factor_disable',
  'two_factor_disable_failed',
  'two_factor_verify',
  'two_factor_verify_failed',
  'change_password',
  'change_password_failed',
  'user_create',
  'user_disable',
  'user_enable',
  'user_role_change',
  'release_create',
  'release_submit',
  'release_approve',
  'release_reject',
  'release_requeue',
  'release_revoke',
  'release_building',
  'release_approved',
  'release_built',
  'release_published',
];

type Identificacao =
  | { conselho: 'CRM'; uf: Uf }
  | { conselho: 'COREN'; categoria: 'ENF'; uf: Uf };
export type EntradaRegistro = Identificacao & { id: string; termo_sha256: string };
export type RevisorYaml = Identificacao & { atestado: string; reviewed_at: string };
/** Atestado completo — so no CMS. */
export type Atestado = Identificacao & {
  id: string;
  nome: string;
  registro: string;
  termo_sha256: string;
};

export type EstadoRevisao =
  | { estado: 'ausente' }
  | { estado: 'invalida'; problemas: string[] }
  | { estado: 'valida'; revisores: RevisorYaml[] };

const SO_ENFERMEIRO =
  'so enfermeiro (ENF) revisa; COREN de tecnico, auxiliar, obstetriz ou parteira nao vale';

const ufSchema = z.enum(UFS);
const idSchema = z.string().regex(ATESTADO_ID, 'formato esperado AT-0000');
const sha256Schema = z.string().regex(/^[0-9a-f]{64}$/, 'esperado SHA-256 em hex minusculo (64)');

/** Conselho + UF + categoria; `shape` acrescenta os campos de cada uso. */
function comIdentificacao<T extends z.ZodRawShape>(shape: T) {
  const crm = z.object({ conselho: z.literal('CRM'), uf: ufSchema, ...shape }).strict();
  const coren = z
    .object({
      conselho: z.literal('COREN'),
      categoria: z.literal('ENF', { error: SO_ENFERMEIRO }),
      uf: ufSchema,
      ...shape,
    })
    .strict();
  return z.discriminatedUnion('conselho', [crm, coren], {
    error: () => `conselho deve ser ${CONSELHOS.join(' ou ')}`,
  });
}

/** Data de calendario AAAA-MM-DD valida (ida e volta por Date.UTC). */
function dataValida(s: string): boolean {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return false;
  const [a, mes, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const t = new Date(Date.UTC(a, mes - 1, d));
  return t.getUTCFullYear() === a && t.getUTCMonth() === mes - 1 && t.getUTCDate() === d;
}

/** Data de revisao: calendario valido e nao posterior ao dia UTC de `agora`. */
function dataDeRevisaoSchema(agora: Date) {
  const hoje = agora.toISOString().slice(0, 10);
  return z
    .string({ error: 'esperado texto AAAA-MM-DD' })
    .refine(dataValida, 'esperado data de calendario AAAA-MM-DD')
    .refine((s) => !dataValida(s) || s <= hoje, `data futura (hoje UTC e ${hoje})`);
}

/** Valida um `reviewed_at` avulso; devolve os problemas (vazio = valida). */
export function avaliarDataRevisao(valor: unknown, agora: Date): string[] {
  const r = dataDeRevisaoSchema(agora).safeParse(valor);
  return r.success ? [] : r.error.issues.map((i) => i.message);
}

function formatar(prefixo: string, erro: z.ZodError): string[] {
  return erro.issues.map((i) => {
    const caminho = i.path.reduce<string>(
      (acc, p) => (typeof p === 'number' ? `${acc}[${p}]` : acc ? `${acc}.${String(p)}` : String(p)),
      prefixo,
    );
    return `${caminho}: ${i.message}`;
  });
}

export function avaliarRevisao(
  entrada: { reviewed_by?: unknown; reviewed_at?: unknown },
  agora: Date,
): EstadoRevisao {
  if (entrada.reviewed_by === undefined || entrada.reviewed_by === null) {
    return { estado: 'ausente' };
  }
  const revisorSchema = comIdentificacao({
    atestado: idSchema,
    reviewed_at: dataDeRevisaoSchema(agora),
  });
  const listaSchema = z.array(revisorSchema).min(MIN_REVISORES, `ao menos ${MIN_REVISORES} revisor(es)`);

  const problemas: string[] = [];
  if (entrada.reviewed_at !== undefined) {
    problemas.push('reviewed_at: reviewed_at mora em cada revisor de reviewed_by, nao no caso');
  }
  const r = listaSchema.safeParse(entrada.reviewed_by);
  if (!r.success) {
    problemas.push(...formatar('reviewed_by', r.error));
    return { estado: 'invalida', problemas };
  }
  const vistos = new Set<string>();
  r.data.forEach((rev, i) => {
    if (vistos.has(rev.atestado)) {
      problemas.push(`reviewed_by[${i}].atestado: ${rev.atestado} duplicado na lista`);
    }
    vistos.add(rev.atestado);
  });
  if (problemas.length > 0) return { estado: 'invalida', problemas };
  return { estado: 'valida', revisores: r.data as RevisorYaml[] };
}

const registroNumeroSchema = z.string({
  error: (i) =>
    typeof i.input === 'number'
      ? 'registro numerico perde zeros a esquerda no YAML: escreva entre aspas ("000123")'
      : 'registro deve ser texto com so digitos',
});

export function avaliarAtestado(
  entrada: unknown,
): { ok: true; atestado: Atestado } | { ok: false; problemas: string[] } {
  const schema = comIdentificacao({
    id: idSchema,
    nome: z
      .string()
      .transform((s) => s.trim())
      .refine((s) => s.split(/\s+/).filter(Boolean).length >= 2, 'nome completo, ao menos 2 palavras'),
    registro: registroNumeroSchema.pipe(
      z.string().regex(/^\d{1,8}$/, {
        error: (i) =>
          `registro deve ter so digitos (1 a 8), sem pontos, hifen nem sufixo; a categoria vai no campo categoria (recebido "${String(i.input)}")`,
      }),
    ),
    termo_sha256: sha256Schema,
  });
  const r = schema.safeParse(entrada);
  if (!r.success) return { ok: false, problemas: formatar('atestado', r.error) };
  return { ok: true, atestado: r.data as Atestado };
}

export function avaliarRegistro(
  entrada: unknown,
): { ok: true; entradas: EntradaRegistro[] } | { ok: false; problemas: string[] } {
  const schema = z
    .object({
      atestados: z.array(
        comIdentificacao({ id: idSchema, termo_sha256: sha256Schema }),
      ),
    })
    .strict();
  const r = schema.safeParse(entrada);
  if (!r.success) return { ok: false, problemas: formatar('', r.error).map((m) => m.replace(/^\.?/, '')) };
  const problemas: string[] = [];
  const ids = new Set<string>();
  const hashes = new Set<string>();
  r.data.atestados.forEach((e, i) => {
    if (ids.has(e.id)) problemas.push(`atestados[${i}].id: ${e.id} repetido`);
    ids.add(e.id);
    if (hashes.has(e.termo_sha256)) {
      problemas.push(`atestados[${i}].termo_sha256: hash repetido (um termo por profissional)`);
    }
    hashes.add(e.termo_sha256);
  });
  if (problemas.length > 0) return { ok: false, problemas };
  return { ok: true, entradas: r.data.atestados as EntradaRegistro[] };
}

/** Problemas de coerencia: atestado ausente do registro, ou conselho/uf/categoria divergentes. */
export function conferirContraRegistro(
  revisores: readonly (Identificacao & { atestado: string })[],
  registro: readonly EntradaRegistro[],
): string[] {
  const porId = new Map(registro.map((e) => [e.id, e]));
  const problemas: string[] = [];
  revisores.forEach((rev, i) => {
    const e = porId.get(rev.atestado);
    if (!e) {
      problemas.push(
        `reviewed_by[${i}].atestado: ${rev.atestado} nao consta em seed/golden/atestados.yaml`,
      );
      return;
    }
    const cat = (x: Identificacao) => ('categoria' in x ? x.categoria : undefined);
    for (const [campo, a, b] of [
      ['conselho', rev.conselho, e.conselho],
      ['uf', rev.uf, e.uf],
      ['categoria', cat(rev), cat(e)],
    ] as const) {
      if (a !== b) {
        problemas.push(
          `reviewed_by[${i}].${campo}: "${String(a)}" diverge do registro (${rev.atestado} tem "${String(b)}")`,
        );
      }
    }
  });
  return problemas;
}
