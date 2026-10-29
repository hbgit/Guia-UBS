/**
 * Importacao dos casos golden do YAML para o CMS (P0-2), com a MESMA regra do
 * packer e das rotas: caso ativo exige revisao clinica valida, e a revisao so e
 * ACRESCIDA — nunca removida nem trocada.
 *
 * Tudo-ou-nada: toda a verificacao acontece antes de qualquer escrita, e um
 * recusado ou conflito devolve o relatorio sem tocar o banco. Importar "o que
 * deu" deixaria a suite pela metade, e quem implanta nao saberia qual metade.
 *
 * O CMS guarda o atestado COMPLETO (nome, registro); o YAML publico so o resumo.
 * O importador confere os dois lados e nunca cria atestado: registrar uma pessoa
 * e ato do revisor (POST /api/golden-cases/atestados), nao de um script.
 */
import { randomUUID } from 'node:crypto';

import {
  MIN_REVISORES,
  avaliarRegistro,
  avaliarRevisao,
  conferirContraRegistro,
  type EntradaRegistro,
  type RevisorYaml,
} from '@guia-ubs/contract';
import type { Client, InStatement } from '@libsql/client';

import { recordAudit } from './audit.js';

export interface CasoGoldenYaml {
  id: string;
  tokens: string[];
  expect: string;
  note?: string;
  reviewed_by?: unknown;
  reviewed_at?: unknown;
}

export interface RelatorioImportacao {
  inseridos: string[];
  revisoresAcrescentados: { id: string; atestados: string[] }[];
  mantidos: string[];
  conflitos: { id: string; motivo: string }[];
  recusados: { id: string; problemas: string[] }[];
}

interface Plano {
  caso: CasoGoldenYaml;
  existe: boolean;
  acrescentar: RevisorYaml[];
}

