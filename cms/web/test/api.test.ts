/**
 * O embrulho de rede: cada forma de falha do servidor vira o `Falha` certo, e o
 * `ETag` de uma leitura chega ao `If-Match` da escrita seguinte.
 *
 * O teste mais importante do arquivo e o ultimo: `gravar` nao aceita nada que
 * nao tenha vindo de `ler`. Isso e verificado pelo compilador, nao aqui — o que
 * este arquivo afirma e o outro lado, que o valor lido REALMENTE viaja.
 */
import { beforeEach, expect, test, vi } from 'vitest';

import {
  ErroApi,
  aoExigirSegundoFator,
  aoPerderSessao,
  buscar,
  criar,
  gravar,
  ler,
} from '../src/api/api.js';

function responder(status: number, corpo: unknown, cabecalhos: Record<string, string> = {}) {
  return new Response(corpo === undefined ? null : JSON.stringify(corpo), {
    status,
    headers: { 'content-type': 'application/json', ...cabecalhos },
  });
}

let chamadas: { url: string; init: RequestInit }[];

beforeEach(() => {
  chamadas = [];
  // Reinstalados a cada teste: sao estado de MODULO, e um aviso deixado por um
  // teste anterior dispararia dentro do proximo.
  aoPerderSessao(() => {});
  aoExigirSegundoFator(() => {});
});

function fingir(...respostas: Response[]) {
  const fila = [...respostas];
  vi.stubGlobal(
    'fetch',
    vi.fn((url: string, init: RequestInit) => {
      chamadas.push({ url, init });
      return Promise.resolve(fila.shift() ?? responder(500, { error: 'erro interno' }));
    }),
  );
}

async function falhaDe(fn: () => Promise<unknown>) {
  try {
    await fn();
  } catch (e) {
    if (e instanceof ErroApi) return e.falha;
    throw e;
  }
  throw new Error('esperava ErroApi e nada foi levantado');
}

test('401 vira nao_autenticado e dispara o aviso de sessao perdida', async () => {
  let avisou = false;
  aoPerderSessao(() => {
    avisou = true;
  });
  fingir(responder(401, { error: 'nao autenticado' }));

  expect(await falhaDe(() => buscar('/api/me'))).toEqual({ tipo: 'nao_autenticado' });
  expect(avisou).toBe(true);
});

test('403 com `next` vira segundo_fator e carrega o caminho DO SERVIDOR', async () => {
  let destino: string | undefined;
  aoExigirSegundoFator((n) => {
    destino = n;
  });
  fingir(
    responder(403, { error: 'segundo fator obrigatorio', next: '/api/auth/two-factor/enable' }),
  );

  expect(await falhaDe(() => buscar('/api/releases'))).toEqual({
    tipo: 'segundo_fator',
    next: '/api/auth/two-factor/enable',
  });
  // Fixar o caminho no cliente criaria uma segunda copia de uma decisao do
  // middleware; o teste afirma que ele veio de la.
  expect(destino).toBe('/api/auth/two-factor/enable');
});

test('os tres 403 restantes sao distinguidos', async () => {
  fingir(responder(403, { error: 'sem permissao' }));
  expect(await falhaDe(() => buscar('/api/users'))).toEqual({ tipo: 'sem_permissao' });

  fingir(responder(403, { error: 'operador desligado' }));
  expect(await falhaDe(() => buscar('/api/me'))).toEqual({ tipo: 'desligado' });

  // Auto-aprovacao: a mensagem do servidor ja e escrita para humanos e vai
  // literal para a tela.
  fingir(responder(403, { error: 'quem cria a release nao a aprova' }));
  expect(await falhaDe(() => criar('/api/approvals', {}))).toEqual({
    tipo: 'proibido',
    mensagem: 'quem cria a release nao a aprova',
  });
});

