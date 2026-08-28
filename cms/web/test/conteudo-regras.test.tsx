/**
 * Conteudo e regras — o que mais importa nas duas telas.
 *
 * O teste do falso negativo e o mais importante do arquivo: `FALSO_NEGATIVO` e
 * o caso em que o aplicativo mandaria para casa alguem que precisava de
 * emergencia. Se ele aparecer como mais um item de lista, a tela deixa de
 * cumprir a unica funcao clinica que tem.
 */
import { act, cleanup, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';

import { aoExigirSegundoFator, aoPerderSessao } from '../src/api/api.js';
import type { Operador } from '../src/api/erros.js';
import { SessaoProvider } from '../src/sessao.js';
import { FormularioDeConteudo } from '../src/telas/conteudo.js';
import { EditorDeRegra } from '../src/telas/regras.js';

const EDITOR: Operador = {
  id: 'op-editor',
  email: 'editor@exemplo.invalid',
  name: 'Editor Teste',
  role: 'editor',
  permissions: ['content:read', 'content:write'],
};

const REVISOR: Operador = {
  id: 'op-revisor',
  email: 'revisora@exemplo.invalid',
  name: 'Revisora Teste',
  role: 'clinical_reviewer',
  permissions: ['content:read', 'approval:decide'],
};

function json(status: number, corpo: unknown, cabecalhos: Record<string, string> = {}) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { 'content-type': 'application/json', ...cabecalhos },
  });
}

let enviados: { url: string; metodo: string; ifMatch?: string; corpo: unknown }[];

afterEach(cleanup);
beforeEach(() => {
  enviados = [];
  aoPerderSessao(() => {});
  aoExigirSegundoFator(() => {});
});

function servidor(rotas: Record<string, (corpo: unknown) => Response>) {
  vi.stubGlobal(
    'fetch',
    vi.fn((url: string, init?: RequestInit) => {
      const cab = (init?.headers ?? {}) as Record<string, string>;
      enviados.push({
        url,
        metodo: init?.method ?? 'GET',
        ifMatch: cab['if-match'],
        corpo: init?.body ? JSON.parse(String(init.body)) : undefined,
      });
      const responder = rotas[`${init?.method ?? 'GET'} ${url}`] ?? rotas[url];
      if (!responder) return Promise.resolve(json(404, { error: 'nao encontrado' }));
      return Promise.resolve(responder(init?.body ? JSON.parse(String(init.body)) : undefined));
    }),
  );
}

function montar(caminho: string, rota: string, elemento: React.ReactElement, quem: Operador) {
  return render(
    <MemoryRouter initialEntries={[caminho]}>
      <SessaoProvider inicial={quem}>
        <Routes>
          <Route path={rota} element={elemento} />
        </Routes>
      </SessaoProvider>
    </MemoryRouter>,
  );
}

// ---------------------------------------------------------------------------
// Regras
// ---------------------------------------------------------------------------

const SIMULACAO_PERIGOSA = {
  problemas: [],
  simulacao: {
    muda: [
      { casoId: 'chest-pain', tokens: ['chest', 'pain'], de: 'EMERGENCY', para: 'ROUTINE_UBS', classe: 'FALSO_NEGATIVO' },
      { casoId: 'headache', tokens: ['head'], de: 'ROUTINE_UBS', para: 'EMERGENCY', classe: 'ESCALADA' },
    ],
    inalterados: 22,
    total: 24,
    falsosNegativos: 1,
    jaVermelhos: 3,
  },
};

test('o falso negativo domina a tela e BLOQUEIA o salvar', async () => {
  servidor({ 'POST /api/rules/simular': () => json(200, SIMULACAO_PERIGOSA) });
  montar('/regras/nova', '/regras/nova', <EditorDeRegra />, EDITOR);

  await userEvent.click(screen.getByRole('button', { name: 'Simular' }));

  // Na regiao de alerta, e com a contagem como manchete — nao um item de lista.
  const alerta = await screen.findByRole('alert');
  expect(alerta.textContent).toMatch(/1 caso\(s\) deixariam de ir para a emergencia/i);
  expect(alerta.textContent).toMatch(/chest-pain/);

  // Salvar bloqueado ate o reconhecimento explicito. Guarda de INTERFACE — o
  // servidor nao a impoe, e o texto diz isso.
  const salvar = screen.getByRole('button', { name: 'Salvar' });
  expect(salvar.hasAttribute('disabled')).toBe(true);

  await userEvent.click(screen.getByRole('checkbox', { name: /estou ciente/i }));
  expect(screen.getByRole('button', { name: 'Salvar' }).hasAttribute('disabled')).toBe(false);
});

