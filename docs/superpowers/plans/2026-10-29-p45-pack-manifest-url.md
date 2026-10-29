# #45 — `PACK_MANIFEST_URL` sem host padrão — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** um APK construído sem `PACK_MANIFEST_URL` deixa de buscar conteúdo em `127.0.0.1` do próprio aparelho: sem o define, o sync se declara "não configurado", não faz requisição nem conta falha, e o build de release recusa a ausência antes de compilar.

**Architecture:** mesmo mecanismo do `MODEL_URL` da #3 (PR #49): `String.fromEnvironment` sem `defaultValue`; o `SyncService` reconhece a URL não configurada no início do `runCycle` e devolve um relatório sem tocar rede nem o `SyncRetryState`; o guarda de build (`app/tool/model_url_check.dart`) passa a conferir as duas URLs a partir do mesmo `config/defines.<modo>.json`.

**Tech Stack:** Flutter/Dart 3, `flutter_test`.

**Spec:** issue #45; `spec/lgpd.md` LGPD-RF17(c) (TLS com validação de certificado); `CLAUDE.md` ("Offline-only em runtime", "falha nunca bloqueia"); padrão do `MODEL_URL` em `spec/stack.md` ADR-004.

## Global Constraints

- `grep -rn "127.0.0.1" app/lib` vazio (critério da issue).
- Sem `PACK_MANIFEST_URL`: zero requisição e **nenhuma** falha registrada no `SyncRetryState` (senão o circuito abriria por causa de configuração, e o defeito da #35 se repetiria em outra forma).
- `tool/build_apk.sh release` sem `PACK_MANIFEST_URL`, ou com `http://`, falha antes de compilar.
- Nenhum host em `app/lib`, nem como padrão. Fora do escopo: allowlist em CI (#4); domínio e servidor (#55).
- Commits sem atribuição de IA. Branch `fix/45-pack-manifest-url`.

## Decisões deste plano

| # | Decisão | Por quê |
|---|---|---|
| D1 | O guarda fica em `model_url_check.dart` (nome mantido), com uma função nova `packManifestUrlProblem`, e o `main` confere as duas chaves | Um passo de build, um arquivo de config; renomear quebraria `build_apk.sh`, `CLAUDE.md` e `docs/operacao.md` por nada |
| D2 | No release, os dois guardas recusam host de exemplo ou local: `*.invalid`, `*.example`, `localhost`, `127.0.0.1`, `10.0.2.2` | Copiar `defines.example.json` para o release produziria um APK "configurado" que não baixa nada; é o mesmo sintoma da #45 com outro nome |
| D3 | `defines.example.json` ganha `PACK_MANIFEST_URL` com `https://conteudo.exemplo.invalid/content-packs/0000000/manifest.json` | Não há domínio (#55). O exemplo documenta a forma; D2 impede que ele vá para um release |
| D4 | Fora do release, `http` é aceito (o emulador fala com `http://10.0.2.2:8081`, o edge de dev) | Mesma regra do `MODEL_URL` |

## Review Focus

1. **App que já tem pack ativo, atualizado para um build sem `PACK_MANIFEST_URL`.** Esperado: o pack ativo continua servindo (o sync só não busca novidades). Teste na Task 1.
2. **Circuito já aberto por falhas anteriores ao `127.0.0.1`.** Esperado: o "não configurado" não mexe no estado gravado, nem para piorar nem para zerar. Teste na Task 1.
3. **`PACK_MANIFEST_URL` relativa ou só com caminho.** Esperado: tratada como não configurada no app; recusada pelo guarda. Teste na Task 1.

---

### Task 1: sem `PACK_MANIFEST_URL`, o sync não toca a rede nem conta falha

**Files:**
- Modify: `app/lib/sync/pack_background_sync.dart:26-31` (sem `defaultValue`; comentário como o de `model_catalog.dart`)
- Modify: `app/lib/sync/sync_service.dart` (`runCycle`)
- Test: `app/test/sync/sync_service_test.dart`, `app/test/sync/pack_manifest_url_test.dart` (novo)

**Interfaces:**
- Produces: `bool isConfiguredHttpUrl(Uri url)` em `sync_service.dart` (absoluta, `http`/`https`, host não vazio); `SyncService.manifestConfigured` (getter). Com `false`, `runCycle()` devolve `SyncReport(state: SyncState.p0Steady, rules: [], detail: 'PACK_MANIFEST_URL ausente ou invalida neste build')` antes de `store.readRetryState()`.

- [ ] **Step 1: Testes que falham**
  - `pack_manifest_url_test.dart`: `'o app nao carrega host padrao para o manifest'` → fonte de `pack_background_sync.dart` sem `127.0.0.1` e sem `http`; `packManifestUrl` vazio em `flutter test`.
  - `sync_service_test.dart`, grupo `'build sem PACK_MANIFEST_URL (#45)'`:
    - `'nao faz requisicao e nao registra falha'` → `SyncService(manifestUrl: Uri.parse(''), …)`; `runCycle()` → `detail` contém `PACK_MANIFEST_URL`; o `_Origin` do teste registra zero requisições; `store.readRetryState()` igual a antes (`failures == 0`).
    - `'pack ativo continua ativo'` → instalar v1 com um serviço configurado; depois um serviço sem URL roda dois ciclos; o pack ativo e o manifest commitado continuam os mesmos.
    - `'nao mexe num circuito ja aberto'` → gravar um `SyncRetryState` com falhas e circuito aberto; ciclo sem URL; o estado gravado é idêntico.
    - `'URL relativa conta como nao configurada'` → `Uri.parse('content-packs/0000000/manifest.json')`.
- [ ] **Step 2:** `cd app && flutter test test/sync/sync_service_test.dart test/sync/pack_manifest_url_test.dart` → FAIL.
- [ ] **Step 3:** implementar as Interfaces; `packManifestUrl = String.fromEnvironment('PACK_MANIFEST_URL')`.
- [ ] **Step 4:** `flutter test test/sync/ && flutter analyze --fatal-infos && grep -rn "127.0.0.1" lib; echo "grep exit=$?"` → PASS, `grep exit=1`.
- [ ] **Step 5: Sabotagem.** Recolocar o `defaultValue` → reprova `pack_manifest_url_test`. Mover a checagem para depois de `readRetryState`/`_registerFailure` (contar como falha) → reprova `'nao registra falha'`. Reverter.
- [ ] **Step 6: Commit** `fix(sync): PACK_MANIFEST_URL sem host padrao; sem ele o sync nao toca a rede (#45)`.

### Task 2: o guarda de build confere `PACK_MANIFEST_URL`

**Files:**
- Modify: `app/tool/model_url_check.dart`, `app/tool/build_apk.sh` (só o comentário do cabeçalho), `app/config/defines.example.json`
- Modify: `CLAUDE.md` (linha do `build_apk.sh`), `docs/operacao.md` §2.10 (o mesmo `defines` leva as duas URLs)
- Test: `app/test/tool/model_url_check_test.dart`

**Interfaces:**
- Produces: `String? packManifestUrlProblem(String? url, {required bool release})` — ausente → mensagem com `PACK_MANIFEST_URL`; não absoluta → `absoluta`; `release` e não `https` → `https`; `release` e host local/de exemplo (D2) → `exemplo ou local`; caminho que não termina em `/manifest.json` → `manifest.json`. `modelUrlProblem` ganha a regra D2 no release.

- [ ] **Step 1: Testes que falham** (grupo `'PACK_MANIFEST_URL (#45)'`): ausente; relativa; `http` no release; `https://conteudo.exemplo.invalid/…` no release reprova com `exemplo ou local`; `http://10.0.2.2:8081/content-packs/0000000/manifest.json` passa fora do release e reprova no release; `https://conteudo.prism.dev/content-packs/0000000/manifest.json` passa; caminho sem `manifest.json` reprova. E para o modelo: `modelUrlProblem('https://conteudo.exemplo.invalid/content-packs/models/gemma-3-1b-it-Q4_K_M-$sha.gguf', release: true, …)` reprova com `exemplo ou local` (antes passava).
- [ ] **Step 2:** `flutter test test/tool/` → FAIL.
- [ ] **Step 3:** implementar; o `main` lê as duas chaves do JSON, imprime `ok` para cada uma ou `FALHOU` com todas as mensagens, e sai 1 se alguma falhar. `defines.example.json` com as duas chaves (D3).
- [ ] **Step 4:** `flutter test test/tool/ && flutter analyze --fatal-infos`; `dart run tool/model_url_check.dart --config config/defines.example.json --mode release` → sai 1 citando `PACK_MANIFEST_URL` e `exemplo ou local`; `--mode debug` → sai 0.
- [ ] **Step 5: Sabotagem.** Remover a regra D2 → reprova o teste `exemplo ou local`. Ignorar a chave no `main` → o comando do Step 4 sai 0 no release. Reverter.
- [ ] **Step 6: Commit** `feat(build): o guarda de build confere PACK_MANIFEST_URL e recusa host de exemplo (#45)`.

### Task 3: verificação em emulador e registro

- [ ] **Step 1:** subir o edge de dev (`infra/`), publicar o pack local (`npm run pack:publish`, com `SOURCE_DATE_EPOCH`) e conferir `curl http://127.0.0.1:8081/content-packs/0000000/manifest.json` → 200.
- [ ] **Step 2:** APK **debug** com `config/defines.debug.json` contendo `PACK_MANIFEST_URL=http://10.0.2.2:8081/content-packs/0000000/manifest.json`; instalação limpa; o conteúdo chega (a inicial deixa de mostrar "Conteúdo ainda não disponível" em "Onde ir").
- [ ] **Step 3:** APK release **sem** os defines (build cru), instalado por cima com a mesma chave: o pack ativo continua servindo; nenhum `SocketException` para `127.0.0.1` no logcat.
- [ ] **Step 4:** registrar em `spec/arquitetura.md` §5 (próxima subseção: AVD, API, build, data, o que foi visto) e fechar o TODO de `log.md:184`.
- [ ] **Step 5:** `cd app && flutter test && flutter analyze --fatal-infos`; `npm test` → verdes. **Commit** `docs(arquitetura): PACK_MANIFEST_URL verificado em emulador (#45)`.

## Rastreabilidade

| Critério da #45 | Onde |
|---|---|
| `grep -rn "127.0.0.1" app/lib` vazio | Task 1 Steps 1, 4, 5 |
| `build_apk.sh release` sem a URL ou com `http` falha antes de compilar | Task 2 |
| Sem o define, `SyncService` não faz requisição e não registra falha | Task 1 Step 1 |
| Escopo 3 (dev e testes passam o valor por `defines.<modo>.json`) | Task 2 Step 3, Task 3 Step 2 |
