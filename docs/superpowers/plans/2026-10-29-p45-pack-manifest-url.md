# #45 — `PACK_MANIFEST_URL` sem host padrão — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** um APK construído sem `PACK_MANIFEST_URL` deixa de buscar conteúdo em `127.0.0.1` do próprio aparelho. Sem a URL, ou com uma URL insegura num release, o sync se declara "não configurado", não faz requisição, não conta falha e não agenda job; quem prepara o aparelho vê isso na tela "Sobre"; e o build de release recusa a configuração errada antes de compilar.

**Architecture:** um helper comum, `lib/sync/endpoint_config.dart`, decide o que é uma origem utilizável em runtime (absoluta, com host, e `https` fora do debug) e quais hosts são locais ou reservados. O `SyncService` e o `ModelArtifact` usam a mesma regra. O estado de retentativa grava a origem a que se refere e é zerado quando ela muda. O guarda de build (`tool/model_url_check.dart`) confere as duas URLs com as regras mais estritas (lista de hosts proibidos e mesmo host), e o `build_apk.sh` é testado de verdade, com um `flutter` substituível.

**Tech Stack:** Flutter/Dart 3, `flutter_test`, Bash.

**Spec:** issue #45; `spec/lgpd.md` LGPD-RF17(c) (TLS com validação de certificado); `spec/espec.md` FSM-B (a matriz não muda: "não configurado" não é estado da máquina, é ausência de origem); `CLAUDE.md` ("Offline-only em runtime", "Freio de sync é estado em disco", "Adiar a troca não é falha"); padrão do `MODEL_URL` em `spec/stack.md` ADR-004.

## Global Constraints

