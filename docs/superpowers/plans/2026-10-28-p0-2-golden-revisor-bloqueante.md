# P0-2 — Caso golden sem revisor vira portão bloqueante — Plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar tarefa a tarefa. Passos usam checkbox (`- [ ]`).

**Objetivo:** todo caminho que produz pack assinado (`packer build`, `packer publish`, worker) recusa assinar com caso golden sem revisão clínica válida. A revisão referencia um atestado de profissional, com ID atribuído uma única vez num registro público sem dado pessoal. Nome e registro ficam só no CMS e no termo. A revisão dos 24 casos fica preparada como etapa humana separada, com regra explícita para discordância.

**Arquitetura:** `contract/src/golden.ts` define o formato e as funções `avaliarRevisao` e `avaliarAtestado`, que devolvem `ausente | invalida | valida`. `seed/golden/atestados.yaml` é a **fonte única dos IDs** de atestado (`id`, `conselho`, `uf`, `categoria`, `termo_sha256`), e todo caminho confere que um atestado citado existe ali e coincide. No packer, o modo (`assinatura` ou `verificacao`) deriva do mesmo booleano que decide se haverá assinatura. No CMS, a revisão sai da FK para `admin_user` e passa a `golden_attestation` (o profissional, com o ID do registro) mais `golden_case_review` (append-only). Release bloqueada continua em `approved` com `blocked_at`, e só volta à fila depois de uma escrita de conteúdo auditada. Os dois instantes vêm do relógio do banco.

**Stack:** TypeScript (Node ≥ 22, `node:test` via `tsx`), Zod 4, Hono, Drizzle + libSQL/`sqld`, `yaml` 2.

**Spec:** issue #2 (P0-2), em `docs/superpowers/issues/2026-10-28/P0-2.md`; `spec/PRD.md` §6.3 R5 (l. 312); `spec/arquitetura.md` §5.12, lacuna 6 (l. 1050); `spec/lgpd.md` §1 (l. 12), LGPD-RF04 (l. 47), RF07; `docs/superpowers/plans/2026-10-28-levantamento-estado-projeto.md` (l. 28, 295); `CLAUDE.md` §"Publicacao: dual review e o job".

## Decisões do dono (2026-10-28)

- **D3 = opção A**, com o registro público `seed/golden/atestados.yaml` como fonte única dos IDs. O critério de aceite da issue muda de "nome(s) do(s) revisor(es)" para "**atestado, conselho, UF e categoria** do(s) revisor(es)". A mudança é registrada na própria issue #2 (Task 8 Step 6).
- **D10:** a pergunta do formulário passa a ser "o desfecho esperado é **clinicamente seguro**?". Entra a resposta "**concordo: seguro, mas mais cauteloso que o ideal**". A retirada fica reservada para caso mal construído.
- **Merge do portão agora: sim.** O MinIO de produção, se existir, fica congelado, e isso é aceitável antes do piloto.

## Restrições globais

- **Fora do escopo:** conteúdo clínico dos casos (`tokens`, `expect`, `note`), simulação de regras (`cms/src/services/rule-simulation.ts`), interface web do CMS.
- **Nenhum dado pessoal de revisor no repositório.** `clinical_cases.yaml` e `atestados.yaml` reais só recebem dados na Task 9, e nunca nome nem registro. Nenhum dado fictício, de exemplo ou provisório nesses dois arquivos. Fixtures fictícias só em `*/test/` (`Revisora Ficticia Teste`, `AT-9001`…).
- **Nenhum teste depende do estado de revisão do seed real.** Todo teste de portão monta os próprios casos e o próprio registro. Teste que lê os YAMLs reais afirma só o que vale em qualquer estado de revisão (D9).
- **Não existe flag para pular portão** (`packer/src/index.ts:8-10`). O modo aviso só é selecionado por "não vai assinar".
- Conselhos: `CRM`, `COREN`. Categorias COREN aceitas: só `ENF`. UFs: as 27 — `AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO`. ID de atestado: `^AT-\d{4}$`.
- `reviewed_at`: `AAAA-MM-DD`, data de calendário válida, não posterior à data UTC de `agora`, **por revisor**.
- Instante comparado entre processos (`blocked_at`, `audit_entry.occurred_at`) é gerado pelo banco: `strftime('%Y-%m-%dT%H:%M:%fZ','now')`.
- Rota, variável de ambiente ou script novo exige linha em `docs/operacao.md` (`cms/test/doc-operacao.test.ts`). Tabela append-only nova exige linha em `cms/test/support/db.ts#APPEND_ONLY_ROWS`.
- Ao fim de cada tarefa: `npm run typecheck && npm test` verdes. Schema do CMS: `npm run cms:check`. Contrato: `npm run contract:check`.
- pt-BR, sem acento em código (padrão do repositório). Commits `tipo(escopo): descrição (#2)`, **sem** atribuição de IA.

## Estado confirmado no código (2026-10-28)

| Item | Achado | Bate com a issue? |
|---|---|---|
| `packer/src/index.ts:104-111` | aviso de `golden.unreviewed`; `blocking` soma só `referential` e `golden.issues` | sim |
| `packer/src/validate.ts:162` | só conta `!testCase.reviewed_by`; campo `string \| null` livre | sim |
| `packer/src/worker.ts:220-249` | assina com caso sem revisor; com `--no-publish` também assina e move para `built` | sim |
| `packer/src/worker.ts:65-73, 285-299`; `infra/compose.yaml:101` | `proximaAprovada` pega a `approved` mais antiga; o laço do compose (`--interval 60`) reivindica a mesma release bloqueada a cada minuto, **sem backoff** (pack reconstruído, 1 `golden_run`, 2 `audit_entry` por volta). Por ser FIFO, **trava as releases mais novas** | — |
| `cms/src/services/audit.ts:90`; `packer/src/worker.ts:93,126` | `occurred_at` e os instantes do worker vêm do relógio JS do processo (`toISOString()`, formato `YYYY-MM-DDTHH:MM:SS.sssZ`, igual ao de `strftime('%Y-%m-%dT%H:%M:%fZ')`). CMS e worker rodam em containers distintos | — (D11) |
| `cms/src/auth/middleware.ts:83-88, 210-217` | `sign_in`, `two_factor_enable/disable/verify` entram em `audit_entry` **com `actor_id`** (resolvido por `resolveAtor`) | — (D11: login não pode reabrir release) |
| Ações com ator hoje (`recordAudit` em `cms/src`) | `content_create/update/delete/translate`, `content_binario_upload`, `rule_create/update/revise`, `release_create/submit/requeue/revoke`, `user_create/role_change`, as de autenticação | — (D11) |
| `seed/golden/clinical_cases.yaml` | 24 casos, todos `reviewed_by: ~`, nenhum `reviewed_at` | sim |
| `cms/src/db/schema/publishing.ts:133` | `golden_case.reviewed_by` é **FK para `admin_user.id`** | **não** — divergência 2 |
| `cms/src/routes/`, `content/registry.ts` | **não há rota** de `golden_case`; só `import-golden.ts` escreve | **não** — divergência 1 |
| `cms/scripts/import-golden.ts:56-60` | `reviewed_by NULL, active 1 ... ON CONFLICT(id) DO NOTHING` | **não** — divergência 3 |
| `cms/src/db/triggers.sql` | nenhum gatilho em `golden_case` hoje | — |
| `cms/src/routes/releases.ts:154` | `POST /:id/reenfileirar` trata só `building → approved` | — (não serve para D11) |
| `packer/src/build-pack.ts`, `contract/src/content-schema.ts` | golden **não** entra no `content.db` nem no manifest | — (nada vai ao aparelho) |
| `app/test/triage/golden_clinical_test.dart:60-62` | lê o mesmo YAML, só `id`, `tokens`, `expect` | — |
| `.github/workflows/contract.yml:63` | CI roda só `pack:check` (= `build --dry-run`) | sim |
| `app/lib/sync/pack_signing_keys.dart:53` | a chave dev `k1` é a padrão de APK sem `--dart-define` | — (divergência 4) |
| `gh repo view` | repositório **público** | — (D3) |
| Cadastro do COREN-RR ("Nossa equipe", corenrr.com.br) | inscrições publicadas na forma número, com ou sem ponto, seguido da **categoria** como sufixo (exemplos fictícios: `123.456-ENF`, `654321-TE`, `9876 – ENF`, `12.345-ENF-IR`; os números reais do cadastro não são reproduzidos aqui). O Cofen lista `ENF`, `OBST`, `TE`, `AE`, `PAR` (anexo da Res. 560/2017, com alterações até a 691/2022) | — (D2) |

