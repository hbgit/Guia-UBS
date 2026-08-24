/**
 * O job que transforma release aprovada em pack publicado.
 *
 * ## Por que e um processo separado, e nao uma rota do CMS
 *
 * Este processo le a chave privada Ed25519. O CMS atende HTTP. Juntar os dois
 * significaria que uma falha de execucao remota no servico web vira conteudo
 * clinico assinado chegando a aparelhos offline — que e exatamente o que a INV-4
 * existe para impedir.
 *
 * O compose sobe este servico SEM `ports:`. A topologia e a garantia: nao ha
 * porta pela qual alcanca-lo.
 *
 * ## O que ele nao faz
 *
 * Nao decide. A release so chega aqui depois de `pending_review -> approved`, que
 * exige aprovacao de um `clinical_reviewer` que nao seja o autor. O job constroi
 * o que ja foi aprovado, roda os portoes, e para se algum ficar vermelho.
 *
 * Uso:
 *   tsx src/worker.ts --once      processa a fila e sai (o do roteiro)
 *   tsx src/worker.ts             laco continuo (o do compose)
 */
import { randomUUID } from 'node:crypto';
import { copyFileSync, mkdirSync } from 'node:fs';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { parseArgs } from 'node:util';

import { PACK_SCHEMA_VERSION } from '@guia-ubs/contract';
import { createClient, type Client } from '@libsql/client';

import { buildPack, readRuleModel } from './build-pack.js';
import { extrairConteudo, lerGoldenDoBanco } from './extract.js';
import {
  buildManifest,
  conferirChaveRegistrada,
  publish,
  writeManifest,
  type S3Target,
} from './release.js';
import { validateGolden, validateReferential } from './validate.js';

const REPO_ROOT = join(import.meta.dirname, '..', '..');
const OUT_DIR = join(REPO_ROOT, 'packer', 'out');

function requireEnv(nome: string): string {
  const valor = process.env[nome];
  if (!valor) throw new Error(`Variavel de ambiente ${nome} nao definida`);
  return valor;
}

function resolveFromRepo(path: string): string {
  return isAbsolute(path) ? path : resolve(REPO_ROOT, path);
}

export interface Release {
  id: string;
  municipalityId: string;
  municipalityCode: string;
  packVersion: number;
  schemaVersion: string;
}

/** Uma release por vez: o claim ja garante que so um job pega cada uma. */
export async function proximaAprovada(client: Client): Promise<Release | null> {
  const r = await client.execute(
    `SELECT pr.id, pr.municipality_id, m.code, pr.pack_version, pr.schema_version
       FROM pack_release pr
       JOIN municipality m ON m.id = pr.municipality_id
      WHERE pr.status = 'approved'
      ORDER BY pr.created_at
      LIMIT 1`,
  );
  const linha = r.rows[0];
  if (!linha) return null;
  return {
    id: String(linha.id),
    municipalityId: String(linha.municipality_id),
    municipalityCode: String(linha.code),
    packVersion: Number(linha.pack_version),
    schemaVersion: String(linha.schema_version),
  };
}

/**
 * Compare-and-set. `false` significa que outro job chegou primeiro.
 *
 * Registra na trilha quando vence: tomar posse E uma transicao de estado, e uma
 * release que aparece em `building` sem nada na trilha nao diz QUANDO o job a
 * pegou nem se pegou mais de uma vez. O teste da trilha exigiu isto.
 */
async function reivindicar(client: Client, releaseId: string): Promise<boolean> {
  const agora = new Date().toISOString();
  const r = await client.execute({
    sql: `UPDATE pack_release SET status = 'building', claimed_at = ?
           WHERE id = ? AND status = 'approved' RETURNING id`,
    args: [agora, releaseId],
  });
  if (r.rows.length !== 1) return false;
  await registrarNaTrilha(client, releaseId, 'approved', 'building', { claimed_at: agora });
  return true;
}

/**
 * `actor_id` NULO: o job nao tem operador. A coluna e nulavel desde o item 17
 * exatamente para este caso — inventar um usuario `system` criaria uma linha em
 * `admin_user` que parece porta dos fundos numa auditoria.
 */
