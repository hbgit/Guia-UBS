/**
 * Ponto de entrada da SPA. Referenciado por `index.html`.
 */
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';

import { App } from './App.js';
import { SessaoProvider } from './sessao.js';
import './estilo.css';

const raiz = document.getElementById('raiz');
// Falhar aqui e melhor que renderizar em lugar nenhum: sem o elemento, o
// `createRoot` lancaria de qualquer jeito, mas com uma mensagem que nao diz que
// o `index.html` e que esta errado.
if (!raiz) throw new Error('elemento #raiz nao encontrado em index.html');

createRoot(raiz).render(
  <StrictMode>
    {/*
      `BrowserRouter` e nao `HashRouter`: o Hono ja faz recuo de historico para
      qualquer GET fora de `/api/*` e `/health` (`cms/src/web.ts`), entao os
      caminhos ficam limpos e compartilhaveis.
    */}
    <BrowserRouter>
      <SessaoProvider>
        <App />
      </SessaoProvider>
    </BrowserRouter>
  </StrictMode>,
);
