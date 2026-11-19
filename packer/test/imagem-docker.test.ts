/**
 * A imagem do `packer` contem o que o worker le (issue #44).
 *
 * O servico `packer` rodou dois meses a partir de uma imagem sem `packer/` nem
 * `seed/`, porque nada conferia os `COPY` contra o que o worker abre. Este teste
 * le o proprio `cms/Dockerfile` e o proprio `seed/000_assets.sql` — lista redigida
 * ao lado envelhece, mesmo motivo de `APPEND_ONLY_TABLES` ser percorrida.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';

import { parse } from 'yaml';

const RAIZ = join(import.meta.dirname, '..', '..');
const ler = (p: string) => readFileSync(join(RAIZ, p), 'utf8');

interface Estagio {
  base: string;
  nome: string | undefined;
  linhas: string[];
}

function estagios(dockerfile: string): Estagio[] {
  const lista: Estagio[] = [];
  for (const linha of dockerfile.split('\n')) {
    const from = /^FROM\s+(\S+)(?:\s+AS\s+(\S+))?/i.exec(linha);
    if (from) lista.push({ base: from[1]!, nome: from[2], linhas: [] });
    else lista.at(-1)?.linhas.push(linha);
  }
  return lista;
}

export function ultimoEstagio(dockerfile: string): string | undefined {
  return estagios(dockerfile).at(-1)?.nome;
}

/** Fontes dos `COPY` sem `--from` do estagio e dos que ele herda por `FROM`. */
export function fontesCopiadas(dockerfile: string, estagio: string): string[] {
  const todos = estagios(dockerfile);
  const fontes: string[] = [];
  for (let atual = todos.find((e) => e.nome === estagio); atual; ) {
    for (const linha of atual.linhas) {
      const m = /^COPY\s+(.*)$/i.exec(linha.trim());
      if (!m) continue;
      const resto = m[1]!.trim();
      // Nao interpretadas; ignora-las faria o teste passar por vacuidade.
      if (resto.startsWith('[')) throw new Error(`COPY na forma JSON nao suportado: ${linha}`);
      if (resto.endsWith('\\')) throw new Error(`COPY com continuacao de linha nao suportado: ${linha}`);
      const args = resto.split(/\s+/);
      if (args.some((a) => a.startsWith('--from'))) continue;
      const semFlags = args.filter((a) => !a.startsWith('--'));
      fontes.push(
        ...semFlags.slice(0, -1).map((f) => f.replace(/^\.\//, '').replace(/\/$/, '')),
      );
    }
    atual = todos.find((e) => e.nome === atual!.base);
  }
  return fontes;
}

const cobre = (fontes: string[], p: string) =>
  fontes.some((f) => p === f || p.startsWith(`${f}/`));

const df = ler('cms/Dockerfile');

test('a imagem do packer contem o que o worker le', () => {
  const assets = [...ler('seed/000_assets.sql').matchAll(/'(assets\/[^']+)'/g)].map(
    (m) => `seed/${m[1]}`,
  );
  assert.ok(assets.length > 0, 'nenhum asset achado em seed/000_assets.sql');
  const necessarios = [
    'package.json',
    'packer/package.json',
    'packer/src/worker.ts',
    'contract/ddl', // readDdl
    'contract/src/index.ts', // @guia-ubs/contract (main)
    'seed/golden/atestados.yaml', // lerAtestadosDoYaml
    ...new Set(assets),
  ];
  const fontes = fontesCopiadas(df, 'packer');
  assert.deepEqual(
    necessarios.filter((p) => !cobre(fontes, p)),
    [],
  );
});

test('a imagem do packer nao leva o cms, a do cms nao leva packer/src nem seed', () => {
  assert.ok(!fontesCopiadas(df, 'packer').some((f) => f === 'cms' || f.startsWith('cms/')));
  assert.ok(!fontesCopiadas(df, 'production').some((f) => /^(seed|packer\/src)(\/|$)/.test(f)));
});

test('production e o ultimo estagio: docker build sem --target entrega o CMS', () => {
  assert.equal(ultimoEstagio(df), 'production');
});

test('nenhuma chave privada entra no contexto de build', () => {
  const linhas = ler('.dockerignore').split('\n').map((l) => l.trim());
  assert.ok(linhas.includes('**/*.pem'));
});

test('o compose constroi cada servico do seu alvo', () => {
  const compose = parse(ler('infra/compose.yaml')) as {
    services: Record<string, { build?: { target?: string } }>;
  };
  assert.equal(compose.services.packer?.build?.target, 'packer');
  assert.equal(compose.services.cms?.build?.target, 'production');
});

test('fontesCopiadas ignora flags e recusa forma JSON e continuacao', () => {
  assert.deepEqual(
    fontesCopiadas('FROM x AS a\nCOPY --chown=node:node --link seed/assets/ ./seed/assets/\n', 'a'),
    ['seed/assets'],
  );
  assert.throws(() => fontesCopiadas('FROM x AS a\nCOPY ["a", "b"]\n', 'a'), /JSON/);
  assert.throws(() => fontesCopiadas('FROM x AS a\nCOPY a \\\n  b\n', 'a'), /continuacao/);
});
