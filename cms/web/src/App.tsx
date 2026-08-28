/**
 * Roteador e casca.
 *
 * O mapeamento tela -> componente mora AQUI, e a lista de telas mora em
 * `rotas.ts`, que e dado sem DOM. A separacao nao e enfeite: `rotas.ts` e
 * importado por um teste `node:test` do workspace do servidor, que roda sem lib
 * de DOM.
 */
import { useEffect, useRef, type ReactNode } from 'react';
import { Link, Navigate, Route, Routes, useLocation, useNavigate } from 'react-router-dom';

import { aoExigirSegundoFator, aoPerderSessao } from './api/api.js';
import { dispensaSessao, navegacaoPara } from './rotas.js';
import { useSessao } from './sessao.js';
import { TelaDeCadastroDe2fa, TelaDeCodigo, TelaDeEntrada } from './telas/entrada.js';
import { Painel } from './telas/painel.js';
import {
  FormularioDeConteudo,
  IndiceDeConteudo,
  ListaDeEntidade,
} from './telas/conteudo.js';
import { EditorDeRegra, ListaDeRegras } from './telas/regras.js';
import { ListaDeReleases, NovaRelease, TelaDaRelease } from './telas/releases.js';

/**
 * Instala os avisos globais de `api.ts`.
 *
 * 401 e o 403 de segundo fator podem sair de QUALQUER chamada; tratar em cada
 * tela garante que uma vai esquecer, e o sintoma e uma tela em branco depois de
 * a sessao expirar.
 */
function useAvisosDeSessao() {
  const navegar = useNavigate();
  const local = useLocation();
  const { esquecer } = useSessao();

  // Numa `ref` para o efeito nao reinstalar os avisos a cada navegacao: eles sao
  // estado de modulo em `api.ts`, e reinstalar a cada rota e desperdicio.
  const caminho = useRef(local.pathname);
  caminho.current = local.pathname;

  useEffect(() => {
    aoPerderSessao(() => {
      esquecer();
      // De DENTRO do fluxo de entrada, um 401 nao e sessao perdida — em
      // `/entrar/cadastrar-2fa` ele e o cookie de 2FA pendente, e redirecionar
      // expulsaria a pessoa da unica tela que resolve o problema dela.
      if (!dispensaSessao(caminho.current)) navegar('/entrar');
    });
    aoExigirSegundoFator(() => {
      // Mesma guarda, e pelo mesmo motivo. Quem ja cadastrou o segundo fator e
      // ainda nao o verificou recebe 403 em `/api/me` — inclusive na sondagem de
      // montagem da tela de ENTRADA. Redirecionar dali para o cadastro fecha um
      // laco: cadastrar manda entrar de novo, e entrar manda cadastrar de novo.
      // O operador nunca alcanca o campo onde digitaria o codigo.
      //
      // Dentro do fluxo de entrada quem decide o destino e `useDestino`, a
      // partir de uma acao explicita da pessoa — nao uma sondagem de fundo.
      if (!dispensaSessao(caminho.current)) navegar('/entrar/cadastrar-2fa');
    });
  }, [navegar, esquecer]);
}

function Barra() {
  const { operador } = useSessao();
  const local = useLocation();
  if (!operador) return null;

  return (
    <header className="barra">
      <nav>
        {navegacaoPara(operador.permissions).map((r) => (
          <Link key={r.caminho} to={r.caminho} aria-current={local.pathname === r.caminho}>
            {r.rotulo}
          </Link>
        ))}
      </nav>
      <span className="quem">
        {operador.name} · {operador.role}
      </span>
    </header>
  );
}

/** Sem sessao carregada, manda entrar. O servidor decide de novo em cada chamada. */
function Protegida({ children }: { children: ReactNode }) {
  const { operador, carregando } = useSessao();
  if (carregando) return <p>Carregando…</p>;
  if (!operador) return <Navigate to="/entrar" replace />;
  return <>{children}</>;
}

export function App() {
  useAvisosDeSessao();

  return (
    <>
      <Barra />
      <Routes>
        <Route path="/entrar" element={<TelaDeEntrada />} />
        <Route path="/entrar/codigo" element={<TelaDeCodigo />} />
        <Route path="/entrar/cadastrar-2fa" element={<TelaDeCadastroDe2fa />} />
        <Route
          path="/"
          element={
            <Protegida>
              <Painel />
            </Protegida>
          }
        />
        <Route
          path="/releases"
          element={
            <Protegida>
              <ListaDeReleases />
            </Protegida>
          }
        />
        <Route
          path="/releases/nova"
          element={
            <Protegida>
              <NovaRelease />
            </Protegida>
          }
        />
        <Route
          path="/releases/:id"
          element={
            <Protegida>
              <TelaDaRelease />
            </Protegida>
          }
        />
        <Route path="/regras" element={<Protegida><ListaDeRegras /></Protegida>} />
        <Route path="/regras/nova" element={<Protegida><EditorDeRegra /></Protegida>} />
        <Route path="/regras/:id" element={<Protegida><EditorDeRegra /></Protegida>} />
        <Route path="/conteudo" element={<Protegida><IndiceDeConteudo /></Protegida>} />
        <Route path="/conteudo/:entidade" element={<Protegida><ListaDeEntidade /></Protegida>} />
        <Route path="/conteudo/:entidade/nova" element={<Protegida><FormularioDeConteudo /></Protegida>} />
        <Route path="/conteudo/:entidade/editar" element={<Protegida><FormularioDeConteudo /></Protegida>} />
        {/*
          O servidor ja devolve a casca para qualquer GET que nao seja `/api/*`
          nem `/health` (recuo de historico). Sem esta linha, um caminho digitado
          errado renderizaria nada — pagina em branco, sem erro no console.
        */}
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </>
  );
}
