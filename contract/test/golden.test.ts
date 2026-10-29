import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  ACOES_QUE_NAO_REABREM,
  ACOES_QUE_REABREM,
  CATEGORIAS_COREN_ACEITAS,
  MIN_REVISORES,
  UFS,
  avaliarAtestado,
  avaliarDataRevisao,
  avaliarRegistro,
  avaliarRevisao,
  conferirContraRegistro,
  type EntradaRegistro,
} from '../src/golden.js';

const REG: EntradaRegistro[] = [
  { id: 'AT-9001', conselho: 'CRM', uf: 'RR', termo_sha256: 'a'.repeat(64) },
  { id: 'AT-9002', conselho: 'COREN', categoria: 'ENF', uf: 'RR', termo_sha256: 'b'.repeat(64) },
];
const REV_CRM = { atestado: 'AT-9001', conselho: 'CRM', uf: 'RR', reviewed_at: '2026-10-28' };
const REV_COREN = {
  atestado: 'AT-9002',
  conselho: 'COREN',
  categoria: 'ENF',
  uf: 'RR',
  reviewed_at: '2026-10-27',
};
const ATESTADO_FICTICIO = {
  id: 'AT-9002',
  nome: 'Revisora Ficticia Teste',
  conselho: 'COREN',
  categoria: 'ENF',
  uf: 'RR',
  registro: '000123',
  termo_sha256: 'b'.repeat(64),
};
const AGORA = new Date('2026-10-28T12:00:00Z');

function problemas(reviewed_by: unknown, extra: Record<string, unknown> = {}): string[] {
  const r = avaliarRevisao({ reviewed_by, ...extra }, AGORA);
  assert.equal(r.estado, 'invalida');
  return r.estado === 'invalida' ? r.problemas : [];
}

test('ausente quando reviewed_by e nulo ou omitido', () => {
  assert.equal(avaliarRevisao({}, AGORA).estado, 'ausente');
  assert.equal(avaliarRevisao({ reviewed_by: null }, AGORA).estado, 'ausente');
});

test('valida com um revisor', () => {
  const r = avaliarRevisao({ reviewed_by: [REV_CRM] }, AGORA);
  assert.equal(r.estado, 'valida');
});

test('valida com dois revisores em datas diferentes', () => {
  const r = avaliarRevisao({ reviewed_by: [REV_CRM, REV_COREN] }, AGORA);
  assert.equal(r.estado, 'valida');
  if (r.estado === 'valida') assert.equal(r.revisores.length, 2);
});

test('lista vazia e invalida, com o minimo derivado da constante', () => {
  const p = problemas([]);
  assert.ok(p.some((m) => m.includes(`ao menos ${MIN_REVISORES} revisor`)), JSON.stringify(p));
});

test('revisor com nome no YAML e invalido', () => {
  // Nome mora so no CMS (D3); `.strict()` recusa a chave a mais no registro publico.
  const p = problemas([{ ...REV_CRM, nome: 'Pessoa Ficticia Teste' }]);
  assert.ok(p.some((m) => m.startsWith('reviewed_by[0]') && m.includes('nome')), JSON.stringify(p));
});

test('reviewed_at no nivel do caso e invalido', () => {
  const p = problemas([REV_CRM], { reviewed_at: '2026-10-28' });
  assert.ok(p.some((m) => m.includes('reviewed_at mora em cada revisor')));
});

test('revisor sem reviewed_at e invalido', () => {
  const { reviewed_at: _, ...sem } = REV_CRM;
  const p = problemas([sem]);
  assert.ok(p.some((m) => m.startsWith('reviewed_by[0].reviewed_at')));
});

test('conselho fora da lista e invalido', () => {
  const p = problemas([{ ...REV_CRM, conselho: 'CRO' }]);
  assert.ok(p.some((m) => m.startsWith('reviewed_by[0]')));
});

test('UF fora das 27 e invalida', () => {
  const p = problemas([{ ...REV_CRM, uf: 'XX' }]);
  assert.ok(p.some((m) => m.startsWith('reviewed_by[0].uf')));
});