async function registrarNaTrilha(
  client: Client,
  releaseId: string,
  de: string,
  para: string,
  extras: Record<string, string | number | null>,
): Promise<void> {
  await client.execute({
    sql: `INSERT INTO audit_entry (id, actor_id, action, entity_type, entity_id,
                                   before_json, after_json, occurred_at)
          VALUES (?, NULL, ?, 'pack_release', ?, ?, ?, ?)`,
    args: [
      randomUUID(),
      `release_${para}`,
      releaseId,
      JSON.stringify({ status: de }),
      JSON.stringify({ status: para, ...extras }),
      new Date().toISOString(),
    ],
  });
}

async function mover(
  client: Client,
  releaseId: string,
  de: string,
  para: string,
  extras: Record<string, string | number | null> = {},
): Promise<void> {
  const colunas = Object.keys(extras);
  const atribuicoes = ['status = ?', ...colunas.map((c) => `${c} = ?`)].join(', ');
  await client.execute({
    sql: `UPDATE pack_release SET ${atribuicoes} WHERE id = ? AND status = ?`,
    args: [para, ...colunas.map((c) => extras[c] ?? null), releaseId, de],
  });
  await registrarNaTrilha(client, releaseId, de, para, extras);
}

async function registrarGolden(
  client: Client,
  releaseId: string,
  relatorio: { passed: number; total: number; issues: { message: string }[] },
): Promise<void> {
  await client.execute({
    sql: `INSERT INTO golden_run (id, pack_release_id, passed, total, failures_json, ran_at)
          VALUES (?, ?, ?, ?, ?, ?)`,
    args: [
      randomUUID(),
      releaseId,
      relatorio.passed,
      relatorio.total,
      relatorio.issues.length === 0 ? null : JSON.stringify(relatorio.issues.map((i) => i.message)),
      new Date().toISOString(),
    ],
  });
}

async function chavesRegistradas(client: Client) {
  const r = await client.execute('SELECT key_id, public_key, retired_at FROM signing_key');
  return r.rows.map((l) => ({
    keyId: String(l.key_id),
    publicKey: String(l.public_key),
    retiredAt: l.retired_at === null ? null : String(l.retired_at),
  }));
}

/**
 * Desfecho padrao = o de MENOR severidade.
 *
 * Mesma derivacao que o CMS usa na simulacao, e pelo mesmo motivo: "nenhuma regra
 * casou" significa o caso menos grave, e nao ha configuracao para inventar. O CLI
 * de `seed/` ainda fixa `ROUTINE_UBS` — divergencia registrada como lacuna.
 */
async function desfechoPadrao(client: Client): Promise<string> {
  const r = await client.execute(
    'SELECT id FROM routing_outcome ORDER BY severity_level ASC LIMIT 1',
  );
  const linha = r.rows[0];
  if (!linha) throw new Error('nao ha nenhum desfecho cadastrado');
  return String(linha.id);
}

export interface ResultadoProcessamento {
  releaseId: string;
  estado: 'publicado' | 'bloqueado' | 'nao_reivindicada';
  problemas?: string[];
}

/**
 * Constroi, valida, assina e publica UMA release.
 *
 * Falha de portao devolve a release para `approved`, nao para um estado de erro:
 * o problema esta no conteudo, e depois de corrigido a mesma release deve poder
 * ser construida de novo. Um estado `failed` exigiria um caminho de volta que
 * ninguem lembraria de usar.
 */
