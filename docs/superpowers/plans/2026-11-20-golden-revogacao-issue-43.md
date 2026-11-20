# Golden: revogação auditada, desativação de caso e `reviewed_hash` (#43) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar os limites D4 e D7 da §5.17: revisão golden vinculada ao conteúdo por hash, revogação auditada de revisão e desativação de caso por rota, sem DELETE físico.

**Architecture:** `golden_case_review` ganha `reviewed_hash` (SHA-256 do conteúdo canônico do caso). Revogação é linha numa tabela nova append-only, `golden_case_review_revocation`. Dois conceitos, usados em lugares diferentes:
- **revisão não revogada**: unicidade (gatilho `one_live` e a pré-checagem da rota): no máximo uma por (caso, atestado), com qualquer hash.
- **revisão válida** = não revogada **e** `reviewed_hash` igual ao conteúdo atual: é a única que conta no portão (extract do packer) e no quórum de ativação (rota e importador).

Desativação é `golden_case.deactivated_at` + `active = 0`. Ser definitiva e a recusa para red flag são **gatilhos do banco**, não regras da rota: checagem só na rota protege apenas contra quem passa pela rota (`cms/src/db/triggers.ts:139-143`).

**Tech Stack:** TypeScript, Hono, Drizzle/libSQL, `node:test`, WebCrypto (`globalThis.crypto.subtle`).

**Spec:** issue #43 (`gh issue view 43`); `spec/arquitetura.md` §5.17 (D4, D7, D8, D10, "Limites conhecidos"); `docs/revisao-golden.md` §4 (linha "caso mal construído": retirada **nunca** para caso de red flag).

## Global Constraints

- Sem DELETE físico em `golden_case_review`; a tabela segue em `APPEND_ONLY_TABLES`. A tabela nova também entra lá e no piso literal de `cms/test/append-only.test.ts`.
- Papel: as rotas novas exigem `requirePermission('approval:decide')` (só `clinical_reviewer` tem; `cms/src/auth/permissions.ts`).
- **Desativação por um único `clinical_reviewer` é aceita de propósito** (o §4 fala em "dono, com o revisor"): o motivo, a trilha e a recusa de red flag no banco substituem a segunda pessoa. O PR diz isso explicitamente, e o `revisao-golden.md` §4 é atualizado para refletir a regra.
- Motivo obrigatório: `motivo.trim().length >= 10` na rota; no banco, `CHECK (length(trim(reason, ' ' || char(9,10,13))) >= 10)` (o `trim()` do SQLite sem 2º argumento só tira espaço; o do JS tira qualquer espaço em branco).
- **Motivo sem dado pessoal** (LGPD; mesmo motivo de `cms/src/routes/golden.ts:160-162`): o motivo vai para duas tabelas append-only, e uma cópia ali não sai com o expurgo do atestado. A rota recusa com 422 o motivo que contém o `nome` (sem diferença de maiúscula e acento) ou o `registro` (como sequência inteira de dígitos, `\b<registro>\b`) de qualquer `golden_attestation`. O manual diz para citar o profissional só pelo `AT-`.
- Toda ação nova vai à trilha via `recordAudit`, com nome começando por `golden_` (já em `ACOES_QUE_REABREM` por prefixo; não acrescentar a `ACOES_QUE_NAO_REABREM`).
- Suíte sem nenhum caso ativo continua bloqueando (`golden_vazia`, `packer/src/validate.ts:216`).
- Red flag = severidade de `expected_outcome_id` não estritamente menor que `MAX(severity_level)` de `routing_outcome`. Desfecho inexistente ou tabela vazia também recusa (fail-closed). A escala é do pack (ADR-008): nenhum limiar fixo.
- `contract/` é importado por `cms/web` (navegador): **proibido `node:crypto` em `contract/src`**.
- Quórum sempre por `COUNT(DISTINCT r.attestation_id)`, para continuar valendo como defesa extra se o gatilho faltar.
- Sem atribuição de IA em commits. Rota nova exige linha em `docs/operacao.md` (`doc-operacao.test.ts`).

## Review Focus