test('o tamanho da amostra aparece, com os que JA divergiam', async () => {
  // Sem `jaVermelhos`, uma regra inofensiva parece inofensiva mesmo quando
  // metade dos casos ja diverge do esperado antes dela.
  servidor({ 'POST /api/rules/simular': () => json(200, SIMULACAO_PERIGOSA) });
  montar('/regras/nova', '/regras/nova', <EditorDeRegra />, EDITOR);

  await userEvent.click(screen.getByRole('button', { name: 'Simular' }));
  const amostra = await screen.findByText(/22 de 24 casos inalterados/, { selector: 'p' });
  // `jaVermelhos` no mesmo paragrafo: e o que impede uma regra inofensiva de
  // parecer inofensiva quando os casos ja divergiam antes dela.
  expect(amostra.textContent).toMatch(/3.*ja divergiam/i);
});

test('o revisor clinico SIMULA e nao pode salvar', async () => {
  // `POST /api/rules/simular` exige so `content:read`, de proposito: e o que
  // permite perguntar "o que esta regra faria?" sem poder escreve-la.
  servidor({ 'POST /api/rules/simular': () => json(200, { problemas: [], simulacao: null }) });
  montar('/regras/nova', '/regras/nova', <EditorDeRegra />, REVISOR);

  expect(screen.getByRole('button', { name: 'Simular' })).toBeTruthy();
  expect(screen.queryByRole('button', { name: 'Salvar' })).toBeNull();
});

test('sem desfecho cadastrado a tela EXPLICA, em vez de parecer falha', async () => {
  // `simulacao: null` acontece exatamente quando ha `desfecho_inexistente` —
  // `desfechoPadrao()` deriva o padrao dos desfechos e lanca quando nao ha
  // nenhum. Sem explicacao, parece que a simulacao quebrou.
  servidor({
    'POST /api/rules/simular': () =>
      json(200, {
        problemas: [{ codigo: 'desfecho_inexistente', mensagem: 'O desfecho X nao existe.' }],
        simulacao: null,
      }),
  });
  montar('/regras/nova', '/regras/nova', <EditorDeRegra />, EDITOR);

  await userEvent.click(screen.getByRole('button', { name: 'Simular' }));
  // `selector` porque o matcher de texto do RTL compara o `textContent` de TODO
  // elemento, entao um regex casa tambem com os ancestrais que contem o trecho.
  expect(await screen.findByText(/nao ha o que comparar/i, { selector: 'p' })).toBeTruthy();
  // E o "como resolver" do codigo, nao so a mensagem do servidor.
  expect(screen.getByText(/Cadastre-o em Conteudo antes/i, { selector: 'span' })).toBeTruthy();
});

test('o 422 alimenta o MESMO painel, com todos os problemas de uma vez', async () => {
  servidor({
    'POST /api/rules': () =>
      json(422, {
        error: 'regra invalida',
        problemas: [
          { codigo: 'sem_termos', mensagem: 'A regra nao tem nenhum termo.' },
          { codigo: 'prioridade_duplicada', mensagem: 'Prioridade 100 ja esta em uso.' },
        ],
      }),
  });
  montar('/regras/nova', '/regras/nova', <EditorDeRegra />, EDITOR);

  await userEvent.type(screen.getByLabelText('Desfecho'), 'ROUTINE_UBS');
  await userEvent.type(screen.getByLabelText('Token do grupo 1'), 'chest');
  await userEvent.click(screen.getByRole('button', { name: 'Salvar' }));

  // OS DOIS: "corrigir um por requisicao faria qualquer revisor desistir na
  // terceira".
  expect(await screen.findByText(/A regra nao tem nenhum termo/)).toBeTruthy();
  expect(screen.getByText(/Prioridade 100 ja esta em uso/)).toBeTruthy();
});