### Mapa dos caminhos que assinam

| Caminho | Assina? | Distribuível? | Modo |
|---|---|---|---|
| `npm run pack:check` → `packer build --dry-run` (CI de PR) | não | não | `verificacao` |
| `packer publish --dry-run` | não | não | `verificacao` |
| `npm run pack:build` → `packer build` | **sim** (`packer/out/manifest.json`) | **sim**: um `mc cp` publica, e a chave dev é aceita por APK sem `--dart-define` | `assinatura` |
| `npm run pack:publish` → `packer publish` | sim, e envia | sim | `assinatura` |
| `packer/src/worker.ts` (com ou sem `--no-publish`) | sim (`pack_release.manifest_json`) | sim | `assinatura` (fixo) |
| testes `packer/test/*` | chave efêmera | não | explícito por teste |

### Divergências em relação à issue

1. **Não existe rota de `golden_case`.** O plano cria `cms/src/routes/golden.ts` com o mínimo: cadastrar caso (sempre inativo), registrar atestado e acrescentar revisor. Não há rota para editar `tokens`/`expect` (D4).
2. **No banco, `reviewed_by` é FK para operador do CMS.** O formato da issue descreve um profissional, que pode não ter conta. A FK sai (D6).
3. **"Reimportar com `cms:import-golden`" não funcionaria** (`ON CONFLICT DO NOTHING`). O importador passa a acrescentar revisores a caso com conteúdo idêntico, e nunca remove nem troca revisor.
4. **`packer build` sem `--dry-run` também assina**, logo entra no modo `assinatura` (D5).
5. **`reviewed_at` mora em cada revisor, não no caso** (D1).
6. **Com a opção A, nome e registro não ficam no YAML.** O formato completo (nome, conselho, UF, categoria, registro) é validado na rota do CMS e no caminho do worker. No caminho `seed/`, o packer valida o que está no YAML e confere o atestado contra `atestados.yaml`.
7. **Critério "nomes na issue e em `arquitetura.md`"** passa a "atestado, conselho, UF e categoria", por decisão do dono, registrada na issue.

## Decisões

**D1 — Lista de revisores, mínimo 1, sem duplicata, data por revisor.** `reviewed_by` é `RevisorYaml[]` com `min(MIN_REVISORES)` e `MIN_REVISORES = 1`. Exigir dois agora prenderia o piloto à disponibilidade de uma segunda pessoa; subir para 2 é mudar a constante, e o CI reprova então todo caso com um só revisor. Cada item traz o próprio `reviewed_at`, para que um segundo revisor não sobrescreva a data do primeiro. O mesmo `atestado` duas vezes na lista reprova, senão uma pessoa contaria como duas quando o mínimo subir. Como o registro só admite um ID por profissional (D3), "mesmo atestado" equivale a "mesma pessoa".

**D2 — "Verificável" = formato validado mais identificação suficiente para consulta humana.** O código **não** consulta CFM nem Cofen: seria uma dependência de rede no pipeline, sem API estável, e com resultado que muda com o tempo. O comentário de `contract/src/golden.ts` diz isso. O que vai para o código, sem rede: no COREN, `categoria` é obrigatória e só `ENF` é aceita, porque a inscrição carrega a categoria (`654321-TE` é técnico). Fica no roteiro: a consulta ao cadastro (registro ativo, nome confere). **Ponto em aberto:** o sufixo `-IR` (`12.345-ENF-IR`). A Task 9 pede confirmação ao setor de inscrição do COREN-RR. **Se a confirmação chegar depois da Task 1 e mudar o formato, a mudança é um commit próprio no contrato** (`fix(contract): ...`, com testes válidos e inválidos do formato novo e o `CHECK` do banco regenerado), feito **antes** da transcrição, e nunca um ajuste feito na hora de transcrever.

**D3 — Opção A (decidida): identificador no público, dados pessoais só no CMS e no termo.** Nada vai ao aparelho.
- **`seed/golden/atestados.yaml`** — registro público, **fonte única dos IDs**: `{ id: AT-NNNN, conselho, uf, categoria?, termo_sha256 }`. Sem nome, sem registro. O `termo_sha256` não expõe nada: sem o PDF, o hash não revela conteúdo; com o PDF, prova o vínculo. Um ID é atribuído **uma vez**, por PR nesse arquivo, e nunca reaproveitado. Regras validadas pelo contrato: IDs únicos, `termo_sha256` hex de 64 caracteres e único (um termo, um atestado).
- **`clinical_cases.yaml`**: `reviewed_by: [{ atestado, conselho, uf, categoria?, reviewed_at }]`. Conselho, UF e categoria são repetidos de propósito: quem revisa o PR lê o caso sem abrir outro arquivo, e o portão confere que coincidem com o registro.
- **CMS** (`golden_attestation`): o mesmo `id` do registro, informado no `POST /atestados` (nunca gerado pelo CMS), com nome e registro. Assim, cada CMS implantado recebe o mesmo ID para o mesmo profissional.
- **Coerência entre os três:** o packer no caminho `seed/` exige que todo atestado citado exista no registro com conselho, UF e categoria iguais; o importador exige o mesmo **e** que o atestado exista no CMS com os mesmos campos e o mesmo `termo_sha256`; o worker exige que todo atestado do banco exista no registro com os mesmos campos.
- **Termo:** arquivado pela **Secretaria Municipal de Saúde (controladora)** no sistema de protocolo dela, fora do repositório e do CMS. Retenção: a da LGPD-RF04 (prazo prescricional), contada a partir da desativação do último caso que cita o atestado; o número de anos vem da tabela de retenção da LGPD-RF07, ainda pendente com o encarregado.

**D4 — Revisão que envelhece ou errada: issue P1 de seguimento.** Duas razões, ambas no texto da issue: (1) `reviewed_hash` (vincular a revisão ao conteúdo do caso); (2) **uma revisão registrada errada é permanente**, porque `golden_case_review` é append-only e não há rota de desativação, então data ou profissional errado só se corrige com essa issue, que precisa oferecer revogação auditada de revisão ou desativação de caso por rota com papel e trilha. Já nesta issue: o CMS não tem rota de edição de `tokens`/`expect`; o importador só acrescenta revisor a caso com conteúdo idêntico; a rota recusa data futura e atestado desconhecido, o que reduz o erro na entrada.

**D5 — `packer build` assina, logo bloqueia** (divergência 4). A alternativa, uma flag para assinar sem revisão, é o atalho proibido.

**D6 — CMS: atestado + revisão append-only.**
- `golden_attestation(id PK, nome, conselho, uf, categoria, registro, termo_sha256, created_by, created_at)`, com `UNIQUE(conselho, uf, registro)` e `UNIQUE(termo_sha256)`, e `CHECK`s gerados das constantes do contrato (incluindo `(conselho = 'COREN' AND categoria IN (...)) OR (conselho = 'CRM' AND categoria IS NULL)`). É o atestado de um profissional, não uma conta, então não é a "segunda tabela de identidade" vetada pelo `CLAUDE.md`. Quem o registrou é o `actor_id` da trilha.
- `golden_case_review(id, case_id, attestation_id, reviewed_at, recorded_by, recorded_at)`, com `UNIQUE(case_id, attestation_id)`, **em `APPEND_ONLY_TABLES`**: "nunca remove nem troca quem atestou" é estrutural.
- `golden_case.reviewed_by` sai. "Revisado" = ≥ `MIN_REVISORES` linhas em `golden_case_review`.

**D7 — Suíte vazia bloqueia, nos dois modos.** A desativação parcial vai para a issue de D4.

**D8 — Importação tudo-ou-nada.** Um caso recusado ou em conflito ⇒ nada é escrito, saída 1. Uma importação parcial deixaria o CMS com uma suíte **menor** que a do repositório, e o worker assinaria contra ela.

**D9 — O CI de PR nunca reprova por revisão AUSENTE; reprova por revisão INVÁLIDA** (formato errado ou atestado fora do registro). Nenhum teste conta casos revisados no YAML real.

