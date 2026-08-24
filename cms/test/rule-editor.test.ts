/**
 * O editor de regras: integridade, transacao e o caminho da revisao.
 *
 * A regra e a parte clinicamente perigosa do CMS — uma regra mal escrita e
 * orientacao errada num aparelho sem internet (PRD risco R5). Estes testes
 * cobrem o que separa "gravou" de "gravou algo que faz sentido".
 */
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { auditRows, freshApp, pedido, seedConteudo, sessaoDe, type Fixture } from './support/app.js';

let f: Fixture;
let editor: string;
let revisor: string;

/** Ontologia e desfechos minimos: dois niveis de severidade e tres tokens. */
async function seedClinico(fixture: Fixture, cookie: string): Promise<void> {
  await seedConteudo(fixture, cookie);
  for (const [id, kind] of [
    ['chest', 'body_part'],
    ['pain', 'symptom'],
    ['severe', 'modifier'],
    ['velho', 'modifier'],
  ] as const) {
    await pedido(fixture, cookie, 'POST', '/api/content/symptom-tokens', {
      id, kind, iconRef: 'icon.exemplo', sortOrder: 0, deprecated: 0,
    });
  }
  await pedido(fixture, cookie, 'PATCH', '/api/content/symptom-tokens/velho', { deprecated: 1 }, 1);

  for (const [id, cor] of [['card.rotina', 'green'], ['card.emerg', 'red']] as const) {
    await pedido(fixture, cookie, 'POST', '/api/content/cards', {
      id, kind: 'result', iconRef: 'icon.exemplo', colorToken: cor, sortOrder: 0,
    });
  }
  await pedido(fixture, cookie, 'POST', '/api/content/venues', {
    id: 'UBS', iconRef: 'icon.exemplo', colorToken: 'green', sortOrder: 0,
  });
  await pedido(fixture, cookie, 'POST', '/api/content/routing-outcomes', {
    id: 'ROUTINE_UBS', severityLevel: 10, cardId: 'card.rotina', venueId: 'UBS',
  });
  await pedido(fixture, cookie, 'POST', '/api/content/routing-outcomes', {
    id: 'EMERGENCY', severityLevel: 100, cardId: 'card.emerg', venueId: 'UBS',
  });
}

before(async () => {
  f = await freshApp();
  editor = (await sessaoDe(f, 'editor')).cookie;
  revisor = (await sessaoDe(f, 'clinical_reviewer')).cookie;
  await seedClinico(f, editor);
});
after(async () => f.close());

const REGRA_VALIDA = {
  id: 'rf-dor-toracica',
  priority: 10,
  outcomeId: 'EMERGENCY',
  rationale: 'Dor toracica intensa e red flag.',
  clinicalSource: 'Protocolo ficticio de exemplo',
  terms: [
    { groupNo: 0, tokenId: 'chest', negated: false },
    { groupNo: 0, tokenId: 'pain', negated: false },
    { groupNo: 0, tokenId: 'severe', negated: false },
  ],
};

// ---------------------------------------------------------------------------
// Catalogo de integridade
// ---------------------------------------------------------------------------

test('regra sem termos e recusada — nunca dispararia', async () => {
  const r = await pedido(f, editor, 'POST', '/api/rules', { ...REGRA_VALIDA, terms: [] });
  assert.equal(r.status, 422);
  const corpo = (await r.json()) as { problemas: { codigo: string }[] };
  assert.ok(corpo.problemas.some((p) => p.codigo === 'sem_termos'));
});

test('token inexistente e token descontinuado sao recusados', async () => {
  const r = await pedido(f, editor, 'POST', '/api/rules', {
    ...REGRA_VALIDA,
    id: 'rf-tokens-ruins',
    terms: [
      { groupNo: 0, tokenId: 'nao-existe', negated: false },
      { groupNo: 0, tokenId: 'velho', negated: false },
    ],
  });
  assert.equal(r.status, 422);
  const codigos = ((await r.json()) as { problemas: { codigo: string }[] }).problemas.map(
    (p) => p.codigo,
  );
  assert.ok(codigos.includes('token_inexistente'));
  assert.ok(codigos.includes('token_descontinuado'));
});