1. **Mesmo profissional corrige a própria data** (revoga e registra de novo com o mesmo `AT-`): hoje o `UNIQUE(case_id, attestation_id)` impede isso, e tem de passar a funcionar. Teste na Task 3.
2. **Importador reinsere revisão revogada** (o YAML ainda lista o mesmo atestado com a mesma data) vira conflito, sem nenhuma escrita. Teste na Task 4.
3. **Revisão ou importação depois de uma desativação** não reativa o caso, nem por rota, nem por importador, nem por SQL direto. Testes nas Tasks 2, 3 e 4.
4. **Linha legada com `reviewed_hash` NULL**: no portão conta como ausente, com diagnóstico; na rota, 409 "revogue a revisão anterior"; no importador, conflito, nunca `mantidos`. Testes nas Tasks 2, 3 e 4.
5. **Revogação que derruba o quórum a zero**: o caso continua `active = 1` e o portão o reprova dizendo por quê, em vez de ele sumir da suíte. Teste na Task 2.

---

### Task 1: Hash canônico do conteúdo no contrato

**Files:**
- Modify: `contract/src/golden.ts`
- Test: `contract/test/golden.test.ts`

**Interfaces:**
- Produces: `export async function hashConteudoGolden(tokens: readonly string[], expect: string): Promise<string>`: SHA-256 hex minúsculo (64) de `JSON.stringify([tokens, expect])`. Comentário de uma linha: o `evaluate` usa `new Set(tokens)` e ignora a ordem, mas a ordem entra no hash porque é o que o revisor leu. Reordenar invalida a revisão, e isso só pode errar para o lado seguro.
- Produces: `export const SQL_REVISAO_NAO_REVOGADA = 'NOT EXISTS (SELECT 1 FROM golden_case_review_revocation v WHERE v.review_id = r.id)'`: exige o alias `r` para `golden_case_review`. Fonte única para a rota, o importador, o extract e o gatilho.

- [ ] **Step 1: Testes que falham**

```ts
test('hashConteudoGolden e estavel, hex de 64 e sensivel a tokens, ordem e desfecho', async () => {
  const h = await hashConteudoGolden(['chest', 'pain'], 'EMERGENCY');
  assert.match(h, /^[0-9a-f]{64}$/);
  assert.equal(h, await hashConteudoGolden(['chest', 'pain'], 'EMERGENCY'));
  assert.notEqual(h, await hashConteudoGolden(['pain', 'chest'], 'EMERGENCY'));
  assert.notEqual(h, await hashConteudoGolden(['chest', 'pain'], 'ROUTINE_UBS'));
  // fronteira: concatenacao ingenua confundiria estes dois
  assert.notEqual(await hashConteudoGolden(['a', 'b'], 'c'), await hashConteudoGolden(['a'], 'bc'));
});
test('contract/src nao importa node:crypto (cms/web consome o contrato no navegador)', () => {
  const src = join(import.meta.dirname, '..', 'src');
  for (const f of readdirSync(src)) assert.doesNotMatch(readFileSync(join(src, f), 'utf8'), /node:crypto/);
});
```

- [ ] **Step 2:** `npm --workspace @guia-ubs/contract test` → FAIL (`hashConteudoGolden` não exportado).
- [ ] **Step 3:** Implementar as duas exportações (`crypto.subtle.digest('SHA-256', new TextEncoder().encode(...))`).
- [ ] **Step 4:** Mesmo comando → PASS; `npm run typecheck` verde.
- [ ] **Step 5:** `git commit -m "feat(contract): hash canonico do conteudo do caso golden (#43)"`

---

### Task 2: Schema, migração 0010, gatilhos e portão no extract

