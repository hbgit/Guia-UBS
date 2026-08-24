/**
 * Gera o CRUD de uma entidade do registro.
 *
 * Tres coisas precisam acontecer em TODA escrita de conteudo, e e por isso que
 * existe fabrica em vez de dezessete arquivos parecidos:
 *
 *   1. conferir a versao que o cliente leu (409 se alguem escreveu antes);
 *   2. gravar incrementando `version` e carimbando o autor;
 *   3. registrar na trilha append-only.
 *
 * Escrito uma vez por entidade, o defeito tipico e a ultima esquecer o passo 3 —
 * e ninguem nota ate precisar da trilha, que e justamente quando nao da mais para
 * reconstruir. Aqui os tres sao estruturais.
 */
import type { Client } from '@libsql/client';
import { eq, getTableName, sql, type SQL } from 'drizzle-orm';
import { createInsertSchema } from 'drizzle-zod';
import { Hono } from 'hono';
import { z } from 'zod';

import type { AuthVariables } from '../auth/middleware.js';
import { requirePermission } from '../auth/middleware.js';
import { createDb } from '../db/client.js';
import { MENSAGENS, STATUS, classificarViolacao } from '../db/errors.js';
import { recordAudit } from '../services/audit.js';
import {
  atualizarComVersao,
  coluna,
  condicaoDaChave,
  versaoAtual,
  type Chave,
} from '../services/optimistic-lock.js';
import { AUTHORING_FIELDS, type EntidadeConteudo } from './registry.js';

/** `/:municipalityId/:id` a partir da chave declarada no registro. */
function caminhoDaChave(entidade: EntidadeConteudo): string {
  return entidade.chave.map((c) => `/:${c}`).join('');
}

function chaveDaRequisicao(entidade: EntidadeConteudo, params: Record<string, string>): Chave {
  const chave: Record<string, string> = {};
  for (const propriedade of entidade.chave) chave[propriedade] = params[propriedade]!;
  return chave;
}

/**
 * Zod de entrada derivado do PROPRIO schema Drizzle, menos as colunas de autoria.
 *
 * Derivar em vez de escrever a mao e o que impede a validacao de envelhecer: uma
 * coluna nova no schema entra aqui sozinha, e uma coluna removida some — sem
 * ninguem lembrar de atualizar dois lugares.
 */
function esquemaDeEntrada(entidade: EntidadeConteudo) {
  const completo = createInsertSchema(entidade.tabela) as unknown as z.ZodObject<
    Record<string, z.ZodTypeAny>
  >;
  const semAutoria: Record<string, true> = {};
  for (const campo of AUTHORING_FIELDS) semAutoria[campo] = true;
  return completo.omit(semAutoria as never);
}

