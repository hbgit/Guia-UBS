/**
 * O portao de revisao clinica na CLI (issue #2).
 *
 * Caso golden sem revisao valida bloqueia toda assinatura (`build`, `publish`);
 * so o `--dry-run`, que nao assina, avisa e passa. Revisao INVALIDA (formato
 * errado ou atestado fora do registro), registro invalido e suite vazia
 * bloqueiam nos dois modos (D9).
 *
 * Nenhum teste depende do estado de revisao dos YAMLs reais: `casos` e
 * `atestados` sao passados explicitamente. O unico que le os reais afirma so o
 * que vale em qualquer estado de revisao. Chave Ed25519 efemera; cada teste tem
 * o proprio outDir.
 */
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';

import { avaliarRegistro, avaliarRevisao, conferirContraRegistro } from '@guia-ubs/contract';

import { executarCli, modoDoComando, type AmbienteCli } from '../src/cli.js';
import { lerAtestadosDoYaml, lerGoldenDoYaml } from '../src/validate.js';
import { REG, REV_CRM, semRevisao } from './support/revisao.js';

const REPO_ROOT = join(import.meta.dirname, '..', '..');
const AGORA = new Date('2026-10-28T12:00:00Z');
const CASO_SEM_REVISOR = semRevisao(REPO_ROOT, 'chest-pain');
const CASO_REVISADO = { ...CASO_SEM_REVISOR, reviewed_by: [REV_CRM] };

let diretorio: string;
const salvo: Record<string, string | undefined> = {};
const CHAVES = ['PACK_SIGNING_KEY_PATH', 'PACK_SIGNING_KEY_ID', 'SOURCE_DATE_EPOCH', 'MINIO_ROOT_USER'];

before(() => {
  for (const k of CHAVES) salvo[k] = process.env[k];
  diretorio = mkdtempSync(join(tmpdir(), 'gubs-cli-'));
  const { privateKey } = generateKeyPairSync('ed25519');
  const keyPath = join(diretorio, 'k.pem');
  writeFileSync(keyPath, privateKey.export({ type: 'pkcs8', format: 'pem' }) as string);
  process.env.PACK_SIGNING_KEY_PATH = keyPath;
  delete process.env.PACK_SIGNING_KEY_ID;
  process.env.SOURCE_DATE_EPOCH = '1787097600';
  delete process.env.MINIO_ROOT_USER;
});

after(() => {
  for (const k of CHAVES) {
    if (salvo[k] === undefined) delete process.env[k];
    else process.env[k] = salvo[k];
  }
  rmSync(diretorio, { recursive: true, force: true });
});

/** Ambiente com outDir proprio; registro ficticio `REG` salvo quando sobrescrito. */
function ambiente(extra: Partial<AmbienteCli>): AmbienteCli & { outDir: string } {
  return {
    repoRoot: REPO_ROOT,
    outDir: mkdtempSync(join(diretorio, 'out-')),
    atestados: REG,
    agora: AGORA,
    ...extra,
  };
}

const assinou = (outDir: string) => existsSync(join(outDir, 'manifest.json'));

// ---------------------------------------------------------------------------
// Caso sem revisor: so o --dry-run passa
// ---------------------------------------------------------------------------

test('build --dry-run passa com caso sem revisor e avisa', async () => {
  const amb = ambiente({ casos: [CASO_SEM_REVISOR] });
  const r = await executarCli(['build', '--dry-run'], amb);
  assert.equal(r.estado, 'verificado');
  assert.ok(!assinou(amb.outDir));
});

test('publish --dry-run nao assina', async () => {
  const amb = ambiente({ casos: [CASO_SEM_REVISOR] });
  const r = await executarCli(['publish', '--dry-run'], amb);
  assert.equal(r.estado, 'verificado');
  assert.ok(!assinou(amb.outDir));
});

test('build sem --dry-run BLOQUEIA caso sem revisor', async () => {
  const amb = ambiente({ casos: [CASO_SEM_REVISOR] });
  const r = await executarCli(['build'], amb);
  assert.equal(r.estado, 'bloqueado');
  assert.ok(r.problemas.some((p) => p.includes(CASO_SEM_REVISOR.id)));
  assert.ok(!assinou(amb.outDir), 'manifest assinado com caso sem revisor');
});

test('publish BLOQUEIA caso sem revisor antes de assinar', async () => {
  // Resolve `bloqueado`, sem chegar ao storage (MINIO_ROOT_USER ausente faria
  // rejeitar) e sem manifest no disco.
  const amb = ambiente({ casos: [CASO_SEM_REVISOR] });
  const r = await executarCli(['publish'], amb);
  assert.equal(r.estado, 'bloqueado');
  assert.ok(!assinou(amb.outDir));
});

test('build assina quando todos os casos tem revisao valida e registrada', async () => {
  const amb = ambiente({ casos: [CASO_REVISADO], atestados: REG });
  const r = await executarCli(['build'], amb);
  assert.equal(r.estado, 'assinado', JSON.stringify(r.problemas));
  assert.ok(assinou(amb.outDir));
});

