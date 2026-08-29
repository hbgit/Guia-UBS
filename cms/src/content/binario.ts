/**
 * Envio e leitura do ARQUIVO de uma entidade de conteudo (hoje, so `asset`).
 *
 * ## Por que corpo cru, e nao multipart
 *
 * O `Content-Type` carrega o tipo e a URL carrega a chave — nao sobra nada para
 * o multipart transportar. O que ele TRARIA e um nome de arquivo escolhido pelo
 * cliente: uma quarta string controlada pelo operador, num caminho que ja tem
 * uma demais (`path`, que por isso deixou de ser digitado).
 *
 * ## Por que `If-Match` e obrigatorio aqui tambem
 *
 * O envio muda a linha e incrementa `version`. Dois editores mandando icones
 * diferentes para o mesmo `ref` e exatamente a escrita perdida que o travamento
 * otimista existe para pegar. Dispensar a pre-condicao numa rota so e o que
 * ensina que o cabecalho e decorativo.
 *
 * ## O que NAO vai para a trilha
 *
 * Os bytes. `audit_entry` e append-only por gatilho, e o que entra ali nao sai
 * nem no expurgo de retencao que a LGPD-RF07 ainda vai exigir. A trilha guarda
 * os dois `sha256` — que respondem "quem trocou quais bytes por quais, quando"
 * em duzentos bytes. `recordAudit` recusa serializar buffer, para isso nao
 * depender de ninguem lembrar.
 */
import { createHash } from 'node:crypto';

import type { Client } from '@libsql/client';
import { getTableColumns } from 'drizzle-orm';
import type { Context } from 'hono';

import { createDb } from '../db/client.js';
import { recordAudit } from '../services/audit.js';
import { atualizarComVersao, condicaoDaChave, type Chave } from '../services/optimistic-lock.js';
import type { EntidadeConteudo } from './registry.js';

/** Assinaturas de arquivo, por MIME. O que faz o cabecalho declarado ser verdade. */
const ASSINATURAS: Readonly<Record<string, (b: Buffer) => boolean>> = {
  /**
   * SVG e XML: pode comecar por `<?xml`, por `<!` (comentario ou DOCTYPE) ou
   * direto por `<svg`.
   *
   * O `<!` entra de proposito, ainda que DOCTYPE seja RECUSADO logo adiante: sem
   * ele a assinatura barrava primeiro, e a resposta dizia "nao parece ser
   * image/svg+xml" — mandando o operador procurar um problema de formato quando
   * o problema era a DTD. Recusar no lugar certo e o que faz a mensagem servir.
   */
  'image/svg+xml': (b) => /^\s*<(\?xml|!|svg)/i.test(b.subarray(0, 64).toString('utf8')),
  'image/png': (b) => b.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex')),
  'image/webp': (b) =>
    b.subarray(0, 4).toString('ascii') === 'RIFF' && b.subarray(8, 12).toString('ascii') === 'WEBP',
  'audio/opus': (b) => b.subarray(0, 4).toString('ascii') === 'OggS',
  'audio/ogg': (b) => b.subarray(0, 4).toString('ascii') === 'OggS',
};

/** Extensao publicada, por MIME. Entra no `path`, que entra na chave do S3. */
const EXTENSOES: Readonly<Record<string, string>> = {
  'image/svg+xml': 'svg',
  'image/png': 'png',
  'image/webp': 'webp',
  'audio/opus': 'opus',
  'audio/ogg': 'ogg',
};

export interface Recusa {
  regra: string;
  motivo: string;
}

/**
 * Valida SVG por RECUSA, nunca por sanitizacao.
 *
 * Um sanitizador e um parser que se passa a manter, e o modo de falha dele e
 * aceitar em silencio o que nao entendeu. Recusar com a regra nomeada devolve o
 * arquivo ao designer — que e o desfecho certo para um catalogo de 47 icones
 * feitos a mao.
 *
 * A regra da referencia externa e a que protege a promessa do produto: um
 * `<image href="https://…">` dentro de um icone assinado e uma chamada de rede
 * num aparelho cuja premissa e nao fazer nenhuma.
 */
