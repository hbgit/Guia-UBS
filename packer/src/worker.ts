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
 * ## Por que release barrada nao volta em laco (P0-2, D11)
 *
 * Portao vermelho devolve a release para `approved` com `blocked_at`. Sem mais
 * nada, a varredura seguinte a reconstruiria — e falharia igual — para sempre.
 * `proximaAprovada` a ignora ate existir uma escrita de CONTEUDO auditada, com
 * operador, a partir do instante do CLAIM — `blocked_at` recebe o `claimed_at`,
 * para que escrita feita durante o build tambem reabra. Os instantes vem do
 * relogio do BANCO
 * (`strftime`): CMS e worker rodam em containers distintos, e comparar relogios
 * de dois processos e comparar dois erros de ajuste.
 *
 * Uso:
 *   tsx src/worker.ts --once      processa a fila e sai (o do roteiro)
 *   tsx src/worker.ts             laco continuo (o do compose)
 */
import { randomUUID } from 'node:crypto';
import { copyFileSync, mkdirSync } from 'node:fs';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { parseArgs } from 'node:util';

import {
  ACOES_QUE_REABREM,
  avaliarAtestado,
  avaliarRegistro,
  PACK_SCHEMA_VERSION,
  type Atestado,
  type EntradaRegistro,
} from '@guia-ubs/contract';
import { createClient, type Client } from '@libsql/client';

import { buildPack, readRuleModel } from './build-pack.js';
import { extrairConteudo, lerAtestadosDoBanco, lerGoldenDoBanco } from './extract.js';
import {
  buildManifest,
  conferirChaveRegistrada,
  publish,
  writeManifest,
  type S3Target,
} from './release.js';
import {
  lerAtestadosDoYaml,
  validateGolden,
  validateReferential,
  type ValidationIssue,
} from './validate.js';

const REPO_ROOT = join(import.meta.dirname, '..', '..');
const OUT_DIR = join(REPO_ROOT, 'packer', 'out');

/** Instante carimbado pelo banco — o mesmo formato de `toISOString()`. */
const AGORA_DO_BANCO = "strftime('%Y-%m-%dT%H:%M:%fZ','now')";

/**
 * `a.action LIKE 'content\_%' ESCAPE '\' OR ...`, montado de `ACOES_QUE_REABREM`.
 * O `_` e curinga no LIKE: sem escapa-lo, `contentX` casaria `content_`.
 */
const ACAO_QUE_REABRE = ACOES_QUE_REABREM.map(
  (prefixo) => `a.action LIKE '${prefixo.replace(/[\\%_]/g, '\\$&')}%' ESCAPE '\\'`,
).join(' OR ');

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

/**
 * Uma release por vez: o claim ja garante que so um job pega cada uma.
 *
 * Release barrada (`blocked_at`) fica de fora ate uma escrita de conteudo com
 * operador a partir do claim que a barrou (D11). `POST /api/releases/:id/reenfileirar`
 * limpa `blocked_at` depois de correcao que nao passa pela trilha (registro
 * publico de atestados, redeploy do worker). Login, 2FA, gestao de operador e
 * transicoes de release nao reabrem — `cms/test/audit-acoes.test.ts` exige que
 * toda acao da trilha esteja classificada. Escrita so por SQL direto, sem
 * trilha, tambem nao reabre: e o limite aceito.
 */
