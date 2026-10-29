/**
 * Politica de leitura anonima do prefixo `models/` no bucket de conteudo
 * (P1-1, #3 — ADR-004).
 *
 * ## Por que nao `mc anonymous set download`
 *
 * Medido em 2026-10-29 com a imagem do compose: o comando mescla com a politica
 * existente, mas (a) libera LISTAGEM anonima do prefixo (`s3:ListBucket`) e
 * (b) grava o recurso `models*`, sem barra, que liberou `models-x/leak.bin`.
 * Aqui o statement e escrito a mao: so `s3:GetObject`, so `models/*`.
 *
 * ## Por que conferir antes e depois
 *
 * A politica dos packs foi configurada fora do repositorio (#46). Uma escrita
 * que a substituisse em vez de mescla-la pararia o sync de conteudo da frota
 * inteira, sem erro visivel no app. `missingPermissions` compara por PERMISSAO
 * (efeito, principal, acao, recurso, condicao), nao por statement inteiro: o
 * MinIO funde e reordena statements ao gravar.
 *
 * CLI (usada por `infra/scripts/publish-model.sh`):
 *   node --import tsx packer/src/models-policy.ts merge <antes.json> --bucket <b>
 *   node --import tsx packer/src/models-policy.ts verify <antes.json> <depois.json>
 */
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export interface Statement {
  Effect: string;
  Principal: unknown;
  Action: string | string[];
  Resource: string | string[];
  Condition?: unknown;
}

export interface Policy {
  Version: string;
  Statement: Statement[];
}

/** O unico statement que a publicacao do modelo acrescenta. */
export function modelsStatement(bucket: string): Statement {
  return {
    Effect: 'Allow',
    Principal: { AWS: ['*'] },
    Action: ['s3:GetObject'],
    Resource: [`arn:aws:s3:::${bucket}/models/*`],
  };
}

/** [antes] com o statement do modelo, sem tocar em nenhum outro. Idempotente. */
export function mergeModelsPolicy(antes: Policy | null, bucket: string): Policy {
  const novo = modelsStatement(bucket);
  const base: Policy = antes ?? { Version: '2012-10-17', Statement: [] };
  const temNovo = missingPermissions({ Version: base.Version, Statement: [novo] }, base).length === 0;
  return {
    Version: base.Version,
    Statement: temNovo ? base.Statement : [...base.Statement, novo],
  };
}

/** Uma linha por permissao elementar, em forma canonica. */
function permissoes(policy: Policy): Set<string> {
  const saida = new Set<string>();
  for (const st of policy.Statement) {
    for (const acao of [st.Action].flat()) {
      for (const recurso of [st.Resource].flat()) {
        saida.add(
          JSON.stringify([st.Effect, canonico(st.Principal), acao, recurso, canonico(st.Condition ?? null)]),
        );
      }
    }
  }
  return saida;
}

/** JSON com chaves e listas ordenadas: o MinIO reordena ambas. */
function canonico(valor: unknown): unknown {
  if (Array.isArray(valor)) return valor.map(canonico).map((v) => JSON.stringify(v)).sort();
  if (valor && typeof valor === 'object') {
    return Object.fromEntries(
      Object.entries(valor as Record<string, unknown>)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([k, v]) => [k, canonico(v)]),
    );
  }
  return valor;
}

/**
 * Permissoes de [antes] que [depois] nao concede mais.
 *
 * Condicoes sao comparadas por igualdade: um `ListBucket` com dois prefixos
 * nao "contem" o de um so. O MinIO funde os prefixos ao gravar, e por isso a
 * condicao de cada `s3:prefix` e expandida antes de comparar.
 */
export function missingPermissions(antes: Policy, depois: Policy): string[] {
  const ter = expandirPrefixos(permissoes(depois));
  return [...expandirPrefixos(permissoes(antes))].filter((p) => !ter.has(p));
}

function expandirPrefixos(perms: Set<string>): Set<string> {
  const saida = new Set<string>();
  for (const p of perms) {
    const [efeito, principal, acao, recurso, condicao] = JSON.parse(p) as unknown[];
    const prefixos = (condicao as { StringEquals?: { 's3:prefix'?: string[] } } | null)?.StringEquals?.[
      's3:prefix'
    ];
    if (!prefixos) {
      saida.add(p);
      continue;
    }
    for (const pre of prefixos) {
      saida.add(
        JSON.stringify([efeito, principal, acao, recurso, { StringEquals: { 's3:prefix': [pre] } }]),
      );
    }
  }
  return saida;
}

/** O `get-json` de bucket sem politica nao devolve JSON: vira `null`. */
function lerPolitica(arquivo: string): Policy | null {
  const texto = readFileSync(arquivo, 'utf8').trim();
  if (!texto.startsWith('{')) return null;
  const json = JSON.parse(texto) as Partial<Policy>;
  return Array.isArray(json.Statement) ? (json as Policy) : null;
}

function main(args: string[]): number {
  const [comando, a, b] = args;
  if (comando === 'merge' && a) {
    const i = args.indexOf('--bucket');
    const bucket = i >= 0 ? args[i + 1] : undefined;
    if (!bucket) return uso();
    process.stdout.write(`${JSON.stringify(mergeModelsPolicy(lerPolitica(a), bucket))}\n`);
    return 0;
  }
  if (comando === 'verify' && a && b) {
    const antes = lerPolitica(a);
    const depois = lerPolitica(b) ?? { Version: '2012-10-17', Statement: [] };
    const faltando = antes ? missingPermissions(antes, depois) : [];
    for (const f of faltando) process.stderr.write(`sumiu: ${f}\n`);
    return faltando.length === 0 ? 0 : 1;
  }
  return uso();
}

function uso(): number {
  process.stderr.write(
    'uso: models-policy.ts merge <antes.json> --bucket <bucket> | verify <antes.json> <depois.json>\n',
  );
  return 64;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  process.exitCode = main(process.argv.slice(2));
}
