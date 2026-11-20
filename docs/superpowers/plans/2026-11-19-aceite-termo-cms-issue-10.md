# Aceite do Termo de Uso no 1º login do CMS (issue #10) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** nenhum operador alcança rota protegida do CMS sem ter aceitado a versão vigente do Termo de Uso. O aceite fica gravado em `consent_record` (versão + hash) e na trilha, na mesma transação.

**Architecture:** um serviço (`cms/src/services/legal.ts`) é a única porta de leitura e escrita de `legal_document` e `consent_record`. As duas tabelas passam a ser append-only por gatilho. O middleware `requireConsent`, montado logo depois de `require2fa`, recusa com `403 {next: '/api/consentimento'}`, no mesmo formato do 403 de 2FA, que a SPA já sabe seguir. O texto entra no banco por script de operação (`cms:publish-legal`). Não há rota HTTP de publicação nem arquivo de termo no repositório.

**Tech Stack:** Hono, Drizzle/libSQL, `node:test` (cms), React + vitest (cms/web).

**Spec:** issue #10; `spec/lgpd.md` LGPD-RF02, RF04, RT04, RT05, DOC01; `spec/arquitetura.md` §5.13 lacuna 1.

## Global Constraints

- Branch nova a partir de `develop`: `feat/10-aceite-termo-cms`. PR com base `develop`.
- Nenhum texto de termo definitivo é escrito neste plano: F-11 (controlador) e T7-R (revisão jurídica) estão pendentes. A fixture de teste usa texto obviamente fictício.
- `doc_type` do aceite do operador: `'tos'` (LGPD-DOC01, "Obrigatório para o CMS"). Nada de `consent`/`privacy` neste item.
- `legal_document` **e** `consent_record` são append-only por gatilho. Corrigir termo publicado = publicar versão nova (LGPD-RT04).
- `doc_hash` = SHA-256 hex (64 caracteres minúsculos) dos bytes UTF-8 do texto **normalizado** (BOM removido, CRLF → LF), calculado no servidor. O cliente nunca informa hash para publicar.
- Linha de domínio e linha da trilha são gravadas **atomicamente** (`client.batch(..., 'write')`). Aceite sem trilha não pode existir.
- Instantes (`effective_from`, `accepted_at`, `occurred_at`) pelo relógio do banco: `strftime('%Y-%m-%dT%H:%M:%fZ','now')`.
- Ações novas da trilha (`legal_publish`, `consent_accept`) entram em `ACOES_QUE_NAO_REABREM` (`contract/src/golden.ts`); `cms/test/audit-acoes.test.ts` reprova se faltarem.
- Rota, script e tela novos exigem linha em `docs/operacao.md`; `cms/test/doc-operacao.test.ts` confere.
- Commits sem atribuição de IA. Mensagens em pt-BR.

## Decisões que divergem do texto da issue (e por quê)

1. **`/api/me` NÃO fica isento do bloqueio** (a issue pedia isenção). A SPA decide o fluxo de entrada pela resposta de `/api/me` (`cms/web/src/api/entrada.ts`), e o painel não faz outra chamada. Com `/api/me` isento, o operador entraria no painel sem nunca ver o termo. A única rota isenta é `/api/consentimento`, como exceção nomeada (padrão de `ROTAS_DE_CADASTRO_2FA`). `/api/auth/*` já está fora do grupo protegido.
2. **Sem termo publicado, o bloqueio fica fechado** (403 com o mesmo `next`), e `GET /api/consentimento` responde 404. A RF02 diz "bloqueia o acesso até o aceite". Abrir por omissão faria o CMS rodar sem termo em produção sem que nada acusasse.
3. **A tela fica em `/entrar/termo`, com `sessao: 'dispensa'`**, e não atrás de `Protegida`. Enquanto o aceite falta, `/api/me` responde 403, e `Protegida` mandaria a pessoa para `/entrar`, criando um laço.
4. **`legal_document` vira append-only nesta PR.** A issue supõe que já é, mas `APPEND_ONLY_TABLES` não a contém. Com o gatilho, o gate não precisa recalcular o hash a partir de `content_md`: o texto de uma versão publicada não muda mais.

## Implantação: termo provisório (decisão do dono, 2026-11-19)

Com esta PR na VPS, ninguém passa do login (nem o admin) até existir um termo publicado. Enquanto F-11 e T7-R estiverem pendentes, quem opera publica pelo `cms:publish-legal` um **termo interno provisório**, que fica fora do repositório. O manual (Task 3) registra:

