# Levantamento do estado do projeto — plano e lista de issues

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Classificar cada feature e requisito do Guia UBS como entregue, parcial, ausente ou divergente, com evidência reproduzível, e chegar a uma lista de issues ordenada para aprovação — sem criar nada no GitHub antes do ponto de decisão.

**Architecture:** O levantamento lê as fontes na ordem de precedência (PRD → `spec/` → registro de progresso em `spec/arquitetura.md` §5 → issues/PRs → código e testes). "Entregue" exige teste automatizado verde; o que só existe em documento conta como não verificado; entrega com lacuna declarada é **parcial**. As tarefas 1–4 reproduzem a evidência; a tarefa 5 é o ponto de decisão; a tarefa 6 só roda após aprovação.

**Tech Stack:** Flutter 3 / Dart (app, `flutter test`, `flutter analyze --fatal-infos`), TypeScript / Node 22 (`npm test`, `npm run typecheck`), llama.cpp `b6100` via shim C (`native/llama_shim/`), `adb` em `~/Android/Sdk/platform-tools`, `gh`.

**Spec:** `spec/PRD.md` (governa), `spec/espec.md` §1.2 (RF-01…15, RNF-01…09), `spec/lgpd.md` §7–8, `spec/stack.md` §9–10 (ADR-001…003), `spec/arquitetura.md` §5 (registro de progresso oficial; não existe `PROGRESS.md` nem `docs/superpowers/plans/` anteriores — este é o primeiro).

## Global Constraints

- Nenhuma issue, label ou marco é criado antes da aprovação explícita da tarefa 5.
- "Entregue" = código + teste automatizado que exercita o critério de aceite da `espec.md` §1.2 (+ prova e2e quando o critério a exige). Teste que não cobre o critério, ou lacuna declarada pelo próprio registro, = Parcial.
- Medição só vale como evidência se for em aparelho arm64 real, com configuração nomeada; número de host não serve (`spec/arquitetura.md` §5.1). Linhas marcadas **provisório** dependem das tarefas 3 e 4, que exigem aparelho físico: hoje só há um emulador x86_64 (`adb devices`), e o APK é arm64-only (`build.gradle.kts:41`).
- Títulos e corpos de issue em português; modelo de issue e labels da seção "Ponto de decisão".
- Não propor feature fora do PRD: o que parecer necessário e não constar vira pergunta ao dono.
- O repositório é `hbgit/Guia-UBS`; `gh issue list --state all` e `gh pr list --state all` devolvem **zero** itens (2026-10-28), então não há duplicata possível. Labels existentes são só os padrão do GitHub.

## Review Focus

1. **APK release sem `INTERNET`** (confirmado na tarefa 2): um aparelho com o APK de release não baixa pack nem modelo e fica sem conteúdo. Pinado em P0-1.
2. **Backup automático do Android ligado por padrão** (confirmado na tarefa 2): sem `allowBackup="false"` nem `dataExtractionRules`, o `user.db`, o pack e o GGUF — todos em `getApplicationSupportDirectory()` (`app_paths.dart:31`, `user_database_connection.dart:30`) — são candidatos a cópia para o Google Drive, saída de dados sem nenhuma chamada de rede no código do app. Pinado em P1-3.
3. **Modelo vindo de `huggingface.co` direto do aparelho**: endpoint fora da topologia self-host, fora de qualquer allowlist, e redistribuição sem os avisos que os termos do Gemma exigem. Pinado em P1-1.
4. **Aparelho de entrada real (4 GB, Cortex-A55)**: a única medição é um intermediário de 7,6 GB com proxy por `taskset`; no alvo real, toda triagem pode cair no timeout de 5 s. Pinado em P1-5.
5. **Casos golden sem revisor clínico**: 24 de 24 casos do semente não têm `reviewed_by`; o packer só avisa, e um caso novo sem revisão regride em silêncio. Pinado em P0-2.

---

### Task 1: Reproduzir a base de evidência (host) ✅

**Files:**
- Leitura: `spec/espec.md:19-49`, `spec/PRD.md:92-113`, `spec/arquitetura.md:301-312,496-502,909-913,1158-1168`, `spec/lgpd.md:258-294`

- [x] **Step 1: Suíte Flutter, análise e codegen**
Run (de `app/`): `flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter analyze --fatal-infos && flutter test`
Resultado (2026-10-28): `No issues found!`; **532 testes verdes, 43 arquivos**.

- [x] **Step 2: Suíte do plano de controle**
Run (da raiz): `npm run typecheck && npm test`
Resultado: **12 + 289 + 30 = 331 testes verdes**, typecheck limpo, 4 arquivos de teste de SPA (`vitest`).

- [x] **Step 3: Pack de referência e portões**
Run: `SOURCE_DATE_EPOCH=1787097600 PACK_SIGNING_KEY_PATH=contract/keys/dev-k1.pem PACK_VERSION=1 npm run pack:build`
Resultado: referencial ok, golden 24/24, `packs/pack-88c2c35a99e1.db` (160 KB), aviso **"24 caso(s) golden sem revisor clínico nomeado"**.

- [x] **Step 4: Issues, PRs e labels** — zero issues, zero PRs, só labels padrão.

- [x] **Step 5: Segredos** — `git ls-files | grep -iE '\.pem$|\.env$|keystore|\.jks$'` vazio; `.gitignore:6-9` cobre `.env` e `contract/keys/*.pem`.

### Task 2: Manifest de release — permissões e backup (host) ✅

**Files:**
- Fonte: `app/android/app/src/main/AndroidManifest.xml` (sem nenhum `uses-permission`, sem `allowBackup`, sem `dataExtractionRules`)
- Evidência: `app/build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`

- [x] **Step 1: Reconstruir o APK de release**
Run (de `app/`): `rm -f android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java; flutter build apk --release --target-platform=android-arm64`
Resultado (2026-10-28): `✓ Built build/app/outputs/flutter-apk/app-release.apk (25.6MB)` — dentro de RNF-03 (APK base 50–80 MB).

- [x] **Step 2: Permissões do manifest mesclado**
Run: `grep -n uses-permission build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`
Resultado: `ACCESS_NETWORK_STATE` (connectivity_plus), `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SHORT_SERVICE`, `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED` (workmanager), `…DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` — **e nenhum `INTERNET`**. `INTERNET` existe só em `src/debug` e `src/profile` (`:6`). **P0-1 confirmada.**

