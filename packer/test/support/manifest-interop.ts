/**
 * Manifest SINTETICO para o job `interop` do CI (`.github/workflows/app.yml`).
 *
 * O job confere que a serializacao canonica de quem assina
 * (`contract/src/manifest.ts`) e a de quem verifica
 * (`app/lib/sync/pack_manifest.dart`) nao divergiram. Para isso basta um
 * manifest assinado AGORA por `buildManifest` — nao um pack de conteudo.
 *
 * Ate a #2 o job chamava `npm run pack:build`, que agora recusa assinar com caso
 * golden sem revisao clinica. Afrouxar o portao para o CI seria o atalho que a
 * #2 proibe; em vez disso, o "pack" aqui sao bytes fixos que nao sao um
 * `content.db` (nenhum aparelho o abriria) e a assinatura usa a chave efemera
 * do job. A lista de assets e a real do seed, para o payload canonico ter a
 * mesma forma do de producao.
 *
 * Uso: node --import tsx packer/test/support/manifest-interop.ts --key <pem> --out <dir>
 *        [--model-url <url> --model-sha256 <hex>] [--pack-version <n>] [--arvore]
 */
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { parseArgs } from 'node:util';

import { PACK_SCHEMA_VERSION } from '@guia-ubs/contract';

import { buildPack } from '../../src/build-pack.js';
import { buildManifest, modeloDoManifest, urlDoAsset, writeManifest } from '../../src/release.js';

const REPO_ROOT = join(import.meta.dirname, '..', '..', '..');

/** Conteudo do "pack": texto, para que ninguem o confunda com um SQLite. */
export const PACK_SINTETICO = 'guia-ubs: pack sintetico do job interop - NAO E CONTEUDO\n';

export function assinarManifestSintetico(opcoes: {
  chave: string;
  saida: string;
  /** Plano B: `model` opcional, para a fixture `manifest-v3-model.json`. */
  model?: { url: string; sha256: string };
  /** Padrao 1. O teste do host de conteudo publica uma v2 por cima da v1. */
  packVersion?: number;
  /**
   * Plano B: deixa a ARVORE publicavel em `saida` (pack em `<pack.url>`, assets
   * em `<asset.url>`), como o `pack:build` faz, para o `content:publish`.
   */
  arvore?: boolean;
}): string {
  mkdirSync(opcoes.saida, { recursive: true });
  const packPath = join(opcoes.saida, 'pack-sintetico.txt');
  writeFileSync(packPath, PACK_SINTETICO);

  // So a lista de assets e aproveitada; o content.db construido e descartado.
  const rascunho = mkdtempSync(join(tmpdir(), 'gubs-interop-'));
  try {
    const { assets } = buildPack({
      repoRoot: REPO_ROOT,
      outDir: rascunho,
      packVersion: 1,
      schemaVersion: PACK_SCHEMA_VERSION,
      municipality: '0000000',
      sourceCommit: 'interop',
    });
    const { manifest, packUrl } = buildManifest({
      schemaVersion: PACK_SCHEMA_VERSION,
      packVersion: opcoes.packVersion ?? 1,
      municipality: '0000000',
      packPath,
      assets,
      minAppBuild: 1,
      keyId: 'k1',
      privateKeyPath: opcoes.chave,
      ...(opcoes.model ? { model: opcoes.model } : {}),
    });
    if (opcoes.arvore) {
      mkdirSync(join(opcoes.saida, dirname(packUrl)), { recursive: true });
      copyFileSync(packPath, join(opcoes.saida, packUrl));
      for (const a of assets) {
        const url = urlDoAsset(a.path, a.sha256);
        mkdirSync(join(opcoes.saida, dirname(url)), { recursive: true });
        writeFileSync(join(opcoes.saida, url), a.content);
      }
    }
    return writeManifest(opcoes.saida, manifest);
  } finally {
    rmSync(rascunho, { recursive: true, force: true });
  }
}

if (import.meta.filename === process.argv[1]) {
  const { values } = parseArgs({
    options: {
      key: { type: 'string' },
      out: { type: 'string' },
      'model-url': { type: 'string' },
      'model-sha256': { type: 'string' },
      'pack-version': { type: 'string' },
      arvore: { type: 'boolean' },
    },
  });
  if (!values.key || !values.out) {
    console.error(
      'uso: manifest-interop.ts --key <pem> --out <dir> [--model-url <url> --model-sha256 <hex>] ' +
        '[--pack-version <n>] [--arvore]',
    );
    process.exit(2);
  }
  const model = modeloDoManifest(values['model-url'], values['model-sha256']);
  console.log(
    assinarManifestSintetico({
      chave: values.key,
      saida: values.out,
      ...(model ? { model } : {}),
      ...(values['pack-version'] ? { packVersion: Number(values['pack-version']) } : {}),
      ...(values.arvore ? { arvore: true } : {}),
    }),
  );
}
