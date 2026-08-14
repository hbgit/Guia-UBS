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
├── docs/                        # especificação (existente)
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
│   │   ├── sync_service.dart                 # máquina explícita (enum + tabela)
│   │   ├── manifest_client.dart              # ETag + condicional
│   │   ├── pack_downloader.dart              # HTTP Range retomável
│   │   ├── pack_verifier.dart                # Ed25519 + SHA-256 + anti-downgrade
│   │   ├── pack_installer.dart               # staging → rename atômico
│   │   └── background_scheduler.dart         # WorkManager
│   ├── speech/{speech_service,system_tts_service,recorded_audio_service}.dart
│   ├── prefs/{user_database.dart,prefs_repository.dart}   # Drift
│   ├── telemetry/{counters.dart,telemetry_uploader.dart}  # allowlist
│   ├── privacy/                              # CAP-13 (LGPD-RF03)
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
│   └── web/                         # SPA React (Vite), servida pelo Hono
├── test/
└── Dockerfile                       # multi-stage: deps→dev→build→production

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
| 1 | `admin_user` | `id`, `email UNIQUE`, `name`, `password_hash` (Argon2id), `role CHECK(role IN ('editor','clinical_reviewer','admin'))`, `totp_secret_enc`, `disabled_at`, `created_at` | RBAC de 3 papéis; 2FA obrigatório |
| 2 | `session` / `account` / `verification` | conforme Better Auth | Sessão ≤ 24 h |
| 3 | `audit_entry` | `id`, `actor_id→admin_user`, `action`, `entity_type`, `entity_id`, `before_json`, `after_json`, `ip_hash`, `occurred_at` | **APPEND-ONLY** (trigger bloqueia UPDATE/DELETE) — LGPD-RT03 |
| 4 | `legal_document` | `id`, `type CHECK(type IN ('tos','privacy','consent'))`, `version`, `content_md`, `content_hash`, `effective_from` | Versionado; muda ⇒ re-aceite |
| 5 | `consent_record` | `id`, `subject_ref`, `doc_type`, `doc_version`, `doc_hash`, `method`, `accepted_at` | **APPEND-ONLY** — LGPD-RT05 (ônus da prova, art. 8º §2º) |

**B. Autoria de conteúdo** — espelha 4.1 em versão mutável: `municipality`, `symptom_token`, `token_translation`, `routing_outcome`, `routing_rule`, `routing_rule_term`, `venue(+trad)`, `card(+trad)`, `service(+trad)`, `document(+trad)`, `service_document`, `flow_step(+trad)`, `asset`. Diferenças em relação ao pack:

- toda entidade editável ganha `version INTEGER NOT NULL DEFAULT 1`, `updated_by→admin_user`, `updated_at`;
- `asset` guarda `storage_key` (objeto no MinIO) além de `sha256` e `bytes`;
- `routing_rule` ganha `status CHECK(status IN ('draft','approved'))` — regra aprovada **nunca é editada in-place**: gera nova linha (append por versão de pack).

**C. Publicação**

| # | Tabela | Colunas-chave | Notas |
|---|---|---|---|
| 6 | `pack_release` | `id`, `municipality_id`, `pack_version INTEGER` (monotônico por município), `schema_version`, `status CHECK(status IN ('draft','pending_review','approved','built','published','revoked'))`, `pack_sha256`, `manifest_json`, `signed_at`, `published_at`, `created_by`, UNIQUE(`municipality_id`,`pack_version`) | Ciclo de vida do artefato |
| 7 | `approval` | `id`, `pack_release_id`, `approver_id→admin_user`, `role`, `decision CHECK(decision IN ('approve','reject'))`, `comment`, `decided_at` | **APPEND-ONLY**; regra de negócio: `approver_id ≠ pack_release.created_by` e exige ≥ 1 `clinical_reviewer` |
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
8. `llama_engine` PoC com bench em device ≤ 4 GB + `rule_only_engine`.
9. `sync_service` PoC: manifest com ETag, download com Range, verificação, swap atômico.
**Saída (gate do PRD):** inferência p95 < 3 s; sync retoma após corte; nenhum pack inválido ativado.

#### 5.1 Resultado do bench do item 8 (2026-08-13)

Medido com `app/tool/bench_inference.dart`, 20 iterações sobre casos derivados das próprias regras do pacote, contexto 512 tokens, 4 threads fixadas em 4 núcleos (`taskset`) de um **Intel i7-12650H** — CPU de notebook, **não** o aparelho alvo.

