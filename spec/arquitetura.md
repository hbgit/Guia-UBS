# Guia UBS — Arquitetura de Implementação (Blueprint)

> **Fonte:** [PRD.md](PRD.md) (governa) · normativos: [espec.md](espec.md) (FSM/invariantes), [stack.md](stack.md) (tecnologia/ADR), [lgpd.md](lgpd.md) (conformidade).
> **Status:** PROPOSTA — aguardando aprovação. Nenhum código será escrito antes da confirmação.
> **Escopo deste documento:** estrutura de pastas do monorepo, esquema completo dos três bancos, contratos de artefato e sequenciamento de construção.

---

## 1. Resumo

Monorepo com quatro artefatos de software (`app/` Flutter, `cms/` e `packer/` TypeScript, `infra/` Compose+Ansible) e um diretório de contratos (`contract/`) que é a espinha dorsal: dele derivam, por codegen, os tipos Dart e a validação TS. Três bancos de dados, todos SQLite/libSQL: **`content.db`** (device, read-only, distribuído e assinado), **`user.db`** (device, read-write, mínimo, sem PII) e o **master do CMS** (autoria, governança e publicação).

A decisão de sequenciamento mais relevante: **o CMS é o último componente a ser construído, não o primeiro.** O app só precisa de um arquivo `content.db` assinado; o `packer` sabe produzi-lo a partir de SQL semente. Isso desbloqueia toda a validação de risco (Fase 1) sem depender da interface de autoria.

## 2. Padrões a Espelhar

| Categoria | Origem | Padrão a estabelecer |
|---|---|---|
| Nomenclatura | — (sem código) | Dart: `snake_case.dart`, um bounded context por diretório de topo em `lib/`. TS: `kebab-case.ts`, schema Drizzle particionado por domínio. Tabelas: `snake_case` singular; junções `a_b`. |
| Erros | [espec.md §3.3](espec.md) | `Result<T,E>` selado no domínio; exceção só na borda de FFI/IO. **Política fail-closed**: indeterminação na triagem resolve para `EMERGENCY`, nunca para silêncio. |
| Logging | [lgpd.md](lgpd.md) RT03 | Ring buffer local de 1 MB, IDs opacos (UUID efêmero de sessão), **proibido dado de saúde ou PII**. Sem stack trace com conteúdo de sessão. |
| Acesso a dados | [stack.md §2.2](stack.md) | Repositório por bounded context; `content.db` aberto somente-leitura; nenhuma escrita de sequência de tokens em disco (INV-5). |
| Testes | [PRD.md §5.3](PRD.md) | Esforço máximo em unitário do gate (golden clínico, pass 100%) e contrato; E2E mínimo (3 jornadas). Testes de FSM espelham linha a linha as matrizes de espec.md §4. |

---

## 3. Estrutura de Pastas (monorepo)

```
Guia-UBS/
├── CLAUDE.md
├── README.md · LICENSE
├── spec/                        # especificação (existente)
├── contract/                    # ── espinha dorsal: fonte dos contratos ──
│   ├── pack-schema.json         # schema do content.db (gerado do Drizzle)
│   ├── manifest-schema.json     # schema do manifest.json
│   ├── telemetry-schema.json    # ALLOWLIST de métricas (LGPD-RF14)
│   ├── keys/
│   │   ├── pack-signing-k1.pub  # chave pública embarcada no app
│   │   └── pack-signing-k2.pub  # dual-key para rotação sem release
│   └── CHANGELOG.md             # histórico de schemaVersion
├── app/                         # ── Flutter (o produto) ──
├── native/                      # ── fronteira C mínima ──
│   └── llama_shim/              # 4 funções sobre o llama.cpp (tag fixa b6100)
│       ├── gubs_llama.h · gubs_llama.c
│       └── CMakeLists.txt       # FetchContent do llama.cpp; build host e arm64
├── cms/                         # ── plano de controle (TS) ──
├── packer/                      # ── CLI de empacotamento (TS) ──
├── infra/                       # ── deploy ──
│   ├── compose.yaml             # topologia de produção (stack.md §7)
│   ├── compose.override.yaml    # dev
│   ├── Caddyfile
│   ├── .env.example
│   └── ansible/                 # provisionamento do VPS (LUKS, firewall, systemd)
├── seed/                        # conteúdo semente versionado (SQL + assets)
│   ├── 001_ontology.sql         # tokens de sintoma
│   ├── 002_routing_rules.sql    # regras + outcomes
│   ├── 003_cards.sql · 004_services.sql · 005_flow.sql
│   ├── golden/clinical_cases.yaml   # suite golden (espelhada no CMS)
│   └── assets/                  # ícones SVG, imagens, áudios Opus
└── .github/workflows/           # CI (ou .woodpecker/ se self-host)
    ├── contract.yml             # codegen + diff-check do contrato
    ├── app.yml                  # analyze + test + build APK
    ├── control-plane.yml        # lint + test cms/packer
    └── pack-release.yml         # valida → assina → publica (aprovação manual)
```

### 3.1 `app/` — Flutter

Organização **feature-first por bounded context** (PRD §2.1), com a regra de dependência `ui → triage → content ← sync`; `speech` e `telemetry` são folhas.

```
app/
├── pubspec.yaml · analysis_options.yaml
├── lib/
│   ├── main.dart · app.dart                  # MaterialApp + GoRouter
│   ├── core/
│   │   ├── result.dart                       # Result<T,E> selado
│   │   ├── disk_space.dart                   # statvfs; portão de 3 GB (RNF-03)
│   │   ├── app_paths.dart                    # getApplicationSupportDirectory
│   │   ├── app_logger.dart                   # ring buffer, sem PII
│   │   ├── clock.dart                        # injetável (testes determinísticos)
│   │   └── theme/                            # tokens: verde/vermelho/azul, 64dp
│   ├── content/                              # catálogo read-only
│   │   ├── data/content_database.dart        # abre content.db RO
│   │   ├── data/content_repository.dart
│   │   ├── data/active_pack_registry.dart    # qual pack está ativo + guard
│   │   └── domain/{card,symptom_token,routing_rule,service_info}.dart
│   ├── triage/                               # ── CONTEXTO CRÍTICO ──
│   │   ├── domain/severity.dart              # enum + operador max()
│   │   ├── domain/{gate_verdict,triage_result,triage_session}.dart
│   │   ├── gate/red_flag_gate.dart           # FUNÇÃO PURA E TOTAL
│   │   ├── engine/triage_engine.dart         # interface (Strategy)
│   │   ├── engine/llama_engine.dart          # política: falha → "sem opinião"
│   │   ├── engine/llama_runner.dart          # isolate dedicado (contexto vivo)
│   │   ├── engine/llama_bindings.dart        # dart:ffi ↔ native/llama_shim
│   │   ├── engine/engine_decoder.dart        # saída do SLM = entrada não confiável
│   │   ├── engine/rule_only_engine.dart      # kill switch (mesma tabela)
│   │   ├── engine/prompt_builder.dart        # determinístico (greedy, temp 0)
│   │   ├── triage_orchestrator.dart          # FSM-A
│   │   └── presentation/                     # telas + providers Riverpod
│   ├── sync/                                 # FSM-B
│   │   ├── resumable_downloader.dart         # Range + SHA-256 (COMPARTILHADO)
│   │   ├── model_downloader.dart             # modelo SLM + portão de 3 GB
│   │   ├── model_catalog.dart                # URL + SHA-256 versionados no app
│   │   ├── model_provisioning.dart           # First-Time Setup + trava + OTG
│   │   ├── model_sync_scheduler.dart         # política UNMETERED / override
│   │   ├── model_background_sync.dart        # ponte WorkManager (traduz a política)
│   │   ├── sync_service.dart                 # máquina explícita (enum + tabela)
│   │   ├── manifest_client.dart              # ETag + condicional
│   │   ├── pack_downloader.dart              # usa resumable_downloader
│   │   ├── pack_verifier.dart                # Ed25519 + SHA-256 + anti-downgrade
│   │   ├── pack_installer.dart               # staging → rename atômico
│   │   └── background_scheduler.dart         # WorkManager
│   ├── speech/{speech_service,system_tts_service,recorded_audio_service}.dart
│   ├── prefs/{user_database.dart,prefs_repository.dart}   # Drift
│   ├── telemetry/{counters.dart,telemetry_uploader.dart}  # allowlist
│   ├── privacy/                              # CAP-13 (LGPD-RF03)
│   ├── ui/onboarding/onboarding_screen.dart  # trava educativa + progresso %
│   ├── ui/{router.dart,screens/,widgets/}
│   └── generated/pack_models.dart            # codegen do contract/ (não editar)
├── assets/models/                            # GGUF baixado por script (fora do git)
├── test/                                     # unitário (espelha árvore de lib/)
│   ├── triage/gate/red_flag_gate_golden_test.dart   # pass 100% obrigatório
│   ├── triage/triage_orchestrator_fsm_test.dart     # matriz espec §4.1
│   └── sync/sync_service_fsm_test.dart              # matriz espec §4.2
├── integration_test/                         # airplane mode, sync instável, swap
└── android/
```

### 3.2 `cms/` e `packer/` — TypeScript

```
cms/
├── src/
│   ├── index.ts                     # bootstrap Hono
│   ├── db/
│   │   ├── schema/{auth,content,governance,publishing,telemetry}.ts
│   │   ├── migrations/              # drizzle-kit (expand→migrate→contract)
│   │   └── client.ts
│   ├── routes/{content,rules,assets,releases,approvals,telemetry}.ts
│   ├── services/
│   │   ├── audit.ts                 # trilha append-only
│   │   ├── optimistic-lock.ts       # 409 em conflito de version
│   │   ├── approval-workflow.ts     # dual review: editor ≠ aprovador
│   │   └── release-orchestrator.ts  # dispara packer
│   ├── auth/                        # Better Auth + RBAC + 2FA TOTP
│   └── web.ts                       # serve `web/dist` e faz recuo de histórico
├── web/                             # SPA React (Vite) — workspace próprio
│   ├── src/{api,telas}/             # `rotas.ts` é dado, sem DOM: `cms/test` o lê
│   └── test/                        # Vitest + Testing Library
├── test/
└── Dockerfile                       # multi-stage: deps→web→production

> **`cms/web/`, e não `cms/src/web/`.** Até o item 23 este bloco escrevia a SPA
> dentro de `src/`, enquanto §5.11, §5.12, o `README.md` e o `docs/operacao.md`
> escreviam `cms/web/`. Ficou `cms/web/`, que é o que todo o resto já dizia — e é
> um **workspace npm próprio**, porque o `npm test` da raiz só enxerga o que está
> em `workspaces`.
>
> O `Dockerfile` também nunca teve o estágio `dev` que este bloco prometia: são
> `deps → web → production`, e `production` precisa continuar sendo o último
> porque o serviço `packer` constrói o mesmo arquivo sem `target:`.

packer/
├── src/
│   ├── index.ts                     # CLI: build | validate | sign | publish
│   ├── extract.ts                   # master → snapshot imutável
│   ├── validate-referential.ts      # regra→token órfão = falha
│   ├── validate-golden.ts           # suite clínica; falha BLOQUEIA assinatura
│   ├── build-pack.ts                # escreve content.db + VACUUM
│   ├── sign.ts                      # Ed25519 do manifest canônico
│   ├── publish.ts                   # upload S3 (MinIO)
│   └── delta.ts                     # bsdiff (Fase 3)
└── test/
```

---

## 4. Esquema de Dados Completo

Convenções: SQLite/libSQL; PK `TEXT` para IDs estáveis de domínio (imutáveis por contrato), `INTEGER` autoincrement só onde a ordem interna importa; `*_at` em **ISO-8601 UTC** (`2026-08-13T14:05:00Z`); booleanos como `INTEGER 0|1`; `FOREIGN KEY` sempre declarada no DDL (`PRAGMA foreign_keys=ON`).

> **Nota de implementação (Fase 0):** o módulo de contrato [`contract/src/content-schema.ts`](../contract/src/content-schema.ts) declara apenas a **forma das linhas** — é dele que sai o codegen. As `FOREIGN KEY` são emitidas pelo DDL do packer e verificadas por `validate-referential.ts` antes da assinatura, que é a trava que realmente importa (um órfão bloqueia a publicação, não apenas um `INSERT`).

### 4.1 `content.db` — device, read-only, distribuído e assinado

Gerado pelo packer, nunca migrado no device (troca de arquivo). Sem qualquer dado de usuário.

| # | Tabela | Colunas | Notas |
|---|---|---|---|
| 1 | `pack_meta` | `id INTEGER PK CHECK(id=1)`, `pack_version INTEGER NOT NULL`, `schema_version TEXT NOT NULL`, `municipality_code TEXT`, `built_at TEXT`, `default_outcome_id TEXT NOT NULL`, `source_commit TEXT` | Linha única; `pack_version` é o inteiro monotônico do anti-downgrade (INV-7) |
| 2 | `symptom_token` | `id TEXT PK`, `kind TEXT CHECK(kind IN ('body_part','symptom','modifier'))`, `icon_ref TEXT NOT NULL→asset`, `sort_order INTEGER`, `deprecated INTEGER DEFAULT 0` | **IDs estáveis e imutáveis** — renomear quebra regra silenciosamente (débito prevenido no espec §7.2) |
| 3 | `token_translation` | `token_id TEXT→symptom_token`, `lang TEXT`, `label TEXT`, `audio_ref TEXT→asset`, PK(`token_id`,`lang`) | `label` é redundante ao ícone (nunca obrigatório na UI) |
| 4 | `routing_outcome` | `id TEXT PK` (`ROUTINE_UBS`,`EMERGENCY`), `severity_level INTEGER NOT NULL UNIQUE`, `card_id TEXT→card`, `venue_id TEXT→venue` | `severity_level` inteiro torna `max(gate,llm)` trivial e permite inserir níveis futuros sem migração de lógica |
| 5 | `routing_rule` | `id TEXT PK`, `priority INTEGER NOT NULL`, `outcome_id TEXT→routing_outcome`, `rationale TEXT`, `clinical_source TEXT` | **Tabela única para gate e RuleOnly** (proíbe lógica duplicada). O "red_flag_rules" da espec = subconjunto `WHERE outcome.severity_level = MAX` |
| 6 | `routing_rule_term` | `rule_id TEXT→routing_rule`, `group_no INTEGER`, `token_id TEXT→symptom_token`, `negated INTEGER DEFAULT 0`, PK(`rule_id`,`group_no`,`token_id`) | Forma normal disjuntiva: **E** dentro do grupo, **OU** entre grupos. Regras viram dados, não código (atualizáveis por pack, sem release) |
| 7 | `venue` | `id TEXT PK` (`UBS`,`UPA`,`HOSPITAL`), `icon_ref TEXT`, `color_token TEXT CHECK(color_token IN ('green','red','blue'))` | Semântica de cor fixa do design |
| 8 | `venue_translation` | `venue_id`, `lang`, `label`, `audio_ref`, PK(`venue_id`,`lang`) | |
| 9 | `card` | `id TEXT PK`, `kind TEXT CHECK(kind IN ('result','info','step','document'))`, `icon_ref TEXT`, `color_token TEXT`, `sort_order INTEGER` | Unidade de resposta exibida |
| 10 | `card_translation` | `card_id`, `lang`, `title TEXT`, `body TEXT`, `audio_ref TEXT`, PK(`card_id`,`lang`) | |
| 11 | `service` | `id TEXT PK`, `venue_id TEXT→venue`, `icon_ref TEXT`, `sort_order INTEGER` | Vacina, curativo, consulta… |
| 12 | `service_translation` | `service_id`, `lang`, `label`, `audio_ref`, PK(`service_id`,`lang`) | |
| 13 | `document` | `id TEXT PK`, `icon_ref TEXT`, `image_ref TEXT→asset` | Cartão SUS, identidade… |
| 14 | `document_translation` | `document_id`, `lang`, `label`, `hint TEXT`, `audio_ref`, PK(`document_id`,`lang`) | |
| 15 | `service_document` | `service_id→service`, `document_id→document`, `required INTEGER DEFAULT 1`, PK(`service_id`,`document_id`) | Junção N:N |
| 16 | `flow_step` | `id TEXT PK`, `venue_id TEXT→venue`, `step_order INTEGER NOT NULL`, `icon_ref TEXT` | Fluxograma de atendimento (CAP-09) |
| 17 | `flow_step_translation` | `step_id`, `lang`, `title`, `body`, `audio_ref`, PK(`step_id`,`lang`) | |
| 18 | `asset` | `ref TEXT PK`, `kind TEXT CHECK(kind IN ('icon','image','audio'))`, `path TEXT NOT NULL`, `sha256 TEXT NOT NULL`, `bytes INTEGER` | `path` relativo dentro do pack; hash verificado na instalação |

