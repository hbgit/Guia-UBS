/**
 * Rotas de casos golden (P0-2): o caso nasce INATIVO e so a revisao de um
 * profissional atestado o ativa. Revisao e so acrescimo — nao ha PUT nem DELETE.
 *
 * Todos os dados sao FICTICIOS: nomes inventados, IDs AT-9xxx, registros zerados.
 */
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { auditRows, freshApp, pedido, seedConteudo, sessaoDe, type Fixture } from './support/app.js';

let f: Fixture;
let editor: { cookie: string; id: string };
let revisor: { cookie: string; id: string };
let revisor2: { cookie: string; id: string };

const termo = (c: string) => c.repeat(64);
const ATESTADO = {
  id: 'AT-9101',
  nome: 'Revisora Ficticia Um',
  conselho: 'CRM',
  uf: 'RR',
  registro: '000101',
  termo_sha256: termo('a'),
};
const ATESTADO_2 = {
  id: 'AT-9102',
  nome: 'Revisor Ficticio Dois',
  conselho: 'COREN',
  categoria: 'ENF',
  uf: 'AC',
  registro: '000202',
  termo_sha256: termo('b'),
};
const CASO = { id: 'caso-novo', tokens: ['chest', 'pain'], expect: 'EMERGENCY', clinicalSource: 'ficticio' };

before(async () => {
  f = await freshApp();
  editor = await sessaoDe(f, 'editor');
  revisor = await sessaoDe(f, 'clinical_reviewer');
  revisor2 = await sessaoDe(f, 'clinical_reviewer');
});
after(async () => f.close());

const post = (cookie: string, caminho: string, corpo?: unknown) =>
  pedido(f, cookie, 'POST', caminho, corpo);

async function caso(id: string, extra: Record<string, unknown> = {}) {
  const r = await post(editor.cookie, '/api/golden-cases', { ...CASO, id, ...extra });
  assert.equal(r.status, 201, `criar ${id} respondeu ${r.status}`);
}
async function registrar(a: Record<string, unknown>) {
  const r = await post(revisor.cookie, '/api/golden-cases/atestados', a);
  assert.equal(r.status, 201, `registrar ${String(a.id)} respondeu ${r.status}`);
}
async function linha(sql: string, args: (string | number)[] = []) {
  return (await f.client.execute({ sql, args })).rows;
}

test('POST caso com active=1 responde 422 e aponta a rota de revisores', async () => {
  const r = await post(editor.cookie, '/api/golden-cases', { ...CASO, id: 'caso-ativo', active: 1 });
  assert.equal(r.status, 422);
  const corpo = (await r.json()) as { error: string; next: string };
  assert.equal(corpo.error, 'caso ativo exige revisao clinica registrada');
  assert.equal(corpo.next, 'POST /api/golden-cases/caso-ativo/revisores');
  assert.equal((await linha("SELECT 1 FROM golden_case WHERE id = 'caso-ativo'")).length, 0);
});

test('POST caso cria inativo', async () => {
  await caso('caso-inativo');
  const [c] = await linha("SELECT active, added_by FROM golden_case WHERE id = 'caso-inativo'");
  assert.equal(c!.active, 0);
  assert.equal(c!.added_by, editor.id);
  assert.ok((await auditRows(f)).some((a) => a.action === 'golden_case_create' && a.entity_id === 'caso-inativo'));
  // id repetido
  const dup = await post(editor.cookie, '/api/golden-cases', { ...CASO, id: 'caso-inativo' });
  assert.equal(dup.status, 409);
  // malformado
  const ruim = await post(editor.cookie, '/api/golden-cases', { id: 'x', tokens: [], expect: 'E' });
  assert.equal(ruim.status, 400);
});

test('POST caso sem content:write responde 403', async () => {
  const r = await post(revisor.cookie, '/api/golden-cases', { ...CASO, id: 'caso-proibido' });
  assert.equal(r.status, 403);
});

test('POST atestado com COREN TE responde 422 so enfermeiro', async () => {
  const r = await post(revisor.cookie, '/api/golden-cases/atestados', {
    ...ATESTADO_2, id: 'AT-9110', categoria: 'TE',
  });
  assert.equal(r.status, 422);
  assert.match(JSON.stringify(await r.json()), /so enfermeiro/);
});

test('POST atestado com registro com ponto responde 422', async () => {
  const r = await post(revisor.cookie, '/api/golden-cases/atestados', {
    ...ATESTADO, id: 'AT-9111', registro: '12.345',
  });
  assert.equal(r.status, 422);
});

test('POST atestado sem id responde 422', async () => {
  const { id: _id, ...semId } = ATESTADO;
  const r = await post(revisor.cookie, '/api/golden-cases/atestados', semId);
  assert.equal(r.status, 422);
});

test('POST atestado sem approval:decide responde 403', async () => {
  const r = await post(editor.cookie, '/api/golden-cases/atestados', ATESTADO);
  assert.equal(r.status, 403);
});