- que o termo é provisório e não substitui o texto revisado;
- a versão a usar (`0.x`, ex. `0.1.0`);
- que, quando o texto revisado chegar, publica-se `1.0.0` e todos os operadores aceitam de novo no próximo acesso.

## Review Focus

1. **Termo trocado enquanto o operador lia**: o POST com hash antigo deve responder 409 com o documento vigente e nunca gravar aceite de um texto que a pessoa não viu. Teste na Task 2.
2. **Edição do texto de versão publicada** (`UPDATE legal_document` à mão): deve ser recusada pelo gatilho. Teste via `append-only.test.ts` (Task 1) e na Task 2.
3. **Clique duplo / dois POSTs simultâneos**: no máximo uma linha de aceite e uma de trilha. Teste com `Promise.all` na Task 2.
4. **Recarregar `/entrar/termo` ou sessão expirada durante a leitura**: a tela leva a `/entrar` no 401 e ao cadastro no 403 de 2FA. Nunca fica em branco. Teste na Task 4.
5. **Operador desligado ou sem 2FA**: os bloqueios anteriores respondem primeiro, e o 403 de consentimento nunca mascara o de 2FA. Teste na Task 2.

## Cobertura dos critérios de aceite da issue

| Critério | Coberto por |
|---|---|
| 403 antes, 200 depois, mudança de hash volta a 403 | `cms/test/consent-gate.test.ts` (Task 2) |
| `doc_hash` igual ao do documento; `UPDATE` recusado | `consent-gate.test.ts` + `append-only.test.ts` |
| "`web-conformance` cobre a tela" | **Reinterpretado.** `web-conformance.test.ts` confere formulários de conteúdo contra o esquema e não tem relação com esta tela. Cobrem a tela: `cms/web/test/telas.test.tsx` (comportamento) e `doc-operacao.test.ts` (`/entrar/termo` em `ROTAS_DA_SPA` exige linha no manual). O PR diz isso explicitamente. |
| `doc-operacao.test.ts` verde | Tasks 2–4 |

---

### Task 1: Serviço de documento legal e aceite, com `legal_document` append-only

**Files:**
- Create: `cms/src/services/legal.ts`
- Modify: `cms/src/services/audit.ts` (extrair `comandoDeAuditoria`; `recordAudit` passa a usá-lo)
- Modify: `cms/src/db/schema/index.ts` (`APPEND_ONLY_TABLES` += `{ table: legalDocument, requirement: 'LGPD-RT04' }`)
- Modify: `cms/src/db/triggers.sql` (gerado por `npm run cms:triggers`, nunca editado à mão)
- Modify: `cms/test/support/db.ts` (`APPEND_ONLY_ROWS.legal_document`, senão `append-only.test.ts` reprova)
- Modify: `cms/src/db/schema/governance.ts` (comentário do cabeçalho: agora são três tabelas append-only)
- Modify: `contract/src/golden.ts` (`ACOES_QUE_NAO_REABREM` += `'legal_publish'`, `'consent_accept'`)
- Test: `cms/test/legal.test.ts`

**Interfaces:**
- Em `cms/src/services/audit.ts`:
  - `export function comandoDeAuditoria(salt: string, event: AuditEvent, condicao?: { sql: string; args: InValue[] }): InStatement`: `INSERT INTO audit_entry (...) SELECT ... [WHERE <condicao>]`. Mantém `recusarBytes`, `pseudonymize(ip)`, `randomUUID()` e o `strftime` do banco. `recordAudit` vira `client.execute(comandoDeAuditoria(salt, event))`, sem mudar a assinatura nem os chamadores.