**Índices:** `routing_rule_term(token_id)`, `card_translation(lang)`, `flow_step(venue_id, step_order)`, `service_document(document_id)`.

**v1.1 (CAP-16/17), fora do MVP:** `vaccine`, `vaccine_schedule(profile, age_months)`, `health_profile`, `condition`, `medication`, `condition_medication` — mesmo padrão entidade + `*_translation`. Reservados aqui para que a evolução de `schemaVersion` seja aditiva (minor).

### 4.2 `user.db` — device, read-write (Drift)

Escopo deliberadamente mínimo. **Não existe tabela de sessão de triagem** — a sequência de tokens vive apenas em memória (INV-5 / LGPD-RF13), e um teste de CI falha se qualquer DAO referenciar tokens.

| # | Tabela | Colunas | Notas |
|---|---|---|---|
| 1 | `preference` | `key TEXT PK`, `value TEXT` | `lang`, `telemetry_opt_out`, `tts_enabled`, `municipality_code` |
| 2 | `sync_state` | `id INTEGER PK CHECK(id=1)`, `active_pack_version INTEGER`, `active_pack_hash TEXT`, `staged_pack_hash TEXT`, `download_offset INTEGER`, `manifest_etag TEXT`, `last_attempt_at TEXT`, `consecutive_failures INTEGER DEFAULT 0`, `circuit_open_until TEXT` | Estado da FSM-B; suporta retomada por Range e circuit breaker |
| 3 | `rejected_pack` | `pack_hash TEXT PK`, `reason TEXT CHECK(reason IN ('bad_signature','hash_mismatch','downgrade','schema_incompatible'))`, `rejected_at TEXT` | Blacklist do estado `REJECTED` |
| 4 | `telemetry_counter` | `metric_key TEXT`, `bucket_day TEXT`, `value INTEGER`, PK(`metric_key`,`bucket_day`) | Somente contadores da allowlist; granularidade diária (nunca timestamp fino) |
| 5 | `app_meta` | `key TEXT PK`, `value TEXT` | Versão do schema Drift, primeira execução |

### 4.3 Master do CMS — libSQL/`sqld` + Drizzle

Quatro domínios de schema. `version INTEGER` nas entidades editáveis implementa o travamento otimista (409 em conflito).

**A. Identidade e governança**

| # | Tabela | Colunas-chave | Notas |
|---|---|---|---|
| 1 | `admin_user` | `id`, `email UNIQUE`, `name`, `email_verified`, `image`, `created_at`, `updated_at`, `two_factor_enabled`, `role CHECK(role IN ('editor','clinical_reviewer','admin'))`, `disabled_at` | É o modelo `user` do Better Auth, **mapeado para esta tabela** em vez de criar uma segunda identidade — assim `audit_entry.actor_id`, `approval.approver_id` e todo `updated_by` continuam apontando para uma linha só. `role` e `disabled_at` entram como `additionalFields`. **Sem `password_hash`** (vive em `account.password`) e **sem `totp_secret_enc`** (vive em `two_factor.secret`, já cifrado pelo plugin) |
| 2 | `session` | conforme Better Auth (`expires_at`, `token UNIQUE`, `ip_address`, `user_agent`, `user_id`) | Expiração ≤ 24 h. `ip_address` é PII de sessão **viva**, apagada no logout; a trilha permanente guarda o IP só hasheado |
| 2b | `account` | conforme Better Auth | **Onde mora o hash Argon2id** da senha. As colunas de OAuth ficam sempre nulas: não há provedor social, e não deve haver |
| 2c | `verification` | conforme Better Auth | Tokens de curta duração |
| 2d | `two_factor` | `secret`, `backup_codes`, `user_id`, `verified`, `failed_verification_count`, `locked_until` | Segredo TOTP e códigos de recuperação **cifrados em repouso** pelo plugin, sob `BETTER_AUTH_SECRET` |
| 2e | `login_attempt` | `subject_key PK` (hash do e-mail), `failures`, `last_failure_at`, `locked_until` | Bloqueio **progressivo por conta** (LGPD-RT07). Tabela nossa: o rate limit do Better Auth é janela fixa por endpoint e quem distribui tentativas entre IPs passa por baixo |
| 3 | `audit_entry` | `id`, `actor_id→admin_user` (**nulável**), `action`, `entity_type`, `entity_id`, `before_json`, `after_json`, `ip_hash`, `occurred_at` | **APPEND-ONLY** (trigger bloqueia UPDATE/DELETE) — LGPD-RT03. `actor_id` nulo quando não houve ator autenticado: um login recusado é exatamente o evento que mais interessa registrar, e atribuí-lo à conta visada afirmaria que a pessoa agiu quando pode ter sido um ataque contra ela. Quem a tentativa visava fica em `entity_id`, pseudonimizado |
| 4 | `legal_document` | `id`, `type CHECK(type IN ('tos','privacy','consent'))`, `version`, `content_md`, `content_hash`, `effective_from` | Versionado; muda ⇒ re-aceite |
| 5 | `consent_record` | `id`, `subject_ref`, `doc_type`, `doc_version`, `doc_hash`, `method`, `accepted_at` | **APPEND-ONLY** — LGPD-RT05 (ônus da prova, art. 8º §2º) |

**B. Autoria de conteúdo** — espelha 4.1 em versão mutável: `municipality`, `symptom_token`, `token_translation`, `routing_outcome`, `routing_rule`, `routing_rule_term`, `venue(+trad)`, `card(+trad)`, `service(+trad)`, `document(+trad)`, `service_document`, `flow_step(+trad)`, `asset`. Diferenças em relação ao pack:

- toda entidade editável ganha `version INTEGER NOT NULL DEFAULT 1`, `updated_by→admin_user`, `updated_at` — **inclusive `municipality`**, que não existe no pack mas é editada; isentá-la faria a fábrica de CRUD do item 18 ter um caso especial, e caso especial em fábrica genérica é onde o próximo defeito se esconde;
- `asset` guarda `storage_key` (objeto no MinIO) além de `sha256` e `bytes`;
- `routing_rule` ganha `status CHECK(status IN ('draft','approved'))` — regra aprovada **nunca é editada in-place**: gera nova linha (append por versão de pack).

**Escopo por município (decidido no item 16).** O pack é por município; este banco é único. O corte não é preferência — é a **direção das chaves estrangeiras** que o decide:

| | Tabelas |
|---|---|
| **Global** (sem `municipality_id`) | `asset`, `symptom_token(+trad)`, `routing_outcome`, `routing_rule(+term)`, `venue(+trad)`, `card(+trad)` |
| **Municipal** (PK composta `(municipality_id, id)`) | `service(+trad)`, `document(+trad)`, `service_document`, `flow_step(+trad)` |

`symptom_token.icon_ref→asset.ref` e `routing_outcome.venue_id→venue.id` saem de tabelas globais. Se `asset` ou `venue` fossem municipais, a PK deles viraria composta e o lado global não teria `municipality_id` para oferecer: a FK não fecharia. Municipal→global é válido e é o único sentido que ocorre.

O ganho clínico é o motivo de as **regras** ficarem do lado global: uma red flag corrigida alcança toda a rede por construção — não existe o estado "corrigido num município, esquecido nos outros". Município que precise de escala de severidade própria é migração **aditiva** depois; o inverso — colapsar N cópias de uma regra clínica numa só — não é.

**C. Publicação**

| # | Tabela | Colunas-chave | Notas |
|---|---|---|---|
| 6 | `pack_release` | `id`, `municipality_id`, `pack_version INTEGER` (monotônico por município), `schema_version`, `status CHECK(status IN ('draft','pending_review','approved','building','built','published','revoked'))`, `claimed_at`, `pack_sha256`, `manifest_json`, `signed_at`, `published_at`, `created_by`, UNIQUE(`municipality_id`,`pack_version`) | Ciclo de vida do artefato |
| 7 | `approval` | `id`, `pack_release_id`, `approver_id→admin_user`, `role`, `decision CHECK(decision IN ('approve','reject'))`, `comment`, `decided_at` | **APPEND-ONLY**. `approver_id ≠ pack_release.created_by` é **gatilho** desde o item 19 — a regra por LINHA mora no banco, porque a ameaça é o insider e uma checagem só na rota protege apenas contra quem passa pela rota. O quórum (≥ 1 `clinical_reviewer`) é agregado sobre outras linhas e vive em `services/approval-workflow.ts` |
| 8 | `golden_case` | `id`, `tokens_json` (ex.: `["chest","pain"]`), `expected_outcome_id`, `clinical_source`, `added_by`, `reviewed_by`, `active` | Suite clínica versionada **no banco**, junto das regras que ela protege |
| 9 | `golden_run` | `id`, `pack_release_id`, `passed INTEGER`, `total INTEGER`, `failures_json`, `ran_at` | Falha ⇒ assinatura bloqueada (R5) |
| 10 | `signing_key` | `key_id TEXT PK` (`k1`,`k2`), `public_key`, `activated_at`, `retired_at` | Rotação dual-key sem release do app (R4) |

**D. Telemetria**

| # | Tabela | Colunas-chave | Notas |
|---|---|---|---|
| 11 | `telemetry_batch` | `id`, `cohort_key` (município+versão app+versão pack), `bucket_day`, `metrics_json`, `k_count INTEGER`, `received_at` | Validador rejeita `k_count < 20` na ingestão (LGPD-RF14); nenhum identificador de device |

### 4.4 Contrato de artefato — `manifest.json`

```jsonc
{
  "schemaVersion": "1.0",          // major incompatível ⇒ app rejeita
  "packVersion": 42,               // monotônico; anti-downgrade
  "municipality": "0000000",       // código fictício de exemplo
  "pack": { "url": "packs/pack-<sha256_12>.db", "sha256": "...", "bytes": 1234567 },
  "assets": [ { "ref": "icon.head", "url": "assets/...", "sha256": "...", "bytes": 2048 } ],
  "minAppBuild": 100,
  "publishedAt": "2026-08-13",
  "signature": { "alg": "Ed25519", "keyId": "k1", "value": "<base64>" }
}
```

A assinatura cobre a serialização canônica de todos os campos exceto `signature`. O device valida **nesta ordem**: assinatura → `packVersion > ativo` → `schemaVersion` suportado → SHA-256 de cada artefato → só então faz o swap.

---

## 5. Sequenciamento de Construção

Ordem derivada da dependência real (contrato → packer → app → CMS) e da urgência de validar riscos.

### Fase 0 — Fundação (pré-requisito de tudo)
1. Monorepo, lockfiles, `analysis_options.yaml`, CI esqueleto.
2. `contract/pack-schema.json` v1.0 + `manifest-schema.json` + `telemetry-schema.json`.
3. Pipeline de codegen TS→Dart com **diff-check em CI** (contrato fora de sincronia = build vermelho).
4. `infra/compose.yaml` subindo `sqld` + MinIO + Caddy.
**Saída:** `docker compose up` verde; codegen reprodutível.

### Fase 1 — PoC (valida R1, H2, H3 — PRD §6.2)
5. `seed/` com ontologia mínima (~30 tokens), regras e cards.
6. `packer` mínimo: build → validação referencial → golden → assinatura → publish.
7. **`red_flag_gate.dart`** (função pura) + suite golden **pass 100%**.
8. `llama_engine` PoC com bench em device ≥ 4 GB + `rule_only_engine`.
9. `sync_service` PoC: manifest com ETag, download com Range, verificação, swap atômico. ✅
**Saída (gate do PRD):** inferência p95 entre 3 s e 5 s ([ADR-003](stack.md)); sync retoma após corte; nenhum pack inválido ativado.

#### 5.1 Resultado do bench do item 8 (2026-08-14)

> **⚠ Leia junto com o [ADR-003](stack.md).** As conclusões abaixo foram escritas contra os orçamentos ORIGINAIS (≤ 400 MB, p95 < 3 s). Em 2026-08-17 esses orçamentos foram elevados para **≤ 1,2 GB** e **p95 entre 3 e 5 s**, justamente por causa destas medições. Sob a régua nova, o **Gemma 3 1B passa nos três critérios** (790 MB de footprint, 4731 ms de p95 no aparelho, 832 MB de RAM). As medições seguem válidas; o que mudou foi o limiar de aprovação.

**Medido em aparelho arm64 real:** Motorola Edge 40 Neo (MediaTek Dimensity 7030 — 6× Cortex-A55 @ 2,0 GHz + 2× Cortex-A78 @ 2,5 GHz), Android 15, 7,6 GB de RAM. Gemma 3 1B Q4_K_M, 20 iterações, contexto 512 tokens, 17 prompts gerados pelo construtor real do app.

O aparelho é **intermediário**, não o "≤ 4 GB de entrada" que o critério nomeia. Para cobrir essa lacuna sem estimativa de papel, o bench nativo (`native/llama_shim/bench_main.c`) roda sob `taskset`: fixar a inferência no cluster Cortex-A55 **mede** a classe de entrada, já que um SoC de entrada é essencialmente um punhado de A55.