test('as 27 UFs sao aceitas', () => {
  assert.equal(UFS.length, 27);
  for (const uf of UFS) {
    assert.equal(avaliarRevisao({ reviewed_by: [{ ...REV_CRM, uf }] }, AGORA).estado, 'valida');
  }
});

test('COREN sem categoria e invalido', () => {
  const { categoria: _, ...sem } = REV_COREN;
  const p = problemas([sem]);
  assert.ok(p.some((m) => m.includes('so enfermeiro')));
});

test('COREN TE, AE, OBST e PAR sao invalidos com a mensagem so enfermeiro', () => {
  for (const categoria of ['TE', 'AE', 'OBST', 'PAR']) {
    const p = problemas([{ ...REV_COREN, categoria }]);
    assert.ok(
      p.some((m) => m.startsWith('reviewed_by[0].categoria') && m.includes('so enfermeiro (ENF)')),
      categoria,
    );
  }
});

test('CATEGORIAS_COREN_ACEITAS e exatamente o que o schema aceita (o CHECK do banco deriva dela)', () => {
  assert.ok(CATEGORIAS_COREN_ACEITAS.length > 0);
  for (const categoria of ['ENF', 'TE', 'AE', 'OBST', 'PAR']) {
    const aceita = avaliarRevisao({ reviewed_by: [{ ...REV_COREN, categoria }] }, AGORA).estado === 'valida';
    assert.equal(aceita, (CATEGORIAS_COREN_ACEITAS as readonly string[]).includes(categoria), categoria);
  }
});

test('CRM com categoria e invalido', () => {
  const p = problemas([{ ...REV_CRM, categoria: 'ENF' }]);
  assert.ok(p.some((m) => m.includes('categoria')));
});

test('ID de atestado fora do formato e invalido', () => {
  for (const atestado of ['AT-1', 'at-0001']) {
    const p = problemas([{ ...REV_CRM, atestado }]);
    assert.ok(p.some((m) => m.startsWith('reviewed_by[0].atestado')), atestado);
  }
});

test('mesmo atestado duas vezes e invalido', () => {
  const p = problemas([REV_CRM, { ...REV_CRM, reviewed_at: '2026-10-27' }]);
  assert.ok(p.some((m) => m.includes('AT-9001') && m.includes('duplic')));
});

test('reviewed_at: futuro invalido, hoje valido, inexistente e formato errado invalidos', () => {
  const p = problemas([{ ...REV_CRM, reviewed_at: '2026-10-29' }]);
  assert.ok(p.some((m) => m.startsWith('reviewed_by[0].reviewed_at')));
  assert.equal(
    avaliarRevisao({ reviewed_by: [{ ...REV_CRM, reviewed_at: '2026-10-28' }] }, AGORA).estado,
    'valida',
  );
  for (const d of ['2026-02-30', '28/10/2026', '2026-1-5', 20261028]) {
    const q = problemas([{ ...REV_CRM, reviewed_at: d }]);
    assert.ok(q.some((m) => m.startsWith('reviewed_by[0].reviewed_at')), String(d));
  }
});

test('avaliarAtestado: valido', () => {
  const r = avaliarAtestado(ATESTADO_FICTICIO);
  assert.equal(r.ok, true);
});

test('avaliarAtestado: registro numerico pede aspas', () => {
  const r = avaliarAtestado({ ...ATESTADO_FICTICIO, registro: 123 });
  assert.equal(r.ok, false);
  if (!r.ok) assert.ok(r.problemas.some((m) => m.includes('entre aspas')));
});

test('avaliarAtestado: registro copiado do cadastro e explicado', () => {
  const r = avaliarAtestado({ ...ATESTADO_FICTICIO, registro: '123.456-ENF' });
  assert.equal(r.ok, false);
  if (!r.ok) {
    assert.ok(r.problemas.some((m) => m.includes('so digitos') && m.includes('categoria')));
  }
});

test('avaliarAtestado: registro com 9 digitos e invalido', () => {
  assert.equal(avaliarAtestado({ ...ATESTADO_FICTICIO, registro: '123456789' }).ok, false);
});