- Em `cms/src/services/legal.ts`:
  - `export const TIPO_DO_TERMO_DO_OPERADOR = 'tos' as const`
  - `export const METODO_DE_ACEITE = 'cms_interface' as const` (valor de `consent_record.method`)
  - `export interface DocumentoVigente { type: 'tos'; version: string; contentMd: string; hash: string; effectiveFrom: string }`
  - `export function normalizarTexto(texto: string): string`: tira o BOM inicial e troca `\r\n` por `\n`.
  - `export function hashDoTexto(contentMd: string): string`: sha256 hex. Puro, não normaliza.
  - `export async function documentoVigente(client: Client): Promise<DocumentoVigente | null>`: linha `type='tos'` com `ORDER BY effective_from DESC, rowid DESC LIMIT 1`.
  - `export async function publicarDocumento(client: Client, salt: string, entrada: { version: string; contentMd: string }, autorId: string | null): Promise<DocumentoVigente>`: normaliza e calcula o hash. Lança `Error` se o texto normalizado for vazio ou tiver o mesmo hash do vigente (sem mudança, não se força re-aceite de todo mundo). Faz `client.batch([insert legal_document, comandoDeAuditoria(legal_publish)], 'write')`, com `entityType: 'legal_document'` e `after: {type, version, hash}`. A versão repetida já é recusada pelo `unique(type, version)`.
  - `export async function aceitouVigente(client: Client, subjectRef: string): Promise<boolean>`: existe `consent_record` com `subject_ref`, `doc_type='tos'` e `doc_version` e `doc_hash` iguais aos do vigente. Devolve `false` se não houver vigente.
  - `export type ResultadoAceite = { ok: true; documento: DocumentoVigente } | { ok: false; motivo: 'sem_documento' } | { ok: false; motivo: 'desatualizado'; documento: DocumentoVigente }`
  - `export async function registrarAceite(client: Client, salt: string, subjectRef: string, visto: { version: string; hash: string }): Promise<ResultadoAceite>`: se `visto` difere do vigente, responde `desatualizado`. Senão, gera `id = randomUUID()` e executa um **único** `client.batch(..., 'write')` com duas instruções:
    ```sql
    INSERT INTO consent_record (id, subject_ref, doc_type, doc_version, doc_hash, method, accepted_at)
    SELECT :id, :sujeito, 'tos', :versao, :hash, 'cms_interface', strftime('%Y-%m-%dT%H:%M:%fZ','now')
    WHERE NOT EXISTS (SELECT 1 FROM consent_record
                      WHERE subject_ref = :sujeito AND doc_type = 'tos'
                        AND doc_version = :versao AND doc_hash = :hash);
    ```
    seguida de `comandoDeAuditoria(salt, {action: 'consent_accept', actorId: subjectRef, entityType: 'consent_record', entityId: id, after: {docType, docVersion, docHash}}, { sql: 'EXISTS (SELECT 1 FROM consent_record WHERE id = ?)', args: [id] })`. A trilha só grava se a linha deste `id` entrou: a repetição é no-op nas duas tabelas. Sem índice único, para não impedir o re-aceite depois de uma revogação (LGPD-RF05, futura).

- [ ] **Step 1: Escrever os testes** em `cms/test/legal.test.ts`, contra o banco de `freshApp()` (`f.client`, `TEST_ENV.hashSalt`). O `subjectRef` é um operador de `novoOperador(f, 'editor')`, porque a FK de `actor_id` exige operador real. Banco sem termo: `freshApp(undefined, { termo: false })` (parâmetro criado na Task 2; até lá `freshApp()` já não tem termo).
  - `hashDoTexto('abc') === 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'`.
  - `normalizarTexto('﻿a\r\nb') === 'a\nb'`.
  - `documentoVigente` devolve `null` sem termo.
  - Publicar v1 e depois v2 → `documentoVigente().version === 'v2'`.
  - Publicar com o mesmo texto do vigente → rejeita; publicar `texto.replace(/\n/g, '\r\n')` → também rejeita (normalização).
  - Publicar grava `legal_publish` na trilha.
  - `registrarAceite` com `visto` correto → `ok`; `consent_record` tem 1 linha com `doc_hash === hashDoTexto(texto)` e `method === 'cms_interface'`; `audit_entry` tem 1 `consent_accept` com `actor_id` = operador e `entity_id` = id da linha.
  - Segundo `registrarAceite` igual → `ok`, e continua 1 linha em `consent_record` **e** 1 `consent_accept`.
  - `visto.hash` errado → `{ ok: false, motivo: 'desatualizado' }` com o `documento` vigente, e nenhuma linha nova.
  - Sem documento → `{ ok: false, motivo: 'sem_documento' }`.
  - `aceitouVigente` vira `false` depois de publicar v2.