| Configuração de núcleos | p50 | **p95** | máx | Pico RAM | Com saída |
|---|---|---|---|---|---|
| A — 4 threads, agendador livre | 3359 ms | **4731 ms** | 4772 ms | 832 MB | 20/20 |
| B — só Cortex-A55 ×4 · *proxy de entrada* | 8841 ms | **13130 ms** | 17121 ms | 832 MB | 20/20 |
| C — só Cortex-A78 ×2 · *melhor caso* | 3663 ms | **4675 ms** | 4816 ms | 831 MB | 20/20 |
| **Orçamento (RF-05 / RNF-03)** | — | **3000 ms** | — | 1536 MB | — |

> **"Com saída" ≠ "válida".** O bench nativo conta apenas geração não vazia; ele não decodifica. Validade (identificador do pacote reconhecido) só é medida pelo bench Dart — para o Gemma 3 1B, **17/20**. Os dois números não são intercambiáveis.

##### Fox-1-1.6B no mesmo aparelho (2026-08-17)

| Configuração | Gemma 3 1B | **Fox-1-1.6B** | Fox-1 / Gemma |
|---|---|---|---|
| A — 4 threads, agendador livre | 4731 ms | **6540 ms** | 1,38× |
| B — só Cortex-A55 ×4 · *proxy de entrada* | 13130 ms | **18870 ms** | 1,44× |
| C — só Cortex-A78 ×2 · *melhor caso* | 4675 ms | **6941 ms** | 1,48× |
| Pico de RAM no aparelho | 832 MB | 1143 MB | 1,37× |
| Arquivo Q4_K_M | 768 MB | 1066 MB | 1,39× |

**Fox-1 avaliado e rejeitado.** Mesma patologia do Gemma 3 1B, agravada: `vocab_size` 256000 com `hidden_size` 2048 põe ~524 M dos 1,6 B parâmetros só na tabela de embeddings — um terço do modelo é vocabulário, e isso não quantiza. É ~1,4× pior que o Gemma em latência, RAM e tamanho, **sem compensação em qualidade**: o modelo **base** (o URL pedido) acerta **1/20**, e a variante **Instruct**, **16/20** — abaixo dos 17/20 do Gemma. Não há eixo em que ele ganhe.

##### Modelos pequenos: Qwen2.5-0.5B e SmolLM2-360M (2026-08-17)

Testados por serem os únicos candidatos que **cabem no orçamento de 400 MB**. Aparelho, mesmas três configurações:

| Configuração | Gemma 3 1B (768 MB) | **Qwen2.5-0.5B Q4 (379 MB)** |
|---|---|---|
| A — 4 threads, agendador livre | 4731 ms | **3208 ms** |
| B — só Cortex-A55 ×4 · *proxy de entrada* | 13130 ms | **8965 ms** |
| C — só Cortex-A78 ×2 · *melhor caso* | 4675 ms | **2556 ms** ✅ |
| Pico de RAM | 832 MB | **433 MB** |
| Válidas (host) | 17/20 | **10/20** |

**Este é o único ponto de todo o estudo que passa no RF-05** — e ele não vale: 2556 ms foram obtidos nos dois núcleos Cortex-A78 de um aparelho intermediário, exatamente o hardware que o critério **não** descreve. Nos núcleos A55, que são a classe alvo, o mesmo modelo dá 8965 ms — 3,0× o orçamento e 1,8× o teto duro de 5 s.

**SmolLM2-360M reprovado antes do aparelho.** Validade de **2/20** (Q4) e **0/20** (Q8) no host; medir latência de um modelo que praticamente nunca responde nada aproveitável não produziria informação. Aos 360 M de parâmetros o modelo não sustenta a instrução de responder só um identificador.

##### Comparação de modelos (host — Intel i7-12650H, 4 núcleos fixados)

| Modelo (Q4_K_M) | Arquivo | p50 | p95 | Pico RAM | Válidas |
|---|---|---|---|---|---|
| Gemma 3 **1B** | 768 MB | 790 ms | **1041 ms** | 1136 MB | **17/20** |
| Gemma 3 **270M** | 241 MB | 394 ms | 589 ms | 540 MB | **1/20** |
| **Phi-4-mini** (3,8 B) | **2376 MB** | 2065 ms | **2197 ms** | **3950 MB** | **20/20** |
| **Fox-1-1.6B** base | 1066 MB | 1113 ms | 1207 ms | 1903 MB | **1/20** |
| **Fox-1-1.6B** Instruct | 1066 MB | 1118 ms | 1248 ms | 1905 MB | 16/20 |
| **Qwen2.5-0.5B** Q8 | 506 MB | 488 ms | 506 ms | 786 MB | 12/20 |
| **Qwen2.5-0.5B** Q4 | **379 MB** | 528 ms | 605 ms | 689 MB | 10/20 |
| **SmolLM2-360M** Q8 | 368 MB | 463 ms | 476 ms | 642 MB | **0/20** |
| **SmolLM2-360M** Q4 | **258 MB** | 593 ms | 626 ms | 550 MB | **2/20** |

**O achado que fecha a investigação: acerto acompanha tamanho, e o orçamento corta exatamente onde o modelo começa a ser útil.** Ordenados por validade — 20/20 (2376 MB), 17/20 (768 MB), 16/20 (1066 MB), 12/20 (506 MB), 10/20 (379 MB), 2/20 (258 MB), 1/20 (241 MB), 0/20 (368 MB) — os únicos que cabem em 400 MB pontuam ≤ 10/20. Não é uma questão de escolher melhor o modelo: é que a tarefa exige mais parâmetros do que o orçamento comporta, e mais parâmetros exigem mais tempo do que o aparelho de entrada tem.

**Cuidado: número de host é instável.** O Gemma 3 1B mediu p95 2549 ms numa sessão com compilações concorrentes e 939/1041/1048 ms em três repetições com a máquina ociosa. Só comparações feitas na MESMA sessão valem — e nenhum número de host serve como evidência de aceite: no aparelho, o mesmo Gemma dá 4731 ms (todos os núcleos) e 13130 ms (proxy A55), ou seja, o host é ~4,7× a ~13× otimista.

**Phi-4-mini avaliado e rejeitado (2026-08-14).** É o único modelo testado que acerta 20/20, mas perde em todo o resto: **2,2× mais lento** que o Gemma 3 1B na mesma sessão, arquivo de **2376 MB** (5,9× o orçamento total do RNF-03, contra 1,9× do Gemma) e pico de **3950 MB de RAM** — 2,6× o teto de 1,5 GB. Projetando pela razão host→aparelho do Gemma, o p95 no proxy de entrada ficaria na casa de **~29 s**; num aparelho de 4 GB o modelo provavelmente nem carregaria, deixando o motor permanentemente indisponível. Não foi medido em aparelho: as reprovações de tamanho e de RAM são aritméticas e independem de bancada.

**Quatro conclusões (avaliadas contra os orçamentos originais):**

1. **RF-05 reprova em todas as configurações medidas.** Nem o melhor caso deste aparelho (4675 ms) chega perto dos 3000 ms. No proxy de entrada, o p95 de 13,1 s é **2,6× o teto duro de 5 s** — praticamente toda triagem estouraria o timeout e cairia no `RuleOnlyEngine`. O modelo ocuparia 768 MB no aparelho para quase nunca responder a tempo. O critério **não** pode ser declarado atendido.

2. **RNF-03 (tamanho) é incompatível com o Gemma 3 1B.** O orçamento é *APK + modelo + pack ≤ 400 MB*. Medido:

   | Parcela | Tamanho |
   |---|---|
   | APK release arm64-v8a (inclui `libllama` + `libggml*` + `libgubs_llama` = 4,2 MB) | **21,1 MB** |
   | Modelo Gemma 3 1B Q4_K_M | **768 MB** |
   | Pack de conteúdo (semente) | < 1 MB |
   | **Total** | **≈ 790 MB** |

   O app não é o problema: ele responde por 2,7% do total. A menor quantização utilizável do 1B é **681 MB** (IQ4_XS), e o gargalo é a tabela de embeddings de 256k tokens, que praticamente não quantiza. Não há ajuste de flag que resolva — ou o orçamento sobe para ~1 GB, ou o modelo muda. **Decisão de produto pendente.**
3. **RNF-03 (RAM) passa, com folga.** Pico de 832 MB no aparelho contra teto de 1,5 GB — e o número é estável nas três configurações, porque o que ocupa memória são os pesos mapeados e o cache KV, não os núcleos. No host o pico foi maior (1136 MB): sob pressão, o Android devolve páginas do `mmap`, ao custo de releitura do armazenamento — que reaparece como latência.
4. **Trocar para o 270M não é saída trivial.** Ele cabe no orçamento e é 4× mais rápido, mas produziu identificador válido em **1 de 20** casos: na prática o app rodaria sempre em modo degradado. Um modelo que se abstém sempre é seguro (o gate decide) e inútil.

**Uma variável descartada por medição:** aplicar o *chat template* do Gemma **piora** o resultado (0/8 válidos — o modelo passa a responder em prosa, e o decodificador corretamente rejeita). O prompt de completação cru é a escolha certa.

**Integração Android (verificada em aparelho):** o `externalNativeBuild` do Gradle compila e empacota `libgubs_llama.so` para `arm64-v8a`, com fecho de dependências completo no APK (`libllama`, `libggml{,-base,-cpu}`, `libc++_shared`). No aparelho, `integration_test/native_shim_test.dart` confirma que o linker encontra a biblioteca, que a ABI compilada é a que o Dart espera, e que modelo ausente devolve `nullptr` sem derrubar o app. Release fixado em arm64-v8a; x86_64 só no debug, para emulador.

**Armadilha de ferramenta, registrada:** `flutter test integration_test/` **desinstala o app ao terminar**, e desinstalar apaga `/sdcard/Android/data/<pkg>/` — levando junto o GGUF de 768 MB enviado por `adb push`. Por isso o bench de aparelho vive em `native/llama_shim/bench_main.c`, rodando de `/data/local/tmp`; ele também é a única forma de fixar núcleos com `taskset`, o que de dentro do processo do app é impossível.

**O que falta:** nada de engenharia. Resta a **decisão de produto** sobre orçamento × modelo — ver as opções em aberto no item 8 da Fase 1.

#### 5.2 Resultado do item 9 — `sync_service` (2026-08-19)

A FSM-B está implementada como **máquina explícita**, não como fluxo dentro do
serviço: [`sync_fsm.dart`](../app/lib/sync/sync_fsm.dart) é a matriz da
[espec.md §4.2](espec.md) transcrita em enum de estados, eventos e ações, sem
I/O nenhum. O [`sync_service.dart`](../app/lib/sync/sync_service.dart) faz rede,
disco e relógio, e traduz o que aconteceu em eventos. **A máquina decide, o
driver executa** — é o antídoto direto para o anti-padrão que a própria espec
registra (*"FSM-B implementada ad hoc dentro do SyncService"*).

| Peça | Arquivo | Papel |
|---|---|---|
| Matriz de transições | `sync/sync_fsm.dart` | Pura. Um teste por linha da §4.2 |
| Verificação Ed25519 | `sync/manifest_verifier.dart` | Fronteira de confiança do conteúdo |
| Serialização canônica | `sync/pack_manifest.dart` | Precisa bater byte a byte com o Node |
| Estado em disco | `sync/pack_store.dart` | Manifest ativo, packs por hash, blacklist, ETag |
| Driver | `sync/sync_service.dart` | Um ciclo por chamada; nunca lança |
| Transporte | `sync/resumable_downloader.dart` | **Reaproveitado** do download do modelo |

**Os dois critérios de saída do PRD, medidos.** 58 testes novos (95 → 153), com
servidor HTTP local que fala `If-None-Match`, `Range`/`206` e corta a conexão no
meio da transferência:

| Critério do PRD §6.2 | Evidência |
|---|---|
| *sync retoma após corte* | Conexão derrubada aos 40 000 B; o parcial sobrevive, o ciclo seguinte manda `Range: bytes=40000-` e commita. Nada fica ativo com download pela metade |
| *nenhum pack inválido ativado* | 6 cenários: assinatura adulterada, campo extra não assinado, `keyId` desconhecido, artefato trocado no espelho, downgrade assinado, schema major futuro. Em todos, `loadActive()` continua devolvendo a versão anterior (ou nada) |

**Três decisões de projeto que a implementação forçou** — todas propagadas para
a [espec.md §4.2](espec.md):

1. **O ponto de commit é o rename do `manifest.json`, não o do banco.** Os packs
   vivem nomeados pelo próprio hash (`pack-<sha256>.db`); ativo é aquele que o
   manifest corrente aponta. Assim a troca de versão é **um** `rename()` POSIX,
   e o cenário S3 (processo morto no meio da troca) deixa de precisar de
   protocolo de recuperação: não existe segundo passo capaz de falhar sozinho.
   De brinde, nomear pelo hash dá a idempotência que o cenário S2 exige — duas
   execuções concorrentes do WorkManager baixam para o mesmo caminho.
2. **A blacklist por assinatura inválida guarda o hash dos BYTES do manifest,
   não o `packHash`.** Num manifest forjado, `packHash` é campo do atacante;
   blacklistá-lo permitiria bloquear um pack legítimo futuro sem possuir chave
   nenhuma. Só a recusa por hash divergente do artefato — onde o manifest já foi
   autenticado — memoriza o `packHash`.
3. **O ETag não é gravado com download em voo.** Gravá-lo ao fechar a janela
   faria o servidor responder `304` na janela seguinte e a máquina perderia o
   manifest de que precisa para retomar. O que identifica a retomada é o parcial
   nomeado pelo `packHash` — endereçamento por conteúdo, mais forte que ETag.

**Um defeito no packer que só o item 9 revelaria.** O `built_at` do `pack_meta`
usava o relógio de parede, então **duas builds do mesmo conteúdo produziam
`content.db` diferentes** — e, como a URL do pack é o próprio hash, cada
republicação sem mudança nenhuma obrigaria a frota inteira a re-baixar o pack
por causa de uma linha de metadado. Num posto rural isso é a diferença entre
atualizar e não atualizar. O packer agora honra `SOURCE_DATE_EPOCH` (a
convenção do reproducible-builds.org, a mesma que o F-Droid usa — [stack.md
§9](stack.md)), no pack e no `publishedAt` do manifest. Há teste que constrói
duas vezes e compara os hashes, e ele reprova se o relógio voltar.

**Interoperabilidade Node → Dart, verificada com artefato real.** O teste que
mais importa neste conjunto não é de FSM: é o que pega o `manifest.json`
assinado pelo **packer de verdade** e o verifica em Dart. Se as duas
serializações canônicas divergissem em um byte, toda assinatura legítima
passaria a parecer forjada e a frota inteira pararia de receber conteúdo — sem
nenhuma mensagem de erro que explicasse por quê. Fixtures em
`app/test/fixtures/sync/`, regeráveis com `npm run pack:build`.

**Sabotagem, para provar que os testes têm dentes.** Quatro proteções foram
desligadas uma a uma; cada uma foi pega por pelo menos um teste, e três delas
por testes independentes em arquivos diferentes:

| Proteção desligada | Testes que falharam |
|---|---|
| `verify` do Ed25519 sempre aceita | 4 |
| Guarda anti-downgrade (INV-7) | 2 |
| Reconferência do pack ativo no cold start (INV-3) | 1 |
| Guarda de quiescência antes do swap | 3 |

