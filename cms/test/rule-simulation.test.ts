/**
 * A simulacao poe o efeito clinico da regra na frente de quem decide, ANTES de
 * gravar.
 *
 * Sem ela, o revisor escreve, salva, a regra e aprovada, e o efeito so aparece
 * no gate do packer — quando desfazer significa reabrir um ciclo de revisao.
 *
 * O caso que mais importa e o FALSO NEGATIVO: a regra que faz um caso de
 * emergencia passar a rotina. E o cenario em que o app manda para casa alguem
 * que precisava de emergencia, e por isso e classe a parte, como no packer.
 */
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { desfechoPadrao } from '../src/services/rule-simulation.js';
import { freshApp, pedido, seedConteudo, sessaoDe, type Fixture } from './support/app.js';

let f: Fixture;
let editor: string;
let revisor: string;

const RED_FLAG = {
  id: 'rf-toracica',
  priority: 10,
  outcomeId: 'EMERGENCY',
  terms: [
    { groupNo: 0, tokenId: 'chest', negated: false },
    { groupNo: 0, tokenId: 'pain', negated: false },
  ],
};

before(async () => {
  f = await freshApp();
  editor = (await sessaoDe(f, 'editor')).cookie;
  revisor = (await sessaoDe(f, 'clinical_reviewer')).cookie;
  await seedConteudo(f, editor);

  for (const [id, kind] of [
    ['chest', 'body_part'],
    ['pain', 'symptom'],
    ['throat', 'body_part'],
  ] as const) {
    await pedido(f, editor, 'POST', '/api/content/symptom-tokens', {
      id, kind, iconRef: 'icon.exemplo', sortOrder: 0, deprecated: 0,
    });
  }
  for (const [id, cor] of [['card.rotina', 'green'], ['card.emerg', 'red']] as const) {
    await pedido(f, editor, 'POST', '/api/content/cards', {
      id, kind: 'result', iconRef: 'icon.exemplo', colorToken: cor, sortOrder: 0,
    });
  }
  await pedido(f, editor, 'POST', '/api/content/venues', {
    id: 'UBS', iconRef: 'icon.exemplo', colorToken: 'green', sortOrder: 0,
  });
  await pedido(f, editor, 'POST', '/api/content/routing-outcomes', {
    id: 'ROUTINE_UBS', severityLevel: 10, cardId: 'card.rotina', venueId: 'UBS',
  });
  await pedido(f, editor, 'POST', '/api/content/routing-outcomes', {
    id: 'EMERGENCY', severityLevel: 100, cardId: 'card.emerg', venueId: 'UBS',
  });

  // Uma red flag JA APROVADA, e dois casos golden. Dados clinicos ficticios.
  await pedido(f, editor, 'POST', '/api/rules', RED_FLAG);
  await f.client.execute(
    "UPDATE routing_rule SET status = 'approved', version = version + 1 WHERE id = 'rf-toracica'",
  );
  const agora = '2026-08-24T12:00:00Z';
  await f.client.execute({
    sql: `INSERT INTO golden_case
            (id, tokens_json, expected_outcome_id, clinical_source, added_by, active)
          VALUES ('caso-toracico', '["chest","pain"]', 'EMERGENCY', 'ficticio', ?, 1)`,
    args: [(await f.client.execute('SELECT id FROM admin_user LIMIT 1')).rows[0]!.id as string],
  });
  await f.client.execute({
    sql: `INSERT INTO golden_case
            (id, tokens_json, expected_outcome_id, clinical_source, added_by, active)
          VALUES ('caso-garganta', '["throat"]', 'ROUTINE_UBS', 'ficticio', ?, 1)`,
    args: [(await f.client.execute('SELECT id FROM admin_user LIMIT 1')).rows[0]!.id as string],
  });
  void agora;
});
after(async () => f.close());

async function simular(cookie: string, proposta: unknown) {
  const r = await pedido(f, cookie, 'POST', '/api/rules/simular', proposta);
  return { status: r.status, corpo: (await r.json()) as Record<string, never> };
}

test('o desfecho padrao e o de MENOR severidade', () => {
  // Nao ha coluna de configuracao para isso, e inventar uma seria decidir por
  // fora o que a semantica ja decide: "nenhuma regra casou" = o caso menos grave.
  const desfechos = new Map([
    ['EMERGENCY', { id: 'EMERGENCY', severityLevel: 100 }],
    ['ROUTINE_UBS', { id: 'ROUTINE_UBS', severityLevel: 10 }],
  ]);
  assert.equal(desfechoPadrao(desfechos), 'ROUTINE_UBS');
});

test('regra inocua nao muda caso nenhum', async () => {
  const { status, corpo } = await simular(editor, {
    id: 'rf-nova-inocua',
    priority: 50,
    outcomeId: 'ROUTINE_UBS',
    terms: [{ groupNo: 0, tokenId: 'throat', negated: false }],
  });
  assert.equal(status, 200);
  const s = corpo.simulacao as unknown as { muda: unknown[]; inalterados: number; total: number };
  assert.deepEqual(s.muda, []);
  assert.equal(s.inalterados, 2);
  assert.equal(s.total, 2, 'a resposta precisa declarar o tamanho da amostra');
});

