/**
 * Nucleo da CLI do packer (o ponto de entrada e index.ts).
 *
 *   packer build    [--dry-run]   constroi o pack e roda todos os portoes
 *   packer publish                constroi, assina e publica no storage
 *
 * A assinatura so acontece depois de referencial e golden verdes. Nao ha flag
 * para pular esses portoes: e o que impede orientacao clinica errada de chegar
 * a um dispositivo offline (PRD risco R5).
 *
 * Caso golden sem revisao clinica bloqueia `build` e `publish`; so `--dry-run`,
 * que nao assina, o deixa passar com aviso (issue #2). O modo sai do comando,
 * nunca de uma flag propria: "avisar em vez de bloquear" so existe onde nada
 * sera assinado.
 */
import { copyFileSync, mkdirSync } from 'node:fs';
import { dirname, isAbsolute, join, resolve } from 'node:path';

import { avaliarRegistro, PACK_SCHEMA_VERSION } from '@guia-ubs/contract';

import { buildPack, readRuleModel } from './build-pack.js';
import { buildManifest, publish, writeManifest, type S3Target } from './release.js';
import {
  lerAtestadosDoYaml,
  lerGoldenDoYaml,
  type GoldenCase,
  type ModoRevisao,
  validateGolden,
  validateReferential,
  type ValidationIssue,
} from './validate.js';

export type EstadoCli = 'bloqueado' | 'verificado' | 'assinado' | 'publicado';

export interface AmbienteCli {
  repoRoot: string;
  outDir: string;
  /** Ausente => lerGoldenDoYaml(repoRoot). */
  casos?: readonly GoldenCase[];
  /** Entradas cruas do registro publico. Ausente => lerAtestadosDoYaml(repoRoot). */
  atestados?: readonly unknown[];
  /** Ausente => relogio do processo; so decide se `reviewed_at` e data futura. */
  agora?: Date;
}

interface Args {
  command: string;
  dryRun: boolean;
  packVersion: number;
  municipality: string;
  minAppBuild: number;
}

function parseArgs(argv: string[]): Args {
  const flag = (name: string): string | undefined => {
    const index = argv.indexOf(`--${name}`);
    return index >= 0 ? argv[index + 1] : undefined;
  };
  return {
    command: argv[0] ?? 'build',
    dryRun: argv.includes('--dry-run'),
    packVersion: Number(flag('pack-version') ?? process.env.PACK_VERSION ?? 1),
    municipality: flag('municipality') ?? process.env.MUNICIPALITY ?? '0000000',
    minAppBuild: Number(flag('min-app-build') ?? 1),
  };
}

/**
 * O modo de revisao e funcao de "este comando vai assinar?", e de nada mais.
 * `--dry-run` nao assina, em `build` nem em `publish`.
 */