test('grupo que exige o mesmo token presente E ausente e recusado', async () => {
  // Os termos de um grupo sao ligados por E: o grupo nunca satisfaz, e a regra
  // parece cobrir um caso que jamais cobre.
  const r = await pedido(f, editor, 'POST', '/api/rules', {
    ...REGRA_VALIDA,
    id: 'rf-contraditoria',
    terms: [
      { groupNo: 0, tokenId: 'chest', negated: false },
      { groupNo: 0, tokenId: 'chest', negated: true },
    ],
  });
  assert.equal(r.status, 422);
  const codigos = ((await r.json()) as { problemas: { codigo: string }[] }).problemas.map(
    (p) => p.codigo,
  );
  assert.ok(codigos.includes('grupo_contraditorio'));
});

test('grupos identicos sao recusados', async () => {
  const r = await pedido(f, editor, 'POST', '/api/rules', {
    ...REGRA_VALIDA,
    id: 'rf-duplicada',
    terms: [
      { groupNo: 0, tokenId: 'chest', negated: false },
      { groupNo: 1, tokenId: 'chest', negated: false },
    ],
  });
  assert.equal(r.status, 422);
  const codigos = ((await r.json()) as { problemas: { codigo: string }[] }).problemas.map(
    (p) => p.codigo,
  );
  assert.ok(codigos.includes('grupos_duplicados'));
});

test('os problemas voltam TODOS de uma vez, nao um por requisicao', async () => {
  // Um revisor que corrige um erro por requisicao desiste na terceira — e
  // desistir aqui significa publicar a regra do jeito que estava.
  const r = await pedido(f, editor, 'POST', '/api/rules', {
    id: 'rf-tudo-errado',
    priority: 1,
    outcomeId: 'DESFECHO_QUE_NAO_EXISTE',
    terms: [
      { groupNo: 0, tokenId: 'nao-existe', negated: false },
      { groupNo: 0, tokenId: 'velho', negated: false },
      { groupNo: 0, tokenId: 'velho', negated: true },
    ],
  });
  assert.equal(r.status, 422);
  const codigos = new Set(
    ((await r.json()) as { problemas: { codigo: string }[] }).problemas.map((p) => p.codigo),
  );
  assert.ok(codigos.size >= 4, `voltaram so ${codigos.size} classes de problema`);
  assert.ok(codigos.has('desfecho_inexistente'));
  assert.ok(codigos.has('token_inexistente'));
  assert.ok(codigos.has('token_descontinuado'));
  assert.ok(codigos.has('grupo_contraditorio'));
});

test('regra invalida NAO deixa rastro no banco', async () => {
  const linhas = await f.client.execute(
    "SELECT COUNT(*) AS n FROM routing_rule WHERE id LIKE 'rf-%'",
  );
  assert.equal(Number(linhas.rows[0]!.n), 0, 'uma recusa gravou a regra assim mesmo');
});

// ---------------------------------------------------------------------------
// Gravacao
// ---------------------------------------------------------------------------

test('regra valida grava com os termos, numa transacao', async () => {
  const r = await pedido(f, editor, 'POST', '/api/rules', REGRA_VALIDA);
  assert.equal(r.status, 201, await r.text());

  const termos = await f.client.execute(
    "SELECT COUNT(*) AS n FROM routing_rule_term WHERE rule_id = 'rf-dor-toracica'",
  );
  assert.equal(Number(termos.rows[0]!.n), 3);
});

test('a regra nasce como rascunho, nunca aprovada', async () => {
  // Aprovar e ato do item 19, e de outra pessoa: quem escreve nao aprova.
  const linhas = await f.client.execute(
    "SELECT status FROM routing_rule WHERE id = 'rf-dor-toracica'",
  );
  assert.equal(linhas.rows[0]!.status, 'draft');
});