test('POST atestado valido entra e a trilha NAO registra nome nem registro', async () => {
  // spec/lgpd.md: `golden_attestation` e a unica tabela com nome e inscricao do
  // revisor. A trilha e permanente e append-only; copia-los para ela criaria uma
  // segunda morada que o expurgo do atestado nao alcanca.
  await registrar(ATESTADO);
  const [a] = await linha("SELECT * FROM golden_attestation WHERE id = 'AT-9101'");
  assert.equal(a!.created_by, revisor.id);
  assert.equal(a!.categoria, null);
  const trilha = (await auditRows(f)).find((x) => x.action === 'golden_attestation_create');
  assert.ok(trilha);
  assert.equal(trilha.entity_id, 'AT-9101');
  const depois = JSON.parse(trilha.after_json!) as Record<string, unknown>;
  assert.deepEqual(Object.keys(depois).sort(), ['categoria', 'conselho', 'id', 'termo_sha256', 'uf']);
  assert.equal(depois.id, 'AT-9101');
  assert.equal(depois.termo_sha256, ATESTADO.termo_sha256);
  assert.doesNotMatch(trilha.after_json!, /Revisora Ficticia Um/);
  assert.doesNotMatch(trilha.after_json!, /000101/);
  assert.equal(trilha.before_json, null);
});

test('ID ja usado por outro profissional responde 409', async () => {
  const r = await post(revisor.cookie, '/api/golden-cases/atestados', {
    ...ATESTADO, nome: 'Outra Pessoa Ficticia', registro: '000999', termo_sha256: termo('c'),
  });
  assert.equal(r.status, 409);
  assert.equal(((await r.json()) as { error: string }).error, 'este ID ja pertence a outro atestado');
  const [a] = await linha("SELECT nome FROM golden_attestation WHERE id = 'AT-9101'");
  assert.equal(a!.nome, 'Revisora Ficticia Um');
});

test('mesmo profissional sob outro ID responde 409 com o id existente', async () => {
  const r = await post(revisor.cookie, '/api/golden-cases/atestados', {
    ...ATESTADO, id: 'AT-9112', termo_sha256: termo('d'),
  });
  assert.equal(r.status, 409);
  assert.equal(((await r.json()) as { existente: string }).existente, 'AT-9101');
});

test('mesmo termo sob outro profissional responde 409', async () => {
  const r = await post(revisor.cookie, '/api/golden-cases/atestados', {
    ...ATESTADO, id: 'AT-9113', registro: '000555',
  });
  assert.equal(r.status, 409);
});

test('atestado identico de novo responde 409 e nao duplica', async () => {
  const r = await post(revisor.cookie, '/api/golden-cases/atestados', ATESTADO);
  assert.equal(r.status, 409);
  assert.equal(((await r.json()) as { error: string }).error, 'atestado ja registrado');
  assert.equal((await linha("SELECT 1 FROM golden_attestation WHERE id = 'AT-9101'")).length, 1);
  assert.equal(
    (await auditRows(f)).filter((a) => a.action === 'golden_attestation_create').length,
    1,
  );
});

test('POST revisores sem reviewed_at responde 422', async () => {
  await caso('caso-r1');
  const r = await post(revisor.cookie, '/api/golden-cases/caso-r1/revisores', { atestado: 'AT-9101' });
  assert.equal(r.status, 422);
});

test('POST revisores com reviewed_at futuro responde 422', async () => {
  const r = await post(revisor.cookie, '/api/golden-cases/caso-r1/revisores', {
    atestado: 'AT-9101', reviewed_at: '2999-01-01',
  });
  assert.equal(r.status, 422);
  assert.equal((await linha('SELECT 1 FROM golden_case_review')).length, 0);
});

test('POST revisores com atestado inexistente responde 422', async () => {
  const r = await post(revisor.cookie, '/api/golden-cases/caso-r1/revisores', {
    atestado: 'AT-9999', reviewed_at: '2026-08-20',
  });
  assert.equal(r.status, 422);
});

test('POST revisores caso inexistente responde 404', async () => {
  const r = await post(revisor.cookie, '/api/golden-cases/nao-existe/revisores', {
    atestado: 'AT-9101', reviewed_at: '2026-08-20',
  });
  assert.equal(r.status, 404);
});

test('POST revisores sem approval:decide responde 403', async () => {
  const r = await post(editor.cookie, '/api/golden-cases/caso-r1/revisores', {
    atestado: 'AT-9101', reviewed_at: '2026-08-20',
  });
  assert.equal(r.status, 403);
});

test('POST revisores pelo autor do caso responde 403', async () => {
  // Promocao: quem criou o caso virou revisor. O papel nao ve; a LINHA ve.
  await f.client.execute({
    sql: `INSERT INTO golden_case (id, tokens_json, expected_outcome_id, added_by, active)
          VALUES ('caso-do-revisor', '["x"]', 'EMERGENCY', ?, 0)`,
    args: [revisor.id],
  });
  const r = await post(revisor.cookie, '/api/golden-cases/caso-do-revisor/revisores', {
    atestado: 'AT-9101', reviewed_at: '2026-08-20',
  });
  assert.equal(r.status, 403);
  assert.equal((await linha("SELECT 1 FROM golden_case_review WHERE case_id = 'caso-do-revisor'")).length, 0);
});

