/**
 * As telas da Fase A.
 *
 * Tres coisas aqui valem mais que as outras:
 *
 * 1. **A ramificacao tripla da entrada.** O ramo sai do STATUS de `/api/me`, e o
 *    401 do meio e o que engana — ele NAO significa "sessao perdida", significa
 *    "o cookie e o de 2FA pendente". Errar isso produz um laco de volta para a
 *    tela de entrada que so termina quando alguem desiste.
 * 2. **O 429 sem digito nenhum.** A LGPD-RT07 e explicita: a resposta nao revela
 *    quanto falta nem quantas tentativas restam, porque seria um oraculo sobre
 *    conta alheia. Um "tente em 30s" bem-intencionado na tela desfaz isso.
 * 3. **`enable` REVOGA a sessao.** A tela nao pode chamar `/api/me` depois — a
 *    resposta seria 401 e pareceria defeito de quem acabou de cadastrar certo.
 */
import { act, cleanup, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';

import type { Operador } from '../src/api/erros.js';
import { aoExigirSegundoFator, aoPerderSessao } from '../src/api/api.js';
import { App } from '../src/App.js';
import { estadoDaSessao } from '../src/api/entrada.js';
import { navegacaoPara } from '../src/rotas.js';
import { SessaoProvider } from '../src/sessao.js';

/** Operador FICTICIO. Nenhum dado real entra em teste. */
function operador(role: Operador['role'], permissions: Operador['permissions']): Operador {
  return { id: 'op-teste', email: 'operador@exemplo.invalid', name: 'Operador Teste', role, permissions };
}

function json(status: number, corpo: unknown) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

let pedidos: string[];

/**
 * Limpeza EXPLICITA.
 *
 * O Testing Library so registra o `afterEach` automatico quando o runner expoe
 * globais, e `vite.config.ts` deliberadamente nao usa `globals: true`. Sem esta
 * linha os renders se acumulam no mesmo `document.body` e as consultas passam a
 * encontrar elementos de testes ANTERIORES — o sintoma e "found multiple
 * elements" num teste que so renderizou uma tela.
 */
afterEach(cleanup);

beforeEach(() => {
  pedidos = [];
  aoPerderSessao(() => {});
  aoExigirSegundoFator(() => {});
});

/**
 * Responde por CAMINHO. Um caminho pode declarar uma SEQUENCIA de respostas: a
 * sondagem de `/api/me` na montagem e a chamada logo apos o `sign-in` sao
 * momentos diferentes do mesmo fluxo, e respondem diferente. A ultima resposta
 * da lista se repete.
 */
function servidor(rotas: Record<string, Response[] | (() => Response)>) {
  const restante: Record<string, Response[]> = {};
  vi.stubGlobal(
    'fetch',
    vi.fn((url: string) => {
      pedidos.push(url);
      const rota = rotas[url];
      if (!rota) return Promise.resolve(json(404, { error: 'nao encontrado' }));
      if (typeof rota === 'function') return Promise.resolve(rota());
      restante[url] ??= [...rota];
      const fila = restante[url]!;
      // `clone()` porque um corpo so pode ser lido UMA vez, e a ultima resposta
      // e reutilizada.
      return Promise.resolve((fila.length > 1 ? fila.shift()! : fila[0]!).clone());
    }),
  );
}

function montar(rotaInicial: string, inicial?: Operador) {
  return render(
    <MemoryRouter initialEntries={[rotaInicial]}>
      <SessaoProvider inicial={inicial}>
        <App />
      </SessaoProvider>
    </MemoryRouter>,
  );
}

async function preencherEntrada() {
  await userEvent.type(screen.getByLabelText('E-mail'), 'operador@exemplo.invalid');
  await userEvent.type(screen.getByLabelText('Senha'), 'senha-ficticia-de-teste-123');
  await userEvent.click(screen.getByRole('button', { name: 'Entrar' }));
}

// ---------------------------------------------------------------------------
// A ramificacao da entrada
// ---------------------------------------------------------------------------

test('sessao completa leva ao painel', async () => {
  servidor({
    '/api/auth/sign-in/email': () => json(200, { ok: true }),
    '/api/me': () => json(200, operador('editor', ['content:read', 'content:write'])),
  });

  montar('/entrar');
  await preencherEntrada();

  await waitFor(() => expect(screen.getByRole('heading', { name: 'Painel' })).toBeTruthy());
});

test('401 em /api/me apos o sign-in significa CODIGO PENDENTE, nao sessao perdida', async () => {
  // O cookie que o `sign-in` devolveu e o de 2FA pendente (600 s). Tratar como
  // "nao autenticado" jogaria a pessoa de volta para /entrar, em laco.
  servidor({
    '/api/auth/sign-in/email': () => json(200, { ok: true }),
    '/api/me': () => json(401, { error: 'nao autenticado' }),
  });

  montar('/entrar');
  await preencherEntrada();

  await waitFor(() =>
    expect(screen.getByRole('heading', { name: 'Codigo do segundo fator' })).toBeTruthy(),
  );
});

test('403 com `next` leva ao cadastro do segundo fator', async () => {
  servidor({
    '/api/auth/sign-in/email': () => json(200, { ok: true }),
    '/api/me': [
      // Sondagem da montagem: ninguem entrou ainda.
      json(401, { error: 'nao autenticado' }),
      // Depois do sign-in: a conta existe e ainda nao cadastrou o segundo fator.
      json(403, { error: 'segundo fator obrigatorio', next: '/api/auth/two-factor/enable' }),
    ],
  });

  montar('/entrar');
  await preencherEntrada();

  await waitFor(() =>
    expect(screen.getByRole('heading', { name: 'Cadastrar segundo fator' })).toBeTruthy(),
  );
});

test('429 mostra a mensagem do servidor e NENHUM digito (LGPD-RT07)', async () => {
  const mensagem = 'muitas tentativas; tente mais tarde';
  servidor({ '/api/auth/sign-in/email': () => json(429, { error: mensagem }) });

  montar('/entrar');
  await preencherEntrada();

  const alerta = await screen.findByRole('alert');
  expect(alerta.textContent).toBe(mensagem);
  // A trava e progressiva (30 s dobrando ate 15 min) e a resposta nao diz quanto
  // falta. Um numero na tela — de segundos ou de tentativas restantes — viraria
  // um oraculo sobre conta alheia.
  expect(alerta.textContent).not.toMatch(/\d/);
});

test('credencial recusada nao distingue e-mail inexistente de senha errada', async () => {
  servidor({ '/api/auth/sign-in/email': () => json(401, { error: 'invalid credentials' }) });

  montar('/entrar');
  await preencherEntrada();

  // Distinguir transformaria a tela num verificador de contas alheias.
  const alerta = await screen.findByRole('alert');
  expect(alerta.textContent).toBe('E-mail ou senha invalidos.');
});

// ---------------------------------------------------------------------------
// Cadastro do segundo fator
// ---------------------------------------------------------------------------

test('apos o `enable`, a tela manda entrar de novo e NAO chama /api/me', async () => {
  const uri = 'otpauth://totp/Guia%20UBS:operador@exemplo.invalid?secret=ABCDEFGHIJKLMNOP&issuer=Guia+UBS';
  servidor({ '/api/auth/two-factor/enable': () => json(200, { totpURI: uri }) });

  montar('/entrar/cadastrar-2fa');
  await userEvent.type(screen.getByLabelText('Confirme sua senha'), 'senha-ficticia-de-teste-123');
  await userEvent.click(screen.getByRole('button', { name: 'Gerar chave' }));

  // A chave base32 aparece mesmo sem canvas no jsdom: o QR e conveniencia.
  await waitFor(() => expect(screen.getByText('ABCDEFGHIJKLMNOP')).toBeTruthy());
  expect((await screen.findByRole('alert')).textContent).toMatch(/entre de novo/i);

  // `enable` deixa `verified = 0` e REVOGA a sessao. Uma consulta a `/api/me`
  // DEPOIS dele responderia 401 e pareceria defeito para quem acabou de acertar
  // tudo. A sondagem da montagem, anterior ao cadastro, e legitima — o contrato
  // e sobre o que vem depois.
  const cadastro = pedidos.indexOf('/api/auth/two-factor/enable');
  expect(cadastro).toBeGreaterThanOrEqual(0);
  expect(pedidos.slice(cadastro)).not.toContain('/api/me');
});

// ---------------------------------------------------------------------------
// Navegacao por permissao
// ---------------------------------------------------------------------------

test('o painel do admin EXPLICA por que ele nao escreve nem aprova', async () => {
  // O primeiro operador do sistema e um admin, e admin nao tem `content:write`
  // nem `approval:decide`. Sem esta explicacao, a primeira pessoa a abrir a
  // interface ve uma tela quase vazia e conclui que esta quebrada.
  servidor({});
  montar('/', operador('admin', ['content:read', 'release:publish', 'user:manage']));

  expect(await screen.findByRole('heading', { name: 'Administrador' })).toBeTruthy();
  expect(screen.getByText(/segregacao/i)).toBeTruthy();
});

test('a barra e derivada das permissoes, nunca do papel', async () => {
  // Guiado por `ROLE_PERMISSIONS` do SERVIDOR: a matriz tem uma fonte so, e uma
  // permissao renomeada la reprova o typecheck aqui.
  const { ROLE_PERMISSIONS } = await import('@guia-ubs/cms/src/auth/permissions.js');

  // Os tres papeis tem `content:read` — inclusive o revisor clinico, que PRECISA
  // chegar a tela de releases para aprovar sem ter `content:write`.
  for (const permissoes of Object.values(ROLE_PERMISSIONS)) {
    expect(navegacaoPara(permissoes).map((r) => r.caminho)).toEqual([
      '/',
      '/releases',
      '/regras',
      '/conteudo',
    ]);
  }

  // E a derivacao e real, nao coincidencia: sem permissao nenhuma, sobra so o
  // painel — que e o caso de um papel fora de `ADMIN_ROLES`, para o qual
  // `/api/me` devolve `permissions: []`.
  expect(navegacaoPara([]).map((r) => r.caminho)).toEqual(['/']);
});

test('recarregar em /entrar/cadastrar-2fa NAO expulsa quem tem 2FA pendente', async () => {
  /**
   * Regressao. A sondagem de `/api/me` na montagem responde 401 para quem esta
   * com o cookie de 2FA PENDENTE — e tratar isso como "sessao perdida" navegava
   * para `/entrar`, tirando a pessoa da unica tela onde ela ativaria o segundo
   * fator que e obrigatorio ter ativado. O laco nao tinha saida: entrar levava
   * de volta ao cadastro, recarregar levava de volta a entrada.
   *
   * Sabotagem que o confirma: remover a guarda `dispensaSessao` em `App.tsx`
   * deixa este teste vermelho.
   */
  servidor({ '/api/me': () => json(401, { error: 'nao autenticado' }) });

  montar('/entrar/cadastrar-2fa');

  /**
   * A ordem aqui e o teste.
   *
   * Afirmar o cabecalho logo apos montar passa mesmo COM o defeito: a sondagem
   * ainda nao respondeu, e a tela certa esta na frente por um instante. E
   * preciso esperar a sondagem acontecer E o React processar o que ela
   * desencadeou — so entao a pergunta "continuo na tela do cadastro?" significa
   * alguma coisa.
   */
  await waitFor(() => expect(pedidos).toContain('/api/me'));
  await act(async () => {
    await Promise.resolve();
  });

  expect(screen.queryByRole('heading', { name: 'Entrar' })).toBeNull();
  expect(screen.getByRole('heading', { name: 'Cadastrar segundo fator' })).toBeTruthy();
});

test('quem ja cadastrou e nao verificou continua conseguindo ABRIR a entrada', async () => {
  /**
   * Regressao, achada no navegador e nao em teste.
   *
   * Depois do `enable`, o operador tem `two_factor_enabled = 1` e `verified = 0`
   * — entao `/api/me` responde 403 "segundo fator obrigatorio", inclusive na
   * sondagem de montagem da tela de ENTRADA. Redirecionar dali para o cadastro
   * fechava um laco sem saida: cadastrar mandava entrar de novo, e entrar
   * mandava cadastrar de novo. O campo onde se digita o codigo era inalcancavel.
   *
   * Sabotagem que o confirma: trocar a guarda de `dispensaSessao` por uma
   * comparacao com `/entrar/cadastrar-2fa` deixa este teste vermelho.
   */
  servidor({
    '/api/me': () =>
      json(403, { error: 'segundo fator obrigatorio', next: '/api/auth/two-factor/enable' }),
  });

  montar('/entrar');

  await waitFor(() => expect(pedidos).toContain('/api/me'));
  await act(async () => {
    await Promise.resolve();
  });

  expect(screen.getByRole('heading', { name: 'Entrar' })).toBeTruthy();
  expect(screen.queryByRole('heading', { name: 'Cadastrar segundo fator' })).toBeNull();
});

test('a tela de cadastro oferece o caminho de quem JA tem a chave', async () => {
  /**
   * `/api/me` devolve o MESMO 403 para dois estados: "nunca cadastrou" e
   * "cadastrou e ainda nao verificou" — a ativacao so acontece na primeira
   * verificacao bem-sucedida, e ate la `two_factor_enabled` continua falso.
   *
   * Medido contra o servidor real: depois do `enable`, entrar de novo devolve
   * sessao completa, `/api/me` responde 403, e e o `verify-totp` sobre essa
   * sessao que ativa. Ou seja: quem chega aqui pela segunda vez precisa do CAMPO
   * DE CODIGO, e nao de gerar outra chave — gerar invalidaria a que ele acabou
   * de guardar no autenticador.
   *
   * O cliente nao consegue distinguir os dois estados, entao a tela pergunta.
   */
  servidor({});
  montar('/entrar/cadastrar-2fa');

  const atalho = await screen.findByRole('link', { name: /digite o codigo/i });
  expect(atalho.getAttribute('href')).toBe('/entrar/codigo');
});

// ---------------------------------------------------------------------------
// Aceite do termo de uso
// ---------------------------------------------------------------------------

const TERMO = {
  type: 'tos',
  version: '0.1.0',
  contentMd: '# Termo\n\nTexto do termo.',
  hash: 'a'.repeat(64),
  effectiveFrom: '2026-11-01',
  aceito: false,
};
const PENDENTE = { error: 'aceite do termo de uso pendente', next: '/api/consentimento' };

test('a tela do termo mostra a versao e o texto', async () => {
  servidor({ '/api/consentimento': () => json(200, TERMO) });
  montar('/entrar/termo');

  expect(await screen.findByText(/Versao 0\.1\.0/)).toBeTruthy();
  expect(screen.getByText(/Texto do termo\./)).toBeTruthy();
});

test('aceitar envia a versao e o hash LIDOS e vai ao painel', async () => {
  const posts: unknown[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn((url: string, init?: RequestInit) => {
      pedidos.push(url);
      if (url === '/api/consentimento' && init?.method === 'POST') {
        posts.push(JSON.parse(String(init.body)));
        return Promise.resolve(json(200, { aceito: true, version: '0.1.0', hash: 'a'.repeat(64) }));
      }
      if (url === '/api/consentimento') return Promise.resolve(json(200, TERMO));
      if (url === '/api/me') return Promise.resolve(json(200, operador('editor', ['content:read'])));
      return Promise.resolve(json(404, {}));
    }),
  );
  montar('/entrar/termo');

  await userEvent.click(await screen.findByRole('button', { name: 'Li e aceito o termo de uso' }));

  expect(posts).toEqual([{ version: '0.1.0', hash: 'a'.repeat(64) }]);
  await waitFor(() => expect(screen.getByRole('heading', { name: 'Painel' })).toBeTruthy());
});

test('409 troca o documento pelo vigente e avisa', async () => {
  vi.stubGlobal(
    'fetch',
    vi.fn((url: string, init?: RequestInit) => {
      if (url === '/api/consentimento' && init?.method === 'POST') {
        return Promise.resolve(
          json(409, {
            error: 'o termo mudou',
            vigente: { ...TERMO, version: '0.2.0', hash: 'h2', contentMd: 'Texto novo.' },
          }),
        );
      }
      return Promise.resolve(json(200, TERMO));
    }),
  );
  montar('/entrar/termo');

  await userEvent.click(await screen.findByRole('button', { name: 'Li e aceito o termo de uso' }));

  expect(await screen.findByText(/Versao 0\.2\.0/)).toBeTruthy();
  expect(screen.getByText(/O termo foi atualizado enquanto voce lia/)).toBeTruthy();
});

test('404 mostra a mensagem e nao oferece aceite', async () => {
  servidor({ '/api/consentimento': () => json(404, { error: 'nenhum termo de uso publicado' }) });
  montar('/entrar/termo');

  expect(await screen.findByText(/Nenhum termo de uso publicado/)).toBeTruthy();
  expect(screen.queryByRole('button', { name: 'Li e aceito o termo de uso' })).toBeNull();
  expect(screen.getByRole('button', { name: 'Sair' })).toBeTruthy();
});

test('401 no GET navega para /entrar', async () => {
  servidor({ '/api/consentimento': () => json(401, { error: 'nao autenticado' }) });
  montar('/entrar/termo');

  expect(await screen.findByRole('heading', { name: 'Entrar' })).toBeTruthy();
});

test('403 de segundo fator no GET navega para o cadastro', async () => {
  servidor({
    '/api/consentimento': () =>
      json(403, { error: 'segundo fator obrigatorio', next: '/api/auth/two-factor/enable' }),
  });
  montar('/entrar/termo');

  expect(await screen.findByRole('heading', { name: 'Cadastrar segundo fator' })).toBeTruthy();
});

test('403 operador desligado mostra a mensagem, sem aceite', async () => {
  servidor({ '/api/consentimento': () => json(403, { error: 'operador desligado' }) });
  montar('/entrar/termo');

  expect(await screen.findByText('Este operador foi desligado.')).toBeTruthy();
  expect(screen.queryByRole('button', { name: 'Li e aceito o termo de uso' })).toBeNull();
});

test('erro de servidor no POST mantem o botao', async () => {
  vi.stubGlobal(
    'fetch',
    vi.fn((url: string, init?: RequestInit) =>
      Promise.resolve(
        init?.method === 'POST' ? json(500, { error: 'x' }) : json(200, TERMO),
      ),
    ),
  );
  montar('/entrar/termo');

  await userEvent.click(await screen.findByRole('button', { name: 'Li e aceito o termo de uso' }));

  expect(await screen.findByText('Erro no servidor; tente de novo.')).toBeTruthy();
  expect(screen.getByRole('button', { name: 'Li e aceito o termo de uso' })).toBeTruthy();
});

test('Sair chama sign-out e navega para /entrar', async () => {
  servidor({
    '/api/consentimento': () => json(200, TERMO),
    '/api/auth/sign-out': () => json(200, { success: true }),
  });
  montar('/entrar/termo');

  await userEvent.click(await screen.findByRole('button', { name: 'Sair' }));

  expect(await screen.findByRole('heading', { name: 'Entrar' })).toBeTruthy();
  expect(pedidos).toContain('/api/auth/sign-out');
});

test('estadoDaSessao com 403 de consentimento devolve precisa_aceitar', async () => {
  servidor({ '/api/me': () => json(403, PENDENTE) });
  expect(await estadoDaSessao()).toEqual({ estado: 'precisa_aceitar' });
});

test('abrir /entrar/termo com /api/me em 403 de consentimento NAO redireciona', async () => {
  servidor({ '/api/me': () => json(403, PENDENTE), '/api/consentimento': () => json(200, TERMO) });
  montar('/entrar/termo');

  await waitFor(() => expect(pedidos).toContain('/api/me'));
  await act(async () => {
    await Promise.resolve();
  });

  expect(await screen.findByText(/Versao 0\.1\.0/)).toBeTruthy();
});

test('rota protegida com /api/me em 403 de consentimento termina na tela do termo', async () => {
  servidor({ '/api/me': () => json(403, PENDENTE), '/api/consentimento': () => json(200, TERMO) });
  montar('/');

  expect(await screen.findByText(/Versao 0\.1\.0/)).toBeTruthy();
  expect(screen.getByRole('heading', { name: 'Termo de uso' })).toBeTruthy();
});

test('a barra nao aparece em /entrar/termo com operador em cache', async () => {
  servidor({ '/api/consentimento': () => json(200, TERMO) });
  montar('/entrar/termo', operador('editor', ['content:read']));

  await screen.findByText(/Versao 0\.1\.0/);
  expect(screen.queryByRole('navigation')).toBeNull();
});

test('GET 500 mostra o erro, sai de Carregando e o retry refaz a leitura', async () => {
  let n = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(() => Promise.resolve((n += 1) === 1 ? json(500, { error: 'x' }) : json(200, TERMO))),
  );
  montar('/entrar/termo');

  expect(await screen.findByText('Erro no servidor; tente de novo.')).toBeTruthy();
  expect(screen.queryByText('Carregando…')).toBeNull();
  await userEvent.click(screen.getByRole('button', { name: 'Tentar de novo' }));
  expect(await screen.findByText(/Versao 0\.1\.0/)).toBeTruthy();
});