export async function processar(
  client: Client,
  release: Release,
  opcoes: { publicar: boolean },
): Promise<ResultadoProcessamento> {
  if (!(await reivindicar(client, release.id))) {
    return { releaseId: release.id, estado: 'nao_reivindicada' };
  }

  const keyId = process.env.PACK_SIGNING_KEY_ID ?? 'k1';
  const keyPath = resolveFromRepo(requireEnv('PACK_SIGNING_KEY_PATH'));

  try {
    // A guarda de chave vem ANTES do build: descobrir no fim que a chave nao esta
    // registrada desperdicaria o build inteiro, e o erro apareceria depois dos
    // portoes verdes, onde ninguem o procura.
    conferirChaveRegistrada(keyId, keyPath, await chavesRegistradas(client));

    const dados = await extrairConteudo({ client, municipalityId: release.municipalityId });
    const built = buildPack({
      repoRoot: REPO_ROOT,
      outDir: OUT_DIR,
      packVersion: release.packVersion,
      schemaVersion: release.schemaVersion || PACK_SCHEMA_VERSION,
      municipality: release.municipalityCode,
      defaultOutcomeId: await desfechoPadrao(client),
      sourceCommit: process.env.GIT_COMMIT ?? 'cms',
      dataSource: dados,
    });

    const referencial = validateReferential(built.dbPath);
    const modelo = readRuleModel(built.dbPath);
    const golden = validateGolden(await lerGoldenDoBanco(client), modelo);
    await registrarGolden(client, release.id, golden);

    const bloqueantes = [...referencial, ...golden.issues];
    if (bloqueantes.length > 0) {
      await mover(client, release.id, 'building', 'approved', { claimed_at: null });
      return {
        releaseId: release.id,
        estado: 'bloqueado',
        problemas: bloqueantes.map((i) => i.message),
      };
    }

    const { manifest, packUrl } = buildManifest({
      schemaVersion: release.schemaVersion || PACK_SCHEMA_VERSION,
      packVersion: release.packVersion,
      municipality: release.municipalityCode,
      packPath: built.dbPath,
      assets: built.assets,
      minAppBuild: Number(process.env.MIN_APP_BUILD ?? 1),
      keyId,
      privateKeyPath: keyPath,
    });
    const manifestPath = writeManifest(OUT_DIR, manifest);

    await mover(client, release.id, 'building', 'built', {
      pack_sha256: manifest.pack.sha256,
      manifest_json: JSON.stringify(manifest),
      signed_at: new Date().toISOString(),
    });

    if (!opcoes.publicar) return { releaseId: release.id, estado: 'publicado' };

    const staged = join(OUT_DIR, packUrl);
    mkdirSync(dirname(staged), { recursive: true });
    copyFileSync(built.dbPath, staged);

    const target: S3Target = {
      endpoint: process.env.S3_ENDPOINT ?? 'http://127.0.0.1:9000',
      bucket: process.env.S3_BUCKET ?? 'content-packs',
      accessKey: requireEnv('MINIO_ROOT_USER'),
      secretKey: requireEnv('MINIO_ROOT_PASSWORD'),
    };
    await publish(
      target,
      release.municipalityCode,
      [
        { key: packUrl, path: staged },
        ...built.assets.map((a) => ({ key: a.path, path: join(REPO_ROOT, 'seed', a.path) })),
      ],
      manifestPath,
    );

    await mover(client, release.id, 'built', 'published', {
      published_at: new Date().toISOString(),
    });
    return { releaseId: release.id, estado: 'publicado' };
  } catch (erro) {
    // Devolve a posse antes de propagar: uma release presa em `building` porque o
    // job estourou so seria destravavel por rota de admin.
    await mover(client, release.id, 'building', 'approved', { claimed_at: null }).catch(() => {});
    throw erro;
  }
}

export async function rodarUmaVez(
  client: Client,
  opcoes: { publicar: boolean },
): Promise<ResultadoProcessamento[]> {
  const resultados: ResultadoProcessamento[] = [];
  for (;;) {
    const release = await proximaAprovada(client);
    if (!release) break;
    const resultado = await processar(client, release, opcoes);
    resultados.push(resultado);
    // Bloqueada volta para `approved` e seria repescada eternamente.
    if (resultado.estado !== 'publicado') break;
  }
  return resultados;
}

// --- CLI --------------------------------------------------------------------

if (import.meta.filename === process.argv[1]) {
  const { values } = parseArgs({
    options: {
      once: { type: 'boolean', default: false },
      'no-publish': { type: 'boolean', default: false },
      interval: { type: 'string', default: '30' },
    },
  });

  const client = createClient({
    url: process.env.CMS_DATABASE_URL ?? 'http://127.0.0.1:8080',
    authToken: process.env.CMS_DATABASE_AUTH_TOKEN,
  });

  const executar = async () => {
    const resultados = await rodarUmaVez(client, { publicar: !values['no-publish'] });
    for (const r of resultados) {
      if (r.estado === 'bloqueado') {
        console.error(`  BLOQUEADO ${r.releaseId} — nada foi assinado`);
        for (const p of r.problemas ?? []) console.error(`            ${p}`);
      } else if (r.estado === 'publicado') {
        console.log(`  ok        ${r.releaseId}`);
      }
    }
    if (resultados.length === 0) console.log('  fila vazia');
  };

  if (values.once) {
    await executar();
    client.close();
  } else {
    const intervalo = Number(values.interval) * 1000;
    console.log(`[packer] job ativo, ${values.interval}s entre varreduras`);
    for (;;) {
      await executar().catch((e: unknown) => console.error('[packer]', (e as Error).message));
      await new Promise((ok) => setTimeout(ok, intervalo));
    }
  }
}