**D10 — Discordância bloqueia de propósito, e cada desfecho tem caminho.** A pergunta do formulário é **"o desfecho esperado é clinicamente seguro?"**.

| Resposta | Efeito | Caminho | Quem decide |
|---|---|---|---|
| **concordo** | revisão transcrita | — | — |
| **concordo: seguro, mas mais cauteloso que o ideal** | conta como concordo: revisão transcrita; justificativa registrada no formulário | issue **P1** de ajuste da regra, **obrigatória no mesmo PR da transcrição** (o checklist do PR exige o link; não há robô); linha na tabela "casos seguros, mas cautelosos" da §5.17 | — (regra fixa) |
| **discordo: inseguro, o esperado seria MAIS grave** | caso fica no YAML, sem revisão; **pack bloqueado** | issue **P0** de conteúdo clínico; revisado de novo depois. **Retirar é proibido** (possível falso negativo) | — (regra fixa) |
| **discordo, num caso de severidade máxima** (red flag), em qualquer direção | idem: fica e bloqueia | issue P0 de conteúdo clínico | — (regra fixa) |
| **caso mal construído** (tokens incoerentes, combinação impossível) | caso fica e bloqueia até decisão | retirada em PR próprio `chore(golden): retira <id> mal construido (#2)` com a justificativa do revisor, e linha em §5.17 "casos retirados"; **nunca** para caso de red flag, que segue a linha anterior. Se o revisor sugerir um caso substituto, ele entra como caso novo, revisado pelo fluxo normal | dono, com o revisor |
| **não sei avaliar** | pendente, bloqueia | outro profissional indicado pela Secretaria | Secretaria |
| **dois revisores divergem** | vale a resposta **mais conservadora** (ordem: discordo/inseguro > mal construído > não sei > cauteloso > concordo). **Proibido** transcrever só quem concordou | o da linha correspondente | conforme a linha |

A #2 fecha quando todos os 24 casos estiverem revisados (concordo, com ou sem cautela) ou retirados como mal construídos. Discordância por insegurança deixa a #2 aberta, com o critério "`pack:check` sem aviso" pendente e referência à P0. As regras de D10 são processo (o YAML não guarda votos); o roteiro as torna obrigatórias, e o formulário guarda todos os votos.

**D11 — Release bloqueada não é repescada até mudar conteúdo.**
- No bloqueio, a transição `building → approved` grava `blocked_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')` **no SQL**. `recordAudit` (CMS) passa a gravar `occurred_at` com a mesma expressão SQL, no lugar de `new Date().toISOString()`, e `registrarNaTrilha` (worker) também. Há um único `sqld` primário, logo um único relógio. O formato coincide com o atual (`...SS.sssZ`), então a comparação textual com as linhas antigas continua correta.
- `proximaAprovada` ignora release com `blocked_at` não nulo enquanto não existir `audit_entry` com `actor_id IS NOT NULL`, `occurred_at >= blocked_at` e `action` numa lista de ações **de conteúdo**.
- `ACOES_QUE_REABREM` (prefixos `content_`, `rule_`, `golden_`) mora em `contract/src/golden.ts`, para que packer e CMS usem a mesma lista. Login, 2FA, gestão de operador e transições de release **não** reabrem. Um teste em `cms/test/` extrai todo literal `action: '...'` de `cms/src` e de `ACOES` do middleware e exige que cada um esteja classificado: casa um prefixo de `ACOES_QUE_REABREM` ou está em `ACOES_QUE_NAO_REABREM`. Ação nova sem classificação reprova, pelo mesmo princípio de `APPEND_ONLY_TABLES`.
- Ao reivindicar, `blocked_at` volta a nulo. Isso complementa, sem reverter, a decisão "portão vermelho devolve para `approved`, não estado de erro" (`CLAUDE.md`). Limite: mudança só por SQL direto não reabre; basta qualquer escrita de conteúdo auditada. `reenfileirar` não serve (só `building → approved`).

## Efeito da transição

- **Com o portão no ar e os 24 casos sem revisão, nenhum caminho produz pack assinado.** O CI de PR segue verde, com aviso (D9).
- **Pack já distribuído:** nada muda. O portão age antes da assinatura e não revoga nada. O aparelho mantém o pack ativo (FSM-B só troca por versão maior validada). O pack de desenvolvimento (`pack-88c2c35a99e1`, MinIO local da P0-1) segue servido. Se existir MinIO de produção, ele fica congelado na versão atual, **aceito pelo dono antes do piloto**.
- **Custo:** a verificação em emulador que precise de pack **novo** espera a revisão, e a contingência do R5, "correção em horas", fica indisponível até lá.
- **Merge do portão agora: decidido.**

## Emulador

**Não se aplica.** O `content.db` não muda, o `manifest-schema.json` não muda (`npm run contract:check` sem diff comprova), e o único leitor do YAML no app (`golden_clinical_test.dart`) ignora `reviewed_by`. Verificação no lado do app, no host: `flutter test test/triage/golden_clinical_test.dart` depois da Task 9.

## Review Focus

1. **Atestado digitado errado no YAML** (`AT-0099` inexistente ou com UF trocada) → reprova até em `--dry-run` (Task 4).
2. **Mesmo profissional com dois IDs no CMS** (`POST /atestados` com conselho+UF+registro já registrados sob outro ID) → 409 (Task 5).
3. **Inscrição copiada do cadastro com ponto ou sufixo** (`123.456-ENF`) → recusa explicando "só dígitos; a categoria vai em `categoria`" (Task 1).
4. **Login reabrindo release bloqueada** → não reabre (Task 4).
5. **Fugir do portão esvaziando a suíte** → bloqueia (Tasks 4 e 6).

## Mapa de arquivos

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `contract/src/golden.ts`, `contract/test/golden.test.ts` | criar | constantes, esquemas, `avaliarRevisao`, `avaliarAtestado`, `avaliarRegistro`, `conferirContraRegistro`, `ACOES_QUE_REABREM` |
| `contract/src/index.ts` | modificar | reexportar |
| `seed/golden/atestados.yaml` | criar | registro público, **vazio** (`atestados: []`) com comentário de cabeçalho |
| `packer/src/cli.ts`, `packer/test/cli.test.ts`, `packer/test/support/revisao.ts` | criar | `executarCli`, `modoDoComando`; fixtures fictícias |
| `packer/src/index.ts` | modificar | só chama `executarCli` |
| `packer/src/validate.ts`, `extract.ts`, `worker.ts` | modificar | portão, `lerAtestadosDoYaml`, leitura do banco, `blocked_at` |
| `packer/test/pipeline.test.ts`, `packer.test.ts` | modificar | worker; fixtures |
| `cms/src/db/schema/publishing.ts`, `index.ts` | modificar | tabelas novas, `blocked_at`, `APPEND_ONLY_TABLES`, `PII_COLUMNS` |
| `cms/src/db/migrations/0009_*.sql`, `triggers.sql` | gerar | `cms:generate`, `cms:triggers` |
| `cms/src/services/audit.ts` | modificar | `occurred_at` pelo relógio do banco |
| `cms/scripts/migrate.ts` | modificar | pré-condição da 0009 |
| `cms/src/routes/golden.ts`, `cms/src/app.ts` | criar/modificar | rotas |
| `cms/src/services/golden-import.ts`, `cms/scripts/import-golden.ts` | criar/modificar | importador |
| `cms/test/golden-*.test.ts`, `audit-acoes.test.ts`, `migrations.test.ts`, `support/db.ts` | criar/modificar | testes |
| `docs/operacao.md`, `docs/revisao-golden.md`, `spec/*.md`, comentário do `clinical_cases.yaml`, `README.md`, `CLAUDE.md` | modificar/criar | Tasks 3, 5, 6, 8 |

## Ordem e dependências

D3 está decidida, e a validação do encarregado (DPO) **não bloqueia o portão**. Só dependem dela a Task 8 Step 2 (texto da `lgpd.md`) e a Task 9. As Tasks 1 a 7 podem ser executadas e ter merge antes da validação. Se o encarregado pedir uma mudança que afete o formato (ex.: tirar `uf` do registro público), ela entra como commit próprio no contrato, com testes, antes da Task 9.

---

