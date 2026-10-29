/**
 * Toda acao que o CMS grava na trilha esta classificada para D11 (P0-2).
 *
 * Release barrada pelo portao golden so volta a fila depois de uma escrita de
 * CONTEUDO auditada (`packer/src/worker.ts#proximaAprovada`). Quem diz o que e
 * conteudo e `ACOES_QUE_REABREM` (prefixos); `ACOES_QUE_NAO_REABREM` e a lista
 * exata do resto. Acao nova fora das duas reprova aqui: sem isso, um login que
 * passasse a se chamar `session_start` reabriria — ou um `golden_*` esquecido
 * deixaria de reabrir — sem ninguem notar.
 *
 * As acoes sao EXTRAIDAS do codigo, nao listadas a mao: uma lista redigida a
 * parte envelhece e passa a mentir, como em `APPEND_ONLY_TABLES`.
 */
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';

import { ACOES_QUE_NAO_REABREM, ACOES_QUE_REABREM } from '@guia-ubs/contract';

import { TRANSICOES } from '../src/services/approval-workflow.js';

const SRC = join(import.meta.dirname, '..', 'src');

function arquivosTs(dir: string): string[] {
  return readdirSync(dir, { recursive: true, encoding: 'utf8' })
    .filter((f) => f.endsWith('.ts'))
    .map((f) => join(dir, f));
}

function acoesDoCodigo(): Set<string> {
  const acoes = new Set<string>();
  for (const arquivo of arquivosTs(SRC)) {
    const texto = readFileSync(arquivo, 'utf8');
    // `action: 'x'` e os dois ramos de `action: cond ? 'x' : 'y'`. So literal no
    // inicio ou depois de `?`/`:` — o `'approve'` de `decision === 'approve'` e
    // o `'action'` de `text('action')` nao sao acoes.
    for (const linha of texto.matchAll(/\baction:\s*([^,\n]+)/g)) {
      for (const literal of linha[1]!.matchAll(/(?:^|[?:])\s*'([a-z_]+)'/g)) {
        acoes.add(literal[1]!);
      }
    }
  }

  // `${acao}_failed` do middleware: os valores do mapa ACOES e suas falhas.
  const middleware = readFileSync(join(SRC, 'auth', 'middleware.ts'), 'utf8');
  const mapa = /const ACOES[^=]*=\s*\{([\s\S]*?)\};/.exec(middleware);
  assert.ok(mapa, 'mapa ACOES nao encontrado em auth/middleware.ts');
  for (const valor of mapa[1]!.matchAll(/:\s*'([a-z_]+)'/g)) {
    acoes.add(valor[1]!);
    acoes.add(`${valor[1]!}_failed`);
  }

  // `release_${para}` de `moverPeloJob`: so as transicoes que o job executa.
  for (const t of TRANSICOES) if (t.por.includes('job')) acoes.add(`release_${t.para}`);
  return acoes;
}

const reabre = (acao: string) => ACOES_QUE_REABREM.some((p) => acao.startsWith(p));

test('toda acao da trilha esta classificada para D11', () => {
  const acoes = acoesDoCodigo();
  // Regex quebrada nao pode ficar verde com zero asercoes.
  assert.ok(acoes.size >= 15, `so ${acoes.size} acao(oes) extraida(s): ${[...acoes].join(', ')}`);
  assert.ok(acoes.has('sign_in_locked') && acoes.has('content_update') && acoes.has('sign_in_failed'));

  for (const acao of acoes) {
    const naLista = ACOES_QUE_NAO_REABREM.includes(acao);
    assert.ok(
      reabre(acao) !== naLista,
      naLista
        ? `"${acao}" casa um prefixo de ACOES_QUE_REABREM E esta em ACOES_QUE_NAO_REABREM`
        : `"${acao}" nao esta classificada: acrescente a ACOES_QUE_NAO_REABREM ou use um prefixo de conteudo`,
    );
  }
});

test('as transicoes do worker do packer nao reabrem a release', () => {
  // O worker grava `release_<estado>` sem ator, fora de cms/src. Ainda que a
  // consulta exija ator, classifica-las como conteudo seria um laco latente.
  for (const acao of ['release_building', 'release_approved', 'release_built', 'release_published']) {
    assert.ok(ACOES_QUE_NAO_REABREM.includes(acao), acao);
    assert.ok(!reabre(acao), acao);
  }
});