- [x] **Step 3: Backup automático**
Run: `grep -n -iE 'allowBackup|dataExtractionRules|fullBackupContent'` no mesmo arquivo.
Resultado: **nenhuma ocorrência**, `targetSdkVersion=36`. Sem o atributo, o Android assume `allowBackup=true` e inclui `files/` (= `getApplicationSupportDirectory()`) no Auto Backup. O `user.db`, o pack ativo e o GGUF moram lá. A cota de 25 MB do Auto Backup tende a excluir o app depois do modelo baixado, mas **antes do modelo** (ou no aparelho que ficou só com regras) o `user.db` e o pack cabem na cota. **P1-3 criada.**

### Task 3: Verificação do LLM offline em aparelho — PROVISÓRIO

**Files:**
- `app/tool/fetch_model.sh`, `native/llama_shim/bench_main.c`, `app/integration_test/inference_bench_test.dart`, `app/integration_test/native_shim_test.dart`, `app/tool/bench_inference.dart`

- [x] **Step 0: Aparelho disponível?**
Run: `adb devices -l` → só `emulator-5554 sdk_gphone64_x86_64`. O APK é arm64-only e o shim nativo só compila para arm64. **Sem aparelho físico nesta sessão**: os passos 1–4 ficam para as issues P1-5, P1-6 e P1-7; as linhas RF-05, RNF-01, RNF-02, RNF-04, RNF-09 e ADR-003 da tabela estão marcadas como provisórias.

- [ ] **Step 1: Obter o modelo e conferir o hash**
Run: `app/tool/fetch_model.sh gemma-3-1b` → `app/assets/models/gemma-3-1b.gguf`, 768 MB, SHA-256 `8ccc5cd1…135`.

- [ ] **Step 2: Bench nativo, três configurações de núcleos, mais tempo de carga e total da triagem**
Run: compilar `bench_main` para arm64, `adb push` para `/data/local/tmp`, `taskset` A (livre) / B (só A55) / C (só A78), 20 iterações, contexto 512 — procedimento de §5.1. Registrar também `gubs_llama_open` (tempo de carga) e, com o bench Dart, o tempo **toque final → cartão** (RNF-02 total < 6 s).
Expected: tabela p50/p95/máx/pico RSS/carga por configuração; p95 entre 3 e 5 s **no aparelho mínimo de 4 GB**.

- [ ] **Step 3: Teste de integração do shim e da degradação**
Run (de `app/`): `flutter test integration_test/native_shim_test.dart -d <device>` → 2 testes verdes. Armadilha (§5.1): esse comando desinstala o app e apaga o GGUF enviado por `adb push`; rodar o bench **antes**.

- [ ] **Step 4: Modo avião (RNF-01) e selo `assistente virtual` (RF-15)**
Run: `adb shell cmd connectivity airplane-mode enable`; app com pack instalado e modelo provisionado; percorrer triagem (rotina e red flag), onde ir, documentos, fluxo, privacidade. O selo `assistente virtual` precisa aparecer em um caso de rotina (lacuna declarada em `spec/espec.md:34`). O Edge 40 Neo serve para isto; não exige aparelho de entrada.

### Task 4: Auditoria de tráfego e endpoints (LGPD-RF01, RT11) — PROVISÓRIO

- [x] **Step 1: Inventário estático de endpoints**
Run: `grep -rn -E 'https?://' app/lib`
Resultado: dois destinos — `PACK_MANIFEST_URL` (`pack_background_sync.dart:28`, constante de compilação, storage próprio) e `https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/…` **fixo no código** (`model_catalog.dart:24`). Telemetria não envia (`telemetry_test.dart`). Nenhum teste fixa essa lista (LGPD-RT11). Com a tarefa 2, há uma **terceira saída de dados sem URL**: o Auto Backup.

- [x] **Step 2: Termos do Gemma (redistribuição)**
Fonte: `ai.google.dev/gemma/terms`, lido em 2026-10-28. §1.1(b) trata qualquer transmissão a terceiros como "Distribution". §3.1 exige, para quem redistribui: (1) as restrições de uso da §3.2 (que incorpora a Política de Uso Proibido) como cláusula vinculante no acordo que rege o uso, com notificação aos usuários; (2) cópia do Agreement a todo destinatário; (3) aviso destacado em arquivo modificado; (4) arquivo "Notice" com a frase *"Gemma is provided under and subject to the Gemma Terms of Use found at ai.google.dev/gemma/terms"*. §4.2 proíbe sugerir endosso do Google. Não há exigência de "powered by" na interface. Consequência: servir o GGUF do storage próprio (P1-1) é redistribuição e entra com esses quatro itens no escopo.

- [ ] **Step 3: Captura em aparelho**
Run: `adb shell tcpdump` (ou mitmproxy com CA de teste) durante 1º acesso, provisionamento do modelo, sync de pack e três triagens; mais um ciclo de backup forçado (`adb shell bmgr backupnow <pkg>`) antes e depois de P1-3.
Expected: só os dois destinos acima; nenhuma requisição com identificador de aparelho ou token de sintoma. Registrar em P1-2.

### Task 5: Ponto de decisão — PARE AQUI

- [x] **Step 1: Tabela e lista de issues preenchidas** (abaixo), com as linhas provisórias marcadas.
- [x] **Step 2: Respostas do dono recebidas (2026-10-28)** — registradas na seção "Decisões do dono" e já refletidas na lista.
- [x] **Step 3: Aprovação final** da lista renumerada, dos labels e dos dois marcos.

### Task 6: Criação das issues (só após aprovação)

- [x] **Step 1: Renumerar, se a aprovação mudar a ordem.** Os códigos abaixo já estão em ordem de criação (P0-1, P0-2, P1-1…P1-11, P2-1…P2-12, P3-1…P3-3). Se o dono cortar ou mover itens, renumerar em sequência, atualizar a coluna "Issue" da tabela e só então seguir.

- [x] **Step 2: Labels com descrição e cor** (reaproveita `bug` e `documentation`; `--force` padroniza os que existirem)
```sh
gh label create feature   --color 0E8A16 --description "Funcionalidade prevista na especificação" --force
gh label create tech-debt --color FBCA04 --description "Dívida técnica" --force
gh label create test      --color 1D76DB --description "Cobertura de teste ou verificação" --force
gh label create infra     --color 5319E7 --description "Compose, Caddy, Ansible, runbooks" --force
gh label create spike     --color D4C5F9 --description "Investigação ou ADR; sem código de produto" --force
gh label create app       --color C2E0C6 --description "Área: app Flutter" --force
gh label create llm       --color BFD4F2 --description "Área: inferência local (shim, modelo, bench)" --force
gh label create backend   --color F9D0C4 --description "Área: CMS, packer, contrato" --force
gh label create ci        --color E99695 --description "Área: GitHub Actions" --force
gh label create spec      --color FEF2C0 --description "Área: documentos normativos em spec/" --force
gh label create P0 --color B60205 --description "Bloqueia uso ou viola segurança/privacidade" --force
gh label create P1 --color D93F0B --description "Requisito obrigatório ainda não atendido" --force
gh label create P2 --color FBCA04 --description "Parcial ou melhoria com impacto claro" --force
gh label create P3 --color 0E8A16 --description "Dívida técnica e documentação" --force
```
Expected: `gh label list` mostra 16 (14 novos + `bug` + `documentation`).