### Task 1: Contrato da revisão e do registro (`contract/src/golden.ts`)

**Files:** Create `contract/src/golden.ts`, `contract/test/golden.test.ts`, `seed/golden/atestados.yaml`; Modify `contract/src/index.ts`.

**Interfaces — Produces:**
```ts
export const CONSELHOS: readonly ['CRM', 'COREN'];
export const CATEGORIAS_COREN_ACEITAS: readonly ['ENF'];
export const UFS: readonly [/* as 27 */];
export const MIN_REVISORES = 1;
export const ATESTADO_ID: RegExp;                      // /^AT-\d{4}$/
export const ACOES_QUE_REABREM: readonly ['content_', 'rule_', 'golden_'];  // prefixos (D11)
export const ACOES_QUE_NAO_REABREM: readonly string[]; // lista exata (D11)

/** Identificacao publica: o que aparece no registro e em cada item de reviewed_by. */
type Identificacao =
  | { conselho: 'CRM'; uf: Uf }
  | { conselho: 'COREN'; categoria: 'ENF'; uf: Uf };
export type EntradaRegistro = Identificacao & { id: string; termo_sha256: string };
export type RevisorYaml = Identificacao & { atestado: string; reviewed_at: string };
/** Atestado completo — so no CMS. */
export type Atestado = Identificacao & { id: string; nome: string; registro: string; termo_sha256: string };

export type EstadoRevisao =
  | { estado: 'ausente' }
  | { estado: 'invalida'; problemas: string[] }
  | { estado: 'valida'; revisores: RevisorYaml[] };
export function avaliarRevisao(entrada: { reviewed_by?: unknown; reviewed_at?: unknown }, agora: Date): EstadoRevisao;
export function avaliarAtestado(entrada: unknown): { ok: true; atestado: Atestado } | { ok: false; problemas: string[] };
export function avaliarRegistro(entrada: unknown): { ok: true; entradas: EntradaRegistro[] } | { ok: false; problemas: string[] };
/** Problemas de coerencia: atestado ausente do registro, ou conselho/uf/categoria divergentes. */
export function conferirContraRegistro(
  revisores: readonly (Identificacao & { atestado: string })[],
  registro: readonly EntradaRegistro[],
): string[];
```
Regras: `ausente` ⇔ `reviewed_by` é `undefined`/`null`. `reviewed_at` no nível do caso é sempre inválido ("reviewed_at mora em cada revisor"). `nome`: aparado, ≥ 2 palavras. `registro`: string `^\d{1,8}$`. COREN sem `categoria`, ou com `TE`/`AE`/`OBST`/`PAR`, é inválido ("so enfermeiro (ENF)"); CRM com `categoria` é inválido. Duplicata de `atestado` na lista é inválida. Registro: IDs únicos, `termo_sha256` hex 64 único. Problemas no formato `"reviewed_by[1].categoria: ..."` / `"atestados[0].id: ..."`.

- [ ] **Step 1: Testes** (fixtures `REG = [{ id: 'AT-9001', conselho: 'CRM', uf: 'RR', termo_sha256: 'a'.repeat(64) }, { id: 'AT-9002', conselho: 'COREN', categoria: 'ENF', uf: 'RR', termo_sha256: 'b'.repeat(64) }]`, `REV_CRM = { atestado: 'AT-9001', conselho: 'CRM', uf: 'RR', reviewed_at: '2026-10-28' }`, `REV_COREN` análogo com `AT-9002` e `'2026-10-27'`, `ATESTADO_FICTICIO = { id: 'AT-9002', nome: 'Revisora Ficticia Teste', conselho: 'COREN', categoria: 'ENF', uf: 'RR', registro: '000123', termo_sha256: 'b'.repeat(64) }`, `AGORA = new Date('2026-10-28T12:00:00Z')`):
  - `avaliarRevisao`: `ausente quando reviewed_by e nulo ou omitido`; `valida com um revisor`; `valida com dois revisores em datas diferentes`; `lista vazia e invalida`; `reviewed_at no nivel do caso e invalido`; `revisor sem reviewed_at e invalido`; `conselho fora da lista e invalido`; `UF fora das 27 e invalida`; `as 27 UFs sao aceitas` (`UFS.length === 27`); `COREN sem categoria e invalido`; `COREN TE, AE, OBST e PAR sao invalidos com a mensagem so enfermeiro`; `CRM com categoria e invalido`; `ID de atestado fora do formato e invalido` (`'AT-1'`, `'at-0001'`); `mesmo atestado duas vezes e invalido`; `reviewed_at futuro e invalido`, `de hoje e valido`, `inexistente no calendario e invalido`, `formato errado e invalido`.
  - `avaliarAtestado`: `valido`; `registro numerico pede aspas`; `registro copiado do cadastro e explicado` (`'123.456-ENF'` → `so digitos` e `categoria`); `registro com 9 digitos e invalido`; `nome de uma palavra e invalido`; `chave desconhecida e invalida`.
  - `avaliarRegistro`: `registro valido`; `registro vazio e valido` (estado atual do repositório); `ID repetido e invalido`; `termo_sha256 repetido e invalido`; `termo_sha256 fora do formato e invalido`; `entrada com nome ou registro e invalida` (`.strict()`: o registro público não aceita dado pessoal).
  - `conferirContraRegistro`: `coerente devolve vazio`; `atestado ausente do registro e acusado` (`AT-0099` → mensagem com `AT-0099` e `atestados.yaml`); `UF divergente e acusada`; `categoria divergente e acusada`.
- [ ] **Step 2:** `npm --workspace contract test` → FAIL (módulo inexistente).
- [ ] **Step 3: Implementar** com Zod (`z.discriminatedUnion('conselho', ...)`, `.strict()`, `superRefine` para duplicatas, data por regex + ida e volta via `Date.UTC`, "futuro" = `> agora.toISOString().slice(0, 10)`). O cabeçalho diz: "valida FORMATO; a existencia e a situacao do registro profissional sao conferidas por pessoa no cadastro do conselho (docs/revisao-golden.md)". `ACOES_QUE_NAO_REABREM` recebe as ações de autenticação, `user_*` e `release_*` listadas em §Estado. Criar `seed/golden/atestados.yaml` com `atestados: []` e um cabeçalho que diz: fonte única dos IDs; sem dado pessoal; um ID por profissional, nunca reaproveitado; formato em `contract/src/golden.ts`. Reexportar em `index.ts`.
- [ ] **Step 4:** `npm --workspace contract test && npm run typecheck && npm run contract:check` → PASS, sem diff.
- [ ] **Step 5: Commit** `feat(contract): formato da revisao golden e registro publico de atestados (#2)`.

### Task 2: Vermelho primeiro — caracterizar que hoje se assina sem revisor

Refatoração sem mudança de comportamento, mais testes que **passam hoje** e documentam o defeito. A Task 4 os inverte.

**Files:** Create `packer/src/cli.ts`, `packer/test/cli.test.ts`, `packer/test/support/revisao.ts`; Modify `packer/src/index.ts`, `packer/test/pipeline.test.ts`.

**Interfaces — Produces:**
```ts
export type EstadoCli = 'bloqueado' | 'verificado' | 'assinado' | 'publicado';
export interface AmbienteCli {
  repoRoot: string; outDir: string;
  casos?: readonly GoldenCase[];        // ausente => lerGoldenDoYaml(repoRoot)
  atestados?: readonly unknown[];       // ausente => lerAtestadosDoYaml(repoRoot) (Task 4)
  agora?: Date;
}
export async function executarCli(argv: string[], ambiente: AmbienteCli): Promise<{ estado: EstadoCli; problemas: string[] }>;
```
`index.ts` vira `executarCli(process.argv.slice(2), { repoRoot: REPO_ROOT, outDir: OUT_DIR })`, com `process.exit(1)` se `bloqueado`.