**Files:**
- Modify: `cms/src/db/schema/publishing.ts`, `cms/src/db/schema/index.ts` (`APPEND_ONLY_TABLES`)
- Modify: `cms/src/db/triggers.ts` + regenerar `cms/src/db/triggers.sql`
- Create: `cms/src/db/migrations/0010_*.sql` (via `npm run cms:generate`)
- Modify: `packer/src/extract.ts` (`lerGoldenDoBanco`), `packer/src/validate.ts` (mensagem de `golden_sem_revisor`)
- Modify (fixtures que a mudança quebra): `packer/test/pipeline.test.ts` (revisões `rv-0` ~l.125 e as de ~l.513 e ~l.573 ganham `reviewed_hash` calculado com `hashConteudoGolden` do caso correspondente; sem isso `g-toracico` fica sem revisor e `o job constroi, assina...` e `lerGoldenDoBanco monta reviewed_by` caem), `cms/test/support/db.ts`, `cms/test/append-only.test.ts`
- Test: `packer/test/pipeline.test.ts`, `cms/test/migrations.test.ts`, `cms/test/append-only.test.ts`

**Interfaces:**
- Consumes: Task 1.
- Produces (schema):
  - `golden_case.deactivated_at TEXT NULL` (`deactivatedAt`).
  - `golden_case_review.reviewed_hash TEXT NULL` (`reviewedHash`), com `check('golden_case_review_hash_hex', ...)` no molde de `golden_attestation_termo_hex`, aceitando NULL (linha legada). **Remove** `unique('golden_case_review_case_attestation')`.
  - `goldenCaseReviewRevocation` = `golden_case_review_revocation(id PK, review_id NOT NULL UNIQUE FK→golden_case_review.id, reason NOT NULL, revoked_by NOT NULL FK→admin_user.id, revoked_at NOT NULL)` + o CHECK do motivo das Global Constraints. Em `APPEND_ONLY_TABLES` com `requirement: '#43'`.
- Produces (gatilhos em `triggers.ts`; mensagens começam com o texto que `classificarViolacao` já reconhece, comentado numa linha):
  - `golden_case_review_one_live`: `BEFORE INSERT ON golden_case_review WHEN EXISTS (SELECT 1 FROM golden_case_review r WHERE r.case_id = NEW.case_id AND r.attestation_id = NEW.attestation_id AND ${SQL_REVISAO_NAO_REVOGADA})` → `RAISE(ABORT, 'UNIQUE constraint failed: golden_case_review revisao nao revogada do mesmo atestado')` → `duplicidade`.
  - `golden_case_deactivation_final`: `BEFORE UPDATE ON golden_case WHEN OLD.deactivated_at IS NOT NULL AND (NEW.active <> 0 OR NEW.deactivated_at IS NOT OLD.deactivated_at)` → `RAISE(ABORT, 'CHECK constraint failed: golden_case desativado e definitivo')`.
  - `golden_case_no_deactivate_red_flag`: `BEFORE UPDATE ON golden_case WHEN OLD.deactivated_at IS NULL AND NEW.deactivated_at IS NOT NULL AND NOT COALESCE((SELECT severity_level FROM routing_outcome WHERE id = NEW.expected_outcome_id) < (SELECT MAX(severity_level) FROM routing_outcome), 0)` → `RAISE(ABORT, 'CHECK constraint failed: golden_case red flag nao se desativa')`. O `COALESCE(..., 0)` recusa quando o desfecho não existe ou a tabela está vazia.
- Produces (portão): `lerGoldenDoBanco` lê todas as revisões com o hash e a marca de revogação; em `reviewed_by` entram só as **válidas** (não revogada e `reviewed_hash === await hashConteudoGolden(tokens, expect)`). O tipo `GoldenCase` (`packer/src/validate.ts`) ganha `descartadas?: { revogadas: number; conteudoMudou: number }`, preenchido só quando alguma foi descartada (hash NULL conta como `conteudoMudou`). Quando `descartadas` existe, a mensagem de `golden_sem_revisor` termina com `" (N revogada(s), M de conteudo anterior ou sem vinculo; registre nova revisao)"`. O `kind` não muda.