export function validarSvg(bytes: Buffer): Recusa | null {
  const texto = bytes.toString('utf8');

  if (!/<svg[\s>]/i.test(texto)) {
    return { regra: 'raiz', motivo: 'o arquivo nao contem um elemento <svg>' };
  }
  if (/<!DOCTYPE|<!ENTITY/i.test(texto)) {
    // Uma checagem, cobertura total de XXE e billion-laughs. Icone legitimo nao
    // tem DTD; nenhum dos 47 do pacote semente tem.
    return { regra: 'dtd', motivo: 'SVG com DOCTYPE ou ENTITY nao e aceito' };
  }
  if (/<script[\s>]|<foreignObject[\s>]/i.test(texto)) {
    return { regra: 'script', motivo: 'SVG com <script> ou <foreignObject> nao e aceito' };
  }
  if (/\son[a-z]+\s*=/i.test(texto) || /javascript:/i.test(texto)) {
    return {
      regra: 'evento',
      motivo: 'SVG com atributo de evento ou URL javascript: nao e aceito',
    };
  }
  if (/<\?xml-stylesheet/i.test(texto)) {
    return { regra: 'stylesheet', motivo: 'SVG com folha de estilo externa nao e aceito' };
  }

  // Referencia externa: so `#fragmento` local passa.
  for (const [, alvo] of texto.matchAll(/(?:xlink:href|href)\s*=\s*["']([^"']*)["']/gi)) {
    if (!alvo!.startsWith('#')) {
      return {
        regra: 'referencia-externa',
        motivo: `SVG referencia "${alvo!.slice(0, 40)}" fora do proprio arquivo`,
      };
    }
  }
  for (const [, alvo] of texto.matchAll(/url\(\s*["']?([^"')]*)["']?\s*\)/gi)) {
    if (!alvo!.startsWith('#')) {
      return {
        regra: 'referencia-externa',
        motivo: `SVG usa url("${alvo!.slice(0, 40)}") fora do proprio arquivo`,
      };
    }
  }
  return null;
}

/** `assets/icon.head.svg` — derivado, nunca digitado. */
export function caminhoPublicado(ref: string, mime: string): string {
  return `assets/${ref}.${EXTENSOES[mime] ?? 'bin'}`;
}

interface Linha {
  kind?: unknown;
  sha256?: unknown;
  bytes?: unknown;
  version?: unknown;
}