- [ ] **Step 1: Mover** o corpo de `main()` para `executarCli`: parâmetros no lugar de `REPO_ROOT`/`OUT_DIR`, `return { estado: 'bloqueado' }` no lugar de `process.exit(1)`. As saídas de console ficam idênticas.
- [ ] **Step 2: Fixtures independentes do seed** em `packer/test/support/revisao.ts`:
  ```ts
  // Conteudo de um caso REAL (para passar nas regras do seed), revisao REMOVIDA
  // explicitamente: o teste nao pode depender de o seed estar ou nao revisado.
  export function semRevisao(repoRoot: string, id: string): GoldenCase {
    const { reviewed_by: _b, reviewed_at: _a, ...resto } =
      lerGoldenDoYaml(repoRoot).find((c) => c.id === id)!;
    return { ...resto, id: `ficticio-${id}` };
  }
  ```
  Mais `REG`, `REV_CRM`, `ATESTADO_FICTICIO` iguais aos da Task 1. Todo teste do CLI passa `casos` e `atestados` **explicitamente**. O `before` gera um par Ed25519 efêmero (`pipeline.test.ts:117-121`), define `PACK_SIGNING_KEY_PATH` e `SOURCE_DATE_EPOCH=1787097600`, apaga `MINIO_ROOT_USER`. Cada teste usa um `outDir` próprio.
- [ ] **Step 3: Caracterização** (`CASO_SEM_REVISOR = semRevisao(REPO_ROOT, 'chest-pain')`):
  - `HOJE: build sem --dry-run assina com caso sem revisor` → `assinado`, `manifest.json` existe.
  - `HOJE: publish assina com caso sem revisor antes de falhar no storage` → `rejects /MINIO_ROOT_USER/` **e** `manifest.json` existe.
  - `build --dry-run nao assina` → `verificado`, sem manifest.
  - `pipeline.test.ts`: `HOJE: o worker assina com caso golden sem revisor` → `g-toracico` com `reviewed_by IS NULL` e `rel-1` em `built` com `pack_sha256`.
- [ ] **Step 4:** `npm --workspace @guia-ubs/packer test` → PASS. `npm run pack:check` → saída idêntica à de antes.
- [ ] **Step 5: Commit** `test(packer): caracteriza assinatura com caso golden sem revisor (#2)`.

### Task 3: Banco do CMS — atestado, revisão append-only, `blocked_at`, relógio do banco

**Files:** Modify `cms/src/db/schema/publishing.ts`, `cms/src/db/schema/index.ts`, `cms/src/services/audit.ts`, `cms/test/support/db.ts`, `cms/test/migrations.test.ts`, `cms/scripts/migrate.ts`, `packer/src/extract.ts`, `packer/test/pipeline.test.ts`, `docs/operacao.md` (§2.3); Generate `0009_*.sql`, `meta/`, `triggers.sql`.

**Interfaces — Produces:**
- `goldenAttestation`, `goldenCaseReview` conforme D6 (`CHECK`s montados das constantes do contrato, nunca digitados). `goldenCase` sem `reviewedBy`. `packRelease.blockedAt: text('blocked_at')`.
- `APPEND_ONLY_TABLES` += `{ table: goldenCaseReview, requirement: 'PRD R5 / P0-2' }`. `PII_COLUMNS` += `golden_attestation.nome`, `golden_attestation.registro`.
- `recordAudit`: `occurredAt: sql\`(strftime('%Y-%m-%dT%H:%M:%fZ','now'))\``.
- `lerGoldenDoBanco(client): Promise<GoldenCase[]>` devolve `reviewed_by` como `RevisorYaml[]` (montado de `golden_case_review` ⨝ `golden_attestation`), ou `null` se vazio, ordenado por `attestation_id`. Também `lerAtestadosDoBanco(client): Promise<Atestado[]>`. `GoldenCase.reviewed_by` vira `unknown`.
- `cms/scripts/migrate.ts`: `preCondicao0009(client): Promise<string[]>` (ids de `golden_case` com `reviewed_by` não nulo, se a coluna existir). Lista não vazia ⇒ aborta antes de `runMigrations`, saída 1.

- [ ] **Step 1: Testes**
  - `support/db.ts`: linha de exemplo `golden_case_review` em `APPEND_ONLY_ROWS` (com `golden_case` e `golden_attestation` fictícios no seed do fixture).
  - `migrations.test.ts`: `golden_case ativo e sem revisor sobrevive a 0009` (aplicar `0000…0008` na ordem do journal, inserir, aplicar a 0009 → as seis colunas intactas, zero revisões); `todo gatilho do triggers.sql existe no banco depois de migrar` (`sqlite_master` ⊇ nomes de `triggerStatementsFromDisk()`, incluindo `golden_case_review_no_update`/`_no_delete`; cobre a reconstrução da tabela); `pre-condicao da 0009 acusa reviewed_by preenchido`.
  - `audit.test.ts`: `occurred_at vem do relogio do banco e tem o formato ISO com milissegundos` (`/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/`, e `>=` um `strftime` lido antes no mesmo banco).
  - `cms/test/golden-cases.test.ts` (nasce aqui): `o banco recusa conselho fora da lista`, `UF fora das 27`, `COREN sem ENF e CRM com categoria`, `o mesmo profissional sob dois IDs` (UNIQUE conselho+uf+registro), `o mesmo termo em dois atestados`.
  - `pipeline.test.ts`: `lerGoldenDoBanco monta reviewed_by a partir das revisoes` (2 atestados fictícios, datas diferentes preservadas).
- [ ] **Step 2:** `npm test` → FAIL.
- [ ] **Step 3: Implementar**; `npm run cms:generate && npm run cms:triggers`. Conferir que a cópia de `golden_case` no `0009_*.sql` preserva as seis colunas. O `INSERT` de `import-golden.ts` perde a coluna `reviewed_by` (o comportamento novo vem na Task 6).
- [ ] **Step 4: Roteiro de implantação, no mesmo commit da migração**, em `docs/operacao.md` §2.3, "Antes de migrar para a 0009": (1) backup do volume `dbdata`; (2) `npm run cms:migrate`, que roda a pré-condição e aborta se houver `reviewed_by` preenchido; (3) se abortar, **parar e falar com o dono**.
- [ ] **Step 5:** `npm run typecheck && npm test && npm run cms:check` → PASS.
- [ ] **Step 6: Commit** `feat(cms): atestado e revisao golden append-only no banco (#2)`.

### Task 4: Portão no packer e worker sem laço

**Files:** Modify `packer/src/validate.ts`, `packer/src/cli.ts`, `packer/src/worker.ts`, `packer/test/cli.test.ts`, `packer/test/pipeline.test.ts`, `packer/test/packer.test.ts`; Create `cms/test/audit-acoes.test.ts`.

**Interfaces — Consumes:** Task 1 (todas as funções), Task 2 (`executarCli`), Task 3 (`lerGoldenDoBanco`, `lerAtestadosDoBanco`, `blocked_at`). **Produces:**
```ts
export type ModoRevisao = 'assinatura' | 'verificacao';
// ValidationIssue.kind += 'golden_sem_revisor' | 'golden_revisao_invalida' | 'golden_vazia' | 'golden_registro_invalido'
export function lerAtestadosDoYaml(repoRoot: string): unknown[];   // seed/golden/atestados.yaml
export function validateGolden(cases, model, opcoes: {
  modo: ModoRevisao; agora: Date; registro: readonly EntradaRegistro[];
}): GoldenReport;
export function modoDoComando(args: { dryRun: boolean }): ModoRevisao;   // cli.ts
```
`validateGolden`: `ausente` conta em `unreviewed` e, em `assinatura`, vira `golden_sem_revisor`; `invalida`, **ou** `valida` com `conferirContraRegistro` não vazio, vira `golden_revisao_invalida` nos dois modos (D9); vazio vira `golden_vazia` nos dois modos. Em `executarCli`, `avaliarRegistro(lerAtestadosDoYaml(...))` inválido ⇒ `golden_registro_invalido` nos dois modos. `modo = modoDoComando(args)` logo depois de `parseArgs`, e o único caminho até `buildManifest` passa por `if (modo === 'verificacao') return { estado: 'verificado', ... }`. Aviso: `aviso N caso(s) golden sem revisao clinica — permitido so em --dry-run; build, publish e o worker bloqueiam.`
Worker: `modo: 'assinatura'` fixo; antes de `validateGolden`, cada atestado de `lerAtestadosDoBanco` passa por `avaliarAtestado` e é conferido contra `lerAtestadosDoYaml(REPO_ROOT)` (id, conselho, UF, categoria e `termo_sha256` iguais), e qualquer problema vira `golden_registro_invalido`. No bloqueio, `UPDATE ... SET status='approved', claimed_at=NULL, blocked_at=strftime('%Y-%m-%dT%H:%M:%fZ','now')`; `registrarNaTrilha` usa a mesma expressão para `occurred_at`. `reivindicar` zera `blocked_at`. `proximaAprovada`:
```sql
AND (pr.blocked_at IS NULL OR EXISTS (
  SELECT 1 FROM audit_entry a
   WHERE a.actor_id IS NOT NULL AND a.occurred_at >= pr.blocked_at
     AND (a.action LIKE 'content\_%' ESCAPE '\' OR a.action LIKE 'rule\_%' ESCAPE '\'
          OR a.action LIKE 'golden\_%' ESCAPE '\')))
```
(os três `LIKE` montados de `ACOES_QUE_REABREM`, não digitados).