export async function proximaAprovada(client: Client): Promise<Release | null> {
  const r = await client.execute(
    `SELECT pr.id, pr.municipality_id, m.code, pr.pack_version, pr.schema_version
       FROM pack_release pr
       JOIN municipality m ON m.id = pr.municipality_id
      WHERE pr.status = 'approved'
        AND (pr.blocked_at IS NULL OR EXISTS (
              SELECT 1 FROM audit_entry a
               WHERE a.actor_id IS NOT NULL
                 AND a.occurred_at >= pr.blocked_at
                 AND (${ACAO_QUE_REABRE})))
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
  const r = await client.execute({
    // `claimed_at` sai do relogio do banco, o mesmo de `audit_entry.occurred_at`:
    // e ele que vira `blocked_at` se o portao ficar vermelho (D11). `blocked_at`
    // volta a nulo: a release foi repescada, e o proximo bloqueio carimba de novo.
    sql: `UPDATE pack_release
             SET status = 'building', claimed_at = ${AGORA_DO_BANCO}, blocked_at = NULL
           WHERE id = ? AND status = 'approved' RETURNING claimed_at`,
    args: [releaseId],
  });
  if (r.rows.length !== 1) return false;
  await registrarNaTrilha(client, releaseId, 'approved', 'building', {
    claimed_at: String(r.rows[0]!.claimed_at),
  });
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
          VALUES (?, NULL, ?, 'pack_release', ?, ?, ?, ${AGORA_DO_BANCO})`,
    args: [
      randomUUID(),
      `release_${para}`,
      releaseId,
      JSON.stringify({ status: de }),
      JSON.stringify({ status: para, ...extras }),
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

/**
 * Devolve a release barrada para `approved`, com `blocked_at` = instante do claim.
 *
 * O instante do claim, e nao o do bloqueio: a extracao le o conteudo logo depois
 * do claim, e uma escrita auditada que caia durante o build nao entrou nele. Com
 * o carimbo no bloqueio, essa escrita ficaria antes de `blocked_at` e nunca
 * reabriria a release. No `UPDATE` do SQLite o lado direito le a linha ANTIGA,
 * entao `blocked_at = claimed_at` copia o valor antes de `claimed_at` virar nulo.
 * Nao e `mover`: o valor sai da propria linha, nao de um argumento.
 */
async function devolverBloqueada(client: Client, releaseId: string): Promise<void> {
  const r = await client.execute({
    sql: `UPDATE pack_release
             SET status = 'approved', blocked_at = claimed_at, claimed_at = NULL
           WHERE id = ? AND status = 'building' RETURNING blocked_at`,
    args: [releaseId],
  });
  await registrarNaTrilha(client, releaseId, 'building', 'approved', {
    claimed_at: null,
    blocked_at: r.rows[0] ? String(r.rows[0].blocked_at) : null,
  });
}

/**
 * Os atestados do CMS conferidos contra o registro publico do repositorio.
 *
 * O CMS guarda o atestado completo; o repositorio, so a parte publica. Atestado
 * no banco sem par identico no registro e revisor cujo termo nao foi publicado
 * — o caso dele nao conta como revisado. Mensagens citam so o ID: nome e numero
 * de registro nao vao para a trilha nem para o log.
 */
function conferirAtestados(
  doBanco: readonly Atestado[],
  registroBruto: readonly unknown[],
): { registro: EntradaRegistro[]; problemas: ValidationIssue[] } {
  const problema = (message: string): ValidationIssue => ({
    kind: 'golden_registro_invalido',
    message,
  });
  const registro = avaliarRegistro({ atestados: registroBruto });
  if (!registro.ok) {
    return {
      registro: [],
      problemas: registro.problemas.map((p) =>
        problema(`registro de atestados invalido (seed/golden/atestados.yaml): ${p}`),
      ),
    };
  }

  const porId = new Map(registro.entradas.map((e) => [e.id, e]));
  const problemas: ValidationIssue[] = [];
  for (const atestado of doBanco) {
    const formato = avaliarAtestado(atestado);
    if (!formato.ok) {
      problemas.push(problema(`atestado ${atestado.id} do CMS com formato invalido`));
      continue;
    }
    const publico = porId.get(atestado.id);
    if (!publico) {
      problemas.push(
        problema(`atestado ${atestado.id} do CMS nao consta em seed/golden/atestados.yaml`),
      );
      continue;
    }
    const categoria = (x: object) => ('categoria' in x ? x.categoria : undefined);
    for (const [campo, a, b] of [
      ['conselho', atestado.conselho, publico.conselho],
      ['uf', atestado.uf, publico.uf],
      ['categoria', categoria(atestado), categoria(publico)],
      ['termo_sha256', atestado.termo_sha256, publico.termo_sha256],
    ] as const) {
      if (a !== b) {
        problemas.push(
          problema(`atestado ${atestado.id}: ${campo} do CMS diverge de seed/golden/atestados.yaml`),
        );
      }
    }
  }
  return { registro: registro.entradas, problemas };
}

async function chavesRegistradas(client: Client) {
  const r = await client.execute('SELECT key_id, public_key, retired_at FROM signing_key');
  return r.rows.map((l) => ({
    keyId: String(l.key_id),
    publicKey: String(l.public_key),
    retiredAt: l.retired_at === null ? null : String(l.retired_at),
  }));
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
  opcoes: {
    publicar: boolean;
    /** Entradas cruas do registro publico. Ausente => lerAtestadosDoYaml(REPO_ROOT). */
    registro?: readonly unknown[];
  },
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
      sourceCommit: process.env.GIT_COMMIT ?? 'cms',
      dataSource: dados,
    });

    const referencial = validateReferential(built.dbPath);
    const modelo = readRuleModel(built.dbPath);
    const atestados = conferirAtestados(
      await lerAtestadosDoBanco(client),
      opcoes.registro ?? lerAtestadosDoYaml(REPO_ROOT),
    );
    // `assinatura` fixo: o worker so existe para assinar. Nao ha `--dry-run` aqui.
    const golden = validateGolden(await lerGoldenDoBanco(client), modelo, {
      modo: 'assinatura',
      agora: new Date(),
      registro: atestados.registro,
    });
    await registrarGolden(client, release.id, golden);

    const bloqueantes = [...referencial, ...atestados.problemas, ...golden.issues];
    if (bloqueantes.length > 0) {
      await devolverBloqueada(client, release.id);
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
  opcoes: { publicar: boolean; registro?: readonly unknown[] },
): Promise<ResultadoProcessamento[]> {
  const resultados: ResultadoProcessamento[] = [];
  for (;;) {
    const release = await proximaAprovada(client);
    if (!release) break;
    const resultado = await processar(client, release, opcoes);
    resultados.push(resultado);
    // Bloqueada volta para `approved` com `blocked_at`, e `proximaAprovada` ja a
    // ignora (D11); a parada aqui e cinto alem do suspensorio contra um laco
    // dentro da mesma varredura. A mais nova sai na proxima.
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