- [ ] **Step 2:** `npm --workspace @guia-ubs/cms test -- test/legal.test.ts` → FAIL (módulo não existe).
- [ ] **Step 3:** Implementar `comandoDeAuditoria`, `legal.ts`, a entrada em `APPEND_ONLY_TABLES` e a linha `APPEND_ONLY_ROWS.legal_document` (`id: 'legal-1'`, `type 'tos'`, `version '1.0.0'`, `content_hash` = `'c'.repeat(64)`, `effective_from` = `NOW`). Rodar `npm run cms:triggers`. Acrescentar as duas ações em `ACOES_QUE_NAO_REABREM`.
- [ ] **Step 4:** `npm test` (raiz) → PASS, incluindo `append-only.test.ts` (agora com `legal_document`), `audit.test.ts` e `audit-acoes.test.ts`. `npm run typecheck` limpo. `npm run cms:check` limpo (o gatilho mora em `triggers.sql`, sem migração nova).
- [ ] **Step 5: Commit**: `feat(cms): termo de uso append-only e aceite atomico com a trilha (#10)`

---

### Task 2: Bloqueio `requireConsent` e rotas `/api/consentimento`

**Files:**
- Modify: `cms/src/auth/middleware.ts` (+ `requireConsent`)
- Create: `cms/src/routes/consent.ts`
- Modify: `cms/src/app.ts` (montagem)
- Modify: `cms/test/support/app.ts` (`freshApp` publica termo; `aceitarTermo`; `sessaoDe` aceita)
- Modify: testes existentes que quebrarem (Step 5)
- Modify: `docs/operacao.md` (tabela de rotas: `GET /api/consentimento`, `POST /api/consentimento`)
- Test: `cms/test/consent-gate.test.ts`

**Interfaces:**
- Consumes: Task 1 (`documentoVigente`, `aceitouVigente`, `registrarAceite`, `publicarDocumento`).
- Produces:
  - `export const ROTA_DE_CONSENTIMENTO = '/api/consentimento'` (em `middleware.ts`)
  - `export function requireConsent(client: Client): MiddlewareHandler<{ Variables: AuthVariables }>`: deixa passar só `ROTA_DE_CONSENTIMENTO`. Nas demais rotas, se `aceitouVigente(client, operador.id)` for falso, responde `403 { error: 'aceite do termo de uso pendente', next: ROTA_DE_CONSENTIMENTO }`.
  - `export function consentRoutes(client: Client, salt: string)`:
    - `GET /` → 200 `{ type, version, contentMd, hash, effectiveFrom, aceito: boolean }`; 404 `{ error: 'nenhum termo de uso publicado' }`.
    - `POST /` com corpo zod `{ version: string().min(1), hash: string().regex(/^[0-9a-f]{64}$/) }`: corpo inválido → 400; `sem_documento` → 404; `desatualizado` → 409 `{ error: 'o termo mudou', vigente: <DocumentoVigente> }`; ok → 200 `{ aceito: true, version, hash }`. O campo é **`vigente`**, nunca `atual`: `CorpoDeErro.atual` da SPA é `string` (estado da FSM), e `classificar` transformaria o objeto num `conflito_estado` torto.
  - Em `app.ts`: `protegido.use('*', requireConsent(client))` logo após `require2fa()`, e `protegido.route('/consentimento', consentRoutes(client, env.hashSalt))`.
  - Em `test/support/app.ts`:
    - `export const TERMO_DE_TESTE = 'Termo de uso FICTICIO, apenas para teste automatizado.'`
    - `freshApp(spa?: string, opcoes?: { termo?: boolean })`: com `termo` (padrão `true`), chama `publicarDocumento(client, salt, { version: 'teste-1', contentMd: TERMO_DE_TESTE }, null)`.
    - `export async function aceitarTermo(fixture: Fixture, cookie: string): Promise<void>`: `GET` + `POST /api/consentimento` pelo fluxo real, com `assert.equal(status, 200)`.
    - `sessaoDe` chama `aceitarTermo` antes de devolver.