- [ ] **Step 1: Inverter a caracterização:** `build sem --dry-run BLOQUEIA caso sem revisor`; `publish BLOQUEIA caso sem revisor antes de assinar` (resolve `bloqueado`, sem manifest); `o worker BLOQUEIA caso golden sem revisor e devolve a release` (`approved`, `claimed_at` nulo, `blocked_at` no formato ISO).
- [ ] **Step 2: Testes novos**
  - `cli.test.ts`: `build --dry-run passa com caso sem revisor e avisa`; `publish --dry-run nao assina`; `build assina quando todos os casos tem revisao valida e registrada` (`[CASO_REVISADO]` + `REG`); `revisao invalida BLOQUEIA ate em --dry-run`; `atestado inexistente no registro BLOQUEIA ate em --dry-run` (`AT-0099`); `UF divergente do registro BLOQUEIA`; `registro com nome BLOQUEIA` (`golden_registro_invalido`); `suite vazia BLOQUEIA` (nos dois modos); tabela de `modoDoComando`.
  - `cli.test.ts`, D9: `os YAMLs reais nao tem revisao invalida` → `avaliarRegistro(lerAtestadosDoYaml(REPO_ROOT)).ok` e, para todo caso, `avaliarRevisao !== 'invalida'` e `conferirContraRegistro` vazio. Vale em qualquer estado de revisão.
  - `pipeline.test.ts`: `suite do banco vazia BLOQUEIA o worker`; `atestado do banco fora do registro BLOQUEIA o worker`; `release bloqueada nao e repescada sem mudanca` (`proximaAprovada` → `null`; `golden_run` de `rel-x` = 1); `release bloqueada volta depois de escrita de conteudo` (`audit_entry` com `actor_id`, `action='content_update'`, `occurred_at` do `strftime` → devolve `rel-x`); `login nao reabre release bloqueada` (`action='sign_in'` → `null`); `release bloqueada nao trava a mais nova`.
  - `cms/test/audit-acoes.test.ts`: `toda acao da trilha esta classificada para D11` → extrai por regex os literais `action: '...'` de `cms/src/**/*.ts` e os valores de `ACOES` em `auth/middleware.ts` (mais as variantes `_failed` e `sign_in_locked`), e exige que cada um case um prefixo de `ACOES_QUE_REABREM` ou esteja em `ACOES_QUE_NAO_REABREM`, e não as duas coisas. Asserção adicional: o total extraído ≥ 15, para não ficar verde com zero asserções.
- [ ] **Step 3:** `npm test` → FAIL.
- [ ] **Step 4: Implementar.** Fixtures existentes: `semear()` em `pipeline.test.ts` cria atestado + revisão fictícios para `g-toracico`, e o teste usa um registro fictício (o worker lê `atestados.yaml` via `REPO_ROOT`: tornar o caminho injetável, com `processar(client, release, { publicar, registro? })`, padrão `lerAtestadosDoYaml(REPO_ROOT)`). `caso golden vermelho BLOQUEIA...` revisa também `g-impossivel`, para bloquear pelo motivo que nomeia, e depois grava uma escrita de conteúdo auditada antes de prosseguir. Em `packer.test.ts:217`: `{ modo: 'verificacao', registro: [] }`.
- [ ] **Step 5:** `npm run typecheck && npm test` → PASS. `npm run pack:check` → aviso, exit 0. `SOURCE_DATE_EPOCH=1787097600 PACK_SIGNING_KEY_PATH=contract/keys/dev-k1.pem PACK_VERSION=1 npm run pack:build` → `BLOQUEADO: 24 problema(s). Nada foi assinado.`, exit 1, `mtime` de `packer/out/manifest.json` inalterado.
- [ ] **Step 6: Commit** `feat(packer): caso golden sem revisor bloqueia toda assinatura (#2)`.

### Task 5: Rotas de golden no CMS

**Files:** Create `cms/src/routes/golden.ts`; Modify `cms/src/app.ts`, `cms/test/golden-cases.test.ts`, `docs/operacao.md`.

**Interfaces — Produces:** `goldenRoutes(client, salt)` em `protegido.route('/golden-cases', ...)`. Semântica única com o importador: **revisão é só acréscimo.**

| Rota | Permissão | Comportamento |
|---|---|---|
| `POST /api/golden-cases` | `content:write` | corpo `{id, tokens≥1, expect, clinicalSource?, active?}`; malformado → 400; `active === 1` → **422** `{error:'caso ativo exige revisao clinica registrada', next:'POST /api/golden-cases/<id>/revisores'}`; grava `active = 0`; id repetido → 409; trilha `golden_case_create` |
| `POST /api/golden-cases/atestados` | `approval:decide` | corpo = `Atestado` (com o **`id` do `atestados.yaml`**, nunca gerado aqui); `avaliarAtestado` inválido → **422** com `problemas`; `id` já usado → **409** (`'este ID ja pertence a outro atestado'` se os dados diferem; `'atestado ja registrado'` se idênticos); mesmo conselho+UF+registro sob outro `id` → **409** com o `id` existente; mesmo `termo_sha256` → 409; trilha `golden_attestation_create` (inclui nome e registro: `audit_entry.*_json`, comentário de `PII_COLUMNS`) |
| `POST /api/golden-cases/:id/revisores` | `approval:decide` | corpo `{ atestado, reviewed_at }`; caso inexistente → 404; atestado inexistente no CMS → 422; data inválida/futura → 422; `added_by === ator.id` → **403** (promoção, `CLAUDE.md`); já atestado por esse atestado → **409** com as revisões atuais; senão insere em `golden_case_review` e, se o caso atingir `MIN_REVISORES`, `active = 1`, num `client.batch(..., 'write')`; trilha `golden_case_review` |

A rota não lê `atestados.yaml`: o arquivo é versionado com o código e chega ao CMS por implantação. A coerência CMS × registro é conferida pelo importador (Task 6) e pelo worker (Task 4), que é onde ela decide alguma coisa. Não há `PUT` nem `DELETE` de revisão (D4).

- [ ] **Step 1: Testes** (sessões `editor`, `clinical_reviewer` ×2 via `sessaoDe`, dados fictícios):
  - `POST caso com active=1 responde 422 e aponta a rota de revisores`; `POST caso cria inativo`; `POST caso sem content:write responde 403`.
  - `POST atestado com COREN TE responde 422 so enfermeiro`; `com registro com ponto responde 422`; `sem id responde 422`; `ID ja usado por outro profissional responde 409`; `mesmo profissional sob outro ID responde 409 com o id existente`; `atestado identico de novo responde 409 e nao duplica`.
  - `POST revisores sem reviewed_at responde 422`; `com reviewed_at futuro responde 422`; `com atestado inexistente responde 422`; `valido ativa o caso`; `segundo revisor ACRESCENTA, nao substitui`; `mesmo atestado de novo responde 409 e nao altera nada`; `pelo autor do caso responde 403`; `sem approval:decide responde 403`; `caso inexistente responde 404`.
  - `a simulacao enxerga o caso recem-ativado`.
- [ ] **Step 2:** FAIL. **Step 3:** implementar no padrão de `routes/approvals.ts` (rota fina, Zod, `mensagemDoErro` para UNIQUE e gatilho → 409).
- [ ] **Step 4: `docs/operacao.md`** — nova §4.x "Casos golden": as três rotas com `curl` fictício e o fluxo "ID atribuído por PR em `atestados.yaml` → mesmo ID registrado em cada CMS → editor cadastra caso inativo → revisor acrescenta revisões".
- [ ] **Step 5:** `npm run typecheck && npm test` → PASS. **Step 6: Commit** `feat(cms): rotas de casos golden com revisao so por acrescimo (#2)`.