- [ ] **Step 1: Testes do portão que falham** (`packer/test/pipeline.test.ts`):
  - `revisao revogada nao conta: caso ativo sem outra revisao fica com reviewed_by null e descartadas.revogadas 1`: o caso continua presente (Review Focus 5).
  - `revisao com reviewed_hash divergente conta como ausente`: revisão com hash certo, depois `UPDATE golden_case SET tokens_json = '["chest"]'` → `reviewed_by === null`, `descartadas.conteudoMudou === 1`.
  - `revisao legada com reviewed_hash NULL conta como ausente` (Review Focus 4).
  - `revisao valida continua contando`: controle positivo, `reviewed_by.length === 1` e sem `descartadas`.
  - `golden_sem_revisor diz quantas revisoes foram descartadas e por que`: `validateGolden` com um caso com `descartadas` → a mensagem contém `revogada`.
  - `caso desativado sai da suite e o ultimo desativado da golden_vazia`: dois casos ativos; `UPDATE ... SET active = 0, deactivated_at = ...` (o mesmo SQL da rota) num deles → `lerGoldenDoBanco` devolve 1 e o `total` da corrida cai; desativar o outro → `golden_vazia`.
- [ ] **Step 2: Testes de banco que falham** (`cms/test/append-only.test.ts`, `cms/test/migrations.test.ts`):
  - O piso literal ganha `'golden_case_review_revocation'`; UPDATE e DELETE nela abortam.
  - `segunda revisao nao revogada do mesmo atestado aborta como duplicidade; revogada a primeira, entra`.
  - `revogacao com motivo so de espacos e tabs viola CHECK`; `segunda revogacao da mesma revisao viola UNIQUE`.
  - `caso desativado nao volta: UPDATE active=1 aborta, UPDATE deactivated_at=NULL aborta` (Review Focus 3, SQL direto).
  - `desativar por SQL caso de severidade maxima aborta; com desfecho inexistente aborta; com routing_outcome vazia aborta; caso de rotina passa`.
  - **Corrigir** `todo gatilho do triggers.sql existe`: hoje aplica só até a 0009 e depois o `triggers.sql` atual, que agora tem gatilho `ON golden_case_review_revocation` → `no such table`. Passa a aplicar até a 0010.
  - **Novo, no molde de `golden_case ativo e sem revisor sobrevive a 0009`**: `revisao anterior a 0010 sobrevive com reviewed_hash NULL e os gatilhos novos existem`: aplica até a 0009, insere caso + atestado + revisão, aplica a 0010 + `triggers.sql`, confere a linha intacta, `reviewed_hash IS NULL` e os quatro gatilhos (`one_live`, `deactivation_final`, `no_deactivate_red_flag` e o append-only da tabela nova) em `sqlite_master`.
  - Em `cms/test/support/db.ts`: linha de exemplo da tabela nova (`review-1` revogada, motivo fictício) e `reviewed_hash` na de `golden_case_review`. Sem isso o teste de append-only roda zero asserções.
- [ ] **Step 3:** `npm test` → FAIL nos novos.
- [ ] **Step 4:** Editar o schema; `npm run cms:generate`; gatilhos em `triggers.ts`; `npm run cms:triggers`; ajustar `lerGoldenDoBanco`, `GoldenCase` e a mensagem; corrigir as fixtures do pipeline.
- [ ] **Step 5:** `npm test`, `npm run cms:check`, `npm run typecheck` → verdes.
- [ ] **Step 6:** `git commit -m "feat(cms,packer): reviewed_hash, revogacao append-only, desativacao definitiva no banco e portao so com revisao valida (#43)"`

---

### Task 3: Rotas de revogação e desativação; rota de revisão grava hash