- [x] **Step 3: Marcos "Piloto" e "v1.1"**
Run: `gh api repos/hbgit/Guia-UBS/milestones -f title=Piloto -f description="P0 e P1 do levantamento de 2026-10-28: o que precisa fechar antes do piloto em UBS"` e `gh api repos/hbgit/Guia-UBS/milestones -f title=v1.1 -f description="Pós-piloto: delta packs, vacinas, farmácia"`. Toda issue P0/P1 recebe `--milestone Piloto`; P2-12 recebe `v1.1`.

- [x] **Step 4: Gerar os corpos em arquivo e revisar por amostragem**
Escrever um arquivo por issue em `docs/superpowers/issues/2026-10-28/<código>.md`, no modelo abaixo (Contexto com arquivo:linha e evidência; Escopo numerado; Critérios de aceite verificáveis; Fora do escopo; Dependências; Referências). Revisar ao menos P0-1, P1-1 e P2-7 lendo o arquivo inteiro contra a tabela. Os arquivos podem ser apagados depois da criação, ou mantidos como registro.

- [x] **Step 5: Criar as issues na ordem da lista**
Run: `gh issue create --title "<título>" --label "<tipo>,<área>,<prioridade>" [--milestone Piloto] --body-file docs/superpowers/issues/2026-10-28/<código>.md`
Depois de criar, substituir "depende de P1-1" pelo `#número` com `gh issue edit`.

- [x] **Step 6: Épica e `PROGRESS.md`**
Issue épica "Índice do levantamento de 2026-10-28" com a lista ordenada e link para este plano. Criar `PROGRESS.md` na raiz com este conteúdo e nada além:
> O registro oficial de progresso é `spec/arquitetura.md` §5 (uma subseção por item entregue, com medições e decisões). Este arquivo é só um ponteiro: aponta para o roadmap (`spec/arquitetura.md` §Roadmap), para a issue épica do levantamento mais recente e para o marco "Piloto". **Não anote progresso aqui** — quem anota em dois lugares acaba com dois registros que divergem.

## Modelo de issue

```
## Contexto
Por que isso existe: requisito ou feature de origem, com a fonte (arquivo e linha), e o estado atual com a evidência (teste, arquivo, medição).

## Escopo
O que entra, numerado.

## Critérios de aceite
Verificáveis: teste, script, medição, ou arquivo atualizado.

## Fora do escopo
O que fica explicitamente para outra issue.

## Dependências
Issues que precisam vir antes.

## Referências
Requisitos, planos, PRs, trechos de código.
```

---

## Ponto de decisão — tabela completa

Estado: **E** entregue · **P** parcial · **A** ausente · **D** divergente · **(prov.)** provisório até as tarefas 3/4 em aparelho.

### Funcionais (espec.md §1.2) e capacidades (PRD §2.2)

