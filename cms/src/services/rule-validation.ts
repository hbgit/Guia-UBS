/**
 * Catalogo de integridade do editor de regras.
 *
 * Recusa ANTES de gravar, e devolve a lista INTEIRA de problemas de uma vez. Um
 * revisor que corrige um erro por requisicao desiste na terceira — e desistir
 * aqui significa publicar a regra do jeito que estava.
 *
 * Estas checagens espelham as do `packer/src/validate.ts`, aplicadas cedo. La
 * elas rodam contra o pack ja construido e bloqueiam a assinatura; aqui rodam
 * contra o banco de autoria e bloqueiam a gravacao. Descobrir no packer significa
 * descobrir com a regra ja escrita e possivelmente ja aprovada.
 */
import type { Client } from '@libsql/client';

export interface TermoProposto {
  groupNo: number;
  tokenId: string;
  negated: boolean;
}

export interface RegraProposta {
  id: string;
  priority: number;
  outcomeId: string;
  rationale?: string | null;
  clinicalSource?: string | null;
  terms: TermoProposto[];
}

export interface ProblemaDeRegra {
  /** Estavel, para o cliente reagir sem casar com texto. */
  codigo:
    | 'sem_termos'
    | 'token_inexistente'
    | 'token_descontinuado'
    | 'desfecho_inexistente'
    | 'grupo_contraditorio'
    | 'grupos_duplicados'
    | 'prioridade_duplicada';
  mensagem: string;
}

/** Assinatura canonica de um grupo, para detectar duplicata e contradicao. */
function assinaturaDoGrupo(termos: TermoProposto[]): string {
  return termos
    .map((t) => `${t.negated ? '!' : ''}${t.tokenId}`)
    .sort()
    .join('&');
}

function agrupar(termos: TermoProposto[]): Map<number, TermoProposto[]> {
  const grupos = new Map<number, TermoProposto[]>();
  for (const termo of termos) {
    const balde = grupos.get(termo.groupNo);
    if (balde) balde.push(termo);
    else grupos.set(termo.groupNo, [termo]);
  }
  return grupos;
}

export async function validarRegra(
  client: Client,
  proposta: RegraProposta,
): Promise<ProblemaDeRegra[]> {
  const problemas: ProblemaDeRegra[] = [];

  // 1. Regra sem termo nunca dispara. `ruleMatches` ja devolve `false`, mas o
  //    efeito de um erro de autoria seria uma regra morta e SILENCIOSA — ela
  //    aparece na lista, parece ativa, e nao faz nada.
  if (proposta.terms.length === 0) {
    problemas.push({ codigo: 'sem_termos', mensagem: 'A regra nao tem nenhum termo e nunca dispararia.' });
  }

  // 2. Tokens: precisam existir e estar em circulacao.
  const ids = [...new Set(proposta.terms.map((t) => t.tokenId))];
  if (ids.length > 0) {
    const marcadores = ids.map(() => '?').join(', ');
    const encontrados = await client.execute({
      sql: `SELECT id, deprecated FROM symptom_token WHERE id IN (${marcadores})`,
      args: ids,
    });
    const porId = new Map(encontrados.rows.map((r) => [String(r.id), Number(r.deprecated) === 1]));

    for (const id of ids) {
      if (!porId.has(id)) {
        problemas.push({
          codigo: 'token_inexistente',
          mensagem: `O token "${id}" nao existe na ontologia.`,
        });
      } else if (porId.get(id)) {
        problemas.push({
          codigo: 'token_descontinuado',
          mensagem: `O token "${id}" esta descontinuado e nao pode entrar em regra nova.`,
        });
      }
    }
  }

  // 3. Desfecho: a FK pegaria, mas com mensagem de banco.
  const desfecho = await client.execute({
    sql: 'SELECT 1 FROM routing_outcome WHERE id = ?',
    args: [proposta.outcomeId],
  });
  if (desfecho.rows.length === 0) {
    problemas.push({
      codigo: 'desfecho_inexistente',
      mensagem: `O desfecho "${proposta.outcomeId}" nao existe.`,
    });
  }

  const grupos = agrupar(proposta.terms);

  // 4. Grupo contraditorio: o mesmo token exigido presente E ausente. Os termos
  //    de um grupo sao ligados por E, entao o grupo nunca satisfaz — a regra
  //    parece cobrir um caso que jamais cobre.
  for (const [numero, termos] of grupos) {
    const positivos = new Set(termos.filter((t) => !t.negated).map((t) => t.tokenId));
    const contraditorios = termos.filter((t) => t.negated && positivos.has(t.tokenId));
    for (const termo of contraditorios) {
      problemas.push({
        codigo: 'grupo_contraditorio',
        mensagem:
          `O grupo ${numero} exige "${termo.tokenId}" presente e ausente ao mesmo ` +
          'tempo, entao nunca sera satisfeito.',
      });
    }
  }

  // 5. Grupos identicos: redundancia pura, e quase sempre sinal de edicao pela
  //    metade (alguem duplicou o grupo para alterar e nao alterou).
  const vistos = new Map<string, number>();
  for (const [numero, termos] of grupos) {
    const assinatura = assinaturaDoGrupo(termos);
    const anterior = vistos.get(assinatura);
    if (anterior !== undefined) {
      problemas.push({
        codigo: 'grupos_duplicados',
        mensagem: `Os grupos ${anterior} e ${numero} sao identicos.`,
      });
    } else {
      vistos.set(assinatura, numero);
    }
  }

  // 6. Prioridade repetida no mesmo desfecho. `evaluate` desempata por
  //    prioridade DENTRO do mesmo nivel de severidade; duas regras com o mesmo
  //    numero deixam o desempate por conta da ordem de leitura do banco, que
  //    ninguem controla.
  const conflito = await client.execute({
    sql: `SELECT id FROM routing_rule
           WHERE outcome_id = ? AND priority = ? AND id <> ? AND status <> 'draft'`,
    args: [proposta.outcomeId, proposta.priority, proposta.id],
  });
  for (const linha of conflito.rows) {
    problemas.push({
      codigo: 'prioridade_duplicada',
      mensagem:
        `A regra "${String(linha.id)}" ja usa a prioridade ${proposta.priority} no mesmo ` +
        'desfecho; o desempate ficaria por conta da ordem de leitura.',
    });
  }

  return problemas;
}
