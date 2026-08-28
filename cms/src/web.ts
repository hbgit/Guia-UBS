/**
 * Serve a interface (`cms/web/dist`) pelo mesmo processo que atende a API.
 *
 * A decisao e da [stack.md](../../spec/stack.md) §1.2: "Vite + React SPA servida
 * pelo proprio Hono — um container so". Nao ha servidor de estaticos separado,
 * nao ha SSR, e o `edge` (Caddy) nao proxia o CMS.
 *
 * ## A ordem de montagem E a garantia
 *
 * Este middleware entra por ULTIMO em `createApp`. O Hono compoe os handlers na
 * ordem de registro, entao `/health` e `/api/*` ja responderam quando a SPA e
 * consultada — um arquivo chamado `health` dentro de `dist/` nao sombreia nada.
 * `test/web-static.test.ts` afirma isso.
 *
 * Ainda assim ha a guarda explicita de `ehDoServidor()`, e ela nao e redundancia:
 * `app.route('/api', protegido)` registra middlewares `ALL /api/*` que chamam
 * `next()` quando nenhuma rota casa. Sem a guarda, `GET /api/rota-com-typo`
 * chegaria aqui e receberia `index.html` — e todo `fetch` da SPA falharia com
 * "Unexpected token '<'" em vez de um 404 legivel. E o modo de falha que mais
 * desperdica tempo neste desenho.
 *
 * A guarda casa por PREFIXO DE CAMINHO, nunca por "a rota e protegida":
 * `/api/telemetry` e publica e montada ANTES do grupo protegido (segunda excecao
 * declarada a LGPD-RT01).
 */
import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

import { serveStatic } from '@hono/node-server/serve-static';
import type { Env as HonoEnv, Hono, MiddlewareHandler } from 'hono';

/**
 * Resolvido a partir DESTE arquivo, nunca do cwd.
 *
 * `serveStatic({root})` faz `join(root, caminho)`, e a propria tipagem dele avisa
 * que um root relativo e "based on current working directory". Aqui ha dois cwd
 * diferentes: `/app` no container (`CMD node --import tsx cms/src/index.ts`) e
 * `cms/` sob `npm --workspace @guia-ubs/cms run dev`. Um caminho relativo
 * resolveria para lugares distintos e falharia so em um dos dois — dependendo de
 * qual voce testasse primeiro.
 */
export const RAIZ_DA_SPA = join(import.meta.dirname, '..', 'web', 'dist');

export const SEM_BUILD = 'interface nao construida; rode `npm run web:build`';

/** Um ano. A saida do Vite tem hash no nome, entao o conteudo nunca muda sob a mesma URL. */
const IMUTAVEL = 'public, max-age=31536000, immutable';

/** Prefixo dos artefatos com hash que o Vite emite. */
const ASSETS = '/assets/';

/**
 * Caminhos que pertencem ao servidor e que a SPA nunca responde.
 *
 * `/health` e comparacao exata: um arquivo `dist/health` nao deve mudar o
 * healthcheck do compose, mas `/healthy` tambem nao deve ser sequestrado daqui.
 */
function ehDoServidor(caminho: string): boolean {
  return caminho === '/health' || caminho === '/api' || caminho.startsWith('/api/');
}

/**
 * Ha build de interface neste caminho?
 *
 * Existe para o BOOT avisar (`index.ts`), nao para `montarSpa` avisar: o fixture
 * de teste monta 243 vezes sem `dist`, e um `console.error` por montagem
 * afogaria a saida da suite num erro que nao e erro nenhum.
 */
export function temInterface(raiz: string = RAIZ_DA_SPA): boolean {
  return existsSync(join(raiz, 'index.html'));
}

export function montarSpa<E extends HonoEnv>(app: Hono<E>, raiz: string = RAIZ_DA_SPA): void {
  const indice = join(raiz, 'index.html');

  /**
   * Construido sob demanda, e memorizado.
   *
   * `serveStatic` faz `console.error` na construcao quando o root nao existe.
   * Construir aqui de olhos fechados encheria a saida das suites que rodam sem
   * `dist` de um erro que nao e erro nenhum.
   */
  let estatico: MiddlewareHandler<E> | undefined;

  /**
   * `existsSync` a cada requisicao SO enquanto nao ha build.
   *
   * Uma vez encontrado, o resultado e memorizado e o caminho feliz nao paga
   * syscall nenhuma. Enquanto nao ha, a checagem continua barata e permite que
   * `npm run web:build` num segundo terminal passe a funcionar sem reiniciar o
   * servidor — que e exatamente o que alguem faz na primeira vez.
   */
  let construida = existsSync(indice);

  app.use('*', async (c, next) => {
    if (ehDoServidor(c.req.path)) return next();
    // Um POST para um caminho qualquer precisa dar 404, nao renderizar pagina.
    if (c.req.method !== 'GET' && c.req.method !== 'HEAD') return next();

    if (!construida) {
      construida = existsSync(indice);
      // 503 e nao 404: a API esta no ar e a interface nao. Um 404 aqui pareceria
      // erro de digitacao no caminho e mandaria procurar no lugar errado.
      if (!construida) return c.json({ error: SEM_BUILD }, 503);
    }

    const ehAsset = c.req.path.startsWith(ASSETS);

    /**
     * Definido ANTES de servir, de proposito: `c.header()` deposita em
     * `preparedHeaders`, que o `c.body()` de dentro do `serveStatic` funde na
     * resposta. Definir depois (pelo `onFound`) nao alcancaria a Response ja
     * construida.
     *
     * `no-store` na casca nao e zelo: sem ele um navegador com o `index.html` de
     * ontem pede um asset com hash que o build novo apagou. O sintoma e tela
     * branca a cada implantacao, com um 404 no console como unica pista.
     */
    c.header('Cache-Control', ehAsset ? IMUTAVEL : 'no-store');

    estatico ??= serveStatic<E>({ root: raiz });

    let achou = true;
    const resposta = await estatico(c, async () => {
      achou = false;
    });
    if (achou && resposta) return resposta;

    /**
     * Miss. Caminho com hash que nao existe e 404, e nao a casca: devolver HTML
     * sob uma URL de asset guardaria o `index.html` por um ano no cache de quem
     * pediu, com `immutable`.
     */
    if (ehAsset) return c.notFound();

    // Recuo de historico: qualquer outro GET e uma rota do react-router.
    return c.html(await readFile(indice, 'utf8'));
  });
}
