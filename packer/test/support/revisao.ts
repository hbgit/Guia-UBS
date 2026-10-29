/**
 * Fixtures de revisao clinica FICTICIAS para os testes do packer.
 *
 * Nada aqui depende de o seed real estar ou nao revisado: o conteudo de um caso
 * real e usado so para passar nas regras do seed, e a revisao e removida
 * explicitamente.
 */
import type { Atestado, EntradaRegistro, RevisorYaml } from '@guia-ubs/contract';

import { lerGoldenDoYaml, type GoldenCase } from '../../src/validate.js';

/** Conteudo de um caso REAL, revisao REMOVIDA, id ficticio. */
export function semRevisao(repoRoot: string, id: string): GoldenCase {
  const { reviewed_by: _b, reviewed_at: _a, ...resto } = lerGoldenDoYaml(repoRoot).find(
    (c) => c.id === id,
  )!;
  return { ...resto, id: `ficticio-${id}` };
}

export const REG: EntradaRegistro[] = [
  { id: 'AT-9001', conselho: 'CRM', uf: 'RR', termo_sha256: 'a'.repeat(64) },
  { id: 'AT-9002', conselho: 'COREN', categoria: 'ENF', uf: 'RR', termo_sha256: 'b'.repeat(64) },
];

export const REV_CRM: RevisorYaml = {
  atestado: 'AT-9001',
  conselho: 'CRM',
  uf: 'RR',
  reviewed_at: '2026-10-28',
};

export const ATESTADO_FICTICIO: Atestado = {
  id: 'AT-9002',
  nome: 'Revisora Ficticia Teste',
  conselho: 'COREN',
  categoria: 'ENF',
  uf: 'RR',
  registro: '000123',
  termo_sha256: 'b'.repeat(64),
};
