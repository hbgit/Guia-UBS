# Plano A: identidade, assinatura, ABIs e pipeline de release do APK

> **Para agentes executores:** SUB-SKILL OBRIGATÓRIA: superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar tarefa por tarefa. Passos em checkbox (`- [ ]`).

**Objetivo:** entregar os itens **25 (#71)** e **31 (#72)** do roadmap:
- o app sai com o id definitivo e com assinatura de release;
- sai em duas ABIs com o mesmo `versionCode`;
- recusa pack que exige app mais novo;
- tem um workflow que transforma uma tag `vX.Y.Z` em release verificável no GitHub.

**Arquitetura:** a mudança fica no build Android (`build.gradle.kts`), em três pontos do Dart e num workflow novo. Cada um desses pontos já tem o seu padrão:
- **shim ausente:** espelha o `notConfigured` do `ModelProvisioning`;
- **`minAppBuild`:** espelha a recusa de `schemaVersion` da FSM-B;
- **guarda de versão:** espelha o `model_url_check.dart`, ferramenta Dart com teste chamada pelo shell.

**Stack:** Gradle Kotlin DSL (AGP), Flutter 3.44.8, Dart, GitHub Actions.

**Spec:**
- [ADR-009](../../../spec/stack.md), a fonte das decisões;
- [`spec/implantacao.md`](../../../spec/implantacao.md) §2;
- [issue #71](https://github.com/hbgit/Guia-UBS/issues/71);
- [issue #72](https://github.com/hbgit/Guia-UBS/issues/72).

**Base:** `develop` em `944f6c4`.

## Restrições globais

- **`applicationId` = `br.com.prismrr.guiasaude`** (ADR-009, item 1). É permanente; nenhum outro valor entra.
- **`versionCode = MAJOR*10000 + MINOR*100 + PATCH`.**
  - Limites: MINOR ≤ 99, PATCH ≤ 99, MAJOR ≤ 210.
  - É o **mesmo** número em todo artefato da tag.
  - **Proibido `--split-per-abi`**: o `FlutterPlugin.kt` sobrescreve o código com `abi*1000 + código`.
- **ABIs:** `arm64-v8a` com o shim; `armeabi-v7a` **sem** o shim; `x86_64` só no debug (emulador). `minSdk` continua 26.
- **A chave Ed25519 do pack não entra em nada deste plano.** O keystore do APK é outra chave.
- **O keystore de release não é gerado por agente.** A custódia é de dois mantenedores, em cofre offline (ADR-009, item 8). Os testes usam um keystore descartável, gerado no scratchpad e **nunca** versionado.
- **Sem atribuição de IA nos commits.** UI conferida no emulador (CLAUDE.md).
- **Upload para a Play fica fora até a F-4** (conta da Play). O AAB sai como artefato do workflow.

## Foco de revisão

1. **ABI empacotada errada.** Um APK `armeabi-v7a` sem `libflutter.so`/`libapp.so` da própria ABI abre e fecha na hora. O `ndk.abiFilters` decide o que é **empacotado**, e um filtro fixo em `arm64-v8a` corta as libs do Flutter 32-bit.
2. **Release assinado com a chave debug em silêncio.** Sem `key.properties`, o Gradle cai no debug. No CI isso precisa **reprovar**, não passar verde.
3. **Download de 806 MB num aparelho que não roda o modelo.** Tanto o primeiro plano quanto o worker do WorkManager podem disparar o download, e os dois precisam saber que o shim não existe.
4. **`minAppBuild` tratado como falha de sync.** Um pack que exige app novo não é erro: é "atualize o binário". Contá-lo no circuito pararia o sync justamente de quem precisa atualizar.
5. **WorkManager com nome antigo.** Os nomes das tarefas mudam com o id. Um agendamento com o nome velho num aparelho de desenvolvimento não pode duplicar trabalho. Como o id novo é outro app, o app velho continua separado.

---

## Tarefas

### A1: identidade `br.com.prismrr.guiasaude` (#71)

**Arquivos:**
- `app/android/app/build.gradle.kts`: `namespace` e `applicationId`.
- `app/android/app/src/main/kotlin/br/gov/exemplo/guia_ubs/MainActivity.kt`: move para `.../br/com/prismrr/guiasaude/MainActivity.kt`, com `package br.com.prismrr.guiasaude`.
- `app/lib/sync/pack_sync_scheduler.dart:19` e `app/lib/sync/model_sync_scheduler.dart:19`: os nomes de tarefa passam a `br.com.prismrr.guiasaude.pack_sync` e `.model_sync`.
- `app/tool/release_permissions.dart:34`: `br.com.prismrr.guiasaude.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
- `app/test/tool/release_permissions_test.dart` e `app/integration_test/inference_bench_test.dart`: as referências.
- Teste novo: `app/test/tool/app_identity_test.dart`.

- [ ] **Passo 1: teste que falha.** `app_identity_test.dart`:
  - `'o applicationId e o namespace sao br.com.prismrr.guiasaude'`: lê `android/app/build.gradle.kts` e confere as duas linhas;
  - `'nenhum arquivo do app cita o id de exemplo'`: percorre `lib/`, `tool/`, `android/app/src/` e `android/app/build.gradle.kts`, e reprova `br.gov.exemplo`;
  - `'tarefas do WorkManager usam o prefixo do id'`: `packSyncTaskName` e `modelSyncTaskName` começam com `br.com.prismrr.guiasaude.`.
- [ ] **Passo 2:** `flutter test test/tool/app_identity_test.dart`. Esperado: FAIL.
- [ ] **Passo 3:** trocar o id em todos os arquivos acima.
- [ ] **Passo 4:** `flutter analyze --fatal-infos && flutter test`, tudo verde. Também `flutter build apk --debug --target-platform=android-x64`; instalar no emulador e abrir. `adb shell pm list packages | grep prismrr` precisa mostrar o pacote novo.
- [ ] **Passo 5:** commit `feat(app): applicationId br.com.prismrr.guiasaude (ADR-009, #71)`.

### A2: ABIs por alvo, sem split (#71)

**Arquivos:** `app/android/app/build.gradle.kts`; `app/tool/build_apk.sh`; `app/test/tool/build_apk_test.dart`.

**Decisão:**
- O `ndk.abiFilters` (o que é **empacotado**) deriva da propriedade `target-platform` que o `flutter build` passa ao Gradle:
  - `android-arm64` → `arm64-v8a`;
  - `android-arm` → `armeabi-v7a`;
  - lista com vírgula → as duas;
  - ausente (o `appbundle` sem flag) → `arm64-v8a` e `armeabi-v7a`.
- O `externalNativeBuild.cmake.abiFilters` (o que é **compilado**) é a interseção com `{arm64-v8a}`, mais `x86_64` no debug. **Nunca** `armeabi-v7a`: o llama.cpp 32-bit não é suportado (comentário atual do arquivo).
- `tool/build_apk.sh` aceita `<modo> [config] [abi]`, com `abi` ∈ `{arm64, arm}` e padrão `arm64`, e repassa `--target-platform=android-<abi>`. As guardas de URL continuam **antes** do build.

- [ ] **Passo 1: teste que falha.** Em `build_apk_test.dart`, `'abi arm passa --target-platform=android-arm ao flutter'`: com o `flutter` falso, o marcador contém `--target-platform=android-arm` e **não** contém `--split-per-abi`. Mais `'abi invalida sai com 64 antes do build'`.
- [ ] **Passo 2:** `flutter test test/tool/build_apk_test.dart`. Esperado: FAIL.
- [ ] **Passo 3:** implementar o Gradle e o script.
- [ ] **Passo 4, verificação de verdade:**
  - rodar `flutter build apk --release --target-platform=android-arm64` e `flutter build apk --release --target-platform=android-arm`, cada um seguido de `unzip -l` do APK;
  - **arm64:** `lib/arm64-v8a/` com `libflutter.so`, `libapp.so` e `libgubs_llama.so`, e nenhum outro diretório em `lib/`;
  - **arm:** `lib/armeabi-v7a/` com `libflutter.so` e `libapp.so`, **sem** `libgubs_llama.so`;
  - `aapt dump badging` dos dois mostra o **mesmo** `versionCode`;
  - registrar os dois tamanhos (o ADR-009 manda medir o `armeabi-v7a`).
- [ ] **Passo 5:** commit.

### A3: sem shim, sem oferta nem download do modelo (#71)

**Arquivos:**
- `app/lib/triage/engine/llama_bindings.dart`: `bool shimSupported({List<String>? candidates})`, que é `openShimLibrary(...) != null`.
- `app/lib/sync/model_provisioning.dart`: novo parâmetro `bool Function() runtimeSupported` (padrão `() => true` nos testes). Novo `SetupBlockReason.deviceUnsupported`, e o `start()` sai **antes** da rede.
- `app/lib/main.dart`: passa `runtimeSupported: shimSupported`; **não** chama `scheduleModelSync` quando não houver shim.
- O ponto de entrada do worker (`app/lib/sync/model_background_sync.dart`): sai sem baixar quando `!shimSupported()`.
- `app/lib/ui/onboarding/onboarding_screen.dart`: texto do novo motivo.
- Testes em `app/test/sync/model_provisioning_test.dart` e `app/test/sync/model_background_sync_test.dart`, ou onde o worker é testado hoje.

**Decisão:**
- Sem shim, o estado inicial é **`readyDegraded`** e não `blocked`. Bloquear oferecendo pendrive seria pedir um arquivo que nunca vai rodar.
- `deviceUnsupported` existe para a UI e a telemetria explicarem, mas não trava a tela clínica. Texto: "Este aparelho não roda o assistente. O atendimento funciona sem ele."
- Hoje esta tela só existe em pt. Este plano mantém o padrão e não a internacionaliza.

- [ ] **Passo 1: testes que falham.**
  - `'sem shim: readyDegraded sem tocar rede nem downloader'`: `runtimeSupported: () => false`; o `networkClass` e o downloader falsos registram chamadas, e as duas listas ficam vazias.
  - `'sem shim: o worker sai sem baixar'`.
  - `'com shim: fluxo de sempre'`: o teste existente continua verde com o padrão `true`.
- [ ] **Passo 2:** os testes novos falham.
- [ ] **Passo 3:** implementar.
- [ ] **Passo 4:** suíte verde. Instalar o APK `armeabi-v7a`, se houver AVD 32-bit, ou forçar `runtimeSupported: () => false` num build debug de teste, e conferir que a tela inicial abre sem pedir download. **Não** deixar a força no código.
- [ ] **Passo 5:** commit.

### A4: guarda de `minAppBuild` (#71)

**Arquivos:**
- `app/lib/sync/sync_fsm.dart`: novo campo de evento `appBuildSupported`, ao lado de `schemaSupported`.
- `app/lib/sync/sync_service.dart`: calcula o campo como `manifest.minAppBuild <= appBuild`.
- Testes em `app/test/sync/sync_fsm_test.dart` e `sync_service_test.dart`.

**Decisão:**
- `appBuild` é o `versionCode` do binário, injetado no `SyncService` (testável), vindo do `PackageInfo.buildNumber` em produção. Ele é **único** entre as ABIs por causa da A2.
- Quando `minAppBuild > appBuild`, o tratamento é **igual ao da B5** (`schemaVersion` não suportado):
  - vai para `f2Rejected` com `SyncAction.awaitBinaryUpdate`;
  - sem blacklist;
  - **não** conta no circuito.
- A regra nova se chama `'B5b P1→F2 minAppBuild > build do app [ADR-009]'` e é avaliada **depois** da assinatura e do anti-downgrade e **antes** do download.
- Ela muda a FSM-B. A matriz normativa está em `spec/espec.md` §4, que ganha a linha **B5b** no mesmo commit (regra de propagação).

- [ ] **Passo 1: testes que falham.**
  - FSM: `minAppBuild` maior que o build leva a `f2Rejected` + `awaitBinaryUpdate`, sem `incrementCircuitCounter`; igual ao build segue para `p2Downloading`.
  - Serviço: um manifest com `minAppBuild: 999999` e o build `10000` não baixa o pack.
- [ ] **Passo 2:** os testes falham.
- [ ] **Passo 3:** implementar e acrescentar a linha B5b na espec.
- [ ] **Passo 4:** suíte verde (inclui o `golden_clinical_test` e os testes da FSM linha a linha).
- [ ] **Passo 5:** commit.

### A5: `signingConfig` de release (#71)

**Arquivos:** `app/android/app/build.gradle.kts`; `app/android/key.properties.example` (novo, versionado, sem segredo); `docs/operacao.md` (seção nova "Assinatura do APK"); `cms/test/doc-operacao.test.ts` (só a exceção da variável, se citada).

**Decisão:**
- `app/android/key.properties`, já no `.gitignore`, traz `storeFile`, `storePassword`, `keyAlias` e `keyPassword`.
- **Presente:** o `release` assina com ele.
- **Ausente:**
  - com `GUBS_REQUIRE_RELEASE_SIGNING=1` no ambiente, o build **falha**, com a mensagem "release sem key.properties: o CI nunca publica APK assinado com a chave debug";
  - sem a variável, assina com a chave debug, como hoje, para a conferência local em aparelho continuar funcionando.
- O workflow da A7 sempre liga a variável.

- [ ] **Passo 1: verificações que falham, sem teste Dart, porque é Gradle:**
  - (a) `GUBS_REQUIRE_RELEASE_SIGNING=1 flutter build apk --release --target-platform=android-arm64`, sem `key.properties`, tem de falhar com a mensagem;
  - (b) com um keystore **descartável** no scratchpad (`keytool -genkeypair ... -keystore <scratchpad>/teste.jks`) e um `key.properties` temporário apontando para ele, `apksigner verify --print-certs` tem de mostrar o certificado do keystore descartável, e não o debug (`62c33cab…46b2`, registrado na §5.16 do `arquitetura.md`).
- [ ] **Passo 2:** implementar.
- [ ] **Passo 3:** rodar (a) e (b) e **apagar** o `key.properties` temporário. Conferir `git status` limpo, sem `.jks` nem `key.properties`.
- [ ] **Passo 4:** acrescentar a "Assinatura do APK" ao `docs/operacao.md`, com o que já existe: o arquivo, a variável e o comportamento. `npm test` verde, incluindo o `doc-operacao`.
- [ ] **Passo 5:** commit. **PR do item 25 (#71)** com A1–A5.

### A6: guarda de versão `tool/release_version.dart` (#72)

**Arquivos:** `app/tool/release_version.dart`; `app/test/tool/release_version_test.dart`.

**Interface:**
- `int versionCodeFor(String semver)`: `MAJOR*10000 + MINOR*100 + PATCH`, ou lança `FormatException` fora dos limites.
- `ReleaseCheck checkRelease({required String tag, required String pubspecVersion, required List<String> existingTags})`, que reprova quando:
  - a tag não é `vX.Y.Z`;
  - o `version:` do pubspec não é `X.Y.Z+<versionCodeFor(X.Y.Z)>`;
  - o código não é **maior** que o da maior tag `vX.Y.Z` em `existingTags`, excluída a própria.
- CLI: `dart run tool/release_version.dart --tag vX.Y.Z`. Ele lê o `pubspec.yaml` e `git tag --list 'v*'`, sai com código 1 e uma mensagem por problema, e imprime `versionCode=<n>` em caso de sucesso.

- [ ] **Passo 1: testes que falham:**
  - `versionCodeFor('0.1.0') == 100`, `('1.2.3') == 10203`, `('210.99.99') == 2109999`;
  - `'1.100.0'`, `'1.0.100'` e `'211.0.0'` lançam;
  - tag `v1.2.3` com o pubspec em `1.2.3+10203` passa;
  - pubspec em `1.2.3+1` reprova;
  - tags existentes `['v1.2.3']` e tag nova `v1.2.3`: passa, porque é a própria;
  - tags `['v1.3.0']` e tag nova `v1.2.9`: reprova (menor que a maior);
  - pre-release `v1.2.4` existente e tag nova `v1.2.4`: passa; `v1.2.3` nova com `v1.2.4` existente: reprova.
- [ ] **Passo 2:** falham.
- [ ] **Passo 3:** implementar.
- [ ] **Passo 4:** passam; `flutter analyze --fatal-infos` limpo.
- [ ] **Passo 5:** commit.

### A7: `app-release.yml`, `CHANGELOG.md` e manual (#72)

**Arquivos:** `.github/workflows/app-release.yml`; `CHANGELOG.md` (raiz, novo); `app/pubspec.yaml` (`version: 0.1.0+100`, que é a fórmula de `0.1.0`); `docs/operacao.md` (seção "Release do app"); `spec/implantacao.md` §2.6 (só se algum passo divergir do que foi construído); `CLAUDE.md` (os comandos novos).

**Decisão do workflow:**
- **Gatilhos:**
  - `push` de tag `v*`: release de verdade;
  - `pull_request` com `paths` no próprio workflow, em `app/android/**`, `app/tool/build_apk.sh` e `app/tool/release_version.dart`: **ensaio**, sem segredos, assinado com a chave debug, sem release.
- **Job `release`** (só em tag):
  - `environment: release`. Os revisores obrigatórios e o *Prevent self-review* são configuração do repositório, feita pelo mantenedor;
  - `GUBS_REQUIRE_RELEASE_SIGNING=1`;
  - o keystore entra por `secrets.ANDROID_KEYSTORE_B64` → arquivo temporário, mais `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` e `ANDROID_KEY_PASSWORD`;
  - o `config/defines.release.json` entra por `secrets.DEFINES_RELEASE_JSON`.
- **Passos:**
  1. `release_version.dart --tag` (precisa de `fetch-depth: 0` para ver as tags);
  2. `tool/build_apk.sh release config/defines.release.json arm64` e `... arm`;
  3. `flutter build appbundle --release`;
  4. `check_release_permissions.dart`;
  5. `apksigner verify --print-certs`, comparado com `vars.RELEASE_CERT_SHA256`. **Diferente reprova**: pega o debug e qualquer chave trocada;
  6. `sha256sum *.apk > SHA256SUMS`;
  7. `gh release create --prerelease` com os APKs e o `SHA256SUMS`, e a nota a partir do modelo da §2.8, com o bloco do `CHANGELOG.md` da versão;
  8. AAB como **artefato do workflow**, sem anexar à release e sem enviar à Play (F-4).
- **Permissões:** `contents: write` só no job `release`.
- **Ações de terceiros:** só as já usadas no repositório (`actions/checkout`, `actions/setup-java`, `subosito/flutter-action`, `actions/cache`, `actions/upload-artifact`). A publicação usa o `gh` do runner.

- [ ] **Passo 1:** escrever o workflow, o `CHANGELOG.md` com a seção `[0.1.0]` e o bump do pubspec. Validar com `python3 -c "import yaml; yaml.safe_load(open(...))"` e, se disponível, `actionlint`.
- [ ] **Passo 2:** `dart run tool/release_version.dart --tag v0.1.0` local deve imprimir `versionCode=100`.
- [ ] **Passo 3:** o **ensaio** roda no próprio PR, porque o workflow muda. O job verde é o aceite: dois APKs, um AAB, `SHA256SUMS`, as `.so` certas por ABI.
- [ ] **Passo 4:** `docs/operacao.md` e CLAUDE.md, mais `npm test` verde (`doc-operacao`).
- [ ] **Passo 5:** commit e **PR do item 31 (#72)**.

---

## O que o mantenedor precisa fazer (não é de agente)

1. **Gerar o keystore de release** e guardá-lo no cofre, com duas custódias (ADR-009, item 8).
2. **Cadastrar os segredos** `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` e `DEFINES_RELEASE_JSON`, e a variável `RELEASE_CERT_SHA256`.
3. **Criar o *environment* `release`** com revisores obrigatórios e *Prevent self-review*.
4. **Ter o `defines.release.json` real.** O `PACK_MANIFEST_URL` exige o domínio de conteúdo, que vem do plano B. Antes dele, a guarda do `build_apk.sh` recusa o release de propósito. **A primeira tag de verdade depende do plano B.**
5. **Conta da Play (F-4)**, para o upload do AAB, que fica para depois.

## Autorrevisão

- **Cobertura da #71:**
  - id: A1;
  - `signingConfig`: A5;
  - ABIs sem split e `armeabi-v7a` sem shim: A2;
  - sem download onde não há shim: A3;
  - guarda de `minAppBuild`: A4;
  - aceite por `aapt`, `.so` por ABI e tamanho: A2, Passo 4.
- **Cobertura da #72:**
  - tag → APKs + AAB, `SHA256SUMS`, pre-release, guarda pela maior tag, *Prevent self-review* e as guardas existentes: A6 e A7;
  - faixa de teste da Play: adiada pela F-4, e dito.
- **Nomes:** `shimSupported`, `runtimeSupported`, `SetupBlockReason.deviceUnsupported`, `appBuildSupported`, `B5b`, `versionCodeFor`, `checkRelease` e `GUBS_REQUIRE_RELEASE_SIGNING` são usados com o mesmo sentido em todas as tarefas.
