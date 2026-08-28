/**
 * A interface de releases nao pode ter uma segunda copia da FSM.
 *
 * `docs/operacao.md` §4.4 é explícito: "`GET /api/releases/<id>` devolve as
 * transições possíveis a partir do estado atual — é dali que uma interface monta
 * os botões, em vez de manter uma segunda cópia das regras". Uma cópia que fique
 * para trás oferece uma ação que o servidor recusa, ou esconde uma que ele
 * permite; nos dois casos, o operador aprende a desconfiar da tela.
 *
 * Este arquivo afirma isso mecanicamente, nos dois sentidos — mesmo padrao de
 * `schema-conformance.test.ts`.
 *
 * ## O ultimo teste do arquivo existe por causa de um defeito real
 *
 * `TRANSICOES` declarava `draft -> pending_review` como `por: ['editor','admin']`
 * enquanto a rota `/submeter` exige `content:write`, que o `admin` nao tem. O
 * dado e a rota discordavam desde o item 19, e NENHUM teste pegava — porque com
 * `curl` quem monta a chamada ja sabe quem pode o que. A interface, que monta os
 * botoes a partir do dado, mostrou: o admin veria "Submeter" e levaria 403.
 */
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { test } from 'node:test';

import { ROLE_PERMISSIONS, type AdminRole, type Permission } from '../src/auth/permissions.js';
import { RULE_STATUSES } from '../src/db/schema/content.js';
import { RELEASE_STATUSES } from '../src/db/schema/publishing.js';
import { TRANSICOES } from '../src/services/approval-workflow.js';
import { ACOES, ROTULO_DO_ESTADO, acaoDe } from '../web/src/releases/acoes.js';

/** Uma transicao e do job quando so o job pode faze-la. */
function ehDoJob(por: readonly string[]): boolean {
  return por.length === 1 && por[0] === 'job';
}

test('toda transicao de operador tem acao na interface', () => {
  const semAcao = TRANSICOES.filter((t) => !ehDoJob(t.por) && !acaoDe(t.de, t.para)).map(
    (t) => `${t.de} -> ${t.para}`,
  );
  assert.deepEqual(
    semAcao,
    [],
    'transicao que um operador pode fazer e que a interface nao oferece: o botao simplesmente nao existe',
  );
});

test('toda acao da interface corresponde a uma transicao real', () => {
  // O sentido inverso, e o que mais engana: um botao que aciona uma transicao
  // que a FSM nao tem mais leva a um 409 que o operador nao consegue interpretar.
  const orfas = ACOES.filter((a) => !TRANSICOES.some((t) => t.de === a.de && t.para === a.para)).map(
    (a) => `${a.de} -> ${a.para}`,
  );
  assert.deepEqual(orfas, [], 'a interface oferece acao para transicao que nao existe na FSM');
});

test('transicao do job NAO vira acao', () => {
  // Job nao tem operador — `actor_id` nulo na trilha. Um botao aqui sugeriria
  // que alguem deveria clicar, e ninguem deveria.
  const comBotao = TRANSICOES.filter((t) => ehDoJob(t.por) && acaoDe(t.de, t.para)).map(
    (t) => `${t.de} -> ${t.para}`,
  );
  assert.deepEqual(comBotao, [], 'transicao do job com botao na interface');
});

test('ha rotulo em portugues para todo estado', () => {
  // `Record<ReleaseStatus, string>` ja garante isso no compilador; aqui a
  // asserção cobre o outro lado — rotulo que sobrou para um estado removido.
  assert.deepEqual(Object.keys(ROTULO_DO_ESTADO).sort(), [...RELEASE_STATUSES].sort());
});