**O que ficou de fora, deliberadamente.** O agendamento por WorkManager para o
pack (item 15 da Fase 2) e o download dos **assets** do manifest — o PoC baixa e
ativa o `content.db`, que é o que a triagem consome. A `PackStore` não é lida por
nenhuma tela ainda: quem consome o pack são as telas dos itens 10–13. O laço
está fechado por um teste que abre o pack recém-instalado com o `sqlite3` real e
carrega o `RuleModel` — o mesmo caminho que o gate usa.

**Uma decisão de custo registrada:** o `PackStore` reconfere o SHA-256 do pack
ativo a cada abertura, porque o pack semente tem 160 KB e o custo é irrelevante.
Se os packs crescerem para dezenas de MB com áudio embarcado, isso sai do
caminho crítico do boot — é exatamente o erro que o marcador `.verificado` do
modelo SLM corrigiu, e a lição está anotada no código.

### Fase 2 — App (CAP-01…13)
10. Casca: tema, GoRouter, i18n pt/es, `speech/`. ✅
11. `content/` (repositórios RO) + `prefs/` (Drift). ✅
12. `triage_orchestrator` completo (FSM-A) + telas de composição/resultado. ✅
13. Encaminhamento, fluxo, documentos. ✅
14. `privacy/` (CAP-13) + `telemetry/` com allowlist. ✅
15. `sync/` endurecido: backoff+jitter, circuit breaker, guard de quiescência. ✅
**Saída:** APK com jornadas verde/vermelha/sync passando em device farm.

#### 5.3 Resultado do item 10 — casca do app (2026-08-19)

Tema, roteador, i18n pt/es e `speech/`, com a mesma tática dos itens anteriores:
**quando o requisito é uma propriedade da estrutura, a estrutura vira dado e o
teste a percorre.** O mapa de rotas
([`app_routes.dart`](../app/lib/ui/app_routes.dart)) é uma lista de descritores;
`buildGubsRouter` só a dobra num `GoRouter`. Profundidade, dead-ends e o alcance
da exceção da INV-8 saem de travessias dessa lista.

| Peça | Arquivo | Papel |
|---|---|---|
| Semântica de cor | `ui/theme/gubs_colors.dart` | `ThemeExtension`; acesso por **severidade**, não por nome de cor |
| Tema | `ui/theme/gubs_theme.dart` | Alvo de 64 dp no `ButtonStyle` padrão, não em cada tela |
| Métricas | `ui/theme/gubs_metrics.dart` | Números da RNF-06 nomeados, para poderem ser verificados |
| Mapa de rotas | `ui/app_routes.dart` + `ui/app_router.dart` | Dado + a dobra que vira `GoRouter` |
| Portões | `ui/router_provider.dart` | `gubsRedirect` é função pura — idioma e INV-8 |
| Casca | `ui/shell/` | Bottom nav de 3 abas; moldura com voltar garantido |
| i18n | `lib/l10n/*.arb` | **Só a casca.** Conteúdo clínico vem do `content.db` assinado |
| Voz | `speech/speaker.dart` | Folha: não lança, não espera, não bloqueia |
| Preferência | `prefs/locale_store.dart` | Porta que o item 11 reimplementa sobre Drift |

**Três defeitos de acessibilidade encontrados por medição, não por revisão
visual.** Os dois primeiros estavam na paleta que o protótipo já usava:

| Defeito | Medido | Correção |
|---|---|---|
| Verde e vermelho do tema claro com a **mesma luminância** (razão **1,01**) — para quem tem deficiência de visão de cores vermelho-verde, cartão de rotina e de emergência eram a mesma cor | 1,01:1 entre si | `red` de `#CE3A3A` para `#9E2626` (razão 1,55; e vermelho mais escuro também lê como mais urgente) |
| Âmbar abaixo do mínimo de 3:1 para componente de interface | 2,91:1 sobre o fundo | `amber` de `#B98A2F` para `#8F651A` |
| Branco sobre o vermelho **claro** do tema escuro | 3,21:1 | `onRed`/`onAmber` viraram tokens; `forSeverity` deixou de escrever `Colors.white` |

As três correções foram propagadas para [`design.html`](design.html), que é a
referência visual.

**Um quarto defeito, este só visível no aparelho.** O rótulo do botão principal
apareceu com **1,94:1** no tema escuro — quase ilegível. Causa: todo estilo de
`Theme.of(context).textTheme` **já vem colorido** com `ColorScheme.onSurface`, e
cor explícita num `TextStyle` vence o `foregroundColor` do botão que o contém. O
teste de paleta não podia pegar: `ink`×`green` não é um par que a paleta preveja
— foi o widget que o inventou.

A lição virou um segundo teste, `rendered_contrast_test.dart`, que lê a cor do
texto **já pintado** (`RenderParagraph`) em vez das constantes. Verificar a
paleta prova que as cores escolhidas são boas; só verificar o renderizado prova
que são elas que chegam à tela.

**Dois defeitos de layout com a fonte ampliada** — ampliar a fonte é a primeira
coisa que faz quem tem presbiopia sem óculos, parte relevante do público. Os
ladrilhos da inicial tinham proporção fixa e estouravam em 2×; o nome do idioma
saía pela borda em tela estreita. Corrigidos com altura intrínseca e `Flexible`,
e cobertos por testes em 1×, 1,3×, 1,6× e 2× nos dois temas.

**Um dead-end que só o aparelho mostrou.** A tela de triagem apareceu sem botão
voltar. `context.canPop()` responde *"existe algo empilhado"*, que não é a
mesma pergunta que *"existe para onde voltar"*: os ladrilhos navegam com `go`,
que substitui em vez de empilhar. O teste passava porque usava `push` — ele
exercitava um caminho que o app não percorre. Agora o destino do voltar vem do
**manifesto** (`parentPath`), não do histórico, e o teste chega às telas por
deep link, que é o pior caso.

**A exceção da INV-8 foi reduzida ao tamanho que o ADR-003 autorizou.** A
implementação anterior travava o app inteiro até o modelo baixar; o ADR autoriza
travar *"a tela principal de atendimento clínico"*. Agora o portão fecha apenas
as rotas marcadas com `requiresModel` — a triagem. "Onde ir", "Documentos",
o fluxo da UBS e, principalmente, **a tela de emergência** seguem abertos sem
modelo nenhum, porque são conteúdo estático assinado que não precisa de
inferência. O primeiro acesso continua abrindo no setup, para a apresentação de
valor e o consentimento acontecerem.

**Verificação em aparelho** (Motorola Edge 40 Neo, APK release arm64): seleção de
idioma, persistência entre reinstalações, app inteiro em espanhol, as três abas,
os quatro ladrilhos, o voltar, e zero erro em `logcat`. APK de **23,8 MB**
(era 21,1 MB) — bem dentro dos 50–80 MB do ADR-003.

**Sabotagem.** Seis proteções desligadas uma a uma; cinco foram pegas de
imediato. A sexta — baixar `minTouchTarget` de 64 para 48 — **não foi**, porque o
teste comparava o widget contra a mesma constante que a sabotagem alterou. Um
teste circular. Corrigido ancorando as constantes nos números da RNF-06.

| Proteção desligada | Testes que falharam |
|---|---|
| Emergência passa a exigir o modelo | 4 |
| Portão trava tudo, não só a triagem | 1 |
| Vermelho volta ao tom que confunde com o verde | 1 |
| Ladrilhos voltam a ter altura fixa | 4 |
| TTS perde o timeout da sondagem | 1 (suíte trava, como esperado) |
| Alvo de toque cai para 48 dp | 0 → **1**, depois de corrigir a circularidade |

**O que ficou de fora.** As telas de triagem (item 12) e as de conteúdo estático
(item 13) são placeholders — mas os **caminhos já existem**, para que a estrutura
seja testável desde agora. Uma rota que só nasce junto com a tela nunca é testada
contra a estrutura. Também ficou para depois o `riverpod_generator` + `freezed`
(item 12, onde os estados de união exaustiva pagam pelo gerador) e a persistência
em Drift (item 11, que reimplementa a porta `LocaleStore`).

#### 5.4 Resultado do item 11 — `content/` + `prefs/` (2026-08-19)

Duas camadas de dados com regras opostas, e é a oposição que importa:
`content/` **só lê** um arquivo que chega assinado de fora; `prefs/` é o único
lugar do aparelho onde o app escreve, e por isso é a superfície que a LGPD
audita.

| Camada | Arquivo | Regra |
|---|---|---|
| Conteúdo | `content/data/content_repository.dart` | Somente leitura, sobre pack já verificado (INV-3/INV-4) |
| Conexão ativa | `content/data/active_content.dart` | Abre o pack do `PackStore`, reabre no swap, `null` quando não há pack |
| Preferências | `prefs/user_database.dart` (Drift) | Colunas tipadas, linha única, sem dado clínico |
| Migração | `prefs/preferences_repository.dart` | Traz o `locale.json` do item 10 e o apaga |

**`content.db` somente leitura não é convenção, é impedimento.** O pacote abre
em `OpenMode.readOnly` e há teste que confirma que um `UPDATE` lança. A razão é
a INV-4: conteúdo clínico só entra por pack assinado com dupla revisão, e um
caminho de escrita no device seria um caminho para orientação não revisada
chegar ao usuário sem passar pela assinatura.

**Falta de tradução recua, não some.** O packer bloqueia publicação com tradução
faltando, então recuo no aparelho indica pack corrompido ou idioma que o pack
não conhece. Ainda assim o repositório recua para `pt` em vez de omitir o item:
sumir com "Onde ir" de quem precisa é pior que mostrá-lo em português para um
hispanofalante — o ícone segue correto e as duas línguas são próximas. O recuo
fica sinalizado em `Localized.isFallback`, disponível para telemetria agregada
contar o defeito.

**O esquema do `user.db` é a resposta a "o que este app guarda sobre a pessoa".**
Colunas tipadas e não chave-valor, deliberadamente: uma tabela `(chave, valor)`
aceitaria qualquer coisa que qualquer código futuro gravasse, e a pergunta
deixaria de ter resposta estática. Com colunas declaradas, `lgpd_surface_test`
as enumera e reprova acréscimo não revisado. As quatro são escolhas de operação
do app — idioma, telemetria agregada, override de dados móveis, setup concluído
— e nenhuma identifica ninguém nem descreve saúde. Sintoma é dado sensível
(art. 5º II) e não é persistido: a sequência morre em memória (INV-2,
LGPD-RF13).

**Uma corrida a menos, de graça.** A análise S1 da [espec.md §4.4](espec.md)
elimina o swap-durante-leitura pelo guard de quiescência. O desenho do item 9 —
packs nomeados pelo hash, commit por rename do manifest — acrescenta uma segunda
barreira independente: no POSIX, remover o arquivo antigo não invalida descritor
já aberto, então uma leitura em voo termina no pack anterior íntegro em vez de
ver um arquivo trocado por baixo. Há teste que abre o pack v1, instala o v2,
remove o v1 e confirma que a leitura antiga continua respondendo v1.

**Dívida do item 10 paga.** A escolha "usar sem a IA assistente" vivia na
memória do processo: quem a tomava revia a apresentação de valor a cada abertura
do app, como se a decisão nunca tivesse sido tomada. Agora `setupCompleted` e o
override de dados móveis moram no `user.db`.

**Sabotagem.** Seis proteções desligadas, todas pegas: coluna de sintoma no
`user.db` (2 testes), `wipe` que não zera o idioma (2), pack aberto para escrita
(1), tradução faltando que some com o item (4), pack ativo servido sem conferir
assinatura (4), `setupCompleted` de volta à memória (4).

**Um risco que a própria sabotagem revelou.** O teste que prova "escrever no
pack é impossível" rodava contra a fixture versionada. Quando a sabotagem
removeu o `readOnly`, o `UPDATE` passou — e corrompeu o arquivo compartilhado,
derrubando 10 testes de sync sem relação com o assunto. O teste agora opera
sobre cópia descartável: **um teste que prova "isto não pode acontecer" precisa
ser inofensivo no dia em que acontecer.**

**Codegen entrou no build.** O Drift gera `*.g.dart`, que não são versionados.
Em checkout limpo, pular `dart run build_runner build` produz ~35 erros de
análise sem relação com o código escrito — por isso o passo entrou no CI, antes
do `flutter analyze`.

#### 5.5 Resultado do item 12 — FSM-A e as telas clínicas (2026-08-19)

A FSM-A seguiu a tática dos itens 9 e 10: matriz da [espec.md §4.1] transcrita
em `triage/orchestrator/triage_fsm.dart`, pura, e um driver
(`triage_session.dart`) que faz relógio, gate e motor. Aqui a separação vale
mais que nos itens anteriores, porque as propriedades que precisam ser
verdadeiras nesta máquina são **clínicas** — e propriedades do grafo só são
verificáveis quando o grafo é dado:

| Propriedade | Como é verificada |
|---|---|
| Red flag nunca chega à inferência | Percorre todos os estados × `GateDone(redFlag: true)` |
| Só S2 consulta o modelo | Percorre todos os pares (estado, evento) |
| Todo caminho ao resultado passa pelo gate | S0 e S1 não alcançam S5 por evento nenhum |
| Falha do gate sempre termina em `E1` | `GateFailed` de qualquer estado |
| Nenhum estado vivo é poço | Todo estado ≠ S0 tem transição de saída |
| Todo cartão dispara áudio | Toda transição para S5/E1 contém `speakResult` |

**Um defeito sério, achado pelo teste de widget.** A conversão de
`severity_level` para classe visual tinha limiares fixos em Dart (`<= 1` rotina,
`2` atenção, resto emergência). **O pack real usa a escala 10/100** — então todo
resultado de rotina caía no `resto` e era pintado de **vermelho, com "Ligue 192"
embaixo**. Para quem depende da cor por não ler o texto, isso é a mensagem
oposta à correta, no lugar mais crítico do app.

A causa não foi um número errado: foi a UI ter **inventado uma escala**.
`severity_level` é definido pelo conteúdo, que é revisado clinicamente e pode
mudar de pack para pack. A correção move a classificação para
`severityFor(level, model)`, que deriva os extremos dos desfechos do próprio
pack — os mesmos que o gate lê. Nenhum limiar clínico sobrou em Dart.

De quebra, o enum `GubsSeverity` saiu do tema e foi para o domínio da triagem: a
regra de dependência da espec §2.2 é `ui → triage`, e severidade dentro da
paleta convidava a decidir severidade a partir de cor.

**Composição em três passos**, correspondendo aos `kind` da ontologia
(`body_part`, `symptom`, `modifier`). A FSM permanece em `S1_COMPOSING` nos
três: compor é um estado só, e os passos são apresentação. Uma rota por passo
criaria estados de navegação que a máquina clínica não reconhece — o botão
voltar do Android pularia para um passo sem a composição correspondente.