| Modelo (Q4_K_M) | Arquivo | p50 | p95 | Pico de RAM | Respostas válidas |
|---|---|---|---|---|---|
| Gemma 3 **1B** | 768 MB | 1455 ms | **2549 ms** | 1136 MB | 17/20 |
| Gemma 3 **270M** | 241 MB | 394 ms | 589 ms | 540 MB | **1/20** |

**Três conclusões, duas delas ruins:**

1. **RNF-03 é incompatível com o Gemma 3 1B.** O orçamento é *APK + modelo + pack ≤ 400 MB*. Medido:

   | Parcela | Tamanho |
   |---|---|
   | APK release arm64-v8a (inclui `libllama` + `libggml*` + `libgubs_llama` = 4,2 MB) | **21,1 MB** |
   | Modelo Gemma 3 1B Q4_K_M | **768 MB** |
   | Pack de conteúdo (semente) | < 1 MB |
   | **Total** | **≈ 790 MB** |

   O app não é o problema: ele responde por 2,7% do total. A menor quantização utilizável do 1B é **681 MB** (IQ4_XS), e o gargalo é a tabela de embeddings de 256k tokens, que praticamente não quantiza. Não há ajuste de flag que resolva — ou o orçamento sobe para ~1 GB, ou o modelo muda. **Decisão de produto pendente.**
2. **RF-05 (p95 < 3 s) está em risco sério.** Os 2549 ms saíram de núcleos Alder Lake de notebook. Um SoC de entrada (Cortex-A53/A55) roda inferência CPU do llama.cpp a uma fração dessa velocidade, então o p95 no aparelho alvo deve ficar bem acima de 3 s — e provavelmente acima do teto duro de 5 s, que dispararia o `RuleOnlyEngine` na maioria das triagens. **O critério não pode ser declarado atendido.**
3. **Trocar para o 270M não é saída trivial.** Ele cabe no orçamento e é 4× mais rápido, mas produziu identificador válido em **1 de 20** casos: na prática o app rodaria sempre em modo degradado. Um modelo que se abstém sempre é seguro (o gate decide) e inútil.

**Duas variáveis já descartadas por medição:** aplicar o *chat template* do Gemma **piora** o resultado (0/8 válidos — o modelo passa a responder em prosa, e o decodificador corretamente rejeita); e o pico de RAM, diferente da latência, **transfere entre arquiteturas**, então os 1136 MB medidos valem para o aparelho e cabem no RNF-03 (≤ 1,5 GB), ainda que com pouca folga.

**Integração Android (verificada):** o `externalNativeBuild` do Gradle compila e empacota `libgubs_llama.so` para `arm64-v8a`, e o fecho de dependências dentro do APK está completo (`libllama`, `libggml{,-base,-cpu}`, `libc++_shared` — nenhuma ausente). Release fixado em arm64-v8a apenas; x86_64 só no debug, para emulador.

**O que falta para fechar de fato:** rodar em arm64 real. Dois degraus continuam sem prova:

1. **Carga do `.so` em runtime Android.** `integration_test/native_shim_test.dart` existe e faz essa checagem, mas não foi executado — o emulador do SDK não sobrevive neste ambiente, e só há imagem x86_64 (que também não mediria CPU de entrada). O fecho estático de dependências acima é evidência forte, não prova.
2. **p95 em SoC de entrada.** Falta o aparelho.

### Fase 2 — App (CAP-01…13)
10. Casca: tema, GoRouter, i18n pt/es, `speech/`.
11. `content/` (repositórios RO) + `prefs/` (Drift).
12. `triage_orchestrator` completo (FSM-A) + telas de composição/resultado.
13. Encaminhamento, fluxo, documentos.
14. `privacy/` (CAP-13) + `telemetry/` com allowlist.
15. `sync/` endurecido: backoff+jitter, circuit breaker, guard de quiescência.
**Saída:** APK com jornadas verde/vermelha/sync passando em device farm.

### Fase 3 — Plano de controle (CAP-14/15)
16. Schema Drizzle completo + migrações + triggers append-only.
17. Better Auth + RBAC + 2FA; trilha de auditoria.
18. CRUD de conteúdo com travamento otimista; editor de regras (DNF) com validação.
19. Workflow de dual review + orquestração de release; ingestão de telemetria com validador k≥20.
**Saída:** pack publicado ponta a ponta pelo CMS, com aprovação clínica registrada.

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