- [ ] **Step 1: Escrever `cms/test/consent-gate.test.ts`**. Aqui `sessao` é um operador com 2FA (`novoOperador` + `ativar2fa` + `loginCom2fa`), **sem** `aceitarTermo`.
  - Antes do aceite: `GET /api/me` e `GET /api/releases` → 403 com `next === '/api/consentimento'`; `GET /api/consentimento` → 200, com `hash === hashDoTexto(TERMO_DE_TESTE)` e `aceito === false`.
  - `POST` com o hash lido → 200. Depois, `/api/me` e `/api/releases` → 200 e `GET /api/consentimento` → `aceito === true`. `consent_record.doc_hash` = hash do documento. `UPDATE consent_record SET method='x'` e `UPDATE legal_document SET content_md='x'` → rejeitam (gatilho).
  - **Concorrência:** `Promise.all` de dois `POST` idênticos → os dois 200; `consent_record` com 1 linha para o operador; `audit_entry` com 1 `consent_accept`.
  - Publicar `teste-2` → `/api/me` volta a 403; aceitar `teste-2` → 200.
  - `POST` com o hash de `teste-1` depois de `teste-2` → 409 com `vigente.version === 'teste-2'` e nenhuma linha nova em `consent_record`.
  - `POST` com `{ version: 'x', hash: 'nao-hex' }` → 400.
  - `freshApp(undefined, { termo: false })`: `/api/me` → 403 com o `next`; `GET /api/consentimento` → 404; `POST` → 404.
  - Operador SEM 2FA (só `login`): `/api/me` → 403 com `next === '/api/auth/two-factor/enable'` (o bloqueio de 2FA responde primeiro).
  - Sem sessão: `GET /api/consentimento` → 401.
- [ ] **Step 2:** `npm --workspace @guia-ubs/cms test -- test/consent-gate.test.ts` → FAIL.
- [ ] **Step 3:** Implementar `requireConsent`, `consentRoutes`, a montagem em `app.ts` e as mudanças em `test/support/app.ts`. Em `legal.test.ts`, passar `{ termo: false }` onde o teste precisa de banco sem termo.
- [ ] **Step 4:** `npm --workspace @guia-ubs/cms test -- test/consent-gate.test.ts` → PASS.
- [ ] **Step 5: Consertar o resto da suíte.** Rodar `npm --workspace @guia-ubs/cms test`. Quebras esperadas, ainda não conferidas:
  - `auth-flow.test.ts` e `audit.test.ts` usam `loginCom2fa` direto e esperam 200 em `/api/me` → chamar `aceitarTermo` antes.
  - Testes que contam linhas de `audit_entry` agora veem `legal_publish`/`consent_accept` → filtrar por ação, sem afrouxar a asserção.
  - `telemetry-ingest.test.ts` lista `/api/me` como rota que exige sessão. Sem cookie continua 401 e deve seguir verde.

  Não editar asserção só para "passar" sem entender a quebra.
- [ ] **Step 6:** Acrescentar as duas rotas à tabela de rotas de `docs/operacao.md`. `npm test` e `npm run typecheck` → verdes.
- [ ] **Step 7: Commit**: `feat(cms): aceite do termo bloqueia rota protegida ate a versao vigente (#10)`

---

### Task 3: Script `cms:publish-legal` e manual de operação

**Files:**
- Create: `cms/scripts/publish-legal.ts`
- Modify: `cms/package.json` (`"publish-legal": "tsx scripts/publish-legal.ts"`), `package.json` raiz (`"cms:publish-legal": "npm --workspace @guia-ubs/cms run publish-legal --"`)
- Modify: `cms/scripts/create-admin.ts` (mensagem final)
- Modify: `docs/operacao.md` (§2.4.1 nova; §2.5 corrigida)

**Interfaces:**
- Consumes: `publicarDocumento` (Task 1; a normalização já acontece lá).
- CLI: `npm run cms:publish-legal -- --autor <id> --versao <x.y.z> --arquivo <caminho.md>`. Faltando argumento → mensagem de uso e `exit(2)`. Imprime `versao`, `hash` e "todos os operadores serão levados a aceitar de novo no próximo acesso". Segue o padrão de `create-admin.ts`/`import-golden.ts`: `loadEnv()`, `createDatabaseClient`, `client.close()` no `finally`. `--autor` é obrigatório para a trilha ter ator; no bootstrap, usa-se o id impresso por `cms:create-admin`.