- `grep -rn "127.0.0.1" app/lib` vazio (critério da issue).
- Sem origem utilizável: zero requisição, **nenhuma** falha registrada no estado de retentativa e nenhum job periódico do pack registrado.
- Em release **e profile**, URL que não seja `https` conta como não configurada, para o manifest e para o modelo (LGPD-RF17(c) garantida no app, não só no script).
- `tool/build_apk.sh release` sem `PACK_MANIFEST_URL`, com `http://`, com host local/reservado ou com hosts diferentes sai com erro **antes** de chamar `flutter build`.
- Nenhum host real nos testes: hosts de exemplo claramente fictícios, com comentário dizendo que o teste não faz rede e que o domínio real vem da #55.
- A matriz da FSM-B (`spec/espec.md`) não muda.
- Fora do escopo: allowlist em CI (#4); domínio e servidor (#55); a contagem de disputa de escritor como falha (#35).
- Commits sem atribuição de IA. Branch `fix/45-pack-manifest-url`.

## Decisões deste plano

| # | Decisão | Por quê |
|---|---|---|
| D1 | O guarda de build continua em `model_url_check.dart` (nome mantido) e confere as duas chaves do mesmo `defines.<modo>.json` | Renomear quebraria `build_apk.sh`, `CLAUDE.md` e `docs/operacao.md` por nada |
| D2 | **Runtime:** `isUsableEndpoint(uri)` exige URL absoluta, com host, e `https` sempre que `!kDebugMode` (release e profile). Só o debug aceita `http`, para o emulador falar com `http://10.0.2.2:8081` | Um `flutter build apk --release` direto não passa pelo script. A regra no app fecha a RF17(c) para qualquer build |
| D3 | **Build:** no release, recusa hosts locais e reservados: `localhost`; `127.0.0.0/8`; `::1`; `0.0.0.0`; `10.0.0.0/8`; `172.16.0.0/12`; `192.168.0.0/16`; `169.254.0.0/16`; TLDs `.local`, `.localhost`, `.test`, `.invalid`, `.example`; e os nomes `example.com`, `example.org` e `example.net`. A lista mora em `endpoint_config.dart` (`isLocalOrReservedHost`), e o guarda a importa | Copiar o `defines.example.json` para o release, ou apontar para o servidor da LAN, produziria um APK "configurado" que não baixa nada |
| D4 | **Build:** no release, `MODEL_URL` e `PACK_MANIFEST_URL` têm o **mesmo host**, os dois do mesmo edge. **Exceção:** quando `MODEL_URL` é exatamente a `huggingFaceExceptionUrl` do ADR-004, a regra não se aplica; quando a #55 remover a exceção, ela passa a valer inteira | Pega configurações misturadas que nenhuma lista pegaria. Sem a exceção, a regra barraria todo release enquanto o modelo vier do Hugging Face |
| D5 | O estado de retentativa grava a **origem** (`scheme://host:port/caminho` do manifest) a que se refere. Se a origem configurada for outra, o ciclo zera a retentativa **e o ETag** antes de seguir | Falhas e ETag são de uma origem. Um aparelho que acumulou falhas contra `127.0.0.1` não pode esperar o circuito fechar para receber o primeiro conteúdo da origem real |
| D6 | "Não configurado" **não** é um estado da FSM-B: o `SyncReport` ganha `bool configured` (padrão `true`), e o ciclo devolve `configured: false` | Mexer na matriz normativa por uma ausência de configuração seria desproporcional. O relatório distingue os dois casos para teste e log |
| D7 | A tela "Sobre" ganha uma linha de **diagnóstico do build**, que só aparece quando falta origem: "Este aparelho não tem origem de conteúdo configurada" e/ou "… do assistente". O dado vem das constantes de build, não do sync | Quem prepara aparelhos para o piloto percebe o build errado antes de entregar. Sync continua invisível no uso (INV-8): a linha descreve o APK, não um estado de rede |
| D8 | Sem origem utilizável, o `main` **cancela** o job periódico do pack em vez de registrá-lo. O cancelamento cobre o job herdado de builds anteriores, que apontavam para `127.0.0.1` | Hoje o job acordaria o aparelho só para não fazer nada |
| D9 | `defines.example.json` ganha `PACK_MANIFEST_URL` com `https://conteudo.exemplo.invalid/content-packs/0000000/manifest.json` | Não há domínio (#55). O exemplo documenta a forma, e D3 impede que ele vá para um release |

## Review Focus

1. **App com pack ativo atualizado para um build sem `PACK_MANIFEST_URL`.** Esperado: o pack ativo continua servindo. Teste na Task 2.
2. **Circuito aberto por falhas contra a origem A, e o build passa a apontar para B.** Esperado: B sincroniza no primeiro ciclo. Teste na Task 2.
3. **Circuito aberto e build sem URL.** Esperado: o estado gravado fica idêntico (nem piora nem é zerado: a origem antiga pode voltar). Teste na Task 2.
4. **Release com `http://` gerado sem o script.** Esperado: o app trata como não configurado, sem socket. Teste na Task 1.

---

### Task 0: medir se o `dart:io` respeita o cleartext do Android (antes de qualquer código)

Responde à pergunta, sem mudar o desenho: D2 vale de qualquer forma.

- [ ] **Step 1:** subir o edge de dev (`docker compose up -d storage edge` com o `.env` de dev; ver `docs/operacao.md` §2) e publicar um `manifest.json` qualquer em `content-packs/0000000/`. Conferir `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8081/content-packs/0000000/manifest.json` → 200.
- [ ] **Step 2:** APK **release** do `develop` atual (antes desta issue), com `--dart-define=PACK_MANIFEST_URL=http://10.0.2.2:8081/content-packs/0000000/manifest.json`, instalado no emulador `sinalacs_ci36`; `logcat -c`; abrir o app até a inicial.
- [ ] **Step 3: Evidência:** `docker compose logs edge` mostra ou não um `GET /content-packs/0000000/manifest.json` vindo do emulador, e o `logcat` mostra ou não `Insecure HTTP is not allowed by platform` / `CLEARTEXT`. Registrar o resultado (as duas linhas) para a subseção do §5 da Task 4.

### Task 1: `endpoint_config.dart` — uma regra de origem para o app e para o build

**Files:**
- Create: `app/lib/sync/endpoint_config.dart`
- Modify: `app/lib/sync/model_downloader.dart` (`ModelArtifact.isConfigured` passa a delegar)
- Test: `app/test/sync/endpoint_config_test.dart` (novo), `app/test/sync/model_downloader_test.dart`

**Interfaces:**
- Produces:
  - `bool isUsableEndpoint(Uri url, {bool requireHttps = !kDebugMode})`: absoluta, `http`/`https`, host não vazio; com `requireHttps`, só `https`.
  - `bool isLocalOrReservedHost(String host)`: lista D3 (IPv4 por faixa, IPv6 `::1`, nomes e TLDs, sem diferenciar maiúsculas).
  - `ModelArtifact.isConfigured => isUsableEndpoint(uri)`.

- [ ] **Step 1: Testes que falham** (`endpoint_config_test.dart`):
  - `isUsableEndpoint`: `''`, `'models/x.gguf'` e `'ftp://h/x'` → falso; `'http://10.0.2.2:8081/x'` → verdadeiro com `requireHttps: false` e **falso** com `requireHttps: true`; `'https://h.example.invalid/x'` → verdadeiro com `requireHttps: true` (a lista D3 é do guarda, não do runtime).
  - `isLocalOrReservedHost`, um `expect` por caso: verdadeiro para `localhost`, `127.0.0.1`, `127.8.9.1`, `::1`, `[::1]`, `0.0.0.0`, `10.0.2.2`, `172.16.0.1`, `172.31.255.255`, `192.168.1.10`, `169.254.1.1`, `srv.local`, `a.localhost`, `x.test`, `x.invalid`, `x.example`, `example.com`, `EXAMPLE.ORG`; falso para `172.15.0.1`, `172.32.0.1`, `11.0.0.1`, `huggingface.co` e `edge.dominio-do-projeto-a-definir.org`. O último leva o comentário: *"fictício; o teste não faz rede. Trocar pelo domínio real quando a #55 decidir."*
  - `model_downloader_test.dart`: `'em release, MODEL_URL http conta como nao configurada'` → `isUsableEndpoint(Uri.parse('http://h/x.gguf'), requireHttps: true)` é falso.
- [ ] **Step 2:** `cd app && flutter test test/sync/endpoint_config_test.dart test/sync/model_downloader_test.dart` → FAIL.
- [ ] **Step 3:** implementar. `ModelArtifact.isConfigured` perde a lógica própria e delega ao helper.
- [ ] **Step 4:** `flutter test test/sync/ && flutter analyze --fatal-infos` → PASS.
- [ ] **Step 5: Sabotagem.** Padrão de `requireHttps` igual a `false` → o caso de release reprova. Tirar `172.16.0.0/12` → `172.31.255.255` reprova. Reverter.
- [ ] **Step 6: Commit** `feat(sync): regra unica de origem utilizavel, https fora do debug (#45)`.

### Task 2: sem origem, o sync não toca a rede; a retentativa é por origem

**Files:**
- Modify: `app/lib/sync/pack_background_sync.dart` (sem `defaultValue`; comentário como o de `model_catalog.dart`)
- Modify: `app/lib/sync/sync_service.dart` (`runCycle`, `SyncReport.configured`)
- Modify: `app/lib/sync/pack_store.dart` (`readRetryOrigin` / gravação junto com o retry; `clearForOrigin`)
- Test: `app/test/sync/sync_service_test.dart`, `app/test/sync/pack_manifest_url_test.dart` (novo)

**Interfaces:**
- Consumes: `isUsableEndpoint` (Task 1).
- Produces:
  - `SyncReport.configured` (padrão `true`).
  - `SyncService.manifestConfigured => isUsableEndpoint(manifestUrl)`. Com `false`, `runCycle()` devolve `SyncReport(state: SyncState.p0Steady, rules: const [], detail: 'PACK_MANIFEST_URL ausente ou insegura neste build', configured: false)` **antes** de qualquer leitura ou escrita do `state.json`.
  - Com origem utilizável: `runCycle()` compara `store.readRetryOrigin()` com `syncOrigin(manifestUrl)` (`scheme://host:port/caminho`, sem query). Se a gravada não for nula e for diferente, chama `store.resetForOrigin(nova)`, que remove `retry` e `etag` e grava a origem nova; se for nula, só grava a origem. Depois segue o ciclo como hoje.

- [ ] **Step 1: Testes que falham**
  - `pack_manifest_url_test.dart`: `'o app nao carrega host padrao para o manifest'` → a fonte de `pack_background_sync.dart` não contém `127.0.0.1` nem `http`; `packManifestUrl` está vazio em `flutter test`.
  - `sync_service_test.dart`, grupo `'origem nao configurada (#45)'`:
    - `'sem URL: nao faz requisicao, nao registra falha e diz por que'` → `Uri.parse('')`; `report.configured` falso e `detail` com `PACK_MANIFEST_URL`; o `_Origin` do teste com zero requisições; `state.json` byte a byte igual ao de antes.
    - `'pack ativo continua ativo'` → instalar v1 com o serviço configurado; dois ciclos sem URL; o pack e o manifest ativos não mudam.
    - `'circuito aberto e build sem URL: estado intacto'` → gravar um retry com circuito aberto; um ciclo sem URL; `state.json` idêntico.
    - `'URL relativa conta como nao configurada'`.
  - Grupo `'retentativa por origem (#45)'`:
    - `'circuito aberto para a origem A nao atrasa a origem B'` → gravar retry com circuito aberto e origem `http://127.0.0.1:9000/content-packs/0000000/manifest.json`; serviço apontado para o `_Origin` do teste; um ciclo instala a v1 (`committed`); o retry gravado volta a zero com a origem nova.
    - `'ETag de outra origem nao e reaproveitado'` → gravar `etag: 'v1'` com a origem A; a origem B responderia 304 a esse ETag; o ciclo pede sem `If-None-Match` e instala.
    - `'mesma origem preserva o circuito'` → circuito aberto com a origem do `_Origin`; o ciclo respeita o circuito (zero requisições).
- [ ] **Step 2:** `flutter test test/sync/` → FAIL.
- [ ] **Step 3:** implementar as Interfaces; `packManifestUrl = String.fromEnvironment('PACK_MANIFEST_URL')`.
- [ ] **Step 4:** `flutter test test/sync/ && flutter analyze --fatal-infos && grep -rn "127.0.0.1" lib; echo "grep exit=$?"` → PASS, `grep exit=1`.
- [ ] **Step 5: Sabotagem.** Recolocar o `defaultValue` → reprova `pack_manifest_url_test`. Mover a checagem para depois de `readRetryState`/`_registerFailure` → reprova `'nao registra falha'`. Desligar o `resetForOrigin` → reprova `'origem A nao atrasa a origem B'`. Zerar também quando a origem é a mesma → reprova `'mesma origem preserva o circuito'`. Reverter.
- [ ] **Step 6: Commit** `fix(sync): PACK_MANIFEST_URL sem host padrao; retentativa e ETag por origem (#45)`.

### Task 3: sem job inútil, e o diagnóstico na tela "Sobre"

**Files:**
- Modify: `app/lib/main.dart` (agendamento), `app/lib/sync/pack_background_sync.dart` (`cancelPackSync`), `app/lib/ui/more/about_screen.dart`, `app/lib/l10n/app_{pt,es}.arb`
- Test: `app/test/sync/pack_sync_scheduler_test.dart` (ou novo `pack_schedule_decision_test.dart`), `app/test/ui/more/about_screen_test.dart`

**Interfaces:**
- Produces:
  - `bool shouldSchedulePackSync(Uri manifestUrl) => isUsableEndpoint(manifestUrl)`.
  - `Future<void> cancelPackSync()`: `Workmanager().cancelByUniqueName(packSyncTaskName)`.
  - No `main`: `shouldSchedulePackSync(...) ? schedulePackSync() : cancelPackSync()`.
  - `typedef BuildOrigins = ({bool content, bool assistant})` e `final buildOriginsProvider = Provider<BuildOrigins>(...)`, lido de `isUsableEndpoint(Uri.parse(packManifestUrl))` e `activeModel.isConfigured`; sobreposto nos testes.
  - "Sobre": um bloco `ValueKey('about-build-diagnostics')`, só quando algum é falso, com ícone `Icons.build_circle_outlined` (azul, de informação) e as linhas ARB `aboutNoContentOrigin` ("Este aparelho não tem origem de conteúdo configurada.") e `aboutNoAssistantOrigin` ("Este aparelho não tem origem do assistente configurada."), com as versões em es.
- [ ] **Step 1: Testes que falham**
  - `shouldSchedulePackSync`: vazio → falso; `https://edge.dominio-do-projeto-a-definir.org/…/manifest.json` → verdadeiro (com o mesmo comentário de host fictício).
  - `about_screen_test`: `'sem origem de conteudo: o Sobre avisa'` (override `(content: false, assistant: true)` → bloco e só a linha de conteúdo); `'com as duas origens: nada aparece'` (`(true, true)` → `findsNothing`); `'em espanhol'`.
- [ ] **Step 2:** FAIL. **Step 3:** implementar. As chaves novas não citam Gemma nem Google; o `no_endorsement_test` continua verde sem exceção nova.
- [ ] **Step 4:** `flutter test && flutter analyze --fatal-infos` → PASS.
- [ ] **Step 5: Sabotagem.** Mostrar o bloco sempre → reprova `'com as duas origens'`. `shouldSchedulePackSync` sempre verdadeiro → reprova. Reverter.
- [ ] **Step 6: Verificar em aparelho** (a Task 4 cobre).
- [ ] **Step 7: Commit** `feat(app): sem origem de conteudo, nenhum job do pack e aviso no Sobre (#45)`.

### Task 4: o guarda de build confere as duas URLs, e o `build_apk.sh` é testado de verdade

**Files:**
- Modify: `app/tool/model_url_check.dart`, `app/tool/build_apk.sh` (`FLUTTER="${FLUTTER:-flutter}"`; cabeçalho), `app/config/defines.example.json`
- Modify: `CLAUDE.md` (linha do `build_apk.sh`), `docs/operacao.md` §2.10 (o mesmo `defines` leva as duas URLs)
- Test: `app/test/tool/model_url_check_test.dart`, `app/test/tool/build_apk_test.dart` (novo)

**Interfaces:**
- Consumes: `isUsableEndpoint`, `isLocalOrReservedHost` (Task 1); `huggingFaceExceptionUrl` (já no arquivo).
- Produces:
  - `String? packManifestUrlProblem(String? url, {required bool release})`: ausente → mensagem com `PACK_MANIFEST_URL`; não absoluta → `absoluta`; release sem `https` → `https`; release com host D3 → `local ou reservado`; caminho que não termina em `/manifest.json` → `manifest.json`.
  - `modelUrlProblem` ganha a regra D3 no release (antes da checagem do sufixo do SHA).
  - `String? sameHostProblem(String modelUrl, String manifestUrl, {required bool release})`: só no release; `null` quando `modelUrl == huggingFaceExceptionUrl` (D4); senão, hosts diferentes → mensagem com os dois hosts.
  - `main`: lê as duas chaves, junta todos os problemas, imprime `ok` por chave ou `FALHOU` com cada mensagem, e sai 1 se houver algum.

- [ ] **Step 1: Testes que falham**
  - `model_url_check_test.dart`, grupo `'PACK_MANIFEST_URL (#45)'`: ausente; relativa; `http` no release; `https://conteudo.exemplo.invalid/content-packs/0000000/manifest.json` no release → `local ou reservado`; `http://192.168.0.10:8081/content-packs/0000000/manifest.json` → passa fora do release e reprova no release; `https://edge.dominio-do-projeto-a-definir.org/content-packs/0000000/manifest.json` → passa (com o comentário de host fictício); caminho sem `manifest.json` → reprova.
  - Modelo: `https://conteudo.exemplo.invalid/content-packs/models/gemma-3-1b-it-Q4_K_M-$sha.gguf` no release → `local ou reservado` (antes passava).
  - Mesmo host: modelo em `edge.dominio-do-projeto-a-definir.org` e manifest em `outro.dominio-do-projeto-a-definir.org` no release → reprova citando os dois; mesmo host → passa; `huggingFaceExceptionUrl` com o manifest em qualquer host válido → passa (D4); fora do release → nunca reprova por host.
  - `build_apk_test.dart` (roda `bash tool/build_apk.sh` com `FLUTTER` apontando para um script falso que grava um marcador com os argumentos):
    - `'release com o defines de exemplo sai com erro antes do flutter build'` → `tool/build_apk.sh release config/defines.example.json`: saída ≠ 0, stderr cita `PACK_MANIFEST_URL`, e o marcador **não** existe.
    - `'release valido chama flutter build com o define'` → um `defines` temporário com `huggingFaceExceptionUrl` e o manifest no host fictício: saída 0 e o marcador contém `build apk --release` e `--dart-define-from-file=`.
- [ ] **Step 2:** `flutter test test/tool/` → FAIL.
- [ ] **Step 3:** implementar. `defines.example.json` com as duas chaves (D9).
- [ ] **Step 4:** `flutter test test/tool/ && flutter analyze --fatal-infos`; à mão: `tool/build_apk.sh release config/defines.example.json` sai 1 sem compilar.
- [ ] **Step 5: Sabotagem.** Remover D3 → reprova `local ou reservado`. Remover a exceção D4 → reprova o caso do Hugging Face. Ignorar a chave do manifest no `main` → reprova o `build_apk_test` do exemplo. Chamar `$FLUTTER` antes do guarda → o marcador aparece e o teste reprova. Reverter.
- [ ] **Step 6: Commit** `feat(build): o guarda confere PACK_MANIFEST_URL, hosts reservados e mesmo host (#45)`.

### Task 5: verificação em emulador e registro

**Notas de instalação (como na #1 e na #3):** o release é `arm64-v8a` e o AVD `sinalacs_ci36` é x86_64. Ele roda sob `libndk_translation` (visto no §5.16 e no §5.18). Debug e release assinam com o mesmo `debug.keystore`; conferir com `apksigner verify --print-certs` nos dois antes de um `install -r`. Com chave diferente, a instalação falha com `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, e desinstalar apagaria o pack que o passo quer preservar.

- [ ] **Step 1:** edge de dev no ar (Task 0, Step 1) e pack publicado (`npm run pack:publish` com `SOURCE_DATE_EPOCH`; precisa de pack assinado. Se o portão da #2 bloquear a assinatura, usar o pack de fixture `app/test/fixtures/sync/` publicado à mão no MinIO e registrar isso).
- [ ] **Step 2:** APK **debug** com `config/defines.debug.json` (`PACK_MANIFEST_URL=http://10.0.2.2:8081/content-packs/0000000/manifest.json`), instalação limpa: o conteúdo chega ("Onde ir" deixa de mostrar "Conteúdo ainda não disponível"), e o "Sobre" não mostra o diagnóstico de conteúdo.
- [ ] **Step 3:** APK **release sem defines** (build cru), mesma chave, instalado com `install -r`: o pack ativo continua servindo; o logcat não mostra conexão para `127.0.0.1`; `dumpsys jobscheduler` não lista o job do pack; o "Sobre" mostra as duas linhas de diagnóstico.
- [ ] **Step 4:** APK **release com `PACK_MANIFEST_URL=http://10.0.2.2:8081/…`** (build cru, sem o script): o "Sobre" mostra o diagnóstico de conteúdo e o edge **não** recebe requisição (D2 no aparelho).
- [ ] **Step 5:** registrar em `spec/arquitetura.md` §5 (próxima subseção): AVD, API, build, data, o resultado da Task 0 (cleartext), os Steps 2 a 4, e as sabotagens. Fechar o TODO de `log.md:184`.
- [ ] **Step 6:** `cd app && flutter test && flutter analyze --fatal-infos`; `npm test` → verdes. **Commit** `docs(arquitetura): PACK_MANIFEST_URL verificado em emulador (#45)`.

## Rastreabilidade

| Critério da #45 / pedido | Onde |
|---|---|
| `grep -rn "127.0.0.1" app/lib` vazio | Task 2 Steps 1, 4, 5 |
| `build_apk.sh release` sem a URL ou com `http` falha antes de compilar | Task 4 (`build_apk_test`) |
| Sem o define, `SyncService` não faz requisição e não registra falha | Task 2 Step 1 |
| Escopo 3: dev e testes passam o valor por `defines.<modo>.json` | Task 4 Step 3, Task 5 Step 2 |
| Revisão 1: `https` em runtime fora do debug, e a medição do cleartext | D2, Task 0, Task 1, Task 5 Step 4 |
| Revisão 2: retentativa por origem | D5, Task 2 |
| Revisão 3: "não configurado" distinguível e visível | D6, D7, Tasks 2 e 3 |
| Revisão 4: lista completa e mesmo host | D3, D4, Task 4 |
| Revisão 5: nenhum host real nos testes | Global Constraints, Tasks 1, 3 e 4 |
| Revisão 6: `build_apk.sh` testado de verdade | Task 4 (`FLUTTER` substituível) |
| Revisão 7: todos os consumidores da URL | `packSyncProvider` e `runPackSyncTask` passam pelo `runCycle` (Task 2); o agendamento, pela D8 (Task 3) |
| Revisão 8: uma regra só | D2, Task 1 |
| Revisão 9: chave e ABI na Task 5 | Notas da Task 5 |