**Files:**
- Modify: `cms/src/routes/golden.ts`
- Test: `cms/test/golden-routes.test.ts`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: `async function motivoComDadoPessoal(client: Client, motivo: string): Promise<boolean>` em `cms/src/routes/golden.ts`. Compara contra todos os `golden_attestation`, com nome normalizado (`normalize('NFD')`, sem diacríticos, minúsculo) e registro como `\b<registro>\b`.
- Produces (HTTP, todas `approval:decide`, corpo `{ motivo: string }`):
  - `POST /api/golden-cases/:id/revisores/:atestado/revogar`: identifica a revisão pelo `AT-`, que é o que o operador tem no formulário. Não existe GET, e o UUID nunca chega a ele. Alvo = a revisão **não revogada** de (caso, atestado), única pelo gatilho. Respostas:
    - 201 `{ ok, caso, atestado, active }`;
    - 404 caso inexistente ou sem revisão não revogada desse atestado (o que já cobre "revisão de outro caso");
    - 422 motivo curto ou com dado pessoal.
    - **Caso desativado é permitido**: corrigir o registro não reativa nada.
    - Trilha `golden_review_revoke`, `entityType: 'golden_case'`, `entityId: caseId`, `after: { atestado, motivo }`.
  - `POST /api/golden-cases/:id/desativar`: `UPDATE golden_case SET active = 0, deactivated_at = ? WHERE id = ? AND deactivated_at IS NULL`. Respostas:
    - 200 `{ ok, caso, active: 0 }`;
    - 404 caso inexistente;
    - 409 se o UPDATE afetou 0 linhas (já desativado);
    - 422 motivo inválido ou com dado pessoal;
    - erro `dominio` do gatilho de red flag → 422 `{ error: 'caso de severidade maxima (red flag) nao se desativa', next: 'docs/revisao-golden.md §4' }`. A rota **não** reimplementa a regra.
    - Trilha `golden_case_deactivate`, `before: { active }`, `after: { active: 0, motivo }`.
- Muda `POST /:id/revisores`:
  - grava `reviewed_hash` do conteúdo atual;
  - caso com `deactivatedAt` → 409 `{ error: 'caso desativado' }`;
  - a pré-checagem de duplicidade passa a usar só "não revogada", qualquer hash (a mesma definição do gatilho), e a mensagem do 409, pré-checada ou vinda do gatilho, vira `'este atestado ja tem revisao neste caso; revogue a anterior em POST /api/golden-cases/<id>/revisores/<atestado>/revogar'`;
  - o UPDATE de ativação passa a ser `... AND deactivated_at IS NULL AND (SELECT COUNT(DISTINCT r.attestation_id) FROM golden_case_review r WHERE r.case_id = ? AND r.reviewed_hash = ? AND ${SQL_REVISAO_NAO_REVOGADA}) >= ?`;
  - o comentário de cabeçalho é atualizado, porque a revogação agora existe.

- [ ] **Step 1: Testes que falham.** Mover a criação dos desfechos (`ROUTINE_UBS` 10 e `EMERGENCY` 100, hoje dentro do último teste, ~l.278–283) para um helper `desfechos()` chamado no `before`. Novos testes:
  - `revogar sem approval:decide responde 403`; `desativar sem approval:decide responde 403`.
  - `revogar com motivo curto responde 422`; `revogar com motivo contendo nome do profissional (sem acento) ou o registro responde 422 e nada grava`; idem em `desativar`.
  - `revogar atestado sem revisao neste caso responde 404 e nao grava` (o atestado revisou outro caso).
  - `revogar registra golden_review_revoke e after_json nao contem nome nem registro`.
  - `revogar duas vezes: a segunda responde 404`.
  - `mesmo atestado corrige a data: revoga e registra de novo` → 201; uma só não revogada (Review Focus 1).
  - `revisao legada sem hash: nova revisao responde 409 mandando revogar; depois de revogar entra` (Review Focus 4; a linha legada é inserida via `f.client`).
  - `revisao grava reviewed_hash igual a hashConteudoGolden(CASO.tokens, CASO.expect)`.
  - `desativar caso de rotina: active 0, deactivated_at preenchido, trilha golden_case_deactivate`.
  - `desativar caso EMERGENCY responde 422 e nada muda`; `desativar caso com desfecho inexistente responde 422`; `desativar duas vezes responde 409`.
  - `revisao em caso desativado responde 409 e o caso segue inativo` (Review Focus 3).
  - `revogar revisao de caso desativado e permitido e o caso segue inativo`.
  - `caso desativado sai da simulacao` (a contagem que o CMS enxerga, por `rule-simulation.ts:118`): estende o teste `a simulacao enxerga o caso recem-ativado`, que já existe, desativando o caso e conferindo que ele some.
  - `desativar pela rota tira o caso da suite do packer; desativar o ultimo da golden_vazia` (critério de aceite da issue, ponta a ponta). Dois casos de rotina são ativados por revisão via rota e desativados um por vez via rota. Depois de cada desativação, `lerGoldenDoBanco(f.client)` devolve um caso a menos, e o `total` de `validateGolden(casos, { rules: [], outcomes: <ROUTINE_UBS/EMERGENCY>, defaultOutcomeId: 'ROUTINE_UBS', tokenIds: <tokens do CASO> }, { modo: 'verificacao', agora: new Date(), registro: [] })` cai junto. Depois do último, a lista de issues contém `kind: 'golden_vazia'`. Import relativo `../../packer/src/extract.js` e `../../packer/src/validate.js`, o espelho do que `packer/test/pipeline.test.ts` já faz com o `cms`. Conferir o nome exato do modo em `ModoRevisao`.
  - `nao ha PUT nem DELETE de revisao` continua verde.