**Redundância de canal na seleção.** Ícone selecionado muda por quatro canais
simultâneos: cor de fundo, espessura da borda, marca de conferido e negrito.
Cor sozinha exclui quem tem deficiência de visão de cores; texto sozinho exclui
quem não lê. Este app não pode escolher um dos dois.

**Verificado no aparelho** (Motorola Edge 40 Neo, pack real no sandbox):
composição nos três passos em espanhol; `peito + dor + muito forte` →
**cartão vermelho** com "Llama al 192" e sem aviso de degradação (red flag não é
degradação, é o caminho previsto); `garganta + dor` → **cartão verde** com o
aviso de degradação (motor ausente ⇒ S4). **O TTS falou de verdade** —
`Utterance ID has started` no logcat, fechando o TODO que o item 10 deixou. Zero
erros de runtime.

**Sabotagem: 7 proteções desligadas, 7 pegas.** A sétima só passou a ser coberta
depois: nenhum teste cobria o mapeamento `icon_ref` → ícone, e numa interface
iconográfica um ícone que some remove a opção inteira de quem não lê o rótulo.
Agora há teste que exige que todo token do pack real tenha ícone próprio, e que
ícones dentro de uma mesma família sejam distintos entre si — dois sintomas com
o mesmo desenho são, para esse usuário, o mesmo botão.

**Uma tensão de produto registrada, não resolvida em código.** A convenção de
"máximo 8 elementos por tela" (CLAUDE.md) casa com `body_part` (8) e `modifier`
(6), mas `symptom` tem **12** e a grade rola. Resolver de verdade exige um dos
dois, e ambos são decisão de conteúdo com dupla revisão clínica: subconjunto de
sintomas por parte do corpo (exige tabela de associação no pack, que hoje não
existe) ou redução da ontologia. Fica anotado para a revisão clínica do piloto.

#### 5.6 Resultado do item 13 — telas estáticas (2026-08-19)

Quatro telas — "Onde ir" (RF-07), "O que levar" (RF-08), "Como funciona"
(RF-09) e emergência — inteiramente alimentadas pelo `content.db`. São o **piso
da escada de degradação**: não usam modelo, não esperam sync, não consultam
rede. Verificadas no aparelho com **os rádios desligados e sem modelo
provisionado**, que é a condição em que elas mais importam.

**Duas falhas que só o aparelho mostrou**, ambas na tela mais usada:

