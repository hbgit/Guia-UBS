/**
 * A tela da release.
 *
 * O que estes testes protegem, em ordem de importancia:
 *
 * 1. **Os botoes saem de `transicoes`, e nao de um `if`.** Uma segunda copia da
 *    FSM oferece acao que o servidor recusa, ou esconde acao que ele permite.
 * 2. **`transicionou: false` e SUCESSO.** O quorum nao fechou, mas a decisao foi
 *    registrada. Pintar de erro faz o revisor achar que o voto se perdeu.
 * 3. **O 409 de estado REDESENHA a partir do que o servidor devolveu.** Insistir
 *    com o botao velho produz um segundo 409, e o operador nao entende nenhum.
 * 4. **A auto-aprovacao mostra a mensagem do servidor, literal.** Ela ja e
 *    escrita para humanos, e reescrever perderia o motivo.
 */
import { act, cleanup, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';

import type { Operador } from '../src/api/erros.js';
import { aoExigirSegundoFator, aoPerderSessao } from '../src/api/api.js';
import { SessaoProvider } from '../src/sessao.js';
import { TelaDaRelease } from '../src/telas/releases.js';

const REVISOR: Operador = {
  id: 'op-revisor',
  email: 'revisora@exemplo.invalid',
  name: 'Revisora Teste',
  role: 'clinical_reviewer',
  permissions: ['content:read', 'approval:decide'],
};

function json(status: number, corpo: unknown) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

/** A release em revisao, com as transicoes que o servidor devolveria. */
const EM_REVISAO = {
  release: {
    id: 'rel-2026-01',
    municipalityId: 'm-exemplo',
    packVersion: 1,
    schemaVersion: '1.0',
    status: 'pending_review',
  },
  transicoes: [
    {
      de: 'pending_review',
      para: 'approved',
      por: ['clinical_reviewer'],
      motivo: 'quorum de revisao clinica alcancado',
    },
    {
      de: 'pending_review',
      para: 'draft',
      por: ['clinical_reviewer'],
      motivo: 'rejeicao devolve para correcao',
    },
  ],
};

let enviados: { url: string; corpo: unknown }[];

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
      const corpo = init?.body ? JSON.parse(String(init.body)) : undefined;
      enviados.push({ url, corpo });
      const responder = rotas[url];
      if (!responder) return Promise.resolve(json(404, { error: 'nao encontrado' }));
      return Promise.resolve(responder(corpo));
    }),
  );
}

function montar() {
  return render(
    <MemoryRouter initialEntries={['/releases/rel-2026-01']}>
      <SessaoProvider inicial={REVISOR}>
        <Routes>
          <Route path="/releases/:id" element={<TelaDaRelease />} />
        </Routes>
      </SessaoProvider>
    </MemoryRouter>,
  );
}

test('os botoes vem de `transicoes`, com o motivo do servidor ao lado', async () => {
  servidor({ '/api/releases/rel-2026-01': () => json(200, EM_REVISAO) });
  montar();

  expect(await screen.findByRole('button', { name: 'Aprovar' })).toBeTruthy();
  expect(screen.getByRole('button', { name: 'Rejeitar' })).toBeTruthy();
  // O texto explicativo e o `motivo` da transicao, nao um texto nosso.
  expect(screen.getByText('quorum de revisao clinica alcancado')).toBeTruthy();
  // E nada alem do que o servidor ofereceu: sem "Submeter", sem "Revogar".
  expect(screen.queryByRole('button', { name: /submeter/i })).toBeNull();
  expect(screen.queryByRole('button', { name: /revogar/i })).toBeNull();
});

test('aprovar envia a decisao para /api/approvals, com o comentario', async () => {
  servidor({
    '/api/releases/rel-2026-01': () => json(200, EM_REVISAO),
    '/api/approvals': () => json(200, { ok: true, de: 'pending_review', para: 'approved' }),
  });
  montar();

  await userEvent.type(
    await screen.findByLabelText('Comentario da revisao'),
    'conferido contra os casos golden',
  );
  await userEvent.click(screen.getByRole('button', { name: 'Aprovar' }));

  await waitFor(() => expect(enviados.some((e) => e.url === '/api/approvals')).toBe(true));
  // A aprovacao NAO viaja por uma rota da release: e em `/api/approvals` que
  // moram o quorum e o gatilho anti-auto-aprovacao.
  expect(enviados.find((e) => e.url === '/api/approvals')?.corpo).toEqual({
    releaseId: 'rel-2026-01',
    decision: 'approve',
    comment: 'conferido contra os casos golden',
  });
});