test('409 de versao carrega contra o que se perdeu', async () => {
  fingir(responder(409, { error: 'a linha mudou desde a leitura', versaoAtual: 7 }));
  expect(await falhaDe(() => gravar({ dados: {}, versao: 3 }, '/api/content/cards/c1', {}))).toEqual(
    { tipo: 'conflito_versao', versaoAtual: 7 },
  );
});

test('409 de estado traz `atual` e `permitidas` para redesenhar os botoes', async () => {
  fingir(
    responder(409, {
      error: 'transicao nao permitida a partir do estado atual',
      atual: 'built',
      permitidas: [{ para: 'revoked', por: ['admin'], motivo: 'revogacao antes de publicar' }],
    }),
  );
  const falha = await falhaDe(() => criar('/api/releases/r1/submeter', {}));
  expect(falha).toMatchObject({ tipo: 'conflito_estado', atual: 'built' });
});

test('422 de regra entrega TODOS os problemas de uma vez', async () => {
  // "Corrigir um por requisicao faria qualquer revisor desistir na terceira."
  const problemas = [
    { codigo: 'sem_termos', mensagem: 'a regra nao tem termos' },
    { codigo: 'prioridade_duplicada', mensagem: 'outra regra ja usa esta prioridade' },
  ];
  fingir(responder(422, { error: 'regra invalida', problemas }));
  expect(await falhaDe(() => criar('/api/rules', {}))).toEqual({
    tipo: 'regra_invalida',
    problemas,
  });
});

test('428 e classificado, ainda que a SPA nao consiga produzi-lo', async () => {
  fingir(responder(428, { error: 'informe a versao lida no cabecalho If-Match' }));
  expect(await falhaDe(() => buscar('/api/content/cards/c1'))).toEqual({ tipo: 'precondicao' });
});

test('rede fora do ar entra na MESMA uniao, e nao como excecao solta', async () => {
  vi.stubGlobal(
    'fetch',
    vi.fn(() => Promise.reject(new TypeError('failed to fetch'))),
  );
  expect(await falhaDe(() => buscar('/api/me'))).toEqual({ tipo: 'servidor' });
});

test('o ETag de `ler` vira o If-Match de `gravar`', async () => {
  fingir(
    responder(200, { id: 'c1', title: 'x' }, { etag: '"4"' }),
    responder(200, { ok: true, versao: 5 }, { etag: '"5"' }),
  );

  const lido = await ler<{ id: string }>('/api/content/cards/c1');
  expect(lido.versao).toBe(4);

  const nova = await gravar(lido, '/api/content/cards/c1', { title: 'y' });
  expect(nova).toBe(5);

  const cabecalhos = chamadas[1]?.init.headers as Record<string, string>;
  // Sem isto o servidor responde 428, e o operador nao tem como interpretar.
  expect(cabecalhos['if-match']).toBe('"4"');
});

test('nenhuma requisicao define `Origin`, e todo caminho e relativo', async () => {
  fingir(responder(200, { ok: true }), responder(200, { ok: true }));
  await buscar('/api/me');
  await criar('/api/releases', { id: 'r1' });

  for (const { url, init } of chamadas) {
    expect(url.startsWith('/')).toBe(true);
    // `Origin` e nome de cabecalho proibido: o `fetch` o descarta. Codigo que o
    // define nao faz nada e ensina que faz.
    const nomes = Object.keys((init.headers ?? {}) as Record<string, string>).map((n) =>
      n.toLowerCase(),
    );
    expect(nomes).not.toContain('origin');
    expect(init.credentials).toBe('same-origin');
  }
});

test('caminho absoluto e recusado antes de sair da maquina', async () => {
  fingir(responder(200, {}));
  // Uma base absoluta reintroduziria, pela porta dos fundos, o 403 de CSRF que o
  // proxy do Vite existe para evitar. Falhar aqui e mais barato que investigar la.
  await expect(buscar('https://exemplo.invalid/api/me')).rejects.toThrow(/relativo/);
});