export async function importarGolden(
  client: Client,
  salt: string,
  entrada: { casos: readonly CasoGoldenYaml[]; registro: readonly unknown[] },
  opcoes: { autor: string; agora: Date },
): Promise<RelatorioImportacao> {
  const rel: RelatorioImportacao = {
    inseridos: [],
    revisoresAcrescentados: [],
    mantidos: [],
    conflitos: [],
    recusados: [],
  };

  const registro = avaliarRegistro({ atestados: entrada.registro });
  if (!registro.ok) {
    rel.recusados.push({ id: '(registro)', problemas: registro.problemas });
    return rel;
  }
  if (entrada.casos.length === 0) {
    rel.recusados.push({
      id: '(suite)',
      problemas: ['suite vazia: nada a importar; confira seed/golden/clinical_cases.yaml'],
    });
    return rel;
  }

  const atestadosCms = new Map<string, Record<string, unknown>>();
  for (const l of (await client.execute('SELECT * FROM golden_attestation')).rows) {
    atestadosCms.set(String(l.id), l as unknown as Record<string, unknown>);
  }
  const registroPorId = new Map<string, EntradaRegistro>(registro.entradas.map((e) => [e.id, e]));

  const planos: Plano[] = [];
  for (const caso of entrada.casos) {
    const revisao = avaliarRevisao(caso, opcoes.agora);
    if (revisao.estado === 'ausente') {
      rel.recusados.push({
        id: caso.id,
        problemas: ['sem revisao clinica — caso ativo exige revisor (reviewed_by)'],
      });
      continue;
    }
    if (revisao.estado === 'invalida') {
      rel.recusados.push({ id: caso.id, problemas: revisao.problemas });
      continue;
    }
    const incoerentes = conferirContraRegistro(revisao.revisores, registro.entradas);
    if (incoerentes.length > 0) {
      rel.recusados.push({ id: caso.id, problemas: incoerentes });
      continue;
    }

    // Cada atestado citado precisa existir neste CMS e bater com o registro.
    const problemas: string[] = [];
    const divergentes: string[] = [];
    for (const rev of revisao.revisores) {
      const cms = atestadosCms.get(rev.atestado);
      if (!cms) {
        problemas.push(
          `${rev.atestado}: nao registrado neste CMS; registre o atestado em POST /api/golden-cases/atestados com o ID de atestados.yaml`,
        );
        continue;
      }
      const reg = registroPorId.get(rev.atestado)!;
      const categoria = 'categoria' in reg ? reg.categoria : null;
      if (
        cms.conselho !== reg.conselho ||
        cms.uf !== reg.uf ||
        (cms.categoria ?? null) !== categoria ||
        cms.termo_sha256 !== reg.termo_sha256
      ) {
        divergentes.push(`${rev.atestado}: CMS e atestados.yaml divergem`);
      }
    }
    if (problemas.length > 0) {
      rel.recusados.push({ id: caso.id, problemas });
      continue;
    }
    if (divergentes.length > 0) {
      rel.conflitos.push({ id: caso.id, motivo: divergentes.join('; ') });
      continue;
    }

    const existente = (
      await client.execute({ sql: 'SELECT * FROM golden_case WHERE id = ?', args: [caso.id] })
    ).rows[0];
    if (!existente) {
      planos.push({ caso, existe: false, acrescentar: revisao.revisores });
      continue;
    }
    if (
      existente.tokens_json !== JSON.stringify(caso.tokens) ||
      existente.expected_outcome_id !== caso.expect
    ) {
      rel.conflitos.push({
        id: caso.id,
        motivo: 'conteudo editado no CMS; a revisao do YAML nao se aplica',
      });
      continue;
    }
    const atuais = new Map<string, string>();
    for (const l of (
      await client.execute({
        sql: 'SELECT attestation_id, reviewed_at FROM golden_case_review WHERE case_id = ?',
        args: [caso.id],
      })
    ).rows) {
      atuais.set(String(l.attestation_id), String(l.reviewed_at));
    }
    const trocas = revisao.revisores.filter(
      (r) => atuais.has(r.atestado) && atuais.get(r.atestado) !== r.reviewed_at,
    );
    if (trocas.length > 0) {
      rel.conflitos.push({
        id: caso.id,
        motivo: `revisao existente com data diferente (${trocas.map((r) => r.atestado).join(', ')}); revisao nao se troca`,
      });
      continue;
    }
    const faltam = revisao.revisores.filter((r) => !atuais.has(r.atestado));
    if (faltam.length === 0) rel.mantidos.push(caso.id);
    else planos.push({ caso, existe: true, acrescentar: faltam });
  }

  // D8: um recusado ou conflito e a importacao inteira que nao acontece.
  if (rel.recusados.length > 0 || rel.conflitos.length > 0) return rel;

  const agora = opcoes.agora.toISOString();
  const comandos: InStatement[] = [];
  for (const { caso, existe, acrescentar } of planos) {
    if (!existe) {
      // Nasce inativo e so a ultima instrucao o ativa, como na rota.
      comandos.push({
        sql: `INSERT INTO golden_case
                (id, tokens_json, expected_outcome_id, clinical_source, added_by, active)
              VALUES (?, ?, ?, ?, ?, 0)`,
        args: [
          caso.id,
          JSON.stringify(caso.tokens),
          caso.expect,
          caso.note ?? 'importado de seed/golden/clinical_cases.yaml',
          opcoes.autor,
        ],
      });
    }
    for (const rev of acrescentar) {
      comandos.push({
        sql: `INSERT INTO golden_case_review
                (id, case_id, attestation_id, reviewed_at, recorded_by, recorded_at)
              VALUES (?, ?, ?, ?, ?, ?)`,
        args: [randomUUID(), caso.id, rev.atestado, rev.reviewed_at, opcoes.autor, agora],
      });
    }
    comandos.push({
      sql: `UPDATE golden_case SET active = 1
            WHERE id = ?
              AND (SELECT COUNT(*) FROM golden_case_review WHERE case_id = ?) >= ?`,
      args: [caso.id, caso.id, MIN_REVISORES],
    });
  }
  await client.batch(comandos, 'write');

  for (const { caso, existe, acrescentar } of planos) {
    const atestados = acrescentar.map((r) => r.atestado);
    if (existe) rel.revisoresAcrescentados.push({ id: caso.id, atestados });
    else rel.inseridos.push(caso.id);
    await recordAudit(client, salt, {
      actorId: opcoes.autor,
      action: existe ? 'golden_case_review' : 'golden_case_import',
      entityType: 'golden_case',
      entityId: caso.id,
      after: { atestados, active: 1 },
    });
  }
  return rel;
}
