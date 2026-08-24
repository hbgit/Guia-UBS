/**
 * Segregacao de funcoes na cadeia clinica (lgpd.md LGPD-RF11).
 *
 * A regra se decompoe em tres, de naturezas diferentes, e cada uma mora onde
 * consegue ser cumprida. Este arquivo afirma as tres — e, crucialmente, afirma a
 * do meio **contra o banco**, nao contra a rota: uma checagem que mora so na rota
 * protege apenas contra quem passa pela rota, e a ameaca nomeada no PRD e o
 * insider, que pode ter outros caminhos.
 */
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { can } from '../src/auth/permissions.js';
import { temQuorumClinico } from '../src/services/approval-workflow.js';
import {
  auditRows,
  freshApp,
  pedido,
  seedConteudo,
  sessaoDe,
  type Fixture,
} from './support/app.js';

let f: Fixture;
let autor: { cookie: string; id: string };
/** Editor que permanece editor — o `autor` e promovido no meio do arquivo. */
let outroEditor: { cookie: string; id: string };
let revisor: { cookie: string; id: string };
let outroRevisor: { cookie: string; id: string };
let admin: { cookie: string; id: string };

before(async () => {
  f = await freshApp();
  autor = await sessaoDe(f, 'editor', 'autor@exemplo.invalid');
  outroEditor = await sessaoDe(f, 'editor', 'editor2@exemplo.invalid');
  revisor = await sessaoDe(f, 'clinical_reviewer', 'revisor@exemplo.invalid');
  outroRevisor = await sessaoDe(f, 'clinical_reviewer', 'revisor2@exemplo.invalid');
  admin = await sessaoDe(f, 'admin', 'admin@exemplo.invalid');
  await seedConteudo(f, autor.cookie);
});
after(async () => f.close());

async function releaseSubmetida(id: string, versao: number, cookie: string) {
  await pedido(f, cookie, 'POST', '/api/releases', {
    id,
    municipalityId: 'mun-1',
    packVersion: versao,
    schemaVersion: '1.0',
  });
  await pedido(f, cookie, 'POST', `/api/releases/${id}/submeter`);
}

// ---------------------------------------------------------------------------
// 1. Por PAPEL — matriz do item 17
// ---------------------------------------------------------------------------

test('quem escreve nao tem permissao de aprovar', () => {
  assert.equal(can('editor', 'approval:decide'), false);
  assert.equal(can('admin', 'approval:decide'), false);
  assert.equal(can('clinical_reviewer', 'approval:decide'), true);
});

test('editor recebe 403 na rota de aprovacao', async () => {
  await releaseSubmetida('rel-papel', 10, autor.cookie);
  const r = await pedido(f, autor.cookie, 'POST', '/api/approvals', {
    releaseId: 'rel-papel',
    decision: 'approve',
  });
  assert.equal(r.status, 403);
});

// ---------------------------------------------------------------------------
// 2. Por LINHA — o gatilho do banco
// ---------------------------------------------------------------------------

test('quem cria a release nao aprova a propria release, mesmo depois de PROMOVIDO', async () => {
  // Este e o caminho pelo qual a auto-aprovacao e de fato alcancavel, e a
  // primeira versao deste teste errou o cenario: um `clinical_reviewer` nao
  // consegue criar release (nao tem `content:write`), entao ele nunca seria o
  // autor. Quem cria e o editor — e um editor PROMOVIDO a revisor passa a ter a
  // permissao de aprovar sem deixar de ser o autor do que ja criou.
  //
  // A matriz de papeis nao ve isso: no instante da aprovacao, o papel esta
  // correto. So a regra por LINHA barra.
  await releaseSubmetida('rel-propria', 11, autor.cookie);

  const promocao = await pedido(f, admin.cookie, 'PATCH', `/api/users/${autor.id}`, {
    role: 'clinical_reviewer',
  });
  assert.equal(promocao.status, 200, await promocao.text());

  const r = await pedido(f, autor.cookie, 'POST', '/api/approvals', {
    releaseId: 'rel-propria',
    decision: 'approve',
  });
  // O corpo so pode ser lido UMA vez: ler no assert e depois parsear estoura
  // "Body has already been read".
  const texto = await r.text();
  assert.equal(r.status, 403, texto);
  assert.match((JSON.parse(texto) as { error: string }).error, /nao aprova a propria release/);
});

test('a recusa vem do BANCO, nao da rota', async () => {
  // E a assercao que importa. Uma checagem que mora so na rota protege apenas
  // contra quem passa pela rota; a ameaca nomeada no PRD e o insider.
  await assert.rejects(
    () =>
      f.client.execute({
        sql: `INSERT INTO approval (id, pack_release_id, approver_id, role, decision, decided_at)
              VALUES ('auto-1', 'rel-propria', ?, 'clinical_reviewer', 'approve', '2026-08-24T12:00:00Z')`,
        args: [autor.id],
      }),
    /nao aprova a propria release/,
  );
});