### Task 6: `cms:import-golden` com a mesma regra

**Files:** Create `cms/src/services/golden-import.ts`, `cms/test/golden-import.test.ts`; Modify `cms/scripts/import-golden.ts`, `docs/operacao.md` §2.6.

**Interfaces — Produces:**
```ts
export interface RelatorioImportacao {
  inseridos: string[]; revisoresAcrescentados: { id: string; atestados: string[] }[];
  mantidos: string[]; conflitos: { id: string; motivo: string }[];
  recusados: { id: string; problemas: string[] }[];
}
export async function importarGolden(client: Client, salt: string,
  entrada: { casos: readonly CasoGoldenYaml[]; registro: readonly unknown[] },
  opcoes: { autor: string; agora: Date }): Promise<RelatorioImportacao>;
```
Ordem, **toda a verificação antes de qualquer escrita**:
1. `avaliarRegistro` inválido → recusado `(registro)`. Suíte vazia → recusado `(suite)`.
2. `avaliarRevisao`: `ausente` → recusado ("sem revisao clinica — caso ativo exige revisor"); `invalida` → recusado; `conferirContraRegistro` não vazio → recusado.
3. Cada atestado citado: inexistente no CMS → recusado ("registre o atestado em POST /api/golden-cases/atestados com o ID de atestados.yaml"); no CMS com conselho/UF/categoria/`termo_sha256` diferentes do registro → conflito ("CMS e atestados.yaml divergem").
4. Caso existente com `tokens_json`/`expected_outcome_id` diferentes → conflito ("conteudo editado no CMS; a revisao do YAML nao se aplica").
5. Caso existente idêntico: acrescenta os atestados do YAML que faltam; revisão no CMS ausente do YAML **permanece**; mesmo atestado com `reviewed_at` diferente → conflito; nada a acrescentar → `mantidos`.
6. `recusados` ou `conflitos` não vazios → retorna sem escrever (D8). Senão, um `client.batch(..., 'write')` e uma trilha por caso (`golden_case_import` / `golden_case_review`).

- [ ] **Step 1: Testes** (fixture `freshApp()`, `f.client`, operador `autor` por `novoOperador`, atestados fictícios pré-registrados com os IDs de `REG`):
  - `recusa caso sem revisor e nao escreve nada` (`COUNT(*)` = 0); `recusa revisao invalida`; `recusa atestado fora do registro`; `recusa atestado ausente do CMS`; `CMS divergente do registro e conflito`; `recusa suite vazia`; `recusa registro invalido`.
  - `importa casos revisados ativos com revisoes e trilha`.
  - `acrescenta revisor a caso existente com conteudo identico` (linha pré-inserida como o importador antigo fazia).
  - `conteudo divergente e conflito e nada e escrito`.
  - `nunca remove revisao que o YAML nao traz`; `nunca troca a data de uma revisao existente`.
  - `reimportar e idempotente`.
  - D9: `todo caso do YAML real com revisao valida e aceito` → lê os dois YAMLs reais, filtra os casos com revisão válida e coerente, pré-registra no CMS de teste atestados fictícios **com os IDs e campos do registro real** (nome e registro fictícios), importa só esses e afirma `recusados.length === 0`. Com 0 revisados, afirma explicitamente que o filtro rodou sobre todos os casos do YAML. **Não** afirma contagem de revisados.
- [ ] **Step 2:** FAIL. **Step 3:** implementar; o script lê os dois YAMLs, imprime as cinco listas e define `process.exitCode = 1` se houver recusa ou conflito.
- [ ] **Step 4: `docs/operacao.md` §2.6** — tudo-ou-nada, acréscimo, conflitos, e a ordem "registrar atestados com o ID do `atestados.yaml` antes de importar".
- [ ] **Step 5:** `npm run typecheck && npm test` → PASS. **Step 6: Commit** `feat(cms): import-golden recusa caso sem revisor e so acrescenta revisao (#2)`.

### Task 7: Sabotagem

Para cada linha: aplicar a edição, rodar o teste, **ver reprovar**, reverter (`git checkout -- <arquivo>`), ver passar. Nada é commitado. Registrar "N proteções, N pegas" na §5.17.

| # | Portão | Edição exata | Deve reprovar |
|---|---|---|---|
| 1 | CLI | `validate.ts`: condição de `golden_sem_revisor` → `false` | `publish BLOQUEIA...`, `build sem --dry-run BLOQUEIA...` |
| 2 | Atalho do dry-run | `modoDoComando` → `args.command === 'publish' ? 'assinatura' : 'verificacao'` | `build sem --dry-run BLOQUEIA...`, tabela de `modoDoComando` |
| 3 | Worker | `worker.ts`: `modo: 'verificacao'` | `o worker BLOQUEIA caso golden sem revisor...` |
| 4 | Suíte vazia | remover `golden_vazia` | `suite vazia BLOQUEIA`, `suite do banco vazia BLOQUEIA o worker` |
| 5 | Formato | `golden.ts`: `uf: z.string()` | `UF fora das 27...`, `revisao invalida BLOQUEIA ate em --dry-run` |
| 6 | Categoria | `CATEGORIAS_COREN_ACEITAS = ['ENF', 'TE']` | `COREN TE, AE... sao invalidos`, `POST atestado com COREN TE responde 422` |
| 7 | Duplicata (D1) | remover o `superRefine` de duplicata de `atestado` | `mesmo atestado duas vezes e invalido` |
| 8 | **Registro: atestado inexistente** | `validateGolden`: não chamar `conferirContraRegistro` | `atestado inexistente no registro BLOQUEIA ate em --dry-run`, `UF divergente do registro BLOQUEIA` |
| 9 | **Registro: sem dado pessoal** | tirar o `.strict()` da entrada do registro | `entrada com nome ou registro e invalida`, `registro com nome BLOQUEIA` |
| 10 | **Worker × registro** | worker não confere `lerAtestadosDoBanco` contra o registro | `atestado do banco fora do registro BLOQUEIA o worker` |
| 11 | Rota: ativo sem revisor | gravar `active` do corpo | `POST caso com active=1 responde 422...` |
| 12 | Rota: autor | remover a checagem `added_by === ator.id` | `revisores pelo autor do caso responde 403` |
| 13 | **Rota: ID de outro profissional** | no `INSERT` de `golden_attestation`, acrescentar `ON CONFLICT(id) DO UPDATE SET nome = excluded.nome, registro = excluded.registro` (o `id` é PK, então a sabotagem é trocar a recusa por sobrescrita) | `ID ja usado por outro profissional responde 409` |
| 14 | Só acréscimo (estrutural) | remover `goldenCaseReview` de `APPEND_ONLY_TABLES` e rodar `cms:triggers` | `append-only.test.ts`, `todo gatilho... existe no banco` |
| 15 | Import: ausente | tratar `ausente` como aceito | `recusa caso sem revisor e nao escreve nada` |
| 16 | Import: tudo-ou-nada | escrever antes de checar `recusados` | `recusa caso sem revisor e nao escreve nada` (contagem ≠ 0) |
| 17 | Import: conflito de conteúdo (D4) | remover a comparação de `tokens_json`/`expected_outcome_id` | `conteudo divergente e conflito e nada e escrito` |
| 18 | Import: nunca troca/remove | apagar as revisões do caso antes de inserir as do YAML | `nunca remove revisao que o YAML nao traz`, `nunca troca a data...` |
| 19 | Import: CMS × registro | remover a comparação do passo 3 | `CMS divergente do registro e conflito` |
| 20 | Worker sem laço (D11) | remover o filtro `blocked_at` de `proximaAprovada` | `release bloqueada nao e repescada sem mudanca`, `...nao trava a mais nova` |
| 21 | Login não reabre (D11) | remover o filtro por `action` | `login nao reabre release bloqueada` |
| 22 | Ação não classificada (D11) | apagar `'sign_in'` de `ACOES_QUE_NAO_REABREM` | `toda acao da trilha esta classificada para D11` |
| 23 | Pré-condição 0009 | `preCondicao0009` → `return []` | `pre-condicao da 0009 acusa reviewed_by preenchido` |