| ID | Feature | Estado | Evidência | Issue |
|---|---|---|---|---|
| RF-01 / CAP-01 | Idioma pt/es por ícone, persistido | **P** | `test/prefs/locale_store_test.dart`, `test/ui/l10n_test.dart`, `test/ui/more/settings_screen_test.dart`. Critério "< 200 ms" sem medição | P2-9 |
| RF-02 / CAP-02 | Navegação iconográfica, 3 abas, prof. ≤ 4, zero dead-ends | **E** | `test/ui/navigation_structure_test.dart` (percorre `app_routes.dart`), `test/ui/shell_navigation_test.dart`, `test/ui/accessibility_test.dart` (8 elementos, 64 dp) | — |
| RF-03 / CAP-03 | Composição 1..5 tokens validados contra o pack | **E** | `test/triage/orchestrator/triage_fsm_test.dart` (A2/A3), `triage_session_test.dart` ("token fora da ontologia é recusado"), `test/ui/triage/triage_flow_test.dart` | — |
| RF-04 / CAP-04 | Gate determinístico pré-LLM, fail-closed, golden 100 % | **E** | `test/triage/red_flag_gate_test.dart`, `test/triage/golden_clinical_test.dart` (mesmo YAML do packer), CI `app.yml`; `max(gate, llm)` em `triage_session_test.dart` | — |
| RF-05 / CAP-05 | SLM local, p95 3–5 s em device ≥ 4 GB, ctx 512–1024, greedy, timeout 5 s | **P (prov.)** | Código: `llama_engine.dart` (timeout 5 s, ctx 512), `gubs_llama.c:118` (greedy), `prompt_builder_test.dart`, `llama_engine_test.dart` (runner falso). Medido só em Motorola Edge 40 Neo (7,6 GB): p95 **4731 ms** livre, **13 130 ms** no proxy A55; validade 17/20. Sem aparelho de 4 GB real, sem tempo de carga | P1-5 |
| RF-06 / CAP-06 | Cartão + TTS; TTS falha ⇒ só visual | **E** | `test/speech/speaker_test.dart`, FSM "todo cartão dispara áudio" (`triage_fsm_test.dart`); TTS ouvido no aparelho (§5.5) | — |
| RF-15 / CAP-06 | Selo de procedência derivado, ordem de leitura, não altera cor | **P** | `test/ui/triage/provenance_badge_test.dart`, `test/triage/guidance_provenance_test.dart`. Estado `assistente virtual` só com motor falso — lacuna declarada em `spec/espec.md:34` | P1-7 |
| RF-07 / CAP-07 | Onde ir (UBS × UPA), `content.db` somente leitura | **E** | `test/ui/content/static_content_test.dart`, `test/content/content_repository_test.dart` (`UPDATE` falha), INV-8 sem modelo/sync/rede | — |
| RF-08 / CAP-08 | Documentos por serviço | **E** | `static_content_test.dart` grupo "documentos (RF-08)" | — |
| RF-09 / CAP-09 | Fluxo de atendimento por `step_order` | **E** | `static_content_test.dart` grupo "fluxo (RF-09)" | — |
| RF-10 / CAP-10 | Sync WorkManager, Range + ETag, backoff, circuito; "manifest + delta" (delta adiado para v1.1 por decisão do dono; PRD §6.2 governa) | **P** | `test/sync/sync_service_test.dart`, `resumable_downloader_test.dart`, `pack_sync_scheduler_test.dart`, freio em disco (§5.8). **Delta não existe**; "janela de 30 s" sem teste; **inoperante em release** (tarefa 2) | P0-1, P2-12 |
| RF-11 / CAP-11 | Ed25519 + SHA-256 antes do swap, rename atômico, anti-downgrade, re-verificação no boot | **E** | `manifest_verifier_test.dart`, `sync_service_test.dart` ("assinatura adulterada não instala", "downgrade é recusado (INV-7)", "manifest ativo com assinatura quebrada em disco não é servido"); CI `interop`; dual-key `k1`/`k2` em `pack_signing_keys.dart` | — |
| RF-12 / CAP-12 | Degradação para `RuleOnlyEngine`, `degraded=true` | **E** | `rule_only_engine_test.dart`, `triage_session_test.dart`, `integration_test/native_shim_test.dart` ("modelo ausente degrada") — mesma tabela do gate | — |
| RF-13 / CAP-19 | Tema, fonte, idioma em `/mais/ajustes`, persistidos | **E** | `settings_screen_test.dart`, `text_scaling_test.dart`, `migration_test.dart` (v1→v2), `lgpd_surface_test.dart` | — |
| RF-14 / CAP-19 | Termos e privacidade embarcados pt/es, com data | **E** | `legal_documents_test.dart`; `app/assets/legal/{privacidade,termos}_{pt,es}.md` | — |
| CAP-13 | Privacidade: opt-out, apagar dados, aviso em áudio | **P** | `privacy_screen_test.dart` (opt-out zera coleta, confirmação, apaga `user.db`, lista = colunas). **Nenhum teste nomeado para "aviso em áudio"** | P2-10 |
| CAP-19 | Menu "Mais": ajustes, tutorial, legais, Sobre | **E** | `more_screen_test.dart`, `how_to_screen_test.dart`, `about_screen_test.dart` | — |
| CAP-14 | CMS: CRUD, RBAC 3 papéis, 2FA, dual review | **P** | 289 testes (`rbac`, `auth-flow`, `lockout`, `dual-review`, `approval-workflow`, `optimistic-lock`, `rule-editor`, `rule-simulation`, `web-*`). Lacunas declaradas em §5.13: aceite de termos no 1º login ausente; tradução sem `If-Match`; sem importador de conteúdo | P1-8, P2-3, P2-4 |
| CAP-15 | Packer: build, portões, assinatura, publicação | **P** | `packer/test/packer.test.ts`, `pipeline.test.ts`, CI `pack:check`. **24 golden sem `reviewed_by`, e o packer só avisa** | P0-2 |
| ADR-003 | Provisionamento do modelo (Range, SHA-256, 3 GB livres, UNMETERED, OTG) | **D (prov.)** | `model_provisioning_test.dart`, `model_downloader_test.dart`, `requiredFreeBytes = 3 GiB`. **Origem = `huggingface.co` fixo** (`model_catalog.dart:24`); redistribuição sem os avisos da §3.1 dos termos do Gemma; inoperante em release (tarefa 2) | P0-1, P1-1 |
| Telemetria / LGPD-RF14 | Coleta por allowlist, k ≥ 20, envio agregado (desligada no piloto por decisão do dono) | **P** | `telemetry_test.dart` (enum, opt-out zera), `cms/test/telemetry-ingest.test.ts` (recusa k < 20). **Sem produtor e sem agregador** (§5.12) | P2-6, P2-7 |
| CAP-16/17/18 | Vacinas, farmácia, v2 | **A** (fora do MVP) | PRD §6.1 | — |

### Não funcionais (espec.md §1.2)

| ID | Requisito | Estado | Evidência | Issue |
|---|---|---|---|---|
| RNF-01 | Offline total, verificado em modo avião | **P (prov.)** | `static_content_test.dart` "INV-8 … sem modelo, sem sync e sem rede" (widget). Sem teste de integração em avião | P1-6 |
| RNF-02 | Gate < 50 ms; p95 inferência 3–5 s; total < 6 s | **P (prov.)** | Gate sem bench; inferência só no intermediário; total não medido | P1-5 (inferência e total), P2-9 (gate) |
| RNF-03 | ≤ 1,2 GB; APK 50–80 MB; ≥ 3 GB livres antes; RAM ≤ 1,5 GB | **P** | APK **25,6 MB** (tarefa 2) e RAM 832 MB (§5.1); `disk_space.dart` + teste. "Pipeline de release" não mede nada | P2-1 |
| RNF-04 | Zero PII em disco, log e rede | **P (prov.)** | `lgpd_surface_test.dart`, `telemetry_test.dart`, sintoma só em memória. Tráfego nunca auditado; **backup automático ligado** (tarefa 2) | P1-2, P1-3 |
| RNF-05 | Cadeia de confiança, CDN não confiável | **E** | = RF-11 | — |
| RNF-06 | 64 dp, WCAG AA, cor semântica, zero texto obrigatório | **E** | `accessibility_test.dart`, `rendered_contrast_test.dart` (dois temas), `theme/contrast_test.dart`, `token_icons_test.dart` | — |
| RNF-07 | 72 h offline sem crash; crash-free ≥ 99,5 % | **A** | Nada; Fase 4 item 20 | P1-11 |
| RNF-08 | Inferência sob demanda; sem wakelock persistente; sync na janela | **P** | `BATNOTLOW` em `pack_sync_scheduler_test.dart`; `WAKE_LOCK`/`RECEIVE_BOOT_COMPLETED`/`FOREGROUND_SERVICE*` entram pelo `workmanager` sem justificativa escrita | P3-3 |
| RNF-09 | minSdk 26, arm64, RAM ≥ 4 GB, degradação em SoC de entrada | **P (prov.)** | `build.gradle.kts:27,41`. SoC de entrada só por proxy `taskset` | P1-5 |

### LGPD (lgpd.md §8) — só o que toca código