test('quorum nao fechado e SUCESSO, e diz quantas faltam', async () => {
  servidor({
    '/api/releases/rel-2026-01': () => json(200, EM_REVISAO),
    '/api/approvals': () => json(200, { ok: true, transicionou: false, faltam: 1 }),
  });
  montar();

  await userEvent.click(await screen.findByRole('button', { name: 'Aprovar' }));

  const aviso = await screen.findByRole('alert');
  expect(aviso.textContent).toMatch(/faltam 1/i);
  // Verde, e nao vermelho: o servidor devolveu 200 justamente para o revisor nao
  // achar que o voto se perdeu.
  expect(aviso.className).toBe('sucesso');
});

test('409 de estado redesenha os botoes a partir de `permitidas`', async () => {
  servidor({
    '/api/releases/rel-2026-01': () => json(200, EM_REVISAO),
    '/api/approvals': () =>
      json(409, {
        error: 'transicao nao permitida a partir do estado atual',
        atual: 'approved',
        permitidas: [
          { de: 'approved', para: 'building', por: ['job'], motivo: 'posse por compare-and-set' },
        ],
      }),
  });
  montar();

  await userEvent.click(await screen.findByRole('button', { name: 'Aprovar' }));

  await waitFor(() => expect(screen.getByRole('alert').textContent).toMatch(/approved/));
  // Os botoes velhos somem, e a transicao do job vira TEXTO — nao botao.
  await waitFor(() => expect(screen.queryByRole('button', { name: 'Aprovar' })).toBeNull());
  expect(screen.getByText(/posse por compare-and-set/)).toBeTruthy();
});

test('auto-aprovacao mostra a mensagem do servidor, literal', async () => {
  // O gatilho do banco e a defesa; a mensagem dele ja e escrita para humanos.
  const doServidor = 'quem cria a release nao a aprova';
  servidor({
    '/api/releases/rel-2026-01': () => json(200, EM_REVISAO),
    '/api/approvals': () => json(403, { error: doServidor }),
  });
  montar();

  await userEvent.click(await screen.findByRole('button', { name: 'Aprovar' }));
  expect((await screen.findByRole('alert')).textContent).toBe(doServidor);
});

test('estado final nao oferece acao nenhuma', async () => {
  servidor({
    '/api/releases/rel-2026-01': () =>
      json(200, {
        release: { ...EM_REVISAO.release, status: 'revoked' },
        transicoes: [],
      }),
  });
  montar();

  await waitFor(() => expect(screen.getByText(/estado final/i)).toBeTruthy());
  await act(async () => {
    await Promise.resolve();
  });
  expect(screen.queryAllByRole('button')).toHaveLength(0);
});

test('o botao so aparece para quem `t.por` nomeia', async () => {
  /**
   * Regressao, achada no navegador.
   *
   * A tela renderizava um botao por transicao, sem olhar `t.por` — entao o
   * EDITOR que acabara de submeter via "Aprovar" logo abaixo, clicava, e recebia
   * 403 com uma mensagem generica. Pior: ele e o autor, e mesmo com o papel certo
   * o gatilho anti-auto-aprovacao o barraria.
   *
   * Usar `por` nao e uma segunda copia da FSM: ele vem do servidor, na MESMA
   * resposta que `de` e `para`. Ignora-lo era usar a resposta pela metade.
   *
   * Sabotagem que confirma: remover `&& podeAgir(t)` do filtro deixa isto
   * vermelho.
   */
  servidor({ '/api/releases/rel-2026-01': () => json(200, EM_REVISAO) });

  render(
    <MemoryRouter initialEntries={['/releases/rel-2026-01']}>
      <SessaoProvider
        inicial={{
          id: 'op-editor',
          email: 'editor@exemplo.invalid',
          name: 'Editor Teste',
          role: 'editor',
          permissions: ['content:read', 'content:write'],
        }}
      >
        <Routes>
          <Route path="/releases/:id" element={<TelaDaRelease />} />
        </Routes>
      </SessaoProvider>
    </MemoryRouter>,
  );

  // As duas transicoes existem e o editor as VE — como texto, dizendo de quem
  // e a vez. Sao duas porque aprovar e rejeitar sao ambas do revisor clinico.
  await waitFor(() => expect(screen.getAllByText(/cabe a clinical_reviewer/i)).toHaveLength(2));
  // Mas nao como botao.
  expect(screen.queryByRole('button', { name: 'Aprovar' })).toBeNull();
  expect(screen.queryByRole('button', { name: 'Rejeitar' })).toBeNull();
  // E, sem botao de decisao, nao ha por que pedir comentario.
  expect(screen.queryByLabelText('Comentario da revisao')).toBeNull();
});