// ---------------------------------------------------------------------------
// Bloqueia nos dois modos (D9)
// ---------------------------------------------------------------------------

for (const argv of [['build', '--dry-run'], ['build']]) {
  const modo = argv.join(' ');

  test(`revisao invalida BLOQUEIA ate em --dry-run (${modo})`, async () => {
    const amb = ambiente({ casos: [{ ...CASO_SEM_REVISOR, reviewed_by: 'Dra. Fulana' }] });
    const r = await executarCli(argv, amb);
    assert.equal(r.estado, 'bloqueado');
    assert.ok(r.problemas.some((p) => /revisao invalida/.test(p)), JSON.stringify(r.problemas));
    assert.ok(!assinou(amb.outDir));
  });

  test(`UF fora das 27 BLOQUEIA ate em --dry-run (${modo})`, async () => {
    // Formato certo em tudo, menos a UF: so o enum de UFS do contrato barra.
    // O registro tambem diz XX: sem o enum, revisao e registro concordariam e assinaria.
    const amb = ambiente({
      casos: [{ ...CASO_SEM_REVISOR, reviewed_by: [{ ...REV_CRM, uf: 'XX' }] }],
      atestados: REG.map((e) => (e.id === REV_CRM.atestado ? { ...e, uf: 'XX' } : e)),
    });
    const r = await executarCli(argv, amb);
    assert.equal(r.estado, 'bloqueado');
    assert.ok(r.problemas.some((p) => /revisao invalida/.test(p)), JSON.stringify(r.problemas));
    assert.ok(!assinou(amb.outDir));
  });

  test(`atestado inexistente no registro BLOQUEIA ate em --dry-run (${modo})`, async () => {
    const amb = ambiente({
      casos: [{ ...CASO_SEM_REVISOR, reviewed_by: [{ ...REV_CRM, atestado: 'AT-0099' }] }],
    });
    const r = await executarCli(argv, amb);
    assert.equal(r.estado, 'bloqueado');
    assert.ok(r.problemas.some((p) => p.includes('AT-0099')), JSON.stringify(r.problemas));
    assert.ok(!assinou(amb.outDir));
  });

  test(`UF divergente do registro BLOQUEIA (${modo})`, async () => {
    const amb = ambiente({ casos: [{ ...CASO_SEM_REVISOR, reviewed_by: [{ ...REV_CRM, uf: 'SP' }] }] });
    const r = await executarCli(argv, amb);
    assert.equal(r.estado, 'bloqueado');
    assert.ok(r.problemas.some((p) => /\.uf: "SP" diverge/.test(p)), JSON.stringify(r.problemas));
  });

  test(`registro com nome BLOQUEIA (${modo})`, async () => {
    // O registro e publico: nome no YAML e dado pessoal publicado no repositorio.
    const amb = ambiente({
      casos: [CASO_REVISADO],
      atestados: [{ ...REG[0], nome: 'Fulana de Tal' }, REG[1]],
    });
    const r = await executarCli(argv, amb);
    assert.equal(r.estado, 'bloqueado');
    assert.ok(
      r.problemas.some((p) => p.startsWith('registro de atestados invalido')),
      JSON.stringify(r.problemas),
    );
    assert.ok(!assinou(amb.outDir));
  });

  test(`suite vazia BLOQUEIA (${modo})`, async () => {
    const amb = ambiente({ casos: [] });
    const r = await executarCli(argv, amb);
    assert.equal(r.estado, 'bloqueado');
    assert.ok(r.problemas.some((p) => /suite golden vazia/i.test(p)));
    assert.ok(!assinou(amb.outDir));
  });
}

test('modoDoComando: so "nao vai assinar" seleciona o modo de aviso', () => {
  const tabela: [boolean, ReturnType<typeof modoDoComando>][] = [
    [true, 'verificacao'],
    [false, 'assinatura'],
  ];
  for (const [dryRun, esperado] of tabela) {
    assert.equal(modoDoComando({ dryRun }), esperado, `dryRun=${dryRun}`);
  }
});

// ---------------------------------------------------------------------------
// Os YAMLs reais (D9): so o que vale em qualquer estado de revisao
// ---------------------------------------------------------------------------

test('os YAMLs reais nao tem revisao invalida', () => {
  // Revisao AUSENTE nao reprova o CI de PR; INVALIDA reprova. Nao conta casos
  // revisados: o teste vale com zero e com vinte e quatro.
  const registro = avaliarRegistro({ atestados: lerAtestadosDoYaml(REPO_ROOT) });
  assert.ok(registro.ok, JSON.stringify(registro));
  const casos = lerGoldenDoYaml(REPO_ROOT);
  assert.ok(casos.length > 0);
  for (const caso of casos) {
    const revisao = avaliarRevisao(caso, new Date());
    assert.notEqual(revisao.estado, 'invalida', `${caso.id}: ${JSON.stringify(revisao)}`);
    if (revisao.estado === 'valida') {
      assert.deepEqual(conferirContraRegistro(revisao.revisores, registro.entradas), [], caso.id);
    }
  }
});
