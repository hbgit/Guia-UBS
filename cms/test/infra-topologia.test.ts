/**
 * A topologia de rede E a garantia, e por isso e afirmada.
 *
 * O `packer` nao abre porta desde o item 19, e o comentario no compose diz que a
 * ausencia e deliberada — mas nada testava. Comentario nao impede uma linha
 * `ports:` acrescentada numa depuracao e esquecida no commit; e o efeito dessa
 * linha, no caso do `cms`, e um caminho que alcanca o formulario de login sem
 * passar pelo TLS da borda.
 *
 * Depois do item 24, o unico servico alcancavel de fora e o `edge`. Este arquivo
 * afirma isso a partir do proprio `compose.yaml`, e nao de uma lista escrita ao
 * lado — mesmo motivo de `PII_COLUMNS` e `APPEND_ONLY_TABLES` serem percorridas.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';

import { parse } from 'yaml';

interface Servico {
  ports?: unknown[];
  depends_on?: Record<string, unknown> | string[];
}

const RAIZ = join(import.meta.dirname, '..', '..');

function servicos(arquivo: string): Record<string, Servico> {
  const bruto = parse(readFileSync(join(RAIZ, 'infra', arquivo), 'utf8')) as {
    services?: Record<string, Servico>;
  };
  return bruto.services ?? {};
}

/**
 * A borda e a UNICA superficie publica.
 *
 * Nao e uma lista de servicos permitidos: e um servico so, e qualquer outro que
 * publique porta reprova — inclusive um que ainda nao existe.
 */
const UNICO_PUBLICO = 'edge';

test('so o `edge` escuta fora do loopback', () => {
  /**
   * `db` e `storage` publicam em `127.0.0.1` por necessidade operacional —
   * `cms:migrate` roda do host, e o console do MinIO e como se inspeciona o que
   * foi publicado. Loopback nao e superficie de rede; o que nao pode existir e
   * uma porta em TODAS as interfaces alem da borda.
   */
  const expostos = Object.entries(servicos('compose.yaml'))
    .filter(([, s]) => (s.ports ?? []).some((p) => !String(p).startsWith('127.0.0.1:')))
    .map(([nome]) => nome);

  assert.deepEqual(
    expostos,
    [UNICO_PUBLICO],
    'servico escutando em todas as interfaces alem do edge',
  );
});

test('`cms` e `packer` nao publicam porta nenhuma', () => {
  /**
   * Os dois que carregam credencial: o `cms` atende o formulario de login, o
   * `packer` monta a chave privada Ed25519. Para eles, nem loopback — uma porta
   * em 127.0.0.1 e um caminho que alcanca o CMS sem passar pelo TLS da borda, e
   * foi exatamente assim que a lacuna deste item existiu.
   */
  const com = ['cms', 'packer'].filter((nome) => (servicos('compose.yaml')[nome]?.ports ?? []).length > 0);
  assert.deepEqual(com, [], 'servico com credencial publicando porta');
});

test('o `edge` depende do `cms`', () => {
  /**
   * Sem isto o proxy sobe apontando para o vazio, e o primeiro acesso vira 502 —
   * que parece defeito da borda quando e ordem de inicializacao. O compose
   * normativo da `spec/stack.md` §7 ja trazia esta dependencia; a implementacao a
   * tinha perdido.
   */
  const edge = servicos('compose.yaml')[UNICO_PUBLICO];
  assert.ok(edge, 'servico `edge` sumiu do compose');

  const dependencias = Array.isArray(edge.depends_on)
    ? edge.depends_on
    : Object.keys(edge.depends_on ?? {});
  assert.ok(dependencias.includes('cms'), 'o edge proxia o cms e nao espera por ele');
});

test('toda porta publicada em desenvolvimento fica presa a 127.0.0.1', () => {
  /**
   * O override existe para desenvolver, e ali ha portas a mais — inclusive a do
   * CMS pelo edge. O que nao pode e alguma delas escutar em todas as interfaces:
   * numa maquina em rede compartilhada, `8082:81` sem o prefixo entrega o
   * formulario de login para o escritorio inteiro.
   */
  const soltas: string[] = [];
  for (const [nome, s] of Object.entries(servicos('compose.override.yaml'))) {
    for (const porta of s.ports ?? []) {
      if (!String(porta).startsWith('127.0.0.1:')) soltas.push(`${nome}: ${String(porta)}`);
    }
  }
  assert.deepEqual(soltas, [], 'porta de desenvolvimento escutando fora do loopback');
});

test('o CMS nao publica porta nem em desenvolvimento', () => {
  // Chega-se a ele pelo edge, como em producao. Publicar 8787 aqui pouparia um
  // salto e faria o unico caminho exercitado em dev ser o que producao nao usa —
  // que e como o `Origin` do CSRF ja mordeu este projeto duas vezes.
  const cms = servicos('compose.override.yaml')['cms'];
  assert.ok(
    cms === undefined || cms.ports === undefined || cms.ports.length === 0,
    'o cms voltou a publicar porta no override: dev deixaria de exercitar o proxy',
  );
});

// ---------------------------------------------------------------------------
// A guarda que corresponde ao predicado do cookie
// ---------------------------------------------------------------------------

test('BETTER_AUTH_URL em http:// fora do loopback DERRUBA o boot', async () => {
  /**
   * O teste mais importante do arquivo.
   *
   * `secure` e o prefixo `__Secure-` do cookie saem de exatamente um predicado no
   * Better Auth: `baseURL.startsWith("https://")`. Sem esta guarda, um `.env` de
   * producao copiado do exemplo sobe com senha, codigo TOTP e cookie atravessando
   * HTTP em claro, e NADA acusa — que e como esta lacuna sobreviveu a Fase 3.
   *
   * O criterio e o LOOPBACK e nao `NODE_ENV` porque a primeira versao apostava
   * num rotulo: o `cms/Dockerfile` define `NODE_ENV=production`, e o compose de
   * desenvolvimento roda essa mesma imagem por HTTP. Quem implanta com o rotulo
   * trocado perderia a protecao em silencio.
   *
   * Sabotagem: remover a chamada a `exigirTlsForaDoLoopback` deixa isto vermelho.
   */
  const { loadEnv } = await import('../src/env.js');
  const base = {
    BETTER_AUTH_SECRET: 'segredo-de-teste-ficticio-com-mais-de-32-caracteres',
    IP_HASH_SALT: 'sal-de-teste-ficticio-com-mais-de-32-caracteres',
  };

  for (const proibido of [
    'http://cms.exemplo.invalid',
    // Mesma rede local tambem conta: ali a credencial cruza um cabo de verdade.
    'http://192.168.1.10:8082',
  ]) {
    assert.throws(
      () => loadEnv({ ...base, BETTER_AUTH_URL: proibido }),
      /https:\/\//,
      `aceitou "${proibido}": o cookie sairia sem \`Secure\` e ninguem seria avisado`,
    );
  }

  // O loopback e o proprio computador — nao atravessa rede, e e onde se
  // desenvolve. Recusar aqui trancaria todo mundo fora do ambiente de trabalho.
  for (const permitido of ['http://127.0.0.1:8082', 'http://localhost:5173']) {
    assert.equal(loadEnv({ ...base, BETTER_AUTH_URL: permitido }).authBaseUrl, permitido);
  }

  // E o caminho de producao, que e o ponto de tudo isto.
  assert.equal(
    loadEnv({ ...base, BETTER_AUTH_URL: 'https://cms.exemplo.invalid' }).authBaseUrl,
    'https://cms.exemplo.invalid',
  );
});
