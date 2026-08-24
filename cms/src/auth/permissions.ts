/**
 * A matriz papel x permissao — como DADO, nao como `if` espalhado.
 *
 * A LGPD-RF11 exige "matriz papel×permissao testada automaticamente". Um teste
 * so consegue percorrer a matriz se ela existir como estrutura; escrita como
 * condicionais dentro das rotas, o que o teste cobre e o que alguem lembrou de
 * cobrir. Aqui `test/rbac.test.ts` percorre o produto cartesiano inteiro.
 *
 * O plugin `admin` do Better Auth traria isto pronto — junto com impersonation.
 * Ficou fora: num sistema com dual review clinico, impersonation deixa um admin
 * aprovar como se fosse o revisor, e a trilha registraria o revisor. A
 * segregacao de funcoes que a LGPD-RF11 exige viraria ficcao, e nao ha teste que
 * pegue isso depois do fato. Desligar por configuracao nao serve: seguranca que
 * depende de manter uma opcao desligada e seguranca que uma atualizacao reverte.
 */
import { ADMIN_ROLES } from '../db/schema/auth.js';

export type AdminRole = (typeof ADMIN_ROLES)[number];

/**
 * Toda permissao do sistema. Nomeada `dominio:acao`.
 *
 * `content:*` e `approval:decide` ja entram, embora as rotas sejam dos itens 18
 * e 19: uma matriz pela metade torna o teste dela decorativo, e a segregacao
 * editor x revisor precisa estar declarada antes de existir rota que a dependa.
 */
export const PERMISSIONS = [
  'content:read',
  'content:write',
  'approval:decide',
  'release:publish',
  'user:manage',
] as const;

export type Permission = (typeof PERMISSIONS)[number];

/**
 * Quem pode o que.
 *
 * A segregacao clinica esta aqui e e o ponto do arquivo: **`editor` nao tem
 * `approval:decide` e `clinical_reviewer` nao tem `content:write`**. Quem
 * escreve nao aprova; quem aprova nao escreve. A regra complementar — que o
 * aprovador tambem nao pode ser quem criou aquele release especifico — e sobre
 * uma LINHA, nao sobre um papel, e por isso vive no item 19.
 *
 * `admin` gere pessoas, nao conteudo clinico: nao ganha `content:write` nem
 * `approval:decide`. Concentrar os tres no admin desfaria a segregacao com uma
 * linha de tabela.
 */
export const ROLE_PERMISSIONS: Readonly<Record<AdminRole, readonly Permission[]>> = {
  editor: ['content:read', 'content:write'],
  clinical_reviewer: ['content:read', 'approval:decide'],
  admin: ['content:read', 'release:publish', 'user:manage'],
};

export function can(role: AdminRole, permission: Permission): boolean {
  return ROLE_PERMISSIONS[role].includes(permission);
}

export function isAdminRole(value: unknown): value is AdminRole {
  return typeof value === 'string' && (ADMIN_ROLES as readonly string[]).includes(value);
}