test('a criacao entra na trilha com a regra inteira', async () => {
  const linhas = await auditRows(f);
  const entrada = linhas.find(
    (l) => l.action === 'rule_create' && l.entity_id === 'rf-dor-toracica',
  );
  assert.ok(entrada, 'regra criada sem entrada na trilha');
  const depois = JSON.parse(entrada.after_json!) as { terms: unknown[] };
  assert.equal(depois.terms.length, 3, 'a trilha precisa guardar os termos, nao so a regra');
});

test('revisor clinico nao escreve regra', async () => {
  const r = await pedido(f, revisor, 'POST', '/api/rules', { ...REGRA_VALIDA, id: 'rf-do-revisor' });
  assert.equal(r.status, 403);
});

// ---------------------------------------------------------------------------
// Edicao e revisao
// ---------------------------------------------------------------------------

test('editar rascunho substitui os termos em bloco', async () => {
  const r = await pedido(
    f, editor, 'PUT', '/api/rules/rf-dor-toracica',
    { ...REGRA_VALIDA, terms: [{ groupNo: 0, tokenId: 'chest', negated: false }] }, 1,
  );
  assert.equal(r.status, 200, await r.text());
  const termos = await f.client.execute(
    "SELECT COUNT(*) AS n FROM routing_rule_term WHERE rule_id = 'rf-dor-toracica'",
  );
  assert.equal(Number(termos.rows[0]!.n), 1, 'os termos antigos ficaram para tras');
});

test('editar sem If-Match e recusado com 428', async () => {
  const r = await pedido(f, editor, 'PUT', '/api/rules/rf-dor-toracica', REGRA_VALIDA);
  assert.equal(r.status, 428);
});

test('editar com versao velha recebe 409 com a versao atual', async () => {
  const r = await pedido(f, editor, 'PUT', '/api/rules/rf-dor-toracica', REGRA_VALIDA, 1);
  assert.equal(r.status, 409);
  assert.equal(((await r.json()) as { versaoAtual: number }).versaoAtual, 2);
});

test('regra APROVADA recusa edicao e diz o que fazer', async () => {
  await f.client.execute(
    "UPDATE routing_rule SET status = 'approved', version = version + 1 WHERE id = 'rf-dor-toracica'",
  );
  const r = await pedido(f, editor, 'PUT', '/api/rules/rf-dor-toracica', REGRA_VALIDA, 3);
  assert.equal(r.status, 409);
  const corpo = (await r.json()) as { next?: string };
  // Devolver so o erro do gatilho deixaria o editor sem saber que existe saida.
  assert.match(corpo.next ?? '', /\/revisao$/);
});

test('a revisao clona a regra sem tocar na aprovada', async () => {
  const r = await pedido(f, editor, 'POST', '/api/rules/rf-dor-toracica/revisao', {
    novoId: 'rf-dor-toracica-v2',
  });
  assert.equal(r.status, 201, await r.text());

  const original = await f.client.execute(
    "SELECT status, version FROM routing_rule WHERE id = 'rf-dor-toracica'",
  );
  assert.equal(original.rows[0]!.status, 'approved', 'a original mudou');
  assert.equal(Number(original.rows[0]!.version), 3, 'a original teve a versao mexida');

  const nova = await f.client.execute(
    "SELECT status FROM routing_rule WHERE id = 'rf-dor-toracica-v2'",
  );
  assert.equal(nova.rows[0]!.status, 'draft');

  const termos = await f.client.execute(
    "SELECT COUNT(*) AS n FROM routing_rule_term WHERE rule_id = 'rf-dor-toracica-v2'",
  );
  assert.equal(Number(termos.rows[0]!.n), 1, 'a revisao precisa levar os termos junto');
});

test('revisao com id ja usado responde 409, nao 500', async () => {
  const r = await pedido(f, editor, 'POST', '/api/rules/rf-dor-toracica/revisao', {
    novoId: 'rf-dor-toracica-v2',
  });
  assert.equal(r.status, 409);
});