test('regra que REBAIXA um caso de emergencia aparece como FALSO_NEGATIVO', async () => {
  // Reescrever a red flag exigindo um token a mais faz o caso golden deixar de
  // casar — e ele cai para o desfecho padrao, que e rotina.
  const { corpo } = await simular(editor, {
    ...RED_FLAG,
    terms: [
      { groupNo: 0, tokenId: 'chest', negated: false },
      { groupNo: 0, tokenId: 'pain', negated: false },
      { groupNo: 0, tokenId: 'throat', negated: false },
    ],
  });
  const s = corpo.simulacao as unknown as {
    muda: { casoId: string; de: string; para: string; classe: string }[];
    falsosNegativos: number;
  };
  assert.equal(s.falsosNegativos, 1);
  const mudanca = s.muda.find((m) => m.casoId === 'caso-toracico');
  assert.ok(mudanca, 'a mudanca precisa nomear o caso');
  assert.equal(mudanca.de, 'EMERGENCY');
  assert.equal(mudanca.para, 'ROUTINE_UBS');
  assert.equal(mudanca.classe, 'FALSO_NEGATIVO');
});

test('regra que ESCALA um caso e classificada a parte do falso negativo', async () => {
  // Subir a severidade e revisao clinica, nao evento de seguranca do paciente.
  const { corpo } = await simular(editor, {
    id: 'rf-garganta-emerg',
    priority: 5,
    outcomeId: 'EMERGENCY',
    terms: [{ groupNo: 0, tokenId: 'throat', negated: false }],
  });
  const s = corpo.simulacao as unknown as {
    muda: { casoId: string; classe: string }[];
    falsosNegativos: number;
  };
  assert.equal(s.falsosNegativos, 0);
  assert.equal(s.muda.find((m) => m.casoId === 'caso-garganta')?.classe, 'ESCALADA');
});

test('a simulacao NAO grava nada', async () => {
  // O ponto inteiro e poder perguntar sem se comprometer.
  const regras = await f.client.execute('SELECT COUNT(*) AS n FROM routing_rule');
  assert.equal(Number(regras.rows[0]!.n), 1, 'a simulacao criou regra');
  const trilha = await f.client.execute(
    "SELECT COUNT(*) AS n FROM audit_entry WHERE action LIKE 'rule_%'",
  );
  assert.equal(Number(trilha.rows[0]!.n), 1, 'so a criacao da red flag deveria estar na trilha');
});

test('a simulacao devolve os problemas de integridade junto', async () => {
  // Simular uma regra invalida e perguntar duas coisas ao mesmo tempo: "isto e
  // valido?" e "o que muda?". Responder so a segunda deixaria o revisor
  // avaliando o efeito de uma regra que nem pode ser gravada.
  const { corpo } = await simular(editor, {
    id: 'rf-invalida',
    priority: 1,
    outcomeId: 'EMERGENCY',
    terms: [],
  });
  const problemas = corpo.problemas as unknown as { codigo: string }[];
  assert.ok(problemas.some((p) => p.codigo === 'sem_termos'));
});

test('quem so revisa PODE simular, mesmo sem poder escrever', async () => {
  // E a segregacao da LGPD-RF11 funcionando: o revisor precisa avaliar o efeito
  // de uma regra sem ter permissao de grava-la.
  const { status } = await simular(revisor, {
    id: 'rf-avaliada',
    priority: 9,
    outcomeId: 'EMERGENCY',
    terms: [{ groupNo: 0, tokenId: 'chest', negated: false }],
  });
  assert.equal(status, 200);

  const escrita = await pedido(f, revisor, 'POST', '/api/rules', RED_FLAG);
  assert.equal(escrita.status, 403, 'simular nao pode virar porta de escrita');
});

test('rascunho de outra pessoa nao influencia a simulacao', async () => {
  // Senao o resultado passa a depender de trabalho inacabado alheio, e duas
  // pessoas simulando a mesma regra veem respostas diferentes.
  //
  // A primeira versao deste teste comparava o `muda` e passava mesmo com o
  // defeito: incluir rascunhos dos DOIS lados da comparacao se cancela, e o diff
  // sai igual. Ele parecia significativo e media um cancelamento. A afirmacao
  // aqui e sobre o veredito ABSOLUTO do "antes" — que e onde o vazamento
  // aparece.
  await pedido(f, editor, 'POST', '/api/rules', {
    id: 'rascunho-alheio',
    priority: 1,
    outcomeId: 'EMERGENCY',
    terms: [{ groupNo: 0, tokenId: 'throat', negated: false }],
  });

  const { corpo } = await simular(editor, {
    id: 'rf-garganta-tambem',
    priority: 7,
    outcomeId: 'EMERGENCY',
    terms: [{ groupNo: 0, tokenId: 'throat', negated: false }],
  });
  const s = corpo.simulacao as unknown as { muda: { casoId: string; de: string }[] };
  const garganta = s.muda.find((m) => m.casoId === 'caso-garganta');

  assert.ok(
    garganta,
    'o rascunho alheio vazou: o "antes" ja escalava o caso e a mudanca sumiu do diff',
  );
  assert.equal(
    garganta.de,
    'ROUTINE_UBS',
    'o "antes" precisa refletir so o conjunto APROVADO',
  );
});