test('outro revisor aprova a mesma release sem problema', async () => {
  const r = await pedido(f, revisor.cookie, 'POST', '/api/approvals', {
    releaseId: 'rel-propria',
    decision: 'approve',
  });
  assert.equal(r.status, 200, await r.text());

  const lida = await pedido(f, admin.cookie, 'GET', '/api/releases/rel-propria');
  const corpo = (await lida.json()) as { release: { status: string } };
  assert.equal(corpo.release.status, 'approved');
});

// ---------------------------------------------------------------------------
// 3. Por QUORUM — o agregado
// ---------------------------------------------------------------------------

test('sem nenhuma aprovacao clinica nao ha quorum', async () => {
  await releaseSubmetida('rel-quorum', 12, outroEditor.cookie);
  const quorum = await temQuorumClinico(f.client, 'rel-quorum');
  assert.equal(quorum.ok, false);
  assert.equal(quorum.aprovacoes, 0);
});

test('uma aprovacao clinica fecha o quorum', async () => {
  const r = await pedido(f, revisor.cookie, 'POST', '/api/approvals', {
    releaseId: 'rel-quorum',
    decision: 'approve',
  });
  assert.equal(r.status, 200);
  const corpo = (await r.json()) as { para?: string };
  assert.equal(corpo.para, 'approved');
});

test('uma rejeicao registrada derruba o quorum', async () => {
  await releaseSubmetida('rel-rejeitada', 13, outroEditor.cookie);
  await pedido(f, revisor.cookie, 'POST', '/api/approvals', {
    releaseId: 'rel-rejeitada',
    decision: 'reject',
    comment: 'a regra de dor toracica esta larga demais',
  });
  const quorum = await temQuorumClinico(f.client, 'rel-rejeitada');
  assert.equal(quorum.ok, false);
  assert.equal(quorum.rejeicoes, 1);
});

test('aprovacao de quem NAO e revisor clinico nao conta para o quorum', async () => {
  // Insercao direta, simulando um caminho que nao passe pela rota: mesmo assim o
  // quorum exige `role = 'clinical_reviewer'` gravado NA LINHA. O papel
  // considerado e o do momento da decisao, nao o papel atual da pessoa —
  // promover alguem depois nao pode fazer uma aprovacao antiga passar a valer.
  await releaseSubmetida('rel-papel-errado', 14, outroEditor.cookie);
  await f.client.execute({
    sql: `INSERT INTO approval (id, pack_release_id, approver_id, role, decision, decided_at)
          VALUES ('ap-admin', 'rel-papel-errado', ?, 'admin', 'approve', '2026-08-24T12:00:00Z')`,
    args: [admin.id],
  });
  const quorum = await temQuorumClinico(f.client, 'rel-papel-errado');
  assert.equal(quorum.ok, false, 'aprovacao de admin fechou o quorum clinico');
  assert.equal(quorum.aprovacoes, 0);
});

// ---------------------------------------------------------------------------
// Rastro
// ---------------------------------------------------------------------------

test('toda decisao entra na trilha com quem decidiu', async () => {
  const linhas = await auditRows(f);
  const aprovacao = linhas.find(
    (l) => l.action === 'release_approve' && l.entity_id === 'rel-quorum',
  );
  assert.ok(aprovacao, 'aprovacao sem entrada na trilha');
  assert.equal(aprovacao.actor_id, revisor.id, 'a trilha precisa dizer QUEM aprovou');

  assert.ok(
    linhas.some((l) => l.action === 'release_reject' && l.entity_id === 'rel-rejeitada'),
    'rejeicao sem entrada na trilha',
  );
});

test('a tentativa de auto-aprovacao NAO grava aprovacao nenhuma', async () => {
  // Recusa que deixa efeito parcial e pior que recusa nenhuma.
  const linhas = await f.client.execute(
    "SELECT approver_id FROM approval WHERE pack_release_id = 'rel-propria'",
  );
  assert.equal(linhas.rows.length, 1);
  assert.equal(linhas.rows[0]!.approver_id, revisor.id);
});

test('a decisao e append-only: nem a rota nem o SQL a reescrevem', async () => {
  await assert.rejects(
    () => f.client.execute("UPDATE approval SET decision = 'approve' WHERE id = 'ap-admin'"),
    /append-only/,
  );
  await assert.rejects(
    () => f.client.execute("DELETE FROM approval WHERE id = 'ap-admin'"),
    /append-only/,
  );
});