- [ ] **Step 2:** `npm --workspace @guia-ubs/cms test` → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Mesmo comando → PASS; `cms/test/audit-acoes.test.ts` verde (prefixo `golden_`).
- [ ] **Step 5:** `git commit -m "feat(cms): revogacao auditada de revisao e desativacao de caso golden por rota (#43)"`

---

### Task 4: Importador respeita revogação, hash e desativação

**Files:**
- Modify: `cms/src/services/golden-import.ts`
- Test: `cms/test/golden-import.test.ts`

**Interfaces:**
- Consumes: Tasks 1–2.
- Mudanças: para cada caso existente, ler **todas** as revisões dele com `reviewed_hash` e a marca de revogação (alias `r`, `${SQL_REVISAO_NAO_REVOGADA}`). Para cada revisor do YAML:
  - existe não revogada com o hash atual e a mesma data → nada a fazer (conta para `mantidos`);
  - existe não revogada com data diferente → conflito, como hoje;
  - existe não revogada com hash NULL ou divergente → conflito `'<AT>: revisao no CMS sem vinculo ao conteudo atual; revogue no CMS e importe de novo'`;
  - não existe não revogada, mas existe **revogada com a mesma data** → conflito `'<AT>: revisao revogada no CMS; corrija o YAML'`;
  - nenhum dos casos acima → acrescenta.
- Caso existente com `deactivated_at` → conflito `'caso desativado no CMS; retire-o do YAML por PR (docs/revisao-golden.md §4)'`. Pela D8, a importação inteira não acontece: o CMS não pode ficar em silêncio com uma suíte menor que a do repositório.
- O `INSERT` grava `reviewed_hash`. O UPDATE de ativação é o mesmo da rota (`deactivated_at IS NULL`, `COUNT(DISTINCT ...)` só de válidas).

- [ ] **Step 1: Testes que falham:**
  - `importar grava reviewed_hash igual a hashConteudoGolden`.
  - `revisao revogada no CMS e YAML com a MESMA data: conflito, nada escrito, nenhuma linha nova em golden_case_review` (Review Focus 2).
  - `revisao revogada no CMS e YAML com outra data: acrescenta a nova`.
  - `revisao legada sem hash no CMS: conflito, nunca mantidos` (Review Focus 4).
  - `caso desativado no CMS ainda no YAML: conflito, nada escrito, caso segue inativo` (Review Focus 3).
- [ ] **Step 2:** `npm --workspace @guia-ubs/cms test` → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** PASS, e `npm test` inteiro verde.
- [ ] **Step 5:** `git commit -m "feat(cms): importador golden nao desfaz revogacao nem desativacao (#43)"`

---

### Task 5: Sabotagem (critério de aceite da issue)

Remover qualquer proteção nova tem de fazer algum teste falhar. Para cada item: aplicar a sabotagem, rodar `npm test`, anotar qual teste caiu e reverter. Proteção que nenhum teste pega ganha teste antes de seguir, como aconteceu com S2 e S8 na §5.16.