test('POST revisores valido ativa o caso', async () => {
  const r = await post(revisor.cookie, '/api/golden-cases/caso-r1/revisores', {
    atestado: 'AT-9101', reviewed_at: '2026-08-20',
  });
  assert.equal(r.status, 201);
  const [c] = await linha("SELECT active FROM golden_case WHERE id = 'caso-r1'");
  assert.equal(c!.active, 1);
  const [rev] = await linha("SELECT * FROM golden_case_review WHERE case_id = 'caso-r1'");
  assert.equal(rev!.recorded_by, revisor.id);
  assert.equal(rev!.reviewed_at, '2026-08-20');
  assert.ok((await auditRows(f)).some((a) => a.action === 'golden_case_review' && a.entity_id === 'caso-r1'));
});

test('segundo revisor ACRESCENTA, nao substitui', async () => {
  const r2 = await post(revisor2.cookie, '/api/golden-cases/atestados', ATESTADO_2);
  assert.equal(r2.status, 201);
  const r = await post(revisor2.cookie, '/api/golden-cases/caso-r1/revisores', {
    atestado: 'AT-9102', reviewed_at: '2026-08-21',
  });
  assert.equal(r.status, 201);
  const revs = await linha(
    "SELECT attestation_id FROM golden_case_review WHERE case_id = 'caso-r1' ORDER BY attestation_id",
  );
  assert.deepEqual(revs.map((x) => x.attestation_id), ['AT-9101', 'AT-9102']);
});

test('mesmo atestado de novo responde 409 e nao altera nada', async () => {
  const antes = await linha('SELECT * FROM golden_case_review ORDER BY id');
  const r = await post(revisor.cookie, '/api/golden-cases/caso-r1/revisores', {
    atestado: 'AT-9101', reviewed_at: '2026-08-22',
  });
  assert.equal(r.status, 409);
  const corpo = (await r.json()) as { revisoes: { attestation_id: string }[] };
  assert.equal(corpo.revisoes.length, 2);
  assert.deepEqual(await linha('SELECT * FROM golden_case_review ORDER BY id'), antes);
});

test('nao ha PUT nem DELETE de revisao', async () => {
  for (const m of ['PUT', 'PATCH', 'DELETE']) {
    const r = await pedido(f, revisor.cookie, m, '/api/golden-cases/caso-r1/revisores', {});
    assert.ok([404, 405].includes(r.status), `${m} respondeu ${r.status}`);
  }
});

test('a simulacao enxerga o caso recem-ativado', async () => {
  await seedConteudo(f, editor.cookie);
  for (const [id, kind] of [['chest', 'body_part'], ['pain', 'symptom'], ['throat', 'body_part']] as const) {
    await pedido(f, editor.cookie, 'POST', '/api/content/symptom-tokens', {
      id, kind, iconRef: 'icon.exemplo', sortOrder: 0, deprecated: 0,
    });
  }
  for (const [id, cor] of [['card.rotina', 'green'], ['card.emerg', 'red']] as const) {
    await pedido(f, editor.cookie, 'POST', '/api/content/cards', {
      id, kind: 'result', iconRef: 'icon.exemplo', colorToken: cor, sortOrder: 0,
    });
  }
  await pedido(f, editor.cookie, 'POST', '/api/content/venues', {
    id: 'UBS', iconRef: 'icon.exemplo', colorToken: 'green', sortOrder: 0,
  });
  await pedido(f, editor.cookie, 'POST', '/api/content/routing-outcomes', {
    id: 'ROUTINE_UBS', severityLevel: 10, cardId: 'card.rotina', venueId: 'UBS',
  });
  await pedido(f, editor.cookie, 'POST', '/api/content/routing-outcomes', {
    id: 'EMERGENCY', severityLevel: 100, cardId: 'card.emerg', venueId: 'UBS',
  });
  const inocua = {
    id: 'rf-inocua', priority: 5, outcomeId: 'ROUTINE_UBS',
    terms: [{ groupNo: 0, tokenId: 'throat', negated: false }],
  };
  const simular = async () => {
    const r = await pedido(f, editor.cookie, 'POST', '/api/rules/simular', inocua);
    return ((await r.json()) as { simulacao: { total: number } }).simulacao.total;
  };
  // caso-r1 esta ativo (revisado); caso-inativo nao.
  assert.equal(await simular(), 1);
  await caso('caso-simula');
  assert.equal(await simular(), 1, 'caso inativo nao entra na simulacao');
  await post(revisor.cookie, '/api/golden-cases/caso-simula/revisores', {
    atestado: 'AT-9101', reviewed_at: '2026-08-20',
  });
  assert.equal(await simular(), 2);
});