- [ ] **Step 1:** Citar `npm run cms:publish-legal` na seção nova do manual e rodar `npm --workspace @guia-ubs/cms test -- test/doc-operacao.test.ts` → FAIL ("todo comando `npm run` citado existe").
- [ ] **Step 2:** Escrever o script e os dois scripts npm.
- [ ] **Step 3: Manual.**
  - **§2.4.1 "Publicar o Termo de Uso"**, logo após "Criar o primeiro operador":
    - Sem termo publicado, **ninguém** passa do login, nem o admin.
    - Enquanto F-11/T7-R estiverem pendentes, publica-se um **termo interno provisório** (versão `0.x`), mantido fora do repositório. Quando o texto revisado chegar, publica-se `1.0.0`, e todos aceitam de novo.
    - Publicar versão nova força re-aceite de todos. Publicar texto idêntico ao vigente é recusado (fim de linha CRLF/LF e BOM não contam como mudança).
    - O texto de uma versão publicada não pode ser editado (gatilho): para corrigir, publica-se versão nova.
    - Ordem de implantação: migrar → criar operador → **publicar termo** → ativar 2FA → aceitar.
  - **§2.5**:
    - No roteiro de `curl`, a linha `/api/me  # 200 = pronto` vira `# 403 aceite pendente`. Acrescentar o passo 4, `GET` e `POST /api/consentimento` com `-H "$J" -H "$O"` (o `Origin` é exigido no POST), passando o `version` e o `hash` lidos no GET. Depois disso, `/api/me` → `200 = pronto`.
    - O parágrafo "Pela interface" passa a dizer que, concluído o segundo fator, a entrada leva a `` `/entrar/termo` `` e só depois do aceite ao painel em `` `/` ``.
- [ ] **Step 4:** `create-admin.ts`: a mensagem final passa a dizer que a conta só alcança rota protegida depois de **(1)** ativar o 2FA e **(2)** aceitar o termo vigente, e que, se não houver termo publicado, é preciso rodar `cms:publish-legal` com o id acima.
- [ ] **Step 5:** `npm test` → PASS.
- [ ] **Step 6:** Rodar o script contra um sqld local de desenvolvimento (se houver) com um `.md` fictício na scratchpad e conferir a linha em `legal_document`. Sem sqld disponível, registrar no PR que o script não foi exercitado fora do teste.
- [ ] **Step 7: Commit**: `feat(cms): script de publicacao do termo de uso e manual (#10)`

---

### Task 4: Tela de aceite na SPA

**Files:**
- Modify: `cms/web/src/api/erros.ts` (`Falha` += `{ tipo: 'consentimento' }`)
- Modify: `cms/web/src/api/api.ts` (`classificar`; `aoExigirConsentimento`; `conferir` dispara o aviso)
- Modify: `cms/web/src/api/entrada.ts` (`EstadoDaEntrada` += `{ estado: 'precisa_aceitar' }`; `estadoDaSessao` distingue pelo `next`)
- Modify: `cms/web/src/rotas.ts` (entrada `/entrar/termo`)
- Modify: `cms/web/src/telas/entrada.tsx` (`TelaDeTermo`; `useDestino` trata `precisa_aceitar`)
- Modify: `cms/web/src/App.tsx` (rota; aviso; `Barra` escondida no fluxo de entrada)
- Modify: `cms/web/src/estilo.css` (`.termo`)
- Test: `cms/web/test/api.test.ts`, `cms/web/test/telas.test.tsx`

**Interfaces:**
- Consumes: o contrato HTTP da Task 2 (403 com `next: '/api/consentimento'`; GET/POST `/api/consentimento`; 409 com `vigente`).
- Produces:
  - `export function aoExigirConsentimento(fn: () => void): void` em `api.ts`.
  - Em `classificar`, **antes** do ramo de segundo fator: `corpo.next === '/api/consentimento'` → `{ tipo: 'consentimento' }`.
  - `estadoDaSessao`: 403 com `next === '/api/consentimento'` → `{ estado: 'precisa_aceitar' }`. Os outros 403 seguem como hoje.
  - `ROTAS_DA_SPA` += `{ caminho: '/entrar/termo', rotulo: 'Termo de uso', exige: null, sessao: 'dispensa', naBarra: false }`.
  - `export function TelaDeTermo()`. Usa `sondar('/api/consentimento')` e `tentar('/api/consentimento', { version, hash })`, que não disparam os avisos globais. Por isso, a tela trata **todos** os status, tanto no GET quanto no POST:
    - 200 (GET) → título, `Versão <version>`, o texto em `<pre className="termo">` (sem biblioteca de markdown nova) e o botão "Li e aceito o termo de uso".
    - 200 (POST) → `recarregar()` e `navegar('/')`.
    - 409 → troca o documento pelo `vigente` do corpo e mostra "O termo foi atualizado enquanto você lia. Leia a versão nova."
    - 404 → "Nenhum termo de uso publicado. Peça a quem opera o servidor para rodar `cms:publish-legal`.", sem botão de aceite.
    - 401 → `navegar('/entrar')` (sessão inexistente ou expirada durante a leitura).
    - 403 com `next` diferente de `/api/consentimento` → `navegar('/entrar/cadastrar-2fa')`.
    - 403 `operador desligado` → mostra "Este operador foi desligado." sem botão de aceite.
    - Outro status → "Erro no servidor; tente de novo." O botão continua disponível.
    - Botão **"Sair"** sempre visível: `tentar('/api/auth/sign-out')`, `esquecer()`, `navegar('/entrar')`. É quem não quer aceitar que precisa de saída; a interface não tinha "Sair" em lugar nenhum.
  - `.termo { white-space: pre-wrap; overflow-wrap: anywhere; }`: termo jurídico tem parágrafo inteiro numa linha.
  - `App.tsx`:
    - `aoExigirConsentimento(() => { if (!dispensaSessao(caminho.current)) navegar('/entrar/termo'); })`;
    - `<Route path="/entrar/termo" element={<TelaDeTermo />} />`;
    - `Barra` devolve `null` quando `dispensaSessao(local.pathname)`: sem isso, o operador em cache faz a barra aparecer na tela do termo, e cada link volta a ela.

