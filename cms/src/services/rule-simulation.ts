/**
 * Simula o efeito clinico de uma regra ANTES de grava-la.
 *
 * E a parte do editor que justifica o item existir. Sem ela, o revisor escreve
 * uma regra, salva, ela e aprovada, e o efeito so aparece no gate do packer —
 * quando desfazer significa reabrir um ciclo de revisao. Com ela, a pergunta
 * "o que isto muda?" tem resposta enquanto ainda da para desistir.
 *
 * Usa `evaluate()` do contrato: o MESMO avaliador do packer e o espelho do gate
 * Dart. Uma copia local mostraria um veredito aqui e outro na publicacao, o que
 * e pior do que nao ter simulacao nenhuma.
 */
import { evaluate, type Outcome, type Rule } from '@guia-ubs/contract';
import type { Client } from '@libsql/client';

import type { RegraProposta } from './rule-validation.js';

export interface MudancaDeCaso {
  casoId: string;
  tokens: string[];
  de: string;
  para: string;
  /**
   * `FALSO_NEGATIVO` e classe a parte, como no packer: e o caso em que o app
   * manda para casa alguem que precisava de emergencia. As outras mudancas sao
   * revisao clinica; esta e evento de seguranca do paciente.
   */
  classe: 'FALSO_NEGATIVO' | 'ESCALADA' | 'OUTRA';
}

export interface Simulacao {
  muda: MudancaDeCaso[];
  inalterados: number;
  /** Total de casos ativos — o revisor precisa ver o tamanho da amostra. */
  total: number;
  falsosNegativos: number;
  /** Casos cujo desfecho esperado nao bate com o conjunto ATUAL, antes da regra. */
  jaVermelhos: number;
}

interface ModeloDeRegras {
  rules: Rule[];
  outcomes: Map<string, Outcome>;
  defaultOutcomeId: string;
}

/**
 * Le regras, termos e desfechos do banco de autoria.
 *
 * Considera apenas regras `approved` mais a proposta: um rascunho de outra
 * pessoa nao pode influenciar a simulacao de quem esta editando agora, senao o
 * resultado depende de trabalho inacabado alheio.
 */
async function carregarModelo(client: Client): Promise<ModeloDeRegras> {
  const desfechos = await client.execute('SELECT id, severity_level FROM routing_outcome');
  const outcomes = new Map<string, Outcome>();
  for (const linha of desfechos.rows) {
    outcomes.set(String(linha.id), {
      id: String(linha.id),
      severityLevel: Number(linha.severity_level),
    });
  }

  const termos = await client.execute(
    `SELECT t.rule_id, t.group_no, t.token_id, t.negated
       FROM routing_rule_term t
       JOIN routing_rule r ON r.id = t.rule_id
      WHERE r.status = 'approved'`,
  );
  const porRegra = new Map<string, Rule['terms']>();
  for (const linha of termos.rows) {
    const id = String(linha.rule_id);
    const termo = {
      groupNo: Number(linha.group_no),
      tokenId: String(linha.token_id),
      negated: Number(linha.negated) === 1,
    };
    const balde = porRegra.get(id);
    if (balde) balde.push(termo);
    else porRegra.set(id, [termo]);
  }

  const regras = await client.execute(
    "SELECT id, priority, outcome_id FROM routing_rule WHERE status = 'approved' ORDER BY priority",
  );
  const rules: Rule[] = regras.rows.map((linha) => ({
    id: String(linha.id),
    priority: Number(linha.priority),
    outcomeId: String(linha.outcome_id),
    terms: porRegra.get(String(linha.id)) ?? [],
  }));

  return { rules, outcomes, defaultOutcomeId: desfechoPadrao(outcomes) };
}

/**
 * Desfecho padrao = o de MENOR severidade.
 *
 * Nao ha coluna de configuracao para isso no banco de autoria, e inventar uma
 * seria decidir por fora o que a semantica ja decide: "nenhuma regra casou"
 * significa o caso menos grave. E o mesmo raciocinio do app, que deriva os
 * extremos dos desfechos do proprio pack em vez de fixar limiares no binario.
 */
export function desfechoPadrao(outcomes: ReadonlyMap<string, Outcome>): string {
  let menor: Outcome | null = null;
  for (const desfecho of outcomes.values()) {
    if (menor === null || desfecho.severityLevel < menor.severityLevel) menor = desfecho;
  }
  if (menor === null) throw new Error('nao ha nenhum desfecho cadastrado');
  return menor.id;
}

/** Substitui (ou acrescenta) a regra proposta no conjunto. */
function comProposta(modelo: ModeloDeRegras, proposta: RegraProposta): Rule[] {
  const semAAntiga = modelo.rules.filter((r) => r.id !== proposta.id);
  return [
    ...semAAntiga,
    {
      id: proposta.id,
      priority: proposta.priority,
      outcomeId: proposta.outcomeId,
      terms: proposta.terms,
    },
  ];
}

export async function simularRegra(
  client: Client,
  proposta: RegraProposta,
): Promise<Simulacao> {
  const modelo = await carregarModelo(client);
  const propostas = comProposta(modelo, proposta);

  const casos = await client.execute(
    'SELECT id, tokens_json, expected_outcome_id FROM golden_case WHERE active = 1',
  );

  const maiorSeveridade = Math.max(
    ...[...modelo.outcomes.values()].map((o) => o.severityLevel),
    Number.NEGATIVE_INFINITY,
  );

  const muda: MudancaDeCaso[] = [];
  let inalterados = 0;
  let falsosNegativos = 0;
  let jaVermelhos = 0;

  for (const linha of casos.rows) {
    const tokens: string[] = JSON.parse(String(linha.tokens_json));
    const conjunto = new Set(tokens);

    const antes = evaluate(conjunto, modelo.rules, modelo.outcomes, modelo.defaultOutcomeId);
    const depois = evaluate(conjunto, propostas, modelo.outcomes, modelo.defaultOutcomeId);

    if (antes.outcomeId !== String(linha.expected_outcome_id)) jaVermelhos += 1;

    if (antes.outcomeId === depois.outcomeId) {
      inalterados += 1;
      continue;
    }

    const rebaixou =
      antes.severityLevel === maiorSeveridade && depois.severityLevel < antes.severityLevel;
    if (rebaixou) falsosNegativos += 1;

    muda.push({
      casoId: String(linha.id),
      tokens,
      de: antes.outcomeId,
      para: depois.outcomeId,
      classe: rebaixou
        ? 'FALSO_NEGATIVO'
        : depois.severityLevel > antes.severityLevel
          ? 'ESCALADA'
          : 'OUTRA',
    });
  }

  return { muda, inalterados, total: casos.rows.length, falsosNegativos, jaVermelhos };
}