| ID | Estado | Evidência | Issue |
|---|---|---|---|
| RF01 permissões mínimas + auditoria de tráfego | **P** | Manifest próprio limpo; 7 permissões de plugins; tráfego não auditado; **backup automático ligado** | P1-2, P1-3, P3-3 |
| RF02 / RF04 / RT04 / RT05 aceite versionado no 1º login do CMS | **A** | `legal_document` e `consent_record` existem, append-only testado; **nenhuma rota os toca** (§5.13) | P1-8 |
| RF03 tela de privacidade | **P** | = CAP-13 | P2-10 |
| RF07 retenção e expurgo | **A** | §5.12; depende da tabela do encarregado | P2-8 |
| RF11 / RT06 / RT07 RBAC, Argon2id, sessão ≤ 24 h, bloqueio | **E** | `rbac.test.ts`, `password.test.ts`, `lockout*.test.ts`, `auth-flow.test.ts` | — |
| RF13 saúde só em memória | **E** | `lgpd_surface_test.dart` enumera colunas; sem coluna de sintoma | — |
| RF14 anti-reidentificação | **P** | = Telemetria | P2-6, P2-7 |
| RF16 CI bloqueia SDK de ads | **P** | Nenhuma lib de ads no `pubspec`; nenhum bloqueio em CI | P2-2 |
| RF17 / RT11 allowlist de endpoints em CI | **A** | Nenhum teste; `huggingface.co` fixo; Auto Backup fora de qualquer lista | P1-1, P1-2, P1-3 |
| RT01 nenhum dado em URL; auth em todo endpoint | **E** | `rbac.test.ts`; duas exceções declaradas | — |

### Dívidas transversais

| Item | Estado | Evidência | Issue |
|---|---|---|---|
| CI não constrói APK de release nem confere manifest/tamanho | **A** | `app.yml`: `analyze`, `test`, `interop`, `shim` — nenhum `flutter build` | P2-1 |
| CI não audita dependências Flutter (só `npm audit`) | **A** | `contract.yml:45` | P2-2 |
| `spec/stack.md` §9 audita 6 de 20 pacotes Flutter e nenhum do backend | **D** | §9 lista só `cryptography go_router flutter_riverpod flutter_localizations flutter_tts package_info_plus` | P3-1 |
| `spec/stack.md` §1.1 diz `llama_cpp_dart`; §1.2/§3.3 prometem `hono/client` (inviável, §5.13); `@hono/zod-openapi` sem uso | **D** | `spec/stack.md:16,28,77-93`; `cms/package.json` | P3-2 |
| Ansible + runbooks | **A** | `infra/` só tem `compose.yaml`, `Caddyfile*`, `.env.example`; Fase 4 item 21 | P2-11 |
| Pack de referência embutido no APK (decisão do dono, entra no PRD) | **A** | `pubspec.yaml` só empacota `assets/legal/` e `assets/branding/`; app instala sem conteúdo | P1-4 |
| LGPD documental: encarregado, canal do titular, DPA, inventário | **A** | `spec/lgpd.md` RF06/RF08/governança; nenhum dono fora do código | P1-9, P1-10 |
| Registro de progresso | **P** | Mora em `spec/arquitetura.md` §5; não há `PROGRESS.md` | tarefa 6, passo 6 |
| Segredos em git | **E** | Nenhum `.pem`/`.env` rastreado | — |

## Issues criadas (2026-10-28)

