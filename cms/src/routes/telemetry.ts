/**
 * Ingestao de telemetria agregada (lgpd.md LGPD-RF14).
 *
 * ## Esta rota e PUBLICA, e e a segunda excecao declarada a LGPD-RT01
 *
 * A primeira e `/health`. Aqui nao ha alternativa: autenticar exigiria
 * identidade de dispositivo, e identidade de dispositivo e exatamente o que a
 * INV-2 proibe. Uma credencial compartilhada embutida no APK seria pior — daria
 * a impressao de controle de acesso sem dar nenhum.
 *
 * ## Duas lacunas declaradas: esta rota NAO TEM PRODUTOR
 *
 * 1. O app **nao envia**. Enviar seria uma terceira chamada de rede, que exige
 *    ADR (o precedente e o ADR-003).
 * 2. Mesmo que enviasse, o lote seria recusado: `TelemetryRecorder` acumula
 *    contadores POR APARELHO, e o contrato exige `kCount >= 20` no lote
 *    submetido. Um aparelho nao tem como saber quantos outros existem na coorte.
 *    **Falta um agregador**, que nenhum documento nomeia.
 *
 * A rota existe para o lote JA AGREGADO — que e a forma que o schema do item 16
 * assume — e as duas lacunas estao em `arquitetura.md 5.12`.
 *
 * ## Superficie de escrita publica
 *
 * Lote forjado degrada qualidade de analise, nao privacidade nem seguranca
 * clinica: nao ha identificador para correlacionar, o `CHECK` de k>=20 do DDL
 * vale para qualquer origem, e `UNIQUE(cohort_key, bucket_day)` limita volume.
 */
import { randomUUID } from 'node:crypto';

import { K_ANONYMITY_MIN, isAcceptableBatch } from '@guia-ubs/contract';
import type { Client } from '@libsql/client';
import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';

import { createDb } from '../db/client.js';
import { classificarViolacao } from '../db/errors.js';
import { telemetryBatch } from '../db/schema/telemetry.js';

/**
 * Teto de corpo. Um lote legitimo tem dez metricas e tres campos de coorte —
 * alguns bytes. O limite existe para uma rota sem autenticacao nao virar caminho
 * de exaustao de memoria.
 */
const MAX_BYTES = 8 * 1024;

export function telemetryRoutes(client: Client) {
  /**
   * O teto agora e MIDDLEWARE, e a diferenca nao e estilo.
   *
   * Ate o item 25 a checagem era `(await c.req.text()).length > MAX_BYTES` — que
   * mede DEPOIS de ter bufferizado tudo. Numa rota sem autenticacao isso
   * significa que qualquer um faz o servidor alocar o corpo inteiro antes de ele
   * ser recusado: o teto protegia o parse, nao a memoria.
   *
   * `bodyLimit` confere o `Content-Length` ANTES de ler um byte, e em corpo
   * chunked conta enquanto le, parando no teto. Passou a valer aqui porque a rota
   * de envio de asset precisou do mesmo mecanismo — e deixar o padrao pior
   * morando ao lado do melhor e como ele se propaga.
   */
  const teto = bodyLimit({
    maxSize: MAX_BYTES,
    onError: (c) => c.json({ error: 'lote grande demais' }, 413),
  });

  return new Hono().post('/', teto, async (c) => {
    const texto = await c.req.text();

    let corpo: unknown;
    try {
      corpo = JSON.parse(texto);
    } catch {
      return c.json({ error: 'corpo invalido' }, 400);
    }

    // UM ponto de decisao: allowlist de metricas e k-anonimato juntos, pela
    // mesma funcao que um produtor usaria para decidir se pode enviar. Duas
    // checagens em lugares diferentes divergiriam, e a que ficasse para tras
    // aceitaria o que a outra recusa.
    if (!isAcceptableBatch(corpo)) {
      // A recusa NAO diz qual campo falhou. Um endpoint publico que explica o
      // formato aceito ensina a forjar lote valido; e um produtor legitimo tem o
      // schema do contrato, nao precisa da mensagem.
      return c.json(
        { error: `lote recusado: exige coorte agregada com k >= ${K_ANONYMITY_MIN}` },
        422,
      );
    }

    const db = createDb(client);
    const cohortKey =
      `${corpo.cohort.municipality}|${corpo.cohort.appVersion}|${corpo.cohort.packVersion}`;

    try {
      await db.insert(telemetryBatch).values({
        id: randomUUID(),
        cohortKey,
        bucketDay: corpo.bucketDay,
        metricsJson: JSON.stringify(corpo.metrics),
        kCount: corpo.kCount,
        receivedAt: new Date().toISOString(),
      });
    } catch (erro) {
      if (classificarViolacao(erro) === 'duplicidade') {
        // Somar em silencio esconderia defeito de produtor: dois lotes para a
        // mesma coorte no mesmo dia significam ou reenvio, ou dois agregadores
        // contando a mesma populacao. As duas coisas precisam ser vistas.
        return c.json({ error: 'ja existe lote para esta coorte neste dia' }, 409);
      }
      throw erro;
    }

    // 202: aceito para processamento, sem prometer que ja esta refletido em
    // relatorio nenhum.
    return c.json({ ok: true }, 202);
  });
}
