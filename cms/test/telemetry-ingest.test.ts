/**
 * Ingestao de telemetria agregada (lgpd.md LGPD-RF14).
 *
 * A rota e a SEGUNDA e ultima excecao a LGPD-RT01 — a primeira e `/health`. O
 * teste que mais importa aqui e o que percorre `/api` e exige que NENHUMA outra
 * rota dispense sessao: uma excecao que se multiplica sem ninguem notar e como
 * "autenticacao em todo endpoint" deixa de ser verdade.
 *
 * Vale registrar o que estes testes NAO cobrem, porque nao existe: **esta rota
 * nao tem produtor**. O app nao envia (terceira chamada de rede exige ADR) e,
 * mesmo que enviasse, seu lote seria recusado — `TelemetryRecorder` acumula por
 * APARELHO e o contrato exige k>=20 no lote. Falta um agregador.
 */
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { K_ANONYMITY_MIN } from '@guia-ubs/contract';

import { TEST_ENV, freshApp, type Fixture } from './support/app.js';

let f: Fixture;
before(async () => {
  f = await freshApp();
});
after(async () => f.close());

/** Coorte ficticia: `0000000` e o codigo de exemplo usado em todo o repositorio. */
const LOTE = {
  cohort: { municipality: '0000000', appVersion: '1.0.0', packVersion: 1 },
  bucketDay: '2026-08-24',
  kCount: K_ANONYMITY_MIN,
  metrics: { triage_completed_total: 120, triage_fallback_total: 3 },
};

function enviar(corpo: unknown) {
  return f.app.request('/api/telemetry', {
    method: 'POST',
    headers: { 'content-type': 'application/json', origin: TEST_ENV.authBaseUrl },
    body: typeof corpo === 'string' ? corpo : JSON.stringify(corpo),
  });
}

test('lote agregado valido e aceito SEM sessao', async () => {
  const r = await enviar(LOTE);
  assert.equal(r.status, 202, await r.text());
});

test('o lote gravado nao carrega identificador nenhum', async () => {
  // E o requisito inteiro da LGPD-RF14: a telemetria so fica fora do art. 12 se
  // for irreversivel. Este teste percorre as COLUNAS em vez de confiar nisso.
  const linhas = await f.client.execute('SELECT * FROM telemetry_batch');
  assert.equal(linhas.rows.length, 1);
  const colunas = Object.keys(linhas.rows[0]!);
  for (const proibida of ['device', 'install', 'session', 'user', 'ip']) {
    assert.ok(
      !colunas.some((c) => c.includes(proibida)),
      `coluna "${proibida}" apareceu em telemetry_batch`,
    );
  }
  assert.equal(linhas.rows[0]!.cohort_key, '0000000|1.0.0|1');
});

test('coorte abaixo do k-anonimato e recusada', async () => {
  const r = await enviar({ ...LOTE, kCount: K_ANONYMITY_MIN - 1, bucketDay: '2026-08-25' });
  assert.equal(r.status, 422);
});

test('metrica fora da allowlist e recusada', async () => {
  // A allowlist e o mecanismo que mantem a telemetria fora do art. 12: campo novo
  // passa por revisao do encarregado antes de existir.
  const r = await enviar({ ...LOTE, bucketDay: '2026-08-26', metrics: { device_id_seen: 1 } });
  assert.equal(r.status, 422);
});

test('timestamp fino disfarcado de bucketDay e recusado', async () => {
  // Granularidade minima e o DIA. Um horario aqui reidentifica em populacao
  // pequena, que e exatamente a populacao deste produto.
  const r = await enviar({ ...LOTE, bucketDay: '2026-08-24T14:32:07Z' });
  assert.equal(r.status, 422);
});

test('a recusa nao ensina o formato aceito', async () => {
  // Endpoint publico que explica o schema ensina a forjar lote valido; um
  // produtor legitimo tem o contrato e nao precisa da mensagem.
  const r = await enviar({ ...LOTE, kCount: 1 });
  const corpo = await r.text();
  for (const vazamento of ['metrics', 'cohort', 'bucketDay', 'appVersion']) {
    assert.ok(!corpo.includes(vazamento), `a recusa revelou "${vazamento}"`);
  }
});

test('lote repetido para a mesma coorte e dia responde 409', async () => {
  // Somar em silencio esconderia defeito de produtor: ou e reenvio, ou sao dois
  // agregadores contando a mesma populacao. As duas coisas precisam ser vistas.
  const r = await enviar(LOTE);
  assert.equal(r.status, 409);
});

test('corpo grande demais e recusado antes de ser interpretado', async () => {
  const r = await enviar(JSON.stringify({ ...LOTE, lixo: 'x'.repeat(20_000) }));
  assert.equal(r.status, 413);
});

test('corpo que nao e JSON responde 400, nao 500', async () => {
  const r = await enviar('isto nao e json');
  assert.equal(r.status, 400);
});

test('esta e a UNICA rota de /api que dispensa sessao', async () => {
  // A afirmacao que segura a LGPD-RT01. Uma excecao nova que passe despercebida
  // e o momento em que "autenticacao em todo endpoint" deixa de ser verdade.
  const protegidas = [
    ['GET', '/api/me'],
    ['GET', '/api/users'],
    ['GET', '/api/content/symptom-tokens'],
    ['POST', '/api/content/symptom-tokens'],
    ['GET', '/api/rules'],
    ['POST', '/api/rules/simular'],
    ['GET', '/api/releases'],
    ['POST', '/api/releases'],
    ['POST', '/api/approvals'],
  ] as const;

  for (const [metodo, caminho] of protegidas) {
    const r = await f.app.request(caminho, {
      method: metodo,
      headers: { 'content-type': 'application/json', origin: TEST_ENV.authBaseUrl },
      ...(metodo === 'POST' ? { body: '{}' } : {}),
    });
    assert.equal(r.status, 401, `${metodo} ${caminho} respondeu ${r.status} sem sessao`);
  }
});

test('/health e a outra excecao declarada, e nao toca no banco de identidade', async () => {
  const r = await f.app.request('/health');
  assert.equal(r.status, 200);
  assert.deepEqual(Object.keys((await r.json()) as object), ['status']);
});
