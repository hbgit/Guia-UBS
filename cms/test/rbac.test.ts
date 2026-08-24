/**
 * A matriz papel x permissao, percorrida inteira (lgpd.md LGPD-RF11 exige
 * "matriz papel×permissao testada automaticamente").
 *
 * O produto cartesiano e o ponto: um teste que confere so os casos que alguem
 * lembrou de conferir cobre o que alguem lembrou. Permissao nova sem decisao
 * para os tres papeis reprova aqui.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { ADMIN_ROLES } from '../src/db/schema/auth.js';
import { PERMISSIONS, ROLE_PERMISSIONS, can } from '../src/auth/permissions.js';

test('todo papel tem entrada na matriz', () => {
  for (const papel of ADMIN_ROLES) {
    assert.ok(ROLE_PERMISSIONS[papel], `papel "${papel}" sem entrada em ROLE_PERMISSIONS`);
  }
});

test('a matriz nao concede permissao que nao existe', () => {
  for (const [papel, concedidas] of Object.entries(ROLE_PERMISSIONS)) {
    for (const permissao of concedidas) {
      assert.ok(
        (PERMISSIONS as readonly string[]).includes(permissao),
        `"${papel}" recebe "${permissao}", que nao esta em PERMISSIONS`,
      );
    }
  }
});

test('o produto cartesiano inteiro tem resposta definida', () => {
  let combinacoes = 0;
  for (const papel of ADMIN_ROLES) {
    for (const permissao of PERMISSIONS) {
      assert.equal(typeof can(papel, permissao), 'boolean');
      combinacoes += 1;
    }
  }
  assert.equal(combinacoes, ADMIN_ROLES.length * PERMISSIONS.length);
});

test('segregacao clinica: quem escreve nao aprova, quem aprova nao escreve', () => {
  // E a regra que a LGPD-RF11 chama de segregacao de funcoes, e a razao de o
  // plugin `admin` do Better Auth (com impersonation) ter ficado de fora: com
  // impersonation, um admin aprovaria como se fosse o revisor.
  assert.equal(can('editor', 'approval:decide'), false, 'editor nao pode aprovar o que escreve');
  assert.equal(
    can('clinical_reviewer', 'content:write'),
    false,
    'revisor nao pode escrever o que aprova',
  );
});

test('admin gere pessoas, nao conteudo clinico', () => {
  // Concentrar os tres no admin desfaria a segregacao com uma linha de tabela.
  assert.equal(can('admin', 'user:manage'), true);
  assert.equal(can('admin', 'content:write'), false);
  assert.equal(can('admin', 'approval:decide'), false);
});

test('so o admin gere pessoas', () => {
  assert.equal(can('editor', 'user:manage'), false);
  assert.equal(can('clinical_reviewer', 'user:manage'), false);
});

test('nenhuma permissao fica sem nenhum papel', () => {
  // Permissao que ninguem tem e rota que ninguem alcanca — quase sempre um
  // esquecimento, nunca um projeto.
  for (const permissao of PERMISSIONS) {
    const donos = ADMIN_ROLES.filter((papel) => can(papel, permissao));
    assert.ok(donos.length > 0, `nenhum papel tem "${permissao}"`);
  }
});