test('Sair com sign-out recusado fica na tela e avisa', async () => {
  servidor({
    '/api/consentimento': () => json(200, TERMO),
    '/api/auth/sign-out': () => json(500, { error: 'x' }),
  });
  montar('/entrar/termo');

  await userEvent.click(await screen.findByRole('button', { name: 'Sair' }));

  expect(await screen.findByText('Nao foi possivel sair; tente de novo.')).toBeTruthy();
  expect(screen.getByRole('heading', { name: 'Termo de uso' })).toBeTruthy();
});

test('termo ja aceito no GET segue direto ao painel, sem o botao', async () => {
  servidor({
    '/api/consentimento': () => json(200, { ...TERMO, aceito: true }),
    '/api/me': () => json(200, operador('editor', ['content:read'])),
  });
  montar('/entrar/termo');

  expect(await screen.findByRole('heading', { name: 'Painel' })).toBeTruthy();
  expect(screen.queryByRole('button', { name: 'Li e aceito o termo de uso' })).toBeNull();
});

test('depois do aceite volta a rota protegida de origem, nao ao painel', async () => {
  servidor({
    '/api/me': [json(403, PENDENTE), json(200, operador('editor', ['content:read']))],
    '/api/consentimento': () => json(200, TERMO),
    '/api/releases': () => json(200, { items: [] }),
  });
  montar('/releases');

  await userEvent.click(await screen.findByRole('button', { name: 'Li e aceito o termo de uso' }));

  expect(await screen.findByRole('heading', { name: 'Releases' })).toBeTruthy();
});
