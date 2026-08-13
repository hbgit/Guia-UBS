#!/usr/bin/env node
/**
 * CLI do packer.
 *
 *   packer build    [--dry-run]   constroi o pack e roda todos os portoes
 *   packer publish                constroi, assina e publica no storage
 *
 * A assinatura so acontece depois de referencial e golden verdes. Nao ha flag
 * para pular esses portoes: e o que impede orientacao clinica errada de chegar
 * a um dispositivo offline (PRD risco R5).
 */
import { copyFileSync, mkdirSync } from 'node:fs';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { PACK_SCHEMA_VERSION } from '@guia-ubs/contract';

import { buildPack, readRuleModel } from './build-pack.js';
import { buildManifest, publish, writeManifest, type S3Target } from './release.js';
import { validateGolden, validateReferential, type ValidationIssue } from './validate.js';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const OUT_DIR = join(REPO_ROOT, 'packer', 'out');

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

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Variavel de ambiente ${name} nao definida`);
  return value;
}

/**
 * Caminhos relativos sao resolvidos contra a raiz do repositorio, nao contra o
 * cwd: rodar via `npm --workspace` muda o cwd e quebraria o caminho da chave.
 */
function resolveFromRepo(path: string): string {
  return isAbsolute(path) ? path : resolve(REPO_ROOT, path);
}

function report(title: string, issues: ValidationIssue[]): void {
  if (issues.length === 0) {
    console.log(`  ok    ${title}`);
    return;
  }
  console.log(`  FALHA ${title} (${issues.length})`);
  for (const issue of issues) console.log(`        [${issue.kind}] ${issue.message}`);
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  console.log(
    `packer ${args.command} — municipio ${args.municipality}, versao ${args.packVersion}\n`,
  );

  // 1. Construcao
  const built = buildPack({
    repoRoot: REPO_ROOT,
    outDir: OUT_DIR,
    packVersion: args.packVersion,
    schemaVersion: PACK_SCHEMA_VERSION,
    municipality: args.municipality,
    defaultOutcomeId: 'ROUTINE_UBS',
    sourceCommit: process.env.GIT_COMMIT ?? 'dev',
  });
  console.log(`  ok    pack construido (${built.assets.length} assets)`);

  // 2. Portoes — nada e assinado com qualquer um destes vermelho
  const referential = validateReferential(built.dbPath);
  report('integridade referencial e traducoes', referential);

  const model = readRuleModel(built.dbPath);
  const golden = validateGolden(REPO_ROOT, model);
  report(`suite golden (${golden.passed}/${golden.total})`, golden.issues);

  if (golden.falseNegatives > 0) {
    console.log(`\n  !!    ${golden.falseNegatives} FALSO(S) NEGATIVO(S) CLINICO(S)`);
    console.log('        Caso em que o app mandaria para casa quem precisa de emergencia.');
  }
  if (golden.unreviewed > 0) {
    console.log(
      `\n  aviso ${golden.unreviewed} caso(s) golden sem revisor clinico nomeado — ` +
        'bloqueia o piloto, nao a Fase 1.',
    );
  }

  const blocking = [...referential, ...golden.issues];
  if (blocking.length > 0) {
    console.error(`\nBLOQUEADO: ${blocking.length} problema(s). Nada foi assinado.`);
    process.exit(1);
  }

  if (args.dryRun) {
    console.log('\n--dry-run: portoes verdes, assinatura nao executada.');
    return;
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
    privateKeyPath: resolveFromRepo(requireEnv('PACK_SIGNING_KEY_PATH')),
  });
  const manifestPath = writeManifest(OUT_DIR, manifest);
  console.log(`  ok    manifest assinado (${packUrl})`);

  if (args.command !== 'publish') {
    console.log(`\nArtefatos em ${OUT_DIR}. Use "publish" para enviar ao storage.`);
    return;
  }

  // 4. Publicacao — artefatos por hash primeiro, manifest por ultimo
  const staged = join(OUT_DIR, packUrl);
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
    ...built.assets.map((a) => ({ key: a.path, path: join(REPO_ROOT, 'seed', a.path) })),
  ];

  const published = await publish(target, args.municipality, files, manifestPath);
  console.log(
    `  ok    ${published.length} objeto(s) publicado(s) em ${target.bucket}/${args.municipality}`,
  );
}

main().catch((error: unknown) => {
  console.error(`\nErro: ${(error as Error).message}`);
  process.exit(1);
});