- [ ] **Step 1: Testes.**
  - Em `api.test.ts`: 403 `{error, next: '/api/consentimento'}` → `ErroApi` com `falha.tipo === 'consentimento'`, e o aviso instalado é chamado uma vez. 403 com `next` de 2FA continua `segundo_fator`.
  - Em `telas.test.tsx` (com o stub de `fetch` por caminho já usado ali):
    - a tela mostra a versão e o texto;
    - o clique envia o `{version, hash}` lido do GET;
    - 409 mostra a versão de `vigente` e o aviso;
    - 404 mostra a mensagem sem botão de aceite;
    - 401 no GET navega para `/entrar`;
    - 403 de 2FA no GET navega para `/entrar/cadastrar-2fa`;
    - 403 `operador desligado` mostra a mensagem;
    - "Sair" chama `/api/auth/sign-out` e navega para `/entrar`;
    - `estadoDaSessao` com 403 de consentimento devolve `precisa_aceitar`;
    - abrir `/entrar/termo` com a sondagem de `/api/me` em 403 de consentimento **não** redireciona;
    - a barra não aparece em `/entrar/termo` com operador em cache.
- [ ] **Step 2:** `npm --workspace @guia-ubs/cms-web test` → FAIL.
- [ ] **Step 3:** Implementar. Se algum `switch` sobre `Falha` ou `EstadoDaEntrada` exigir exaustividade, `tsc` aponta o lugar; tratar ali como "aceite pendente".
- [ ] **Step 4:** `npm --workspace @guia-ubs/cms-web test`, `npm test` (doc-operacao confere `/entrar/termo` no manual, já citado pela Task 3) e `npm run typecheck` → verdes.
- [ ] **Step 5: Verificação manual.** Rodar `npm --workspace @guia-ubs/cms run dev` + `npm --workspace @guia-ubs/cms-web run dev` contra um banco local e percorrer: operador novo → publicar termo `0.1.0` → 2FA → cai em `/entrar/termo` sem barra → aceita → painel; publicar `0.2.0` → recarregar → volta ao termo; "Sair" funciona. Se não houver ambiente, dizer isso no PR.
- [ ] **Step 6: Commit**: `feat(cms-web): tela de aceite do termo de uso (#10)`

---

### Task 5: Fechar a lacuna na arquitetura

**Files:**
- Modify: `spec/arquitetura.md` (§5.13: lacuna 1 riscada com "Fechada pela #10, §5.x"; nova subseção §5.x com o resultado)
- Modify: `spec/arquitetura.md` §Roadmap, se a #10/P1-8 tiver linha lá

- [ ] **Step 1:** Escrever a §5.x:
  - as quatro decisões divergentes acima;
  - a implantação com termo provisório;
  - o critério de `web-conformance` reinterpretado;
  - o que ficou de fora: revogação de aceite pelo operador (LGPD-RF05); Política de Privacidade (`privacy`) e Aviso (`consent`) não são exigidos no login; o expurgo por prazo (RT10) agora também precisa considerar `legal_document`.
- [ ] **Step 2:** `npm test` → verde.
- [ ] **Step 3: Commit**: `docs(arquitetura): resultado da #10, aceite do termo no 1o login do CMS`