test('avaliarAtestado: nome de uma palavra e invalido', () => {
  assert.equal(avaliarAtestado({ ...ATESTADO_FICTICIO, nome: 'Revisora' }).ok, false);
});

test('avaliarAtestado: chave desconhecida e invalida', () => {
  assert.equal(avaliarAtestado({ ...ATESTADO_FICTICIO, cpf: '1' }).ok, false);
});

test('avaliarRegistro: registro valido', () => {
  const r = avaliarRegistro({ atestados: REG });
  assert.equal(r.ok, true);
  if (r.ok) assert.equal(r.entradas.length, 2);
});

test('avaliarRegistro: registro vazio e valido', () => {
  const r = avaliarRegistro({ atestados: [] });
  assert.equal(r.ok, true);
});

test('avaliarRegistro: ID repetido e invalido', () => {
  const r = avaliarRegistro({ atestados: [REG[0], { ...REG[1], id: 'AT-9001' }] });
  assert.equal(r.ok, false);
  if (!r.ok) assert.ok(r.problemas.some((m) => m.includes('AT-9001')));
});

test('avaliarRegistro: termo_sha256 repetido e invalido', () => {
  const r = avaliarRegistro({ atestados: [REG[0], { ...REG[1], termo_sha256: 'a'.repeat(64) }] });
  assert.equal(r.ok, false);
});

test('avaliarRegistro: termo_sha256 fora do formato e invalido', () => {
  assert.equal(avaliarRegistro({ atestados: [{ ...REG[0], termo_sha256: 'xyz' }] }).ok, false);
});

test('avaliarRegistro: entrada com nome ou registro e invalida', () => {
  assert.equal(avaliarRegistro({ atestados: [{ ...REG[0], nome: 'Fulano de Tal' }] }).ok, false);
  assert.equal(avaliarRegistro({ atestados: [{ ...REG[0], registro: '123' }] }).ok, false);
});

test('conferirContraRegistro: coerente devolve vazio', () => {
  assert.deepEqual(conferirContraRegistro([REV_CRM, REV_COREN] as never, REG), []);
});

test('conferirContraRegistro: atestado ausente do registro e acusado', () => {
  const p = conferirContraRegistro([{ ...REV_CRM, atestado: 'AT-0099' }] as never, REG);
  assert.ok(p.some((m) => m.includes('AT-0099') && m.includes('atestados.yaml')));
});

test('conferirContraRegistro: UF divergente e acusada', () => {
  const p = conferirContraRegistro([{ ...REV_CRM, uf: 'SP' }] as never, REG);
  assert.ok(p.some((m) => m.includes('uf')));
});

test('conferirContraRegistro: categoria divergente e acusada', () => {
  const p = conferirContraRegistro([{ ...REV_COREN, categoria: undefined }] as never, REG);
  assert.ok(p.some((m) => m.includes('categoria')));
});

test('prefixos que reabrem nao colidem com acoes que nao reabrem', () => {
  for (const a of ACOES_QUE_NAO_REABREM) {
    assert.ok(!ACOES_QUE_REABREM.some((p) => a.startsWith(p)), a);
  }
  assert.ok(ACOES_QUE_NAO_REABREM.includes('release_published'));
  assert.ok(ACOES_QUE_NAO_REABREM.includes('sign_in_failed'));
});

test('avaliarDataRevisao aceita hoje e recusa futuro, calendario invalido e nao-texto', () => {
  const agora = new Date('2026-08-24T12:00:00Z');
  assert.deepEqual(avaliarDataRevisao('2026-08-24', agora), []);
  assert.deepEqual(avaliarDataRevisao('2026-01-02', agora), []);
  assert.match(avaliarDataRevisao('2026-08-25', agora).join(), /futura/);
  assert.match(avaliarDataRevisao('2026-02-30', agora).join(), /calendario/);
  assert.match(avaliarDataRevisao(20260824, agora).join(), /texto/);
  assert.notEqual(avaliarDataRevisao(undefined, agora).length, 0);
});