/** `version` chega como ETag, nunca no corpo. */
function versaoEsperada(header: string | undefined): number | null {
  if (!header) return null;
  const limpo = header.replace(/^W\//, '').replace(/^"|"$/g, '');
  const numero = Number(limpo);
  return Number.isInteger(numero) && numero > 0 ? numero : null;
}

export function crudRoutes(entidade: EntidadeConteudo, client: Client, salt: string) {
  const app = new Hono<{ Variables: AuthVariables }>();
  const entrada = esquemaDeEntrada(entidade);
  const parcial = entrada.partial();
  const caminho = caminhoDaChave(entidade);
  const tipoEntidade = getTableName(entidade.tabela);

  const filtroDeEscopo = (municipalityId?: string): SQL | undefined =>
    entidade.escopo === 'municipal' && municipalityId
      ? eq(coluna(entidade.tabela, 'municipalityId'), municipalityId)
      : undefined;

  // --- leitura ---------------------------------------------------------------
  app.get('/', requirePermission('content:read'), async (c) => {
    const db = createDb(client);
    // Entidade municipal exige o municipio: uma listagem que devolve o conteudo
    // de todos os municipios de uma vez e uma listagem que ninguem consegue ler.
    const municipio = c.req.query('municipalityId');
    if (entidade.escopo === 'municipal' && !municipio) {
      return c.json({ error: 'informe municipalityId' }, 400);
    }
    const consulta = db.select().from(entidade.tabela);
    const filtro = filtroDeEscopo(municipio);
    const linhas = await (filtro ? consulta.where(filtro) : consulta);
    return c.json({ items: linhas });
  });

  app.get(caminho, requirePermission('content:read'), async (c) => {
    const db = createDb(client);
    const chave = chaveDaRequisicao(entidade, c.req.param());
    const linhas = await db
      .select()
      .from(entidade.tabela)
      .where(condicaoDaChave(entidade.tabela, chave))
      .limit(1);
    if (linhas.length === 0) return c.json({ error: 'nao encontrado' }, 404);

    // O ETag e a versao: e o que o PATCH devolve no `If-Match`.
    const linha = linhas[0] as Record<string, unknown>;
    c.header('ETag', `"${String(linha.version)}"`);
    return c.json(linha);
  });

  // --- criacao ---------------------------------------------------------------
  app.post('/', requirePermission('content:write'), async (c) => {
    const corpo = entrada.safeParse(await c.req.json().catch(() => null));
    if (!corpo.success) {
      return c.json({ error: 'dados invalidos', detalhes: corpo.error.issues }, 400);
    }

    const ator = c.get('operador');
    const db = createDb(client);
    const valores = {
      ...corpo.data,
      version: 1,
      updatedBy: ator.id,
      updatedAt: new Date().toISOString(),
    };

    try {
      await db.insert(entidade.tabela).values(valores as never);
    } catch (erro) {
      return respostaDeIntegridade(c, erro);
    }

    const chave = chaveDaRequisicao(entidade, corpo.data as Record<string, string>);
    await recordAudit(client, salt, {
      actorId: ator.id,
      action: 'content_create',
      entityType: tipoEntidade,
      entityId: Object.values(chave).join('/'),
      after: corpo.data,
    });
    c.header('ETag', '"1"');
    return c.json({ ...corpo.data, version: 1 }, 201);
  });

  // --- atualizacao -----------------------------------------------------------
  app.patch(caminho, requirePermission('content:write'), async (c) => {
    const esperada = versaoEsperada(c.req.header('if-match'));
    if (esperada === null) {
      // 428 e o codigo exato para "esta requisicao exige uma pre-condicao"
      // (RFC 6585). Devolver 400 diria "voce errou o corpo", que manda o cliente
      // procurar no lugar errado.
      return c.json({ error: 'informe a versao lida no cabecalho If-Match' }, 428);
    }

    const corpo = parcial.safeParse(await c.req.json().catch(() => null));
    if (!corpo.success) {
      return c.json({ error: 'dados invalidos', detalhes: corpo.error.issues }, 400);
    }

    const db = createDb(client);
    const chave = chaveDaRequisicao(entidade, c.req.param());
    const antes = await db
      .select()
      .from(entidade.tabela)
      .where(condicaoDaChave(entidade.tabela, chave))
      .limit(1);

    const ator = c.get('operador');
    let resultado;
    try {
      resultado = await atualizarComVersao({
        client,
        tabela: entidade.tabela,
        chave,
        versaoEsperada: esperada,
        valores: corpo.data as Record<string, unknown>,
        atorId: ator.id,
      });
    } catch (erro) {
      return respostaDeIntegridade(c, erro);
    }

    if (resultado.estado === 'ausente') return c.json({ error: 'nao encontrado' }, 404);
    if (resultado.estado === 'conflito') {
      // O 409 carrega a versao atual: um conflito que nao diz contra o que se
      // perdeu obriga a pessoa a recarregar a tela para descobrir.
      return c.json(
        { error: 'a linha mudou desde a leitura', versaoAtual: resultado.versaoAtual },
        409,
      );
    }

    await recordAudit(client, salt, {
      actorId: ator.id,
      action: 'content_update',
      entityType: tipoEntidade,
      entityId: Object.values(chave).join('/'),
      before: antes[0],
      after: corpo.data,
    });
    c.header('ETag', `"${resultado.versao}"`);
    return c.json({ ok: true, versao: resultado.versao });
  });

  // --- remocao ---------------------------------------------------------------
  if (entidade.apagavel) {
    app.delete(caminho, requirePermission('content:write'), async (c) => {
      const db = createDb(client);
      const chave = chaveDaRequisicao(entidade, c.req.param());
      const antes = await db
        .select()
        .from(entidade.tabela)
        .where(condicaoDaChave(entidade.tabela, chave))
        .limit(1);
      if (antes.length === 0) return c.json({ error: 'nao encontrado' }, 404);

      try {
        await db.delete(entidade.tabela).where(condicaoDaChave(entidade.tabela, chave));
      } catch (erro) {
        return respostaDeIntegridade(c, erro);
      }

      await recordAudit(client, salt, {
        actorId: c.get('operador').id,
        action: 'content_delete',
        entityType: tipoEntidade,
        entityId: Object.values(chave).join('/'),
        before: antes[0],
      });
      return c.body(null, 204);
    });
  }

  // --- traducao, aninhada ----------------------------------------------------
  if (entidade.traducao) {
    const traducao = entidade.traducao;
    const entradaTraducao = createInsertSchema(traducao.tabela) as unknown as z.ZodObject<
      Record<string, z.ZodTypeAny>
    >;

    app.put(`${caminho}/traducoes/:lang`, requirePermission('content:write'), async (c) => {
      const params = c.req.param() as Record<string, string>;
      const corpo = await c.req.json().catch(() => null);
      if (corpo === null || typeof corpo !== 'object') {
        return c.json({ error: 'dados invalidos' }, 400);
      }

      // A chave da traducao e a da entidade, renomeada coluna a coluna, mais o
      // idioma. Vem do registro para nao existir uma segunda descricao dessa
      // correspondencia, que divergiria.
      const chaveTraducao: Record<string, string> = { lang: params.lang! };
      traducao.chaveEstrangeira.forEach((destino, i) => {
        chaveTraducao[destino] = params[entidade.chave[i]!]!;
      });

      const validado = entradaTraducao
        .omit({ version: true, updatedBy: true, updatedAt: true } as never)
        .safeParse({ ...(corpo as object), ...chaveTraducao });
      if (!validado.success) {
        return c.json({ error: 'dados invalidos', detalhes: validado.error.issues }, 400);
      }

      const ator = c.get('operador');
      const db = createDb(client);
      const agora = new Date().toISOString();
      const alvo = Object.keys(chaveTraducao).map((k) => coluna(traducao.tabela, k));

      try {
        await db
          .insert(traducao.tabela)
          .values({ ...validado.data, version: 1, updatedBy: ator.id, updatedAt: agora } as never)
          .onConflictDoUpdate({
            target: alvo,
            set: {
              ...validado.data,
              // Traducao tambem e versionada, e o gatilho do item 16 exige que o
              // incremento seja de exatamente 1 — inclusive no ramo de UPDATE
              // de um upsert.
              version: sql`${coluna(traducao.tabela, 'version')} + 1`,
              updatedBy: ator.id,
              updatedAt: agora,
            } as never,
          });
      } catch (erro) {
        return respostaDeIntegridade(c, erro);
      }

      await recordAudit(client, salt, {
        actorId: ator.id,
        action: 'content_translate',
        entityType: getTableName(traducao.tabela),
        entityId: Object.values(chaveTraducao).join('/'),
        after: validado.data,
      });
      return c.json({ ok: true });
    });
  }

  return app;
}

/**
 * Traduz violacao de integridade do banco em resposta legivel.
 *
 * A FK que recusa apagar um token usado por regra e a protecao clinica
 * funcionando; devolver 500 faria parecer defeito do servidor e ensinaria o
 * editor a insistir. A classificacao vem de `db/errors.ts` — ver la por que ler
 * `error.message` sozinho nao funciona.
 */
function respostaDeIntegridade(
  c: { json: (corpo: unknown, status: 409 | 422) => Response },
  erro: unknown,
): Response {
  const classe = classificarViolacao(erro);
  if (classe === null) throw erro;
  return c.json({ error: MENSAGENS[classe] }, STATUS[classe]);
}