// ---------------------------------------------------------------------------
// Conteudo
// ---------------------------------------------------------------------------

test('editar reenvia o ETag lido como If-Match', async () => {
  servidor({
    'GET /api/content/cards/c1': () =>
      json(200, { id: 'c1', kind: 'info', iconRef: 'i1', colorToken: 'blue' }, { etag: '"4"' }),
    'PATCH /api/content/cards/c1': () => json(200, { ok: true, versao: 5 }, { etag: '"5"' }),
  });
  montar('/conteudo/cards/editar?id=c1', '/conteudo/:entidade/editar', <FormularioDeConteudo />, EDITOR);

  await waitFor(() => expect((screen.getByLabelText('Tipo') as HTMLInputElement).value).toBe('info'));
  await userEvent.click(screen.getByRole('button', { name: 'Gravar' }));

  await waitFor(() => expect(enviados.some((e) => e.metodo === 'PATCH')).toBe(true));
  // Sem isto o servidor responde 428 — que a tela nao teria como explicar.
  expect(enviados.find((e) => e.metodo === 'PATCH')?.ifMatch).toBe('"4"');
});

test('o formulario NUNCA envia campo de autoria', async () => {
  // `version`/`updatedBy`/`updatedAt` voltam no GET e sao descartadas na escrita.
  // Envia-las faria o operador ver uma edicao que "nao salvou".
  servidor({
    'GET /api/content/cards/c1': () =>
      json(
        200,
        { id: 'c1', kind: 'info', iconRef: 'i1', colorToken: 'blue', version: 4, updatedBy: 'x' },
        { etag: '"4"' },
      ),
    'PATCH /api/content/cards/c1': () => json(200, { ok: true, versao: 5 }, { etag: '"5"' }),
  });
  montar('/conteudo/cards/editar?id=c1', '/conteudo/:entidade/editar', <FormularioDeConteudo />, EDITOR);

  await waitFor(() => expect((screen.getByLabelText('Tipo') as HTMLInputElement).value).toBe('info'));
  await userEvent.click(screen.getByRole('button', { name: 'Gravar' }));

  await waitFor(() => expect(enviados.some((e) => e.metodo === 'PATCH')).toBe(true));
  const corpo = enviados.find((e) => e.metodo === 'PATCH')?.corpo as Record<string, unknown>;
  for (const proibido of ['version', 'updatedBy', 'updatedAt']) {
    expect(Object.keys(corpo)).not.toContain(proibido);
  }
});

test('409 de versao mostra o conflito e NAO reenvia sozinho', async () => {
  servidor({
    'GET /api/content/cards/c1': () => json(200, { id: 'c1', kind: 'info' }, { etag: '"4"' }),
    'PATCH /api/content/cards/c1': () =>
      json(409, { error: 'a linha mudou desde a leitura', versaoAtual: 9 }),
  });
  montar('/conteudo/cards/editar?id=c1', '/conteudo/:entidade/editar', <FormularioDeConteudo />, EDITOR);

  await waitFor(() => expect((screen.getByLabelText('Tipo') as HTMLInputElement).value).toBe('info'));
  await userEvent.click(screen.getByRole('button', { name: 'Gravar' }));

  expect((await screen.findByRole('alert')).textContent).toMatch(/versao 9/);
  await act(async () => {
    await Promise.resolve();
  });
  // Reenviar sozinho seria exatamente o atropelo silencioso que o travamento
  // otimista existe para impedir.
  expect(enviados.filter((e) => e.metodo === 'PATCH')).toHaveLength(1);
});

test('nao ha botao de apagar onde a rota nao existe', async () => {
  // `cards` nao e `apagavel`: a FK recusaria, e oferecer um botao que sempre
  // falha ensina o editor a ignorar mensagem de erro.
  servidor({ 'GET /api/content/cards/c1': () => json(200, { id: 'c1' }, { etag: '"1"' }) });
  montar('/conteudo/cards/editar?id=c1', '/conteudo/:entidade/editar', <FormularioDeConteudo />, EDITOR);

  await waitFor(() => expect(screen.getByRole('button', { name: 'Gravar' })).toBeTruthy());
  expect(screen.queryByRole('button', { name: 'Apagar' })).toBeNull();
});