Épica: [#29](https://github.com/hbgit/Guia-UBS/issues/29). Labels criados (14), marcos `Piloto` (#1) e `v1.1` (#2). Corpos em `docs/superpowers/issues/2026-10-28/`.

| Código | Issue |
|---|---|
| P0-1 | [#1](https://github.com/hbgit/Guia-UBS/issues/1) |
| P0-2 | [#2](https://github.com/hbgit/Guia-UBS/issues/2) |
| P1-1 | [#3](https://github.com/hbgit/Guia-UBS/issues/3) |
| P1-2 | [#4](https://github.com/hbgit/Guia-UBS/issues/4) |
| P1-3 | [#5](https://github.com/hbgit/Guia-UBS/issues/5) |
| P1-4 | [#6](https://github.com/hbgit/Guia-UBS/issues/6) |
| P1-5 | [#7](https://github.com/hbgit/Guia-UBS/issues/7) |
| P1-6 | [#8](https://github.com/hbgit/Guia-UBS/issues/8) |
| P1-7 | [#9](https://github.com/hbgit/Guia-UBS/issues/9) |
| P1-8 | [#10](https://github.com/hbgit/Guia-UBS/issues/10) |
| P1-9 | [#11](https://github.com/hbgit/Guia-UBS/issues/11) |
| P1-10 | [#12](https://github.com/hbgit/Guia-UBS/issues/12) |
| P1-11 | [#13](https://github.com/hbgit/Guia-UBS/issues/13) |
| P2-1 | [#14](https://github.com/hbgit/Guia-UBS/issues/14) |
| P2-2 | [#15](https://github.com/hbgit/Guia-UBS/issues/15) |
| P2-3 | [#16](https://github.com/hbgit/Guia-UBS/issues/16) |
| P2-4 | [#17](https://github.com/hbgit/Guia-UBS/issues/17) |
| P2-5 | [#18](https://github.com/hbgit/Guia-UBS/issues/18) |
| P2-6 | [#19](https://github.com/hbgit/Guia-UBS/issues/19) |
| P2-7 | [#20](https://github.com/hbgit/Guia-UBS/issues/20) |
| P2-8 | [#21](https://github.com/hbgit/Guia-UBS/issues/21) |
| P2-9 | [#22](https://github.com/hbgit/Guia-UBS/issues/22) |
| P2-10 | [#23](https://github.com/hbgit/Guia-UBS/issues/23) |
| P2-11 | [#24](https://github.com/hbgit/Guia-UBS/issues/24) |
| P2-12 | [#25](https://github.com/hbgit/Guia-UBS/issues/25) |
| P3-1 | [#26](https://github.com/hbgit/Guia-UBS/issues/26) |
| P3-2 | [#27](https://github.com/hbgit/Guia-UBS/issues/27) |
| P3-3 | [#28](https://github.com/hbgit/Guia-UBS/issues/28) |

## Lista de issues proposta (ordem de criação = ordem dos códigos)

Critérios dentro da mesma prioridade: desbloqueia outras → maior risco de retrabalho → menor esforço. Marco **Piloto** = P0 + P1 (inclusive as issues `documentation` com dono fora da equipe). Marco **v1.1** = P2-12.

### P0

1. **P0-1** `bug` `app` — **APK de release não declara `android.permission.INTERNET`; download de pack e de modelo impossível fora de debug.**
   Contexto: `app/android/app/src/main/AndroidManifest.xml` não tem `uses-permission`; só `src/debug` e `src/profile:6` declaram `INTERNET`. Manifest mesclado de release reconstruído em 2026-10-28 (tarefa 2) lista 7 permissões de plugins e nenhum `INTERNET`. Sem pack embarcado, o release instala sem conteúdo (P1-4 reduz o dano, não a causa).
   Escopo: (1) declarar `INTERNET` no manifest principal com comentário citando ADR-003 e as duas únicas chamadas; (2) teste que lê o manifest mesclado de release e exige exatamente a lista permitida de permissões (LGPD-RF01; a lista fechada é mantida por P3-3); (3) verificar sync de pack e provisionamento do modelo em aparelho com APK release.
   Aceite: `grep INTERNET` no manifest mesclado; teste novo (roda localmente até P2-1 o levar ao CI); registro em `spec/arquitetura.md` §5 com aparelho e versão.
   Fora: política UNMETERED (já coberta); backup (P1-3).

2. **P0-2** `bug` `backend` `spec` — **Caso golden sem revisor clínico barra a publicação; os 24 casos do semente ganham revisor identificável.**
   Contexto: `npm run pack:build` avisa "24 caso(s) golden sem revisor clínico nomeado" e assina mesmo assim; a revisão feita uma vez regride em silêncio no próximo caso. Segurança clínica (R5).
   Escopo: (1) no packer, caso sem `reviewed_by` vira issue **bloqueante** em `publish` e em `packer/src/worker.ts`; continua aviso em `build --dry-run` e no CI de PR; (2) mesma regra no `cms:import-golden` e na rota de `golden_case` (recusar `active=1` sem revisor); (3) `reviewed_by` passa a identificar o profissional de forma verificável — nome, conselho e número de registro (CRM/COREN), com formato validado por Zod; (4) revisão dos 24 casos por médico ou enfermeiro da atenção primária ligado à UBS piloto — idealmente **dois**, espelhando o dual review do CMS; reimportar.
   Aceite: teste em `packer/test/` (sem revisor → `publish` bloqueado, `--dry-run` passa com aviso); teste de rota; validação do formato; `pack:check` sem aviso após a revisão.
   Fora: conteúdo clínico dos casos (é trabalho do revisor, nomeado na issue).
   Depende: Secretaria de Saúde indicar o(s) revisor(es) — decisão 5.

### P1

3. **P1-1** `feature` `llm` `spec` — **Servir o GGUF do storage próprio, com os termos do Gemma incorporados aos termos de uso do app e análise da Política de Uso Proibido no ADR.**
   Contexto: `model_catalog.dart:24` fixa `huggingface.co`. Diverge de stack §9, PRD §4.1 e LGPD-RT11/RF17. Servir o modelo é "Distribution" (§1.1(b) dos termos do Gemma); a §3.1 exige que as restrições de uso sejam **cláusula vinculante no acordo que rege o uso** — que aqui são os `termos_{pt,es}.md` do app —, cópia dos termos a todo destinatário e um arquivo "Notice".
   Escopo: (1) **ADR** em stack §10, escrito antes do código, com a leitura da Política de Uso Proibido contra o caso de uso e o argumento arquitetural: o gate determinístico decide a severidade, o SLM só escala (`max(gate, llm)`, nunca rebaixa) e o cartão orienta para onde ir, sem diagnosticar. **Se a leitura for desfavorável, a troca de modelo vira P0** e P2-5 deixa de ser contingência; (2) objeto `models/<nome>-<sha256>.gguf` no MinIO/Caddy (site só GET/HEAD) com o arquivo "Notice" ao lado; (3) `MODEL_URL` por `String.fromEnvironment`, como `PACK_MANIFEST_URL`; (4) **seção nova nos `termos_{pt,es}.md`** incorporando as restrições de uso da §3.2 e a Política de Uso Proibido como cláusula, mais `assets/legal/gemma_terms_{pt,es}.md` com a cópia dos termos — o texto do "Notice" fica **em inglês**, como os termos exigem, com tradução só como cortesia; ambos listados na tela "Sobre" e cobertos por `legal_documents_test.dart`; (5) script/seção em `docs/operacao.md` para publicar o modelo.
   Aceite: ADR aprovado pelo dono; download no aparelho a partir do endpoint próprio com SHA conferido; nenhuma string `huggingface.co` em `app/lib`; `doc-operacao.test.ts` verde; teste de que "Sobre" lista os dois documentos e de que os termos contêm a seção.
   Depende: P0-1 (verificar em release).

4. **P1-2** `test` `ci` `app` — **Allowlist de endpoints fixada em teste e auditoria de tráfego registrada (LGPD-RF01/RT11).**
   Escopo: teste em `app/test/` que varre `lib/` por `http(s)://` e compara com lista fechada; captura em aparelho (tarefa 4, passo 3) registrada em `spec/lgpd.md` como evidência da RF01, incluindo `bmgr backupnow` antes e depois de P1-3.
   Aceite: teste verde; registro com data, aparelho e hosts observados. Depende: P1-1, P1-3.

5. **P1-3** `bug` `app` — **Desligar o backup automático do Android (`allowBackup="false"` + `dataExtractionRules`), e registrar que perder as preferências ao trocar de aparelho é intencional.**
   Contexto: tarefa 2, passo 3 — nenhum atributo no manifest; `targetSdk 36`; `user.db`, pack e GGUF em `files/`, incluído no Auto Backup por padrão. Saída de dados para o Google Drive sem URL no código, fora da allowlist e da LGPD-RT11.
   Escopo: (1) `android:allowBackup="false"` e `android:dataExtractionRules` com `cloud-backup` e `device-transfer` excluindo tudo; (2) o teste de manifest de P0-1 passa a exigir os dois atributos; (3) linha em `spec/lgpd.md` RF01 dizendo que **o usuário perde idioma, tema e fonte ao trocar de aparelho, e que isso é intencional** — para ninguém "consertar" religando o backup.
   Aceite: manifest mesclado com os atributos; `bmgr backupnow` não transfere nada (registrado em P1-2); linha na spec. Depende: P0-1 (mesmo teste).

6. **P1-4** `feature` `app` `backend` `spec` — **Pack de referência embutido no APK, assinado, verificado no boot e substituído pelo sync.**
   Contexto: decisão 6 do dono. O app instala sem conteúdo e depende de rede no primeiro acesso, mesmo para "onde ir", documentos e o gate, que não precisam do modelo. O pack tem 160 KB. Não estava no PRD — entra nele nesta issue.
   Escopo: (1) linha no PRD §2.2 (CAP-10/11) e critério na espec RF-11: pack embutido como asset, **assinado com a chave de produção**, passando pelo mesmo caminho de verificação do boot (INV-3) e com **versão menor que a primeira publicada**, para o sync sempre substituí-lo; (2) `pack_store` instala o embutido quando não há pack ativo; (3) CI confere que o asset é **idêntico** ao pack publicado daquela release (hash) — reaproveita `SOURCE_DATE_EPOCH`; (4) risco de conteúdo envelhecido: mostrar a **data do pack** (`built_at`) em "onde ir" e na tela "Sobre", se ainda não aparece; (5) `pack_signing_keys`/dual-key: o asset é assinado por `k1` ou `k2`.
   Aceite: instalação limpa com rádio desligado navega "onde ir", documentos, fluxo e triagem por regras; teste de que downgrade do embutido sobre um pack ativo é recusado; teste de CI do hash; teste de widget da data.
   Fora: delta (P2-12). Depende: nenhuma; desbloqueia P1-6 e enfraquece o impacto de P0-1.

7. **P1-5** `spike` `llm` — **Bench em aparelho de ENTRADA real (4 GB, Cortex-A53/A55): tempo de carga, latência, total da triagem, pico de RAM, `fallback_rate`.**
   Contexto: só o Edge 40 Neo com proxy `taskset`; tempo de `gubs_llama_open` nunca medido; o total "toque → cartão < 6 s" (RNF-02) só faz sentido no mesmo aparelho e sessão. Decisão 5: perguntar à Secretaria/ACS quais modelos aparecem em campo e **comprar um ou dois** da faixa mais comum de 4 GB.
   Escopo: tarefa 3, passos 1–3 no aparelho comprado; registrar carga, p50/p95, total, RSS; decidir com o dono se o SLM fica ligado por padrão nessa classe (gatilho de revisão do ADR-003).
   Aceite: subseção em `spec/arquitetura.md` §5 com tabela e recomendação; modelo do aparelho registrado em RNF-09. Depende: compra do aparelho; não depende de P0-1.

8. **P1-6** `test` `app` — **Teste de integração em modo avião (critério da RNF-01).**
   Escopo: `integration_test/offline_test.dart` com rádio desligado por `adb`, pack embutido (P1-4) ou de fixture, percurso completo do ator A1; `README` em `integration_test/`. Aceite: verde em aparelho. Depende: P1-4 (preferível) ou fixture.

9. **P1-7** `test` `llm` `app` — **Observar o selo `assistente virtual` em aparelho real (lacuna declarada da RF-15).**
   Escopo: composição em que o SLM escala acima do gate; captura nos dois temas; TalkBack lendo procedência → severidade → título. O Edge 40 Neo serve. Aceite: registro em §5; remoção da frase de lacuna em `spec/espec.md:34`. Depende: nenhuma.

10. **P1-8** `feature` `backend` — **Aceite de termo de uso no primeiro login do CMS (LGPD-RF02/RF04/RT04/RT05).**
    Escopo: `GET/POST /api/consentimento`; middleware que bloqueia tudo exceto auth e consentimento até aceite da versão vigente; tela na SPA; re-aceite por mudança de `doc_hash`. Aceite: teste de rota (403 antes, 200 depois); `consent_record` com hash; `web-conformance`; linha em `docs/operacao.md`.

11. **P1-9** `documentation` — **Nomeação do encarregado (DPO) e canal do titular (LGPD-RF08, art. 41).** *Responsável: prefeitura / Secretaria de Saúde (controladora). A equipe de desenvolvimento só fornece insumos.*
    Contexto: decisões 2 e 7. Sem encarregado não há tabela de retenção (P2-8) nem canal do art. 18. Bloqueia o piloto juridicamente.
    Escopo: (1) ato de nomeação publicado; (2) canal do titular (e-mail/endereço) e fluxo com protocolo e prazo de 15 dias; (3) o canal entra nos `privacidade_{pt,es}.md` do app (hoje usa endereço fictício).
    Aceite: nome e canal em `spec/lgpd.md` "Governança"; documentos legais do app atualizados e `legal_documents_test.dart` verde.

12. **P1-10** `documentation` — **DPA com operadores e inventário de dados (LGPD-RF06, RT11).** *Responsável: prefeitura / encarregado. A equipe fornece o inventário técnico.*
    Escopo: (1) inventário técnico extraído das tabelas de `spec/lgpd.md` e do schema (`PII_COLUMNS`, `user.db`), entregue pela equipe; (2) lista de operadores: VPS do plano de controle, Google (TTS do sistema, Play), origem do modelo (P1-1); (3) DPA arquivado por operador; avaliação de transferência internacional quando houver.
    Aceite: inventário versionado em `spec/lgpd.md`; DPAs referenciados. Depende: P1-9 (quem assina).

13. **P1-11** `test` `app` — **Ensaio de 72 h offline (RNF-07) e crash-free.**
    Escopo: roteiro/monkey em aparelho com rádio desligado, `logcat` sem PII, relatório. Aceite: zero crash em 72 h; registro em §5. Depende: P0-1, P1-6.

### P2

14. **P2-1** `ci` `infra` — **CI constrói o APK de release, confere o manifest mesclado e mede o tamanho (RNF-03 "pipeline de release").** Aceite: job `release` em `app.yml`; o teste de P0-1/P1-3 roda nele; tamanho como artifact, conferido contra 50–80 MB.
15. **P2-2** `ci` — **Auditoria de dependências Flutter e bloqueio de SDKs de ads/tracking (LGPD-RF16).** Aceite: passo de CI com OSV/`pub outdated` e lista negra que reprova.
16. **P2-3** `bug` `backend` — **Tradução sem travamento otimista (`PUT …/traducoes/<lang>` sem `If-Match`/`ETag`).** Aceite: 428/409 como no CRUD; teste em `optimistic-lock.test.ts`; SPA reenvia.
17. **P2-4** `feature` `backend` — **Importador de conteúdo `seed/` → CMS.** Aceite: `npm run cms:import-seed`; release 1 construída só pela interface; linha em `docs/operacao.md`.
18. **P2-5** `spike` `llm` — **Contingência de licença: medir um modelo Apache 2.0 de porte parecido com o Gemma 3 1B.** Decisão 1: o Qwen2.5 0.5B (10/20 válidas) não é alternativa real. Escopo: escolher 1–2 candidatos ~1 B Apache 2.0/MIT com GGUF (ex.: Qwen2.5-1.5B, SmolLM2-1.7B, Llama-3.2-1B tem licença própria — fora), rodar a bancada de §5.1 no Edge 40 Neo e no aparelho de P1-5, registrar latência/RAM/validade. Aceite: subseção em §5 com tabela e veredito. **Sobe para P0 se o ADR de P1-1 for desfavorável.** Depende: nenhuma.
19. **P2-6** `feature` `app` — **Telemetria fora da tela de privacidade enquanto estiver desligada.** Decisão 4: o app não envia nada, e a tela promete um opt-out de algo que não existe. Escopo: ocultar o bloco e a coleta enquanto não houver produtor (flag de compilação), mantendo a coluna do `user.db` justificada em `lgpd_surface_test.dart` ou removendo-a com migração v3 (a decisão fica para a issue); atualizar `privacidade_{pt,es}.md`. Aceite: `privacy_screen_test.dart` e `lgpd_surface_test.dart` verdes e coerentes; tela não menciona telemetria.
20. **P2-7** `spike` `spec` `backend` — **ADR: produtor e agregador de telemetria — pós-piloto.** Decisão 4: no piloto, o North Star é medido à mão com a UBS (registros de atendimento, protocolo curto de observação, entrevistas com usuários e ACS). Entrega: ADR em stack §10 com a opção escolhida e as issues derivadas; roteiro da medição manual em `docs/`. Sem código.
21. **P2-8** `feature` `backend` — **Expurgo por retenção (LGPD-RF07/RT10), com proposta de tabela por classe para aprovação do encarregado.** Decisão 2. Escopo: (1) proposta em `spec/lgpd.md`: trilha de auditoria e `consent_record` **nunca expurgados pelo job** (append-only; prazo de guarda vem do jurídico); contas desativadas, sessões e tentativas de login — prazo curto após desativação/expiração; telemetria — nada a reter enquanto desligada; `user.db` — sob controle do titular pela tela de privacidade, fora do job; (2) job de expurgo logado implementando a tabela aprovada. Aceite: proposta aprovada pelo encarregado; teste de que o job não toca `audit_entry`/`consent_record`. Depende: P1-9.
22. **P2-9** `test` `app` — **Bancada de latência de UI e gate: gate < 50 ms, idioma/tema ≤ 200 ms, cold start < 2,5 s.** Aceite: bench do gate em teste de unidade com `Stopwatch` sobre o pack real; os demais em aparelho, registrados em §5.
23. **P2-10** `test` `app` — **Confirmar "aviso em áudio" na tela de privacidade (CAP-13).** Verificar primeiro; se falta, implementar com o `Speaker`. Aceite: teste em `privacy_screen_test.dart`.
24. **P2-11** `infra` `documentation` — **Ansible + runbooks: incidente (LGPD-RF12), rotação de chave, revogação de pack.** Fase 4 item 21; stack §3.2; R4. O runbook de incidente é **um só** e cobre a RF12 (comunicação à ANPD e aos titulares em prazo regulamentar, responsáveis nomeados, tabletop anual) — não há documento separado na parte documental da LGPD. Aceite: playbook sobe `infra/compose.yaml` num VPS limpo; três runbooks em `docs/`; o de incidente cita a RF12 e o encarregado de P1-9.
25. **P2-12** `feature` `app` `backend` — **Delta packs (bsdiff) — marco v1.1.** Decisão 3: o PRD governa e condiciona delta a pack > 10 MB (hoje 160 KB). A espec RF-10 passa a repetir a condição do PRD (feito em P3-2). Aceite (v1.1): manifest com `delta` opcional, `bsdiff` no packer, aplicação e verificação no app.

### P3

26. **P3-1** `documentation` `spec` — **Completar a auditoria open source de stack §9** com todos os pacotes de `app/pubspec.yaml` e dos quatro `package.json`. Aceite: teste que compara a lista de §9 com os manifests.
27. **P3-2** `tech-debt` `spec` `backend` — **Alinhar stack.md e espec.md ao decidido:** §1.1 `llama_cpp_dart` → shim C (ADR-002); §1.2/§3.3 `hono/client` inviável (§5.13); remover `@hono/zod-openapi` ou justificar; **RF-10 da espec passa a condicionar delta a pack > 10 MB, como o PRD §6.2**. Aceite: ADR-004 curto; `npm ls` sem o pacote; espec e PRD coerentes.
28. **P3-3** `documentation` `app` — **Justificar as 7 permissões herdadas de plugins** em `spec/lgpd.md` RF01 e confirmar ausência de wakelock persistente (RNF-08). Aceite: tabela permissão → plugin → por quê; a lista fechada do teste de P0-1 referencia esta tabela.

## Decisões do dono (2026-10-28)

Respostas às sete perguntas do ponto de decisão, já refletidas na lista acima.

1. **Licença do modelo:** manter o Gemma no piloto, **verificando primeiro a Política de Uso Proibido** contra o caso de uso no ADR de P1-1 (argumento: gate decide, SLM só escala, cartão orienta sem diagnosticar). Leitura desfavorável ⇒ troca de modelo vira P0. Contingência: P2-5 mede um modelo Apache 2.0 de porte parecido; Qwen2.5 0.5B não serve.
2. **Retenção:** o controlador é a prefeitura (Secretaria de Saúde), que nomeia o encarregado (P1-9). P2-8 leva uma proposta por classe de dado para aprovação.
3. **Delta packs:** v1.1. O PRD governa; a espec RF-10 passa a repetir a condição (P3-2); P2-12 vai para o marco v1.1.
4. **Telemetria:** desligada no piloto; North Star medido à mão com a UBS. P2-7 vira ADR pós-piloto; P2-6 tira a telemetria da tela de privacidade enquanto estiver desligada.
5. **Aparelho e revisor:** comprar um ou dois aparelhos de 4 GB (A53/A55) da faixa mais comum em campo (P1-5); revisor clínico com registro profissional ligado à UBS piloto, idealmente dois, com `reviewed_by` verificável (P0-2).
6. **Pack embutido no APK:** sim, P1-4 no marco Piloto, registrado no PRD, com assinatura de produção, versão menor que a primeira publicada, CI conferindo identidade com o pack publicado, e data do pack visível.
7. **LGPD documental:** issues `documentation` no marco Piloto com responsável fora da equipe (P1-9, P1-10); o runbook de incidente fica em P2-11.

## Labels e marcos (precisam de aprovação final)

Reaproveitar `bug` e `documentation`; criar os 14 da tarefa 6, passo 2. Marco **Piloto** = P0-1, P0-2, P1-1…P1-11. Marco **v1.1** = P2-12.