export function modoDoComando(args: { dryRun: boolean }): ModoRevisao {
  return args.dryRun ? 'verificacao' : 'assinatura';
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Variavel de ambiente ${name} nao definida`);
  return value;
}

/**
 * Caminhos relativos sao resolvidos contra a raiz do repositorio, nao contra o
 * cwd: rodar via `npm --workspace` muda o cwd e quebraria o caminho da chave.
 */
function resolveFromRepo(repoRoot: string, path: string): string {
  return isAbsolute(path) ? path : resolve(repoRoot, path);
}

function report(title: string, issues: ValidationIssue[]): void {
  if (issues.length === 0) {
    console.log(`  ok    ${title}`);
    return;
  }
  console.log(`  FALHA ${title} (${issues.length})`);
  for (const issue of issues) console.log(`        [${issue.kind}] ${issue.message}`);
}

export async function executarCli(
  argv: string[],
  ambiente: AmbienteCli,
): Promise<{ estado: EstadoCli; problemas: string[] }> {
  const { repoRoot, outDir } = ambiente;
  const args = parseArgs(argv);
  const modo = modoDoComando(args);
  console.log(
    `packer ${args.command} — municipio ${args.municipality}, versao ${args.packVersion}\n`,
  );

  // 1. Construcao
  const built = buildPack({
    repoRoot: repoRoot,
    outDir: outDir,
    packVersion: args.packVersion,
    schemaVersion: PACK_SCHEMA_VERSION,
    municipality: args.municipality,
    sourceCommit: process.env.GIT_COMMIT ?? 'dev',
  });
  console.log(`  ok    pack construido (${built.assets.length} assets)`);

  // 2. Portoes — nada e assinado com qualquer um destes vermelho
  const referential = validateReferential(built.dbPath);
  report('integridade referencial e traducoes', referential);

  // Registro invalido bloqueia nos dois modos: e erro de quem editou o YAML, e
  // um nome ali e dado pessoal publicado no repositorio.
  const registro = avaliarRegistro({
    atestados: ambiente.atestados ?? lerAtestadosDoYaml(repoRoot),
  });
  const registroIssues: ValidationIssue[] = registro.ok
    ? []
    : registro.problemas.map((p) => ({
        kind: 'golden_registro_invalido',
        message: `registro de atestados invalido (seed/golden/atestados.yaml): ${p}`,
      }));
  report('registro de atestados', registroIssues);

  const model = readRuleModel(built.dbPath);
  const golden = validateGolden(ambiente.casos ?? lerGoldenDoYaml(repoRoot), model, {
    modo,
    agora: ambiente.agora ?? new Date(),
    registro: registro.ok ? registro.entradas : [],
  });
  report(`suite golden (${golden.passed}/${golden.total})`, golden.issues);

  if (golden.falseNegatives > 0) {
    console.log(`\n  !!    ${golden.falseNegatives} FALSO(S) NEGATIVO(S) CLINICO(S)`);
    console.log('        Caso em que o app mandaria para casa quem precisa de emergencia.');
  }
  if (golden.unreviewed > 0) {
    console.log(
      `\n  aviso ${golden.unreviewed} caso(s) golden sem revisao clinica — ` +
        'permitido so em --dry-run; build, publish e o worker bloqueiam.',
    );
  }

  const blocking = [...referential, ...registroIssues, ...golden.issues];
  if (blocking.length > 0) {
    console.error(`\nBLOQUEADO: ${blocking.length} problema(s). Nada foi assinado.`);
    return { estado: 'bloqueado', problemas: blocking.map((p) => p.message) };
  }

  // O UNICO caminho ate `buildManifest` passa por aqui. Daqui para baixo nada
  // consulta `args.dryRun`: o modo ja decidiu.
  if (modo === 'verificacao') {
    console.log('\n--dry-run: portoes verdes, assinatura nao executada.');
    return { estado: 'verificado', problemas: [] };
  }

  // 3. Assinatura
  const { manifest, packUrl } = buildManifest({
    schemaVersion: PACK_SCHEMA_VERSION,
    packVersion: args.packVersion,
    municipality: args.municipality,
    packPath: built.dbPath,
    assets: built.assets,
    minAppBuild: args.minAppBuild,
    keyId: process.env.PACK_SIGNING_KEY_ID ?? 'k1',
    privateKeyPath: resolveFromRepo(repoRoot, requireEnv('PACK_SIGNING_KEY_PATH')),
  });
  const manifestPath = writeManifest(outDir, manifest);
  console.log(`  ok    manifest assinado (${packUrl})`);

  if (args.command !== 'publish') {
    console.log(`\nArtefatos em ${outDir}. Use "publish" para enviar ao storage.`);
    return { estado: 'assinado', problemas: [] };
  }

  // 4. Publicacao — artefatos por hash primeiro, manifest por ultimo
  const staged = join(outDir, packUrl);
  mkdirSync(dirname(staged), { recursive: true });
  copyFileSync(built.dbPath, staged);

  const target: S3Target = {
    endpoint: process.env.S3_ENDPOINT ?? 'http://127.0.0.1:9000',
    bucket: process.env.S3_BUCKET ?? 'content-packs',
    accessKey: requireEnv('MINIO_ROOT_USER'),
    secretKey: requireEnv('MINIO_ROOT_PASSWORD'),
  };

  const files = [
    { key: packUrl, path: staged },
    ...built.assets.map((a) => ({ key: a.path, path: join(repoRoot, 'seed', a.path) })),
  ];

  const published = await publish(target, args.municipality, files, manifestPath);
  console.log(
    `  ok    ${published.length} objeto(s) publicado(s) em ${target.bucket}/${args.municipality}`,
  );
  return { estado: 'publicado', problemas: [] };
}