| # | Sabotagem | Teste que deve cair |
|---|---|---|
| S1 | `lerGoldenDoBanco` sem a comparação de hash | `revisao com reviewed_hash divergente...` |
| S2 | `lerGoldenDoBanco` sem `SQL_REVISAO_NAO_REVOGADA` | `revisao revogada nao conta...` |
| S3 | UPDATE de ativação da rota sem o `NOT EXISTS` | teste de rota: revoga a única revisão de um caso inativo e registra outro atestado com hash antigo, e o caso **não** ativa (acrescentar se faltar) |
| S4 | rota sem `AND deactivated_at IS NULL` | `revisao em caso desativado...` |
| S4b | `UPDATE` da rota `desativar` sem `active = 0` | `desativar pela rota tira o caso da suite do packer...` |
| S5 | importador sem `AND deactivated_at IS NULL` / sem o conflito de desativado | `caso desativado no CMS ainda no YAML...` |
| S6 | gatilho `no_deactivate_red_flag` removido | `desativar caso EMERGENCY responde 422` e o de SQL direto |
| S7 | gatilho `deactivation_final` removido | `caso desativado nao volta...` |
| S8 | gatilho `one_live` removido | `segunda revisao nao revogada...` |
| S9 | `golden_case_review_revocation` fora de `APPEND_ONLY_TABLES` | piso literal do append-only |
| S10 | `motivoComDadoPessoal` devolvendo sempre `false` | `revogar com motivo contendo nome...` |
| S11 | importador sem o conflito de revogada com a mesma data | `revisao revogada no CMS e YAML com a MESMA data...` |

- [ ] **Step 1:** Rodar S1–S11 e registrar o resultado em `spec/arquitetura.md` (Task 6), no formato da §5.17 ("Sabotagem: N proteções, N pegas").
- [ ] **Step 2:** `git commit` só se algum teste foi acrescentado: `test(cms,packer): fecha sabotagem sem teste (#43)`.

---

### Task 6: Documentação e registro

**Files:**
- Modify: `docs/operacao.md` §4.5b. Duas linhas na tabela de rotas, mais um exemplo `curl` de revogar (`/revisores/AT-NNNN/revogar`) e de desativar. Notas:
  - o motivo cita o profissional só pelo `AT-`;
  - linha legada sem hash precisa ser revogada antes de um novo registro;
  - caso desativado ainda presente no YAML trava o `cms:import-golden` até o PR de retirada.
- Modify: `docs/revisao-golden.md` §4. Retirada de caso mal construído passa a ser `POST .../desativar` por um `clinical_reviewer`, com motivo, mais o PR que tira o caso do YAML. Red flag continua proibida, e quem recusa agora é o banco.
- Modify: `spec/arquitetura.md`:
  - §5.17: riscar os três limites da #43, dizer o que os fechou, a decisão de uma pessoa só na desativação e o resultado da sabotagem;
  - §Roadmap.
- Modify: `CLAUDE.md`, na linha "golden_case_review e append-only": revisão errada se corrige por revogação auditada, identificada pelo `AT-`, sem DELETE; caso desativado é definitivo no banco.
- Test: `cms/test/doc-operacao.test.ts`

- [ ] **Step 1:** `npm --workspace @guia-ubs/cms test -- --test-name-pattern operacao` → FAIL enquanto as rotas não estiverem no manual.
- [ ] **Step 2:** Editar os quatro documentos (pt-BR).
- [ ] **Step 3:** `npm test` → PASS.
- [ ] **Step 4:** `git commit -m "docs: revogacao e desativacao golden no manual, no roteiro e na 5.17 (#43)"`

---

## Fora de escopo (dizer no PR)

- O caminho `seed/` (YAML) não ganha `reviewed_hash`: lá a revisão e o conteúdo mudam no mesmo diff de PR, revisado por pessoa. A issue limita o hash a `golden_case_review`.
- Sem reativação de caso desativado (o banco a recusa): o substituto entra como caso novo (D10).
- Sem rota GET nem tela no `cms/web`: a revogação usa o `AT-`, que o operador já tem.
- Desativação por uma só pessoa (`clinical_reviewer`), aceita conforme as Global Constraints.