- [ ] **Step 1:** executar as 23. **Esperado: 23 proteções, 23 pegas.** Teste que não reprova é decorativo: corrigir antes de seguir.
- [ ] **Step 2:** `git status` limpo, `npm test` verde.

### Task 8: Documentação, roteiro e propagação

**Files:** `spec/arquitetura.md`, `spec/lgpd.md`, `docs/operacao.md` (l. 758), `docs/revisao-golden.md` (novo), comentário do `seed/golden/clinical_cases.yaml`, `README.md:15`, `CLAUDE.md`.

- [ ] **Step 1: `spec/arquitetura.md`** — §5.17 "Resultado da P0-2 (issue #2)": portão, mapa de caminhos, D1–D11, sabotagem 23/23, tabelas "casos seguros, mas cautelosos" e "casos retirados" (vazias), e **"Revisor(es): pendente — ver Task 9"**. Lacuna 6 (l. 1050), tabela de entidades (l. 268: `golden_attestation`, `golden_case_review`, `pack_release.blocked_at`), árvore de `seed/` (l. 59: `atestados.yaml`), Roadmap: P0-2 "portão entregue; revisão pendente". Registrar que D11 complementa §5.12.
- [ ] **Step 2: `spec/lgpd.md`** (depende da validação do encarregado; as Tasks 1-7 não esperam) — inventário: "revisores clínicos da suíte golden": nome e registro só no CMS (`golden_attestation`); público só `id`, conselho, UF, categoria e `termo_sha256`; finalidade (rastreabilidade da revisão clínica, PRD R5); termo arquivado pela Secretaria (controladora); retenção pela LGPD-RF04 a partir da desativação do último caso, número de anos pendente da RF07.
- [ ] **Step 3: `docs/revisao-golden.md`** (entrada da Task 9):
  - quem pode revisar: médico (CRM) ou enfermeiro (COREN, categoria ENF) da APS, com registro ativo, ligado à UBS piloto, indicado pela Secretaria;
  - o termo de ciência (D3) e onde ele fica;
  - como ler um caso (tokens → rótulos pt de `seed/`; `expect` → cartão e local);
  - **a pergunta "o desfecho esperado é clinicamente seguro?"** e a tabela de D10, literal, incluindo a ordem de conservadorismo entre dois revisores e "proibido transcrever só quem concordou";
  - conferência do registro no cadastro do conselho (Cofen/COREN-RR, CFM/CRM-RR) por quem recebe o formulário: situação ativa, categoria ENF, nome confere; sufixo `-IR` confirmado com o setor de inscrição do COREN-RR; **se a confirmação mudar o formato, parar e abrir mudança de contrato antes de transcrever (D2)**;
  - atribuição do ID: o mantenedor abre um PR acrescentando `{ id, conselho, uf, categoria, termo_sha256 }` a `atestados.yaml` (próximo número livre, nunca reaproveitado); depois do merge, registra o atestado completo **com o mesmo ID** em cada CMS implantado;
  - formulário por caso, com campo para **cada** revisor (resposta, justificativa, desfecho que considera seguro se discorda, data);
  - checklist do PR de transcrição: só "concordo" (com ou sem cautela) de **todos** os revisores; uma issue P1 por caso "cauteloso", com o link; linha correspondente na §5.17;
  - tabela dos 24 casos gerada do YAML (id, tokens com rótulo pt, `expect`, `note`), dizendo de qual commit saiu.
- [ ] **Step 4: comentário do `clinical_cases.yaml`** — formato em `contract/src/golden.ts`, IDs em `atestados.yaml`, roteiro em `docs/revisao-golden.md`, "build, publish e o worker recusam caso sem revisao". **Sem exemplo de dados.**
- [ ] **Step 5:** `docs/operacao.md` l. 758, `README.md:15`, `CLAUDE.md` (em "Publicacao": modo derivado de "vai assinar"; suíte vazia bloqueia; registro público como fonte única dos IDs; revisão append-only; `blocked_at` + ação de conteúdo auditada reabre, instantes pelo relógio do banco; toda ação nova da trilha precisa de classificação).
- [ ] **Step 6: Issue #2** — comentar a mudança de critério ("nome(s)" → "atestado, conselho, UF e categoria") com a justificativa da D3 e editar o critério no corpo. **Mostrar o texto ao dono antes de `gh issue comment`/`gh issue edit`.**
- [ ] **Step 7: Rascunhar a issue P1 de seguimento** (D4, as duas razões): (1) `reviewed_hash`; (2) **revisão registrada errada é permanente** (append-only, sem rota de desativação), com revogação auditada de revisão e desativação de caso por rota com papel e trilha; e a desativação parcial da D7. **Mostrar ao dono; `gh issue create` só com aprovação.**
- [ ] **Step 8:** `npm test` → PASS. Commit `docs: portao de revisao golden e roteiro do revisor (#2)`.

### Task 9 (HUMANA — não executável pelo agente): revisão dos 24 casos

**Entrada:** `docs/revisao-golden.md` e o termo. **Saída:** cada um dos 24 casos revisado ("concordo", com ou sem cautela) no YAML e no CMS, ou retirado como mal construído; `pack:check` sem aviso.

- [ ] **Step 1 (encarregado):** validar a D3 e o termo.
- [ ] **Step 2 (Secretaria):** indicar o(s) profissional(is); termo assinado e arquivado pela Secretaria; SHA-256 do PDF entregue ao mantenedor.
- [ ] **Step 3 (quem recebe):** conferir o registro no cadastro do conselho; esclarecer o sufixo `-IR` se aparecer (D2).
- [ ] **Step 4 (mantenedor, PR 1):** `atestados.yaml` com o(s) novo(s) ID(s). CI valida.
- [ ] **Step 5 (operação):** em **cada** CMS implantado, `POST /api/golden-cases/atestados` com o **mesmo** ID, nome, registro e `termoSha256`.
- [ ] **Step 6 (revisor):** formulário preenchido caso a caso.
- [ ] **Step 7 (dono, se houver):** D10 caso a caso; retiradas em PR próprio; P0 de conteúdo abertas. **A #2 só fecha quando nenhum caso pendente restar.**
- [ ] **Step 8 (mantenedor, PR 2):** transcrever `reviewed_by` dos casos com "concordo" de todos os revisores; abrir as P1 dos casos "cautelosos" e linká-las no PR. CI: `pack:check` valida formato e registro (D9).
- [ ] **Step 9 (verificação):** `npm run pack:check` → **sem a linha de aviso**; `SOURCE_DATE_EPOCH=1787097600 PACK_SIGNING_KEY_PATH=contract/keys/dev-k1.pem PACK_VERSION=1 npm run pack:build` → assina; de `app/`: `flutter test test/triage/golden_clinical_test.dart` → verde.
- [ ] **Step 10 (operação):** em cada CMS, `npm run cms:import-golden -- --autor <id>` → todos com revisão, zero conflitos; release de teste → `published`.
- [ ] **Step 11:** registrar na issue #2 e na §5.17: **atestado, conselho, UF e categoria** de cada revisor. Fechar a issue.

## Rastreabilidade

| Critério de aceite | Onde | Estado após o agente |
|---|---|---|
| `packer/test/`: sem revisor → `publish` e worker bloqueiam; `--dry-run` passa com aviso | Task 2, Task 4 Steps 1-2, Task 7 #1-4, #8, #10, #20-21 | atendido |
| Rota: `active=1` sem revisor → 4xx; formato inválido → 4xx | Task 5 Step 1, Task 7 #5-7, #11-14 | atendido |
| Escopo 2: mesma regra no `cms:import-golden` | Task 6, Task 7 #15-19 | atendido |
| Escopo 3: formato estruturado, Zod no contrato, reprova no packer e na rota | Tasks 1, 3, 4, 5 | atendido (divergência 6) |
| `npm run pack:check` sem o aviso após a revisão | Task 9 Step 9 | **pendente (humano)** |
| Atestado, conselho, UF e categoria do(s) revisor(es) na issue e em `arquitetura.md` §5 (critério alterado pelo dono) | Task 8 Steps 1 e 6, Task 9 Step 11 | **pendente (humano)** |
| Escopo 4: revisão dos 24 casos e reimportação | Task 8 Step 3, Task 9 | **pendente (humano)** |
