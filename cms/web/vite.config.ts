/**
 * Build e desenvolvimento da interface de operacao.
 *
 * ## Os dois modos, e por que o proxy nao forja cabecalho
 *
 * O Better Auth RECUSA POST autenticado cuja origem nao esteja em
 * `trustedOrigins` — e `trustedOrigins` nao esta configurado, entao a unica
 * origem confiavel e o `BETTER_AUTH_URL`. Ha teste afirmando isso
 * (`cms/test/auth-flow.test.ts`), o que faz dela uma garantia, nao um acaso.
 *
 * **Modo 1 (HMR):** a origem que o NAVEGADOR usa e o Vite, entao e ela que
 * precisa ser confiavel. Suba o CMS com `BETTER_AUTH_URL=http://localhost:5173`
 * e abra `localhost:5173`. O proxy abaixo repassa `/api` e `/health` para o
 * :8787 com `changeOrigin: false`, entao nenhum cabecalho e reescrito: o
 * navegador manda `Origin: http://localhost:5173`, que e a origem confiavel, e a
 * protecao contra CSRF continua real em desenvolvimento.
 *
 * Reescrever `Origin` aqui foi considerado e REJEITADO: forjaria justamente a
 * protecao que tem teste, e faria qualquer pagina de terceiro poder POSTar para
 * `localhost:5173` e ter o proxy lavando a origem para ela.
 *
 * **Modo 2 (prova real):** `npm run web:build && npm run cms:dev` com
 * `BETTER_AUTH_URL=http://127.0.0.1:8787`, abrindo o :8787 direto. E o unico
 * modo que exercita `montarSpa` — o Modo 1 nunca passa por ele.
 *
 * ⚠️ `localhost` e `127.0.0.1` sao ORIGENS DIFERENTES. Abrir o Modo 2 em
 * `localhost:8787` com `BETTER_AUTH_URL` em `127.0.0.1` da 403 em todo POST, com
 * uma mensagem que deliberadamente nao diz por que.
 */
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

const API = 'http://127.0.0.1:8787';

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    // Sem source map: a saida vai para dentro da imagem de producao, e o
    // Dockerfile ja declara que nao quer mapa no meio na hora de investigar.
    sourcemap: false,
  },
  server: {
    host: '127.0.0.1',
    port: 5173,
    /**
     * Nao e cosmetico. Com a porta ocupada, o Vite mudaria para 5174 em silencio
     * e TODO POST passaria a dar 403, porque a origem deixaria de bater com o
     * `BETTER_AUTH_URL`. `strictPort` troca um 403 inexplicavel por "porta em
     * uso".
     */
    strictPort: true,
    proxy: {
      '/api': { target: API, changeOrigin: false },
      '/health': { target: API, changeOrigin: false },
    },
  },
  test: {
    environment: 'jsdom',
    include: ['test/**/*.test.{ts,tsx}'],
    // Sem `globals`: os testes importam `test`/`expect` de `vitest`
    // explicitamente, e `vitest/globals` nao precisa entrar em `types`.
    restoreMocks: true,
  },
});