1. **Todo serviço aparecia com um "?".** O mapa `icon_ref → ícone` cobria só os
   tokens de sintoma; serviços, documentos e passos do fluxo ficaram de fora. O
   teste que eu havia escrito no item 12 percorria `symptomTokens`, então
   passava. A pergunta certa não era *"os tokens têm ícone?"* e sim *"tudo que o
   pack manda desenhar tem ícone?"* — o teste agora percorre `SELECT ref FROM
   asset WHERE ref LIKE 'icon.%'`.
2. **A tela liderava com "Hospital".** `venue` não tinha `sort_order`, então a
   ordenação era por `id` — alfabética. A tela cujo propósito é encaminhar para
   a atenção básica quem não precisa de pronto-socorro abria com o hospital no
   topo.

A segunda correção atravessou a stack, e esse é o ponto: **qual local aparece
primeiro é curadoria de conteúdo, não `ORDER BY` do binário.** Foi acrescentada
uma coluna `sort_order` em `venue` no contrato Drizzle, migração
`0001_content.sql` gerada por drizzle-kit, valores no `seed/` com o porquê
escrito ali, e o repositório passou a ordenar por ela. Agora um município pode
republicar a ordem sem tocar no app.

**Tradução de cor sem chute perigoso.** O pack diz `green`/`red`/`blue` — nomes
semânticos — e o binário converte. Token desconhecido vira **azul**, nunca verde
nem vermelho: chutar verde diria "pode esperar", chutar vermelho diria "corra", e
azul diz "isto é informação", que é a única coisa verdadeira sobre um token que o
binário não entende.

**Sem rolagem horizontal nos seletores.** A primeira versão do seletor de
atendimento era uma régua rolante, e o último item ficava fora da tela. Para este
público, conteúdo fora da tela é conteúdo que não existe — ninguém arrasta de
lado atrás de algo cuja existência não foi anunciada. Virou `Wrap`, e há teste
que reprova se qualquer opção passar da borda.

**O 192 não é botão.** Número em destaque com ícone de telefone, sem ação de
toque: discagem a partir de um toque acidental ocupa a linha do SAMU. A decisão
de ligar é da pessoa.

**Sabotagem: 7 proteções desligadas.** Seis pegas de imediato. A sétima — o 192
virar botão — **passou ilesa**, e o motivo é instrutivo: o teste usava
`find.byType(ButtonStyleButton)`, e `find.byType` compara o tipo **exato**, então
jamais casaria com um `TextButton`. O teste era estruturalmente incapaz de
falhar. Corrigido com `find.byWidgetPredicate`, e a sabotagem passou a ser pega.

**Uma string que não deveria existir no app.** Escrevi "sem documento você ainda
é atendido" em ARB e retirei: é afirmação sobre **direito do usuário do SUS**,
não rótulo de casca. Se aparecer, tem de vir do pack, com dupla revisão
(INV-4). Fica registrado como conteúdo que o pack deveria carregar — a tela de
documentos ganharia muito com ele, e o público que mais precisa dessa informação
é exatamente o que o app atende.

#### 5.7 Resultado do item 14 — privacidade e telemetria (2026-08-19)

**A tela de privacidade não escreve à mão o que o app guarda.** Ela lista uma
entrada por preferência do `user.db`, e há teste que compara a contagem das duas
listas. Isso não é zelo: uma lista redigida à parte envelhece, e o resultado é
uma tela que mente para o titular em português claro, com toda a aparência de
verdade. O teste pegou na primeira execução — `allow_metered_download` existia no
banco e não aparecia na tela.

**Opt-out na contagem, não no envio.** A LGPD-RF03 exige que o opt-out zere os
envios; aqui ele zera a **coleta**, o que é mais forte: quem desligou não tem nem
número em memória a respeito de si. Desligar também apaga o que já foi contado —
um opt-out que só vale para o futuro deixaria em memória exatamente o que a
pessoa acabou de recusar.

**Um defeito que a sabotagem não precisou encontrar, porque o teste encontrou
primeiro.** A primeira versão tinha *dois* providers lendo o mesmo opt-out do
`user.db`: a tela invalidava um e o contador escutava o outro. O resultado é o
pior defeito possível numa opção de privacidade — o botão desliga na tela e a
coleta continua. Virou um estado síncrono único (`telemetryConsentProvider`).

**A allowlist é fechada por construção.** Não existe API que aceite `String`: só
`MetricKey`, uma enum. Um campo novo passa obrigatoriamente pelo diff, que é onde
a revisão do encarregado acontece (LGPD-RF14). Há teste que confere a enum contra
o `telemetry-schema.json` gerado pelo contrato — mesma técnica do manifest, mesmo
risco de as duas listas divergirem em silêncio.

**O que o módulo de telemetria deliberadamente NÃO faz**, e por quê:

| Ausência | Motivo |
|---|---|
| Não transmite | O app faz **duas** chamadas de rede (manifest/pack e modelo). Uma terceira exige ADR, não uma decisão de passagem |
| Não persiste | Contador em disco viraria tabela nova no `user.db`, onde `lgpd_surface_test` obriga a justificar cada coluna. Sem envio, ninguém lê — persistir seria risco sem benefício |
| Não guarda série temporal | `observeMax` guarda o pior caso do dia. A série por aparelho é justamente o que a LGPD-RF14 quer evitar; o percentil real é da coorte, calculado no pipeline |

O `kAnonymityMin` vive no código como **documentação do contrato**, não como
regra que o aparelho aplique: k é propriedade do conjunto de aparelhos, e um
aparelho sozinho não sabe quantos outros compõem sua coorte. Quem recusa lote com
k < 20 é o pipeline.

**A ação destrutiva tem a saída como caminho fácil.** "Apagar meus dados" abre uma
confirmação em que *"Não apagar"* é o botão preenchido e vem primeiro, e
*"Apagar mesmo assim"* é texto discreto embaixo. Verificado no aparelho: o
apagamento confirma na tela e, na reabertura, o app volta a perguntar o idioma —
que é o sinal visível de que aconteceu de fato.

**Uma convenção esclarecida, não afrouxada.** O teto de oito elementos por tela
conta **escolhas**, não moldura. Voltar, barra de abas e o escudo de privacidade
não competem pelo escaneamento — e sem essa distinção a tela exigida pela
LGPD-RF03 não teria onde caber na inicial, que já usava as oito posições. A regra
está escrita no teste, não implícita.

**Sabotagem: 6 proteções desligadas, 6 pegas** — chave fora do contrato, opt-out
filtrando só na saída, desligar sem apagar o já contado, apagar virando ação de
um toque, `wipe` deixando o idioma para trás, e preferência nova invisível na
tela.

#### 5.8 Resultado do item 15 — sync endurecido (2026-08-19)

O item 9 entregou a FSM-B correta. Este item corrigiu o fato de que **dois dos
seus freios não existiam no aparelho**, só no código.

**O circuito e o backoff viviam em memória.** O WorkManager executa o trabalho
num **isolate novo a cada disparo**: um isolate recém-criado nasce com o
circuito fechado e sem backoff pendente. O freio funcionava em teste e no app
aberto, e nunca em produção — uma frota sem rede voltaria a bater no servidor a
cada janela, com o circuito "aberto" em memórias que já morreram.

Agora o estado vive em disco, ao lado do ETag e das blacklists (mesmo arquivo,
mesma vida útil, longe da superfície auditável do `user.db`). E o circuito
deixou de ser um booleano *"aberto até a próxima janela"* para virar um
**instante** *"fechado a partir de"* — um processo que acabou de nascer não sabe
em que janela está, mas sabe que horas são.

**Um furo que o teste de persistência revelou.** Restaurar o estado do disco não
bastava: um processo novo nasce em `p0Steady`, e a linha B1 só consulta o
circuito — o backoff é guarda da linha B14, que sai de `f1Retryable`. Cada
reinício pulava o backoff e ia direto à rede. A correção restaura também a
**posição** da máquina: se há falhas registradas, ela estava em F1 quando o
processo morreu.

**O guard de quiescência tinha o que proteger e não tinha o que consultar.** Era
um callback que ninguém fornecia. Agora ele pergunta ao controlador de triagem
se a FSM-A está em `S0_IDLE`, que é o que a linha B11 exige. E adiar não conta
como falha: se contasse, cinco triagens seguidas abririam o circuito e o
aparelho pararia de sincronizar **justamente por estar sendo usado**.

**O erro de projeto mais silencioso do item.** `Workmanager().initialize()`
aceita **uma** função, que recebe todas as tarefas. Havia dois dispatchers — um
para o modelo, outro para o pack — e só o do modelo era registrado. O do pack
existia, compilava, tinha comentário explicando seu papel, e nunca seria
chamado: a tarefa de conteúdo caía no `if (task != modelSyncTaskName) return
true` do outro e era silenciosamente marcada como concluída. O sync estaria
agendado e nunca aconteceria; nada falharia e nenhum log apareceria. Hoje há um
único ponto de entrada que roteia as tarefas.

**Política do pack ≠ política do modelo.** O modelo exige rede não tarifada; o
pack, não. São ~800 MB baixados uma vez contra centenas de KB que carregam
correção clínica revisada — um posto sem Wi-Fi não pode ficar meses com
orientação desatualizada porque a política de um arquivo mil vezes maior foi
aplicada a ele.

**Duas sabotagens escaparam, e uma delas apontou código morto.** Desligar o teto
do backoff não quebrou teste nenhum: com orçamento de 5 falhas, `n` nunca passa
de 4 e `2^4` são 16 segundos — o teto **não binda com os parâmetros de hoje**.
Ele ficou, porque `2^11` já passa de meia hora e `2^16` passa de 18 horas, e um
freio que nunca solta é indistinguível de um app que parou de sincronizar; mas
agora o cálculo é uma função pura, testada fora da faixa alcançável. A outra
sabotagem — remover o jitter — também passava, porque jitter é propriedade da
frota e não de um aparelho; virou teste sobre a dispersão entre sementes.

**Verificado no aparelho:** os dois trabalhos periódicos coexistem com
restrições distintas — `NET BATNOTLOW STORENOTLOW` (modelo) e `NET BATNOTLOW`
(pack) —, período de 6 h, zero erros de runtime.

**Sabotagem: 7 proteções, 7 pegas** depois de fechar as duas lacunas acima.

### Fase 3 — Plano de controle (CAP-14/15)
16. Schema Drizzle completo + migrações + triggers append-only. ✅
17. Better Auth + RBAC + 2FA; trilha de auditoria. ✅
18. CRUD de conteúdo com travamento otimista; editor de regras (DNF) com validação. ✅
19. Workflow de dual review + orquestração de release; ingestão de telemetria com validador k≥20. ✅
**Saída:** pack publicado ponta a ponta pelo CMS, com aprovação clínica registrada. ✅ **Fase 3 concluída** (§5.12).

#### 5.9 Resultado do item 16 — banco master do CMS (2026-08-23)

**28 tabelas, 24 gatilhos, 85 sentenças de DDL, 49 testes.** O banco existe e é aplicável; não há rota, autenticação nem UI — itens 17 a 19.

**O corte por município não foi escolhido: foi derivado.** A intenção era "clínico global, logística municipal", com `venue` e `asset` do lado municipal. Não fecha. `symptom_token.icon_ref→asset.ref` e `routing_outcome.venue_id→venue.id` saem de tabelas globais, e uma FK global→municipal exigiria que o lado global oferecesse um `municipality_id` que ele não tem. As duas tabelas foram para o lado global porque a integridade referencial não deixa alternativa — o pool de arquivos é global, o **uso** é que é municipal.

**Os gatilhos não são migração do drizzle-kit, e isso é decisão.** `generate --custom` cria arquivo numerado e imutável no journal. Uma tabela versionada acrescentada daqui a três meses exigiria migração nova só para os gatilhos dela, com o gerador incapaz de saber quais já foram emitidos; o conjunto passaria a viver espalhado por N arquivos históricos e "quais gatilhos existem hoje?" deixaria de ter resposta num lugar só. Em vez disso `src/db/triggers.sql` carrega o conjunto **completo**, cada `CREATE` precedido de `DROP ... IF EXISTS`, reaplicado a cada migração. Gatilho não é dado; recriá-lo é idempotente. De quebra, gatilho que sumiu — restauração de backup antiga, `DROP` manual num expurgo interrompido — **volta sozinho** na próxima migração, em vez de ficar ausente e silencioso até o dia em que importa.

**A lista append-only é constante, não literal.** `APPEND_ONLY_TABLES` mora em `schema/index.ts`, o gerador emite o SQL a partir dela e o teste a percorre. É o mesmo motivo de `app/test/prefs/lgpd_surface_test.dart` enumerar colunas em vez de conferir contra um texto ao lado: lista redigida à parte envelhece e passa a mentir. Há um teste só para o modo de falha por vacuidade — tabela acrescentada à constante sem linha de exemplo no suporte de teste reprova, em vez de rodar zero asserções e ficar verde.

**O gatilho de versão monotônica veio junto com a coluna.** `version` nasceu neste item, e o precedente de `theme_mode`/`font_scale` no `user.db` é que coluna e guarda chegam no mesmo commit. Sem ele, um `UPDATE` que esqueça de incrementar `version` perde o travamento otimista **em silêncio** — a próxima escrita concorrente sobrescreve sem 409, e o único sintoma é a edição de alguém sumindo sem explicação. A regra é `NEW.version = OLD.version + 1`, não `>`: um salto também denuncia escrita que não passou pelo caminho do travamento, e ser estrito custa zero para quem usa `SET version = version + 1 WHERE id = ? AND version = ?`.

**Duas regras de dual review foram deliberadamente deixadas fora do banco.** `approver_id ≠ created_by` e "≥ 1 `clinical_reviewer`": a segunda é agregado sobre outras linhas, que gatilho SQLite só expressa com subquery frágil, e a primeira sozinha daria a impressão de que a regra inteira mora no banco quando só metade moraria. Ambas são do item 19, com teste próprio.

**`CHECK` de verdade, porque `enum` do Drizzle não é restrição.** `text(..., { enum })` é tipagem só de TypeScript — o `contract/ddl/0000_content.sql` do pack comprova, sai sem um `CHECK` sequer. No CMS um `role` inválido é escalada de privilégio e um `status` inválido quebra a FSM de release, então as restrições foram escritas com `check()` e existem no DDL. O piso de k-anonimato entrou como `CHECK(k_count >= 20)`: o validador de aplicação protege a porta de entrada, o `CHECK` protege importação manual, script de migração e correção "rápida" no shell.

**O expurgo de retenção e o `BEFORE DELETE` incondicional colidem, e a colisão foi resolvida por escrito.** A LGPD-RF07 obriga a eliminar por prazo; o gatilho proíbe. O gatilho **fica** incondicional, e o expurgo é procedimento nomeado que derruba e recria os gatilhos numa transação, registrando a própria execução em `audit_entry`. O caminho de aplicação — uma rota, um bug de ORM, uma sessão comprometida — continua incapaz de apagar, que é a ameaça real. O script é do item 19: depende da tabela de retenção aprovada pelo encarregado.

**`telemetry_batch` NÃO é append-only, e a ausência é a decisão.** Auditoria e aceite valem por serem irrefutáveis; lote de telemetria é dado operacional com prazo de retenção. Bloquear `DELETE` ali criaria conflito com a obrigação de expurgo sem proteger nada que precisasse de proteção.

**Um buraco no próprio guarda-corpo, achado antes de ir para o CI.** `git diff --exit-code` **ignora arquivo não rastreado** — e migração nova nasce exatamente assim. Quem alterasse o schema e esquecesse `cms:generate` passaria no CI com o defeito que o check existe para pegar. `cms:check` ganhou `git add --intent-to-add` antes do diff; verificado nos três cenários (árvore em dia passa, migração nova reprova, `triggers.sql` alterado reprova).

**Sabotagem: 5 proteções, 5 pegas.** Gatilho apagado de `triggers.sql` (4 testes vermelhos), coluna extra na autoria fora da allowlist, coluna do pack faltando na autoria, família de gatilhos de versão desligada (3 vermelhos), `CHECK` de papel afrouxado. A suíte volta a verde em todas.

**Verificado contra o `sqld` de verdade**, não só contra o SQLite dos testes — porque "libSQL é um fork do SQLite" é argumento, não medição. Com o `db` do `infra/compose.yaml` no ar: **28 tabelas, 24 gatilhos**; `DELETE` e `UPDATE` em `audit_entry` recusados com a mensagem que nomeia a LGPD-RT03; `role` fora dos três papéis e `k_count = 19` recusados pelos `CHECK`; e `runMigrations()` rodado uma segunda vez deixa os mesmos 24 gatilhos, confirmando a idempotência no banco real e não só em memória.


#### 5.10 Resultado do item 17 — autenticação, RBAC e trilha (2026-08-24)

**104 testes no `cms`, 5 rotas, 6 tabelas novas.** O plano de controle passou a ter porta de rede — e ela nasceu com sessão de 24 h, 2FA obrigatória, três papéis segregados e trilha append-only.

**O item revisou o item 16, e a leitura da biblioteca é que forçou.** `admin_user` tinha `password_hash` e `totp_secret_enc`: o Better Auth guarda a senha em `account.password`, e o plugin `two-factor` **cifra** o segredo TOTP na tabela dele com o `BETTER_AUTH_SECRET`. A coluna `totp_secret_enc` teria ficado vazia para sempre — prometendo no nome uma criptografia que estava em outro lugar. As duas saíram na migração `0001`.

**Uma quebra de convenção, forçada e declarada.** O resto do banco usa `*_at` em ISO-8601 TEXT. `admin_user` passou a usar `integer(timestamp_ms)`: o Better Auth passa objetos `Date` ao adapter, e o Drizzle só converte `Date` em coluna INTEGER. Forçar TEXT exigiria um tipo de coluna customizado no caminho de autenticação — frágil, e no lugar errado.

**A migração gerada estava errada, e os testes pegaram.** O `drizzle-kit` emitiu um `INSERT … SELECT` que lia `email_verified`, `image`, `updated_at` e `two_factor_enabled` da tabela **antiga**, onde não existem; e copiava `created_at` de TEXT para INTEGER, o que o SQLite aceitaria calado e transformaria toda data do sistema em lixo. A conversão (`unixepoch(created_at) * 1000`) foi escrita à mão, com o motivo no cabeçalho do arquivo — é o tipo de coisa que um gerador não tem como saber.

**O plugin `admin` do Better Auth ficou fora por causa da impersonation.** Num sistema com dual review clínico, impersonation deixa um admin aprovar como se fosse o revisor, e a trilha registraria o revisor: a segregação da LGPD-RF11 viraria ficção, sem teste que pegasse depois do fato. Desligar por configuração não serve — segurança que depende de manter uma opção desligada é segurança que uma atualização reverte. A matriz papel×permissão virou dado próprio, percorrida pelo produto cartesiano inteiro.

**2FA obrigatória é enforcement, não configuração.** O Better Auth a trata como opt-in por usuário; a LGPD-RF11 diz obrigatório. Virou middleware que recusa toda rota protegida com `two_factor_enabled` falso, com **uma exceção nomeada** — o próprio fluxo de cadastro do TOTP. Sem ela o sistema trancaria todo mundo do lado de fora no primeiro login.

**`sign-up` público não existe.** `disableSignUp: true` fecha a rota inclusive para chamadas de servidor. Operador é criado por um admin, pela rota auditada, ou pelo `create-admin.ts` no bootstrap — que exige acesso ao banco, ou seja, já é a credencial.

**O teste mais valioso do item pegou dois defeitos antes da primeira requisição.** `auth-schema-conformance` compara o schema Drizzle contra `getAuthTables()` — o que a biblioteca declara precisar, em runtime. Achou (1) que o modelo do 2FA se chamaria `twoFactor` e o adapter procuraria `schema.twoFactor`, que não existe, quebrando a 2FA no primeiro uso e não no boot; e (2) que o adapter resolve campos pelo **nome da propriedade Drizzle** (camelCase), não pela coluna SQL — confundir os dois era o erro que o teste original cometia. Ficou também uma asserção de que as colunas seguem snake_case, para o nome de propriedade não vazar para o banco.

**Escrever os testes revelou duas propriedades que viraram asserção.** O Better Auth recusa requisição autenticada sem `Origin` (proteção CSRF) — afirmado como garantia, porque um afrouxamento futuro deixaria um site de terceiros disparar ações na sessão de um operador. E `two-factor/enable` **não liga** a 2FA: entrega o segredo e deixa `verified = 0`, revogando a sessão; a ativação só acontece quando a pessoa prova ter o autenticador, o que é a ordem correta — o contrário trancaria para fora quem digitasse o segredo errado no aplicativo.

**Um erro sutil de TOTP que o teste teria mascarado.** O `secret` do `totpURI` está em **base32**, e `createOTP` espera o segredo bruto. Passar a string base32 direto produz um código de seis dígitos que parece válido e nunca confere — o sintoma é só "Invalid code". A primeira versão do fixture ligava `two_factor_enabled = 1` direto no banco e teria passado verde por cima disso; foi trocada pelo fluxo real.

**O `sqld` real mostrou o que teste em memória não mostrou.** Na primeira passada por HTTP, `sign_in` e `two_factor_enable` bem-sucedidos entravam na trilha com `actor_id` nulo — essas rotas não passam por `requireSession`, então `c.get('operador')` estava vazio. "Quem ativou o segundo fator?" ficaria sem resposta, que é justamente a pergunta de uma auditoria de acesso. O ator passou a ser resolvido pela sessão da requisição ou, no login, pelo e-mail do corpo; falha continua sem ator, de propósito.

**O rate limit virou parâmetro explícito.** Uma suíte que faz dezenas de logins em segundos batia no teto de 5/60s e transformava cada teste seguinte em falso vermelho. Desligar é privilégio do teste, e há asserção de que o padrão é ligado — senão a exceção do teste vira o comportamento de produção sem ninguém decidir isso. Desligá-lo **não** desliga a trava por conta, que é a proteção que a LGPD-RT07 exige.

**Sabotagem: 6 proteções, 6 pegas.** 2FA obrigatória removida do grupo protegido, `editor` ganhando permissão de aprovar, trilha registrando o corpo da requisição, IP gravado em claro, trava progressiva desligada, `twoFactorTable` removido.

**Verificado contra o `sqld` real, por HTTP:** `/api/me` sem sessão 401; autocadastro 400; senha errada 401; login 200 mas `/api/me` 403 com o caminho da saída; após o TOTP, 200 com papel e permissões resolvidas; trava disparando na 4ª tentativa e recusando a senha **certa** com 429; trilha sem senha, sem hash de senha, sem segredo TOTP e sem e-mail em claro; `DELETE` em `audit_entry` recusado pelo gatilho do item 16.

**Fica para o item 18:** a regra de dual review que depende de LINHA e não de papel — `approver_id ≠ pack_release.created_by` e "≥ 1 `clinical_reviewer`". A primeira sozinha daria a impressão de que a regra inteira está no banco; a segunda é agregado sobre outras linhas, que gatilho SQLite só expressa com subquery frágil.


#### 5.11 Resultado do item 18 — CRUD, travamento otimista e editor de regras (2026-08-24)

**192 testes no `cms`** (104 ao início do item), 10 entidades com CRUD gerado, editor de regras com catálogo de integridade e simulação clínica.

**A pergunta que abriu o item tinha resposta favorável, e mesmo assim mudou o código.** Nada ligava `PRAGMA foreign_keys` no caminho de runtime; medido, o `sqld` v0.24 e o libSQL em memória ligam por padrão. Mas "a versão de hoje liga por padrão" é fato de versão, não garantia nossa, e o que depende dela não é pouco — sem FK, apagar um `symptom_token` deixa regras clínicas órfãs em silêncio. Entrou `assertForeignKeysEnforced()` no boot, no mesmo espírito de `loadEnv()`. E a asserção que existia — `migrations.test.ts` lendo a pragma — **media a pragma que o próprio fixture tinha acabado de ligar**: um teste que tranquiliza sem guardar. Ficou, renomeada para dizer o que realmente afirma, e a garantia sobre o produto passou para `foreign-keys.test.ts`, que exercita comportamento nos dois sentidos (aceita banco ligado, recusa banco desligado).

**O avaliador DNF mudou de casa.** `packer/src/rules.ts` → `contract/src/rules.ts`. O CMS precisa dele para simular, e copiar seria o que o `CLAUDE.md` proíbe — com uma consequência específica: a simulação mostraria um veredito e o gate de publicação produziria outro, o que é pior do que não ter simulação. São três avaliadores no sistema (TS no packer e no CMS, `RedFlagGate` e `RuleOnlyEngine` em Dart), e a suíte golden é o que os mantém alinhados.

**A fábrica existe porque três passos precisam acontecer em toda escrita.** Conferir a versão lida, gravar carimbando o autor, registrar na trilha. Escritos uma vez por entidade, o defeito típico é a última esquecer o terceiro — e ninguém nota até precisar da trilha, que é exatamente quando não dá mais para reconstruir. O registro (`content/registry.ts`) é dado; o teste o percorre e exige os três de cada entidade.

**`version` chega por `If-Match`, não pelo corpo**, e a ausência responde **428** (RFC 6585), não 400: 400 diria "você errou o corpo" e mandaria o cliente procurar no lugar errado. O 409 carrega a versão atual, porque um conflito que não diz contra o que se perdeu obriga a pessoa a recarregar a tela para descobrir.

**O mesmo defeito apareceu três vezes antes de virar módulo.** O Drizzle **substitui** a mensagem do driver por `Failed query: <sql>` e guarda a original em `cause`. Casar com `error.message` fazia toda violação de integridade virar 500 — ou seja, a proteção referencial funcionando parecia defeito do servidor e ensinava o editor a insistir. Aconteceu na fábrica de CRUD, no editor de regras e no log de erro do app; virou `db/errors.ts`.

**O fixture de teste estava mentindo, e só uma transação revelou.** Com `url: ':memory:'`, cada conexão do libSQL abre um banco **próprio e vazio**. `db.transaction()` abre conexão nova e caía num schema inexistente — o sintoma era `no such table` numa tabela recém-usada. Nenhum teste anterior usava transação, então nada denunciava. O fixture passou a usar arquivo temporário, que também aproxima o teste do que roda: o `sqld` é um servidor com um banco só.

**A simulação é o que dá valor clínico ao editor.** Ela roda `evaluate()` sobre `golden_case` com e sem a regra proposta e devolve quais casos mudam de veredito, com **falso negativo como classe à parte** — é o caso em que o app manda para casa alguém que precisava de emergência. Não bloqueia salvar rascunho (quem bloqueia é o gate do item 19); põe o efeito na frente de quem decide, enquanto ainda dá para desistir. Considera apenas regras `approved` mais a proposta: rascunho alheio faria o resultado depender de trabalho inacabado de outra pessoa.

**O desfecho padrão é derivado, não configurado.** Não há coluna para ele no banco de autoria, e inventar uma seria decidir por fora o que a semântica já decide: "nenhuma regra casou" significa o caso menos grave. É o mesmo raciocínio do app, que deriva os extremos dos desfechos do próprio pack.

**Regra aprovada responde 409 com o caminho da saída** (`/api/rules/:id/revisao`), em vez de deixar o gatilho do item 16 devolver erro de banco. O gatilho continua sendo a defesa; a rota é quem diz o que fazer.

**Sabotagem: 7 proteções, 7 pegas — mas a sétima só depois de o teste ser corrigido.** O teste de "rascunho alheio não influencia a simulação" comparava o **diff**, e incluir rascunhos nos dois lados se cancela: ele parecia significativo e media um cancelamento. Passou a afirmar o veredito **absoluto** do "antes". A primeira tentativa de sabotagem também estava errada — removia só metade do filtro, e a regra vazada entrava sem termos.

**Uma lacuna de CI fechada de passagem.** `tsc` nunca rodava em lugar nenhum: o `tsx` (esbuild) apaga tipo sem conferir. Havia um import duplicado em `packer/test/packer.test.ts` que passava despercebido há dois itens. Entrou `npm run typecheck` no job `contract`.

**Verificado contra o `sqld` real, por HTTP:** ciclo completo de CRUD com ETag, 428 sem `If-Match`, 409 com versão velha carregando a versão atual, tradução por upsert, FK recusando referência inexistente com 409, grupo contraditório recusado com o problema nomeado, simulação apontando `FALSO_NEGATIVO` com o caso identificado, regra aprovada recusando edição e a revisão clonando sem tocar na original, e a trilha com uma entrada por escrita.

##### Lacunas declaradas ao fim do item

1. [DONE] **Não há `cms/web/`.** A [stack.md](stack.md) decide "Vite + React SPA servida pelo próprio Hono" e **nenhum item do roadmap a nomeia** — 16 a 19 são todos backend. Sem interface, o revisor clínico não consegue exercer o papel, e o risco "modelagem DNF expressiva demais/de menos" (§7, probabilidade Média) continua sem a validação com casos reais que a própria tabela de riscos prescreve. **É pré-requisito de piloto.**
2. [DOING] **Upload de asset não existe.** `asset` tem CRUD de metadado; o binário continua vindo de `seed/assets/`. Publicar um ícone novo só pelo CMS não é possível até isso fechar. O `putObject` (SigV4) já existe em `packer/src/release.ts` e é o ponto de partida.
3. **O packer fixa `defaultOutcomeId: 'ROUTINE_UBS'` no código** ([packer/src/index.ts](../packer/src/index.ts)). O CMS deriva o padrão da menor severidade; os dois concordam hoje por coincidência de nomenclatura. Um município que nomeie o desfecho de rotina de outro jeito quebra o packer, não o CMS.


#### 5.12 Resultado do item 19 — dual review, orquestração e telemetria (2026-08-24)

**262 testes TypeScript** (9 contract + 233 cms + 29 packer). **A Fase 3 fecha aqui:** conteúdo editado no CMS, aprovado por outra pessoa, construído, assinado e publicado — verificado ponta a ponta contra `sqld` + MinIO reais.

**A chave privada nunca toca o processo que atende HTTP.** O CMS move a release para `approved`; um job separado (`packer/src/worker.ts`, serviço `packer` no compose **sem `ports:`**) constrói, valida, assina e publica. Juntar os dois faria uma falha de execução remota no serviço web virar conteúdo clínico assinado chegando a aparelhos offline — que é o que a INV-4 existe para impedir. **A topologia é a garantia**, não uma configuração.

**A FSM ganhou um estado que a §4.3-C não tinha.** Entre `approved` e `built` faltava posse: dois processos do job construiriam a mesma release em paralelo. Entrou `building` com `claimed_at`, tomado por compare-and-set. "Uma instância hoje" é a mesma classe de suposição que o item 18 converteu em invariante ao medir o `PRAGMA foreign_keys`.

**O dual review tem três metades, e cada uma mora onde consegue ser cumprida.** Por PAPEL (matriz do item 17), por LINHA (gatilho novo: quem cria a release não a aprova) e por QUÓRUM (≥ 1 `clinical_reviewer`, agregado no serviço). O item 17 adiou a segunda argumentando que meia regra no banco daria falsa impressão; com as duas metades juntas, a que **é** expressável em SQL virou estrutural.

**O gatilho pegou o fixture de teste no primeiro build.** A linha de exemplo de `approval` no `test/support/db.ts` aprovava com o **mesmo** operador que criou a release — uma auto-aprovação que passava despercebida desde o item 16.

**E o teste do dual review estava errando o cenário.** A primeira versão fazia um `clinical_reviewer` criar a release, mas ele não tem `content:write` — nunca seria o autor. O caminho pelo qual a auto-aprovação é de fato alcançável é a **promoção**: um editor cria a release, é promovido a revisor, e passa a ter permissão de aprovar sem deixar de ser o autor. A matriz de papéis não vê isso; só a regra por linha barra.

**O extrator tem três responsabilidades que não podem falhar em silêncio.** Só regras `approved` entram (rascunho no pack é conteúdo não revisado chegando a aparelho sem internet); só o município da release; nenhuma coluna de autoria atravessa. As três têm teste próprio.

**Duas fontes para a suíte golden, e nenhuma sincronização.** O YAML alimenta o caminho `seed/` (que o CI roda em toda PR, sem docker); `golden_case` alimenta o caminho do CMS, onde o revisor clínico acrescenta casos pela interface. Cada caminho tem **uma** fonte, e as duas desaguam na mesma `validateGolden` — que é o que impede os critérios divergirem. `import-golden.ts` semeia a tabela uma vez e é idempotente: não sobrescreve caso editado no CMS.

**Guarda nova na assinatura.** Assinar com chave que não está em `signing_key` produz um pack que **toda a frota rejeita em silêncio**: o sync tenta, a assinatura não confere, e nada no servidor acusa. A guarda deriva a pública da privada e compara com o registro — transformando um incidente mudo de frota inteira numa falha de build com nome. Roda **antes** do build, porque descobrir no fim desperdiçaria o trabalho e o erro apareceria depois dos portões verdes, onde ninguém o procura.

**Portão vermelho devolve a release para `approved`, não para um estado de erro.** O problema está no conteúdo, e depois de corrigido a mesma release deve poder ser construída de novo. Um estado `failed` exigiria um caminho de volta que ninguém lembraria de usar. A corrida golden fica registrada em `golden_run` mesmo quando falha.

**O teste da trilha encontrou uma transição não auditada.** Tomar posse (`approved → building`) alterava o estado sem registrar nada: uma release em `building` não diria quando o job a pegou. Corrigido — e todas as transições do job registram `actor_id` **NULO**, que é a verdade (inventar um usuário `system` criaria uma linha em `admin_user` que parece porta dos fundos numa auditoria).

**A telemetria ganhou endpoint e duas lacunas declaradas.** `POST /api/telemetry` é a **segunda e última** exceção à LGPD-RT01 — autenticar exigiria identidade de dispositivo, que a INV-2 proíbe. Há teste percorrendo `/api` e exigindo que nenhuma outra rota dispense sessão.

**Achado ao ler o desenho: a telemetria não tem produtor possível, e não é só falta de ADR.** `TelemetryRecorder` acumula contadores **por aparelho**; o contrato exige `kCount >= 20` no lote submetido, e um aparelho não tem como saber quantos outros existem na coorte. **Falta um agregador, que nenhum documento nomeia.** São duas causas independentes, e as duas ficam registradas abaixo.

**Sabotagem: 7 proteções, 7 pegas** — gatilho anti-auto-aprovação removido, quórum aceitando qualquer papel, atalho `draft → approved` na FSM, validador k≥20 desligado, extrator deixando rascunho passar, extrator ignorando o município, guarda de chave desligada.

**Verificado contra `sqld` + MinIO reais:** sessão com 2FA; conteúdo criado pelo CMS; autor tentando aprovar → **403**; revisora clínica aprovando → `approved`; job construindo, rodando a suíte golden (1/1), assinando e publicando → `published`; três objetos no MinIO; **assinatura conferindo com a chave registrada, e falhando ao adulterar versão ou hash**; trilha distinguindo operador de job pelo `actor_id` nulo. Ambiente derrubado com `down -v`.

##### Lacunas ao fim da Fase 3

1. **Não há `cms/web/`.** A [stack.md](stack.md) decide "Vite + React SPA servida pelo próprio Hono" e **nenhum item do roadmap a nomeia**. Sem interface, o revisor clínico não exerce o papel. **Pré-requisito de piloto.**
2. **A telemetria não tem produtor**, por duas causas independentes: o app não envia (terceira chamada de rede exige ADR) e, mesmo que enviasse, seu lote seria recusado por falta de agregação. **Quem agrega é uma decisão de arquitetura ainda não tomada.**
3. **Não há importador de CONTEÚDO** de `seed/` para o CMS — só de casos golden. Um CMS recém-implantado começa vazio, e a primeira release precisa ser montada pela API. A verificação deste item usou um conjunto mínimo por isso.
4. **Upload de asset não existe.** O binário ainda vem de `seed/assets/`; `asset.storage_key` aponta para objetos que ninguém enviou.
5. **`defaultOutcomeId` fixo no CLI do packer** (`ROUTINE_UBS`), enquanto o worker e o CMS o derivam da menor severidade. Concordam hoje por coincidência de nomenclatura.
6. **24 casos golden sem `reviewed_by`.** O packer e o importador avisam; bloqueia piloto.
7. **Expurgo por retenção (LGPD-RF07) não implementado** — depende da tabela de retenção aprovada pelo encarregado.


#### 5.13 Resultado do item 23 — interface de operação (2026-08-27)

**Primeiro frontend do repositório.** Workspace `cms/web` (Vite 7, React 19, Vitest + Testing Library), servido pelo próprio Hono, com estágio de build novo no `cms/Dockerfile`. 20 testes de SPA e 12 de servidor entram no `npm test` da raiz sem passo novo no CI.

**O mecanismo de type safety que a stack.md prescreve não é viável, e isso precisa estar escrito.** A [stack.md](stack.md) §3.3 exige "mudança no schema do banco quebra o build do frontend" e nomeia `hono/client` como o meio. Quatro impedimentos independentes, qualquer um fatal: o tipo de rotas do Hono só cresce por **encadeamento**, e `app.ts` usa declarações soltas; o CRUD é montado num **laço** sobre `CONTENT_ENTITIES`, e caminho derivado de variável é `string`, não literal — ~48 das ~65 rotas são estruturalmente não-inferíveis; `hc()` precisa do app como valor, e `createApp` é fábrica que recebe um `Client` vivo; e reconstruir a inferência exigiria abandonar o laço do registro, que é a melhor decisão estrutural do plano de controle. **O requisito é honrado por outro caminho** — tipos derivados de `InferInsertModel` do Drizzle, mais amarrações de exaustividade (`Record<AdminRole, …>` no painel já reprova se um papel novo entrar em `ADMIN_ROLES`). `@hono/zod-openapi` continua instalado e sem uso, e `hono/client` continua ausente: a distância entre a spec e a realidade **aumentou** neste item, e está declarada aqui para que o próximo leitor não implemente contra a spec.

**A guarda de `/api/*` é a linha que sustenta o desenho.** Sem ela, `GET /api/rota-com-typo` recebe o `index.html` do recuo de histórico e todo `fetch` da SPA falha com `Unexpected token '<'` — um erro que aparece no console do navegador e não em tela nenhuma. Ela casa por **prefixo de caminho**, e não por "a rota é protegida": `/api/telemetry` é público e montado antes do grupo protegido, e uma guarda escrita da segunda forma quebraria a única rota sem sessão do sistema.

**A SPA é montada com `app.use('*')`, nunca `app.get('*')`.** `use` grava `method: 'ALL'`, que `doc-operacao.test.ts` filtra ao percorrer `app.routes`; um `GET *` no catálogo faria o teste "toda rota aparece no manual" passar **por vacuidade**, porque o manual contém `*` em qualquer negrito. Asserção verde por vacuidade é pior que vermelha.

**O CSRF em desenvolvimento foi resolvido sem forjar cabeçalho.** Reescrever `Origin` no proxy do Vite falsificaria uma proteção que tem teste, e deixaria qualquer página de terceiro POSTar para `localhost:5173` com a origem lavada pelo proxy. Em vez disso, o `BETTER_AUTH_URL` aponta para a porta do **Vite** no modo de desenvolvimento — a origem que o navegador de fato usa — e o proxy repassa sem tocar em nada. `strictPort: true` não é cosmético: com a porta ocupada, o Vite mudaria para 5174 e todo POST passaria a dar 403 sem explicação.

**Um defeito de laço fechado, achado por teste.** Quem recarrega a página em `/entrar/cadastrar-2fa` está com o cookie de 2FA **pendente**, e a sondagem de `/api/me` responde 401. Tratar isso como "sessão perdida" e navegar para `/entrar` expulsa a pessoa da única tela onde ela ativaria o segundo fator que é obrigatório ter ativado — e entrar de novo a devolve ao cadastro, num laço sem saída. A guarda usa `sessao: 'dispensa'` de `rotas.ts`, que já existia como dado.

**O teste desse defeito passava pelo motivo errado antes de ser corrigido.** Ele afirmava o cabeçalho logo após montar, quando a sondagem ainda não havia respondido e a tela certa estava na frente por um instante — ou seja, passava **com** o defeito. Só depois de esperar a sondagem acontecer *e* o React processar o que ela desencadeou é que a pergunta "continuo na tela do cadastro?" significa alguma coisa. A sabotagem confirma: sem a guarda, vermelho.

**Um `403` com dois significados, e o cliente não consegue desempatar.** Achado no navegador, não em teste. Depois do `enable`, `two_factor_enabled` continua **falso** até a primeira verificação bem-sucedida — então `/api/me` responde o mesmo `403` para "nunca cadastrou" e para "já cadastrou e não verificou". A primeira versão da SPA assumia sempre o primeiro caso e mandava a pessoa gerar outra chave, o que **invalidaria a que ela acabou de guardar no autenticador**. Pior: isso fechava um laço — cadastrar mandava entrar de novo, entrar mandava cadastrar de novo, e o campo de código era inalcançável. A correção tem duas metades: a sondagem de fundo não navega de dentro do fluxo de entrada (quem decide é a ação explícita da pessoa), e a tela de cadastro **pergunta**, oferecendo o atalho para `/entrar/codigo`. Medido contra o servidor: a ativação é o `verify-totp` sobre a sessão do próprio login, e não exige cookie de 2FA pendente.

**O Testing Library não limpa sozinho sem `globals: true`.** Como `vite.config.ts` deliberadamente não usa globais, os renders se acumulavam no mesmo `document.body` e as consultas passavam a encontrar elementos de testes **anteriores** — o sintoma era "found multiple elements" num teste que renderizou uma tela só. `afterEach(cleanup)` explícito.

**A paleta do CMS é cinza, e a divergência é a decisão.** A semântica verde/vermelho/azul/lilás é do app Android e existe para quem tem baixo letramento; nenhum documento a estende ao operador. Estendê-la seria ruim: `venue.color_token` e `card.color_token` são **dado** que o operador atribui, e uma ferramenta pintada com os mesmos verdes e vermelhos faria confundir a cor da tela com a cor sendo atribuída ao conteúdo.

**O estado vazio por papel é conteúdo, não enfeite.** O primeiro operador do sistema é criado por `cms:create-admin` e é um `admin` — que não tem `content:write` nem `approval:decide`. A primeira pessoa a abrir a interface é exatamente a que menos botões enxerga, e sem uma explicação em tela a conclusão razoável é "está quebrado".

**Uma dependência a mais que o orçamento mínimo, declarada:** `qrcode` (MIT, sem transitivas), carregada sob demanda — sai em chunk separado de 26 kB e não entra no bundle inicial de quem já tem 2FA. Digitar 32 caracteres em base32 no celular é onde um revisor clínico municipal desiste, e ele só faz isso uma vez, sozinho. A falha ao gerar o QR é isolada da falha de cadastro: sem canvas, a chave continua na tela e o cadastro continua válido.

##### 23c — o ciclo da release, e dois defeitos do mesmo tipo

**Verificado no navegador, com duas contas:** o editor cria e submete, a revisora clínica aprova, e a trilha registra atores diferentes para cada passo. Nenhum `curl` no caminho. A release para em `approved` com a única transição restante — a do job — renderizada como **texto**, porque um botão desabilitado sugeriria falta de permissão quando o que falta é o job rodar.

**Dois defeitos, e os dois são a mesma classe: usar metade da resposta do servidor.** `GET /api/releases/<id>` devolve `transicoes` com `de`, `para`, `por` e `motivo`. A primeira versão da tela renderizava um botão por transição olhando só `de`/`para` — então o editor que acabara de submeter via "Aprovar" logo abaixo, clicava, e recebia 403 com uma mensagem genérica. Pior: ele é o autor, e mesmo com o papel certo o gatilho anti-auto-aprovação o barraria. Usar `por` **não** é uma segunda cópia da FSM: ele vem na mesma resposta, e ignorá-lo era ler a resposta pela metade. Agora a transição que não é sua aparece como "cabe a `clinical_reviewer`" — a segregação da LGPD-RF11 virou algo que se **vê**.

O outro é o defeito de backend abaixo, que só apareceu porque a tela monta os botões a partir do dado.

**A lista de lacunas do painel mentiu no mesmo commit em que deixou de ser verdade.** `AINDA_NO_CURL` era literal: com a tela de releases pronta, o painel continuava mandando o editor usar `curl` para o que ele acabara de ganhar em botão. Virou derivação de `ROTAS_DA_SPA` — a área some da lista quando a rota aparece. É o mesmo motivo de `PII_COLUMNS` e `APPEND_ONLY_TABLES` serem percorridas por teste, e é a segunda vez neste item que uma lista redigida à parte envelheceu.

**`web-releases-conformance.test.ts` fecha o laço nos dois sentidos**, e um dos seus testes é estrutural: **nenhum literal de estado de release pode aparecer em código de `cms/web/src` fora de `acoes.ts`**. Um `if (status === 'pending_review')` numa tela é o começo da segunda cópia da FSM, e ela não volta atrás sozinha. Comentário que explique a FSM continua permitido — é o oposto do risco.

##### 23d — a cadeia de type safety, e o que ela não alcança

**O elo é `keyof`, e ele foi verificado por sabotagem.** `Campo.nome` é `keyof EntradaDeConteudo[E]`, com `EntradaDeConteudo` derivado de `InferInsertModel` menos `AUTHORING_FIELDS`. Renomear `icon_ref` para `asset_ref` em `db/schema/content.ts` produz **6 erros** em `campos.ts` e reprova `npm run typecheck` — que é o que a [stack.md](stack.md) §3.3 exige, por um caminho diferente do que ela prescreve.

**`keyof` pega renome e remoção; não pega ACRÉSCIMO** — e essa é a metade que importa mais na prática. Uma coluna `NOT NULL` sem default significa que o editor deixa de conseguir criar a linha, o `POST` passa a responder 400 para sempre, e o compilador fica mudo. `web-conformance.test.ts` fecha isso comparando `getTableColumns()` com `CAMPOS` nos dois sentidos; sabotado com uma coluna nova em `card`, reprova nomeando `cards.sabotagem`.

**Uma cópia frouxa quase desfez a cadeia inteira, em silêncio.** `api/erros.ts` declarava seu próprio `ProblemaDeRegra` com `codigo: string`. Parecia inofensivo e significava que um código novo em `rule-validation.ts` passaria pelo compilador sem tocar em `COMO_RESOLVER` — a tela mostraria um problema clínico sem explicação. Passou a reexportar o tipo do servidor: agora o `Record` fica incompleto e reprova.

**Três metadados são repetidos no cliente, e a repetição é comparada.** `registry.ts` importa as tabelas do Drizzle, que são objetos de runtime; importá-lo no navegador arrastaria o ORM inteiro para o bundle por causa de três campos. `META` os repete e o teste os compara campo a campo com `CONTENT_ENTITIES` — que é a diferença entre repetir e duplicar. O mesmo vale para os campos de tradução, conferidos contra as colunas de `*_translation`: campo a menos ali vira pack que o **packer recusa publicar**, longe de quem causou.

**O índice de conteúdo é a resposta a uma frase do manual.** "O `409` diz o que aconteceu mas não o que faltava" (§4.1). Com o banco vazio, o índice mostra as dez entidades na ordem que as FKs impõem e, para cada uma, **nomeia o que falta** — `venues` precisa de `assets`, `routing-outcomes` precisa de `cards` e `venues`. Verificado no navegador.

**A guarda contra a segunda cópia da FSM teve um falso positivo, e a correção foi restringir, não contornar.** `draft` e `approved` são estados de release **e** de regra (`RULE_STATUSES`): o editor de regras usa os dois legitimamente. Proibi-los obrigaria a contorná-los, o que é pior que não guardar. A guarda passou a cobrir os cinco estados inequívocos, onde uma cópia da FSM de release de fato apareceria.

**Um defeito visual que só a tela mostrou:** `form { flex-direction: column }` alcança apenas os filhos diretos, e nos editores os campos ficam dentro de `section.cartao` — rótulo e campo caíam lado a lado, "Identificador [campo] Prioridade [campo]" numa linha só. Nenhum dos 38 testes veria isso.

**A lista de lacunas do painel virou derivação, depois de mentir duas vezes.** Era literal, e ficou falsa no mesmo commit em que releases ganhou tela; na 23d o mesmo teria acontecido com conteúdo e regras. Agora cada área aponta para o prefixo de rota que a cobre, e some quando a rota aparece.

##### Defeito de backend encontrado em 23c, e corrigido

`TRANSICOES[0]` declara `draft → pending_review` como `por: ['editor', 'admin']`, mas a rota `/submeter` exige `content:write`, que o `admin` **não tem**. Como a tela monta os botões a partir de `transicoes` — que é o que a [operacao.md](../docs/operacao.md) §4.4 manda fazer —, um admin veria "Submeter" habilitado e receberia 403. Contornar na SPA seria criar a segunda cópia das regras que a instrução existe para impedir. Corrigido no **dado**: `'admin'` saiu daquela transição, alinhando-a à rota, à matriz de papéis do item 17 e ao manual. Corrigir pelo outro lado — dar `content:write` ao admin — desfaria a segregação que a LGPD-RF11 exige.

O defeito sobreviveu desde o item 19 porque **nenhum teste comparava a FSM com a permissão da rota**: com `curl`, quem monta a chamada já sabe quem pode o quê, e a divergência não tem sintoma. Agora `web-releases-conformance.test.ts` percorre `TRANSICOES` e exige que todo ator declarado em `por` realmente tenha, em `ROLE_PERMISSIONS`, a permissão que a rota correspondente cobra — com a ponte entre os dois vocabulários escrita à mão, porque é exatamente a informação que nenhum dos dois lados carrega sozinho. Transição nova sem linha nessa tabela reprova.

##### Lacunas novas, declaradas ao fim de 23b

1. **Não há aceite de Termo de Uso no primeiro login.** `legal_document` e `consent_record` existem e são append-only desde o item 16, e **nenhuma rota os toca**. A LGPD-RF02/RF04 exige que o primeiro login do CMS bloqueie o acesso até o aceite, com versão e hash do documento registrados. Construir a tela de entrada tornou a lacuna mais visível, não menor.
2. **Tradução não tem travamento otimista.** `PUT …/traducoes/<lang>` é upsert sem `If-Match` e responde sem `ETag`; dois editores se sobrescrevem em silêncio. A SPA não tem como corrigir isso do lado dela.
3. ~~**O CMS não está atrás de TLS.**~~ **Fechada no item 24** — ver §5.14.


#### 5.14 Resultado do item 24 — o CMS atrás de TLS (2026-08-28)

Fecha a lacuna 3 do item 23. O que mudou de peso entre um item e outro: enquanto o plano de controle era API consumida por `curl` de quem já tinha acesso ao host, uma porta em `127.0.0.1` era inócua; com **sete telas** e um formulário de login em uso real, senha, código TOTP e cookie de sessão passaram a atravessar HTTP em claro.

**O interruptor é um só, e estava desligado.** Medido em `node_modules/better-auth/dist/cookies/index.mjs:20-46`: `secure` e o prefixo `__Secure-` saem da **mesma** variável, e ela é `baseURLString.startsWith("https://")`. Não há bloco `advanced` em `auth/config.ts` que sobrescreva, e **`NODE_ENV=production` não socorre** — o fallback por ambiente só vale quando não há `baseURL` nenhum. O mesmo valor governa `trustedOrigins`, que é exatamente `[new URL(baseURL).origin]`.

Por isso a correção central não é o bloco no Caddy: é **`loadEnv()` derrubar o processo** quando, em produção, o `BETTER_AUTH_URL` não começa com `https://`. Mesmo padrão do `IP_HASH_SALT` ausente, aplicado ao predicado exato de que o cookie depende. Sem ela, um `.env` copiado do exemplo sobe com o cookie desprotegido e **nada acusa** — que é literalmente como esta lacuna nasceu e sobreviveu a uma fase inteira.

**A armadilha do arquivo, escrita onde ela seria cometida.** O site de conteúdo tem `@mutating not method GET HEAD` / `respond @mutating 405`, porque o aparelho só lê. Copiá-lo como ponto de partida para o bloco do CMS — o gesto mais natural do mundo — quebraria login, aprovação e toda gravação, com um `405` que ninguém associa ao Caddy. Os dois blocos são separados de propósito, e o comentário diz isso.

**O `cms` deixou de publicar porta**, como o `packer` já não publicava: a topologia **é** a garantia. `db` e `storage` seguem em `127.0.0.1` por necessidade operacional (migração pelo host, console do MinIO); os dois que carregam credencial — o CMS com o formulário, o packer com a chave privada — não publicam nem loopback.

**Dev passou a chegar pelo `edge` também**, em HTTP e por porta (`:80` conteúdo, `:81` CMS). Não é capricho: o caminho do proxy — cabeçalhos, `Origin`, `X-Forwarded-*` — é onde este projeto já se queimou duas vezes, e produção é o pior lugar para exercitá-lo pela primeira vez. O que dev não reproduz é o TLS, e portanto nem o `Secure`; a guarda de boot é o que impede essa divergência de embarcar.

**Um defeito latente encontrado ao escrever o teste.** `loadEnv(source)` aceitava um ambiente e `obrigatorio()` lia `process.env` direto — metade do arquivo ignorava o parâmetro. Passava por acidente enquanto o `.env` do desenvolvedor tinha os segredos, e falharia em CI por um motivo que não é o do teste. É a mesma classe de "teste que tranquiliza sem guardar" que o item 18 encontrou na pragma de FK.

**Duas lacunas de verificação fechadas de passagem:** o job `infra` do CI usava `-f compose.yaml`, então o override de desenvolvimento **nunca era validado**; e **não existia `caddy validate` em lugar nenhum** do repositório — um erro de sintaxe no Caddyfile só aparecia quando o `edge` reiniciava, em produção, com o serviço já fora do ar.

**Sabotagem: 3 guardas, 3 pegas.** Guarda de https removida do `loadEnv`; `ports:` devolvido ao `cms`; `depends_on: cms` removido do `edge`.

**O aplicativo não é afetado, e vale saber por quê:** `PACK_MANIFEST_URL` é constante de compilação apontando para o `storage`, sem pinning nem trust store próprio. Acrescentar um site do CMS não toca nada. Mexer em `CONTENT_DOMAIN`, esse sim, exigiria recompilar e redistribuir o APK — e por isso ficou de fora.


### Fase 3.5 — Interface de operação (pré-requisito de piloto) ✅
23a. Fiação: workspace `cms/web`, servir estáticos pelo Hono, estágio de build no Dockerfile. ✅
23b. Entrada, cadastro do segundo fator e painel. ✅
23c. Releases: lista, detalhe com botões vindos de `transicoes`, aprovar/rejeitar. ✅
23d. Regras (editor DNF + simulação) e CRUD de conteúdo. ✅
**Saída:** §4 do `docs/operacao.md` executável de ponta a ponta pelo navegador, por dois operadores diferentes.

### Fase 4 — Endurecimento e GA
20. Testes de perf/estabilidade (72 h), auditoria de tráfego (zero PII), varredura de dependências.
21. Ansible + runbooks (incidente, rotação de chave, revogação de pack).
22. Delta packs (bsdiff), espelhos rsync, F-Droid/Play Store.

---

## 6. Validação (comandos a serem criados)

```bash
# contrato — quebra se schema e Dart divergirem
npm --prefix cms run contract:generate && git diff --exit-code contract/ app/lib/generated/

# app
flutter analyze && flutter test                       # inclui golden do gate (pass 100%)
flutter test integration_test/ --dart-define=OFFLINE=true

# plano de controle
npm --prefix cms test && npm --prefix packer test
docker compose -f infra/compose.yaml config --quiet

# pack ponta a ponta (falha se golden ou integridade referencial falhar)
docker compose run --rm packer build --municipality 0000000 --dry-run
```

## 7. Riscos deste plano

| Risco | Prob. | Mitigação |
|---|---|---|
| Duplicação de schema (autoria no CMS × pack) divergir | **Alta** | Schema Drizzle é fonte única; o pack é **projeção gerada**, nunca escrito à mão; diff-check em CI |
| Modelagem DNF das regras ser expressiva demais/de menos para o clínico | Média | Validar na Fase 1 com o revisor clínico usando casos reais antes de construir o editor da Fase 3 |
| Codegen TS→Dart frágil (quicktype com tipos complexos) | Média | Manter o `pack-schema.json` deliberadamente plano; sem `oneOf`/polimorfismo |
| Fase 1 escorregar por scaffolding excessivo | Média | Fase 0 é intencionalmente magra; `seed/` substitui o CMS até a Fase 3 |
| `pack_version` global vs. por município | Baixa | Já decidido: monotônico **por município** (UNIQUE composta), habilitando o sharding do PRD §7.1 |

## 8. Aceitação

- [ ] Estrutura de pastas criada conforme §3, sem diretório órfão
- [ ] Três esquemas implementados conforme §4, com `PRAGMA foreign_keys=ON` e triggers append-only ativos
- [ ] `red_flag_gate` é função pura e total; suite golden com pass 100%
- [ ] Nenhuma tabela ou log persiste sequência de tokens (verificado por teste de CI)
- [ ] Contrato gera Dart e TS a partir de fonte única; divergência quebra o build
- [ ] Packer recusa assinar pack com órfão referencial ou golden vermelho
- [ ] Compose sobe a topologia completa localmente