/** `version` chega como ETag, nunca no corpo. Mesma leitura do `crud.ts`. */
function versaoEsperada(header: string | undefined): number | null {
  if (!header) return null;
  const limpo = header.replace(/^W\//, '').replace(/^"|"$/g, '');
  const numero = Number(limpo);
  return Number.isInteger(numero) && numero > 0 ? numero : null;
}

/**
 * `PUT <chave>/binario` — recebe os bytes.
 *
 * Chamada por `crudRoutes` quando o registro declara `binario`.
 */
export async function receberBinario(
  c: Context,
  entidade: EntidadeConteudo,
  client: Client,
  salt: string,
  chave: Chave,
): Promise<Response> {
  const spec = entidade.binario!;
  const esperada = versaoEsperada(c.req.header('if-match'));
  if (esperada === null) {
    return c.json({ error: 'informe a versao lida no cabecalho If-Match' }, 428);
  }

  const colunas = getTableColumns(entidade.tabela);
  const db = createDb(client);
  const linhas = (await db
    .select({
      kind: colunas['kind']!,
      sha256: colunas['sha256']!,
      bytes: colunas['bytes']!,
      version: colunas['version']!,
    })
    .from(entidade.tabela)
    .where(condicaoDaChave(entidade.tabela, chave))
    .limit(1)) as Linha[];
  if (linhas.length === 0) return c.json({ error: 'nao encontrado' }, 404);
  const antes = linhas[0]!;

  // O teto e por `kind`, e o `kind` e fato da LINHA — nao da requisicao. O
  // middleware ja protegeu a memoria com o teto global; aqui protege-se o
  // orcamento de tamanho do pack.
  const regra = spec.tipos[String(antes.kind)];
  if (!regra) return c.json({ error: `tipo "${String(antes.kind)}" nao aceita envio` }, 422);

  const mime = (c.req.header('content-type') ?? '').split(';')[0]!.trim().toLowerCase();
  if (!regra.mime.includes(mime)) {
    return c.json(
      {
        error: `Content-Type "${mime}" nao e aceito para ${String(antes.kind)}`,
        aceitos: regra.mime,
      },
      422,
    );
  }

  const corpo = Buffer.from(await c.req.arrayBuffer());
  if (corpo.byteLength === 0) return c.json({ error: 'corpo vazio' }, 422);
  if (corpo.byteLength > regra.teto) {
    return c.json(
      { error: `acima do teto de ${regra.teto} bytes para ${String(antes.kind)}` },
      413,
    );
  }

  // Os magic bytes sao o que torna o cabecalho declarado VERDADEIRO: o tipo vira
  // o `Content-Type` do objeto no S3, que vira o que a borda diz ao aparelho.
  if (!ASSINATURAS[mime]?.(corpo)) {
    return c.json({ error: `o conteudo nao parece ser ${mime}` }, 422);
  }

  if (mime === 'image/svg+xml') {
    const recusa = validarSvg(corpo);
    if (recusa) return c.json({ error: recusa.motivo, regra: recusa.regra }, 422);
  }

  const sha256 = createHash('sha256').update(corpo).digest('hex');
  const ator = c.get('operador') as { id: string };

  // UMA escrita, pela funcao que ja existe: blob, hash e tamanho na mesma versao.
  // Em dois `UPDATE` o gatilho `asset_version_monotonic` abortaria — a guarda
  // funcionando, mas e melhor nao escrever.
  const resultado = await atualizarComVersao({
    client,
    tabela: entidade.tabela,
    chave,
    versaoEsperada: esperada,
    valores: {
      [spec.coluna]: corpo,
      sha256,
      bytes: corpo.byteLength,
      path: caminhoPublicado(String(Object.values(chave)[0]), mime),
    },
    atorId: ator.id,
  });

  if (resultado.estado === 'ausente') return c.json({ error: 'nao encontrado' }, 404);
  if (resultado.estado === 'conflito') {
    return c.json(
      { error: 'a linha mudou desde a leitura', versaoAtual: resultado.versaoAtual },
      409,
    );
  }

  await recordAudit(client, salt, {
    actorId: ator.id,
    action: 'content_binario_upload',
    entityType: 'asset',
    entityId: Object.values(chave).join('/'),
    // Os dois hashes, e nunca os bytes. Ver o cabecalho deste arquivo.
    before: { sha256: antes.sha256, bytes: antes.bytes, version: antes.version },
    after: { sha256, bytes: corpo.byteLength, contentType: mime },
  });

  c.header('ETag', `"${resultado.versao}"`);
  return c.json({ ok: true, versao: resultado.versao, sha256, bytes: corpo.byteLength });
}

/** `GET <chave>/binario` — devolve os bytes, para a previa e para conferencia. */
export async function entregarBinario(
  c: Context,
  entidade: EntidadeConteudo,
  client: Client,
  chave: Chave,
): Promise<Response> {
  const spec = entidade.binario!;
  const colunas = getTableColumns(entidade.tabela);
  const db = createDb(client);
  const linhas = (await db
    .select({
      binario: colunas[spec.coluna]!,
      sha256: colunas['sha256']!,
      path: colunas['path']!,
    })
    .from(entidade.tabela)
    .where(condicaoDaChave(entidade.tabela, chave))
    .limit(1)) as { binario?: unknown; sha256?: unknown; path?: unknown }[];

  if (linhas.length === 0) return c.json({ error: 'nao encontrado' }, 404);
  const linha = linhas[0]!;
  if (!linha.binario) return c.json({ error: 'este item ainda nao tem binario' }, 404);

  const bytes = Buffer.isBuffer(linha.binario)
    ? linha.binario
    : Buffer.from(linha.binario as ArrayBuffer);

  const extensao = String(linha.path).split('.').pop() ?? '';
  const mime =
    Object.entries(EXTENSOES).find(([, e]) => e === extensao)?.[0] ?? 'application/octet-stream';

  c.header('Content-Type', mime);
  // Endereçado por conteudo: um refetch da previa vira 304.
  c.header('ETag', `"${String(linha.sha256)}"`);
  c.header('Cache-Control', 'private, no-cache');
  /*
   * Duas defesas para servir SVG nao confiavel na MESMA origem da interface.
   *
   * `attachment` faz uma navegacao baixar em vez de renderizar — que e o caminho
   * pelo qual um SVG com script viraria XSS no CMS. A previa continua
   * funcionando, porque `<img src>` e subrecurso e ignora o Content-Disposition.
   *
   * A CSP por resposta neutraliza o arquivo mesmo se algum codigo futuro decidir
   * renderiza-lo num frame.
   */
  c.header('Content-Disposition', 'attachment');
  c.header('Content-Security-Policy', "default-src 'none'; sandbox");
  return c.body(new Uint8Array(bytes));
}