test('a interface nao contem literal de estado de release fora de `acoes.ts`', async () => {
  /**
   * A guarda estrutural: se um `if (status === 'pending_review')` aparecer numa
   * tela, a segunda copia da FSM ja comecou — e ela nao volta atras sozinha.
   *
   * `acoes.ts` e a unica excecao, porque e o mapa de transporte, conferido pelos
   * testes acima.
   */
  /**
   * `draft` e `approved` sao AMBIGUOS neste repositorio: sao estados de release
   * E de regra (`RULE_STATUSES`). O editor de regras usa os dois legitimamente, e
   * proibi-los aqui obrigaria a contorna-los — o que e pior que nao guardar.
   *
   * Os cinco restantes so podem se referir a uma release, e sao onde uma segunda
   * copia da FSM apareceria: `if (status === 'building')`, `=== 'published'`.
   */
  const AMBIGUOS = new Set<string>(RULE_STATUSES);
  const INEQUIVOCOS = RELEASE_STATUSES.filter((e) => !AMBIGUOS.has(e));
  assert.ok(INEQUIVOCOS.length >= 5, 'a sobreposicao com RULE_STATUSES cresceu demais');

  const raiz = join(import.meta.dirname, '..', 'web', 'src');
  async function arquivos(dir: string): Promise<string[]> {
    const saida: string[] = [];
    for (const entrada of await readdir(dir, { withFileTypes: true })) {
      const caminho = join(dir, entrada.name);
      if (entrada.isDirectory()) saida.push(...(await arquivos(caminho)));
      else if (/\.tsx?$/.test(entrada.name)) saida.push(caminho);
    }
    return saida;
  }

  const infratores: string[] = [];
  for (const caminho of await arquivos(raiz)) {
    if (caminho.endsWith(join('releases', 'acoes.ts'))) continue;
    const conteudo = await readFile(caminho, 'utf8');
    // So CODIGO: comentario que explica a FSM e bem-vindo, e e o oposto do risco.
    const semComentarios = conteudo.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
    for (const estado of INEQUIVOCOS) {
      if (semComentarios.includes(`'${estado}'`)) {
        infratores.push(`${caminho.slice(raiz.length + 1)}: '${estado}'`);
      }
    }
  }
  assert.deepEqual(
    infratores,
    [],
    'literal de estado fora de `acoes.ts` — a segunda copia da FSM comecou aqui',
  );
});

test('quem a FSM diz que pode agir TEM a permissao que a rota exige', () => {
  /**
   * O defeito que a interface expos, agora travado.
   *
   * `TRANSICOES.por` e consumido pela tela para saber quem age; a rota decide de
   * verdade com `requirePermission`. Quando os dois discordam, a tela oferece um
   * botao que sempre da 403 — e o operador conclui que o sistema esta quebrado.
   *
   * A tabela abaixo e a ponte entre os dois vocabularios, escrita a mao porque e
   * exatamente a informacao que nenhum dos dois lados carrega sozinho. Transicao
   * nova sem linha aqui REPROVA, em vez de passar despercebida.
   */
  const PERMISSAO_DA_ROTA: Readonly<Record<string, Permission>> = {
    'draft->pending_review': 'content:write', // POST /api/releases/:id/submeter
    'pending_review->approved': 'approval:decide', // POST /api/approvals
    'pending_review->draft': 'approval:decide', // POST /api/approvals
    'building->approved': 'release:publish', // POST /api/releases/:id/reenfileirar
    'built->revoked': 'release:publish', // POST /api/releases/:id/revogar
    'published->revoked': 'release:publish', // POST /api/releases/:id/revogar
  };

  const divergentes: string[] = [];
  for (const t of TRANSICOES) {
    if (ehDoJob(t.por)) continue;
    const chave = `${t.de}->${t.para}`;
    const exigida = PERMISSAO_DA_ROTA[chave];
    assert.ok(exigida, `transicao ${chave} sem permissao mapeada — acrescente a tabela acima`);

    for (const ator of t.por) {
      if (ator === 'job') continue;
      const permissoes = ROLE_PERMISSIONS[ator as AdminRole] ?? [];
      if (!permissoes.includes(exigida)) {
        divergentes.push(`${chave}: a FSM permite "${ator}", mas a rota exige "${exigida}"`);
      }
    }
  }

  assert.deepEqual(
    divergentes,
    [],
    'a FSM promete o que a rota recusa: a interface mostraria um botao que da 403',
  );
});
