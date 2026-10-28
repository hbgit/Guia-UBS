# P0-1 — `INTERNET` no APK release — Plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar tarefa a tarefa. Passos usam checkbox (`- [ ]`).

**Objetivo:** o APK release passa a declarar `android.permission.INTERNET` (e só ela, além das sete herdadas de plugins), com uma verificação de lista fechada que reprova qualquer permissão a mais ou a menos, e a FSM-B e o provisionamento do modelo comprovados em runtime com o APK release.

**Arquitetura:** a correção é uma linha no manifest principal. O guarda é uma biblioteca Dart pura em `app/tool/` (`release_permissions.dart`, testada em `app/test/tool/` sem build) mais um CLI (`check_release_permissions.dart`) que lê o manifest mesclado de release e falha alto quando ele não existe ou está desatualizado. A verificação em runtime usa o AVD com tradução ARM, um servidor HTTP local para o pack e o Hugging Face para o modelo, com evidência tirada do disco do app (`adb root`), do log do servidor e do `logcat` do WorkManager.

**Stack:** Flutter/Dart, AGP 9.0.1, Gradle 9.1.0, `package:xml` (dev), `aapt2` (build-tools 36.0.0), `adb`.

**Spec:** a issue #1 (P0-1), transcrita no pedido; `spec/stack.md` ADR-003 (l. 342); `spec/lgpd.md` LGPD-RF01 (l. 25, 276); `spec/espec.md` RF-10 (l. 30), RNF-03 (l. 43); `CLAUDE.md` "Offline-only em runtime"; `docs/superpowers/plans/2026-10-28-levantamento-estado-projeto.md` (Task 2, Step 2).

## Restrições globais

- Única permissão nova: `android.permission.INTERNET`. Nenhuma outra, em nenhum manifest.
- Fora do escopo (não tocar): política UNMETERED e restrições do WorkManager (`pack_sync_scheduler.dart`, `model_sync_scheduler.dart`), backup automático (#5, P1-3), justificativa das permissões herdadas (#28, P3-3), build release no CI (#14, P2-1).
- `src/debug` e `src/profile` ficam como estão (o `flutter` tool precisa deles; redundância inofensiva).
- Lista fechada (8, exata): `android.permission.INTERNET`, `android.permission.ACCESS_NETWORK_STATE`, `android.permission.POST_NOTIFICATIONS`, `android.permission.FOREGROUND_SERVICE`, `android.permission.FOREGROUND_SERVICE_SHORT_SERVICE`, `android.permission.WAKE_LOCK`, `android.permission.RECEIVE_BOOT_COMPLETED`, `br.gov.exemplo.guia_ubs.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
- Build de referência: `flutter build apk --release --target-platform=android-arm64` (de `app/`).
- `flutter analyze --fatal-infos` limpo e `flutter test` verde ao fim de cada tarefa que toca Dart.
- Textos, comentários e mensagens em pt-BR; commits no estilo `tipo(escopo): descrição`.

## Estado confirmado no código (2026-10-28)

| Item | Achado | Bate com a issue? |
|---|---|---|
| `src/main/AndroidManifest.xml` | nenhum `uses-permission` | sim |
| `src/debug` e `src/profile` `:6` | `INTERNET` | sim |
| Manifest mesclado (`merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml:30-58`) | as 7 permissões listadas, sem `INTERNET` | sim |
| `aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk` (APK de 2026-10-28 11:21, 25,6 MB) | as mesmas 7, sem `INTERNET`; `native-code: 'arm64-v8a'` | sim — **causa confirmada no artefato final** |
| Caminho do manifest mesclado no AGP 9.0.1 | existem **dois** idênticos: `intermediates/merged_manifest/release/processReleaseMainManifest/` e `intermediates/merged_manifests/release/processReleaseManifest/` (este com `output-metadata.json`, `versionName 0.1.0`, `versionCode 1`) | sim, mas é caminho **interno** do AGP (mudou entre AGP 7 e 8) — por isso o CLI falha alto se não o achar, e o `aapt2` sobre o APK é a confirmação independente |

### Divergências em relação à issue

1. **Data do manifest mesclado.** A issue diz que ele foi "reconstruído em 2026-10-28". O arquivo no disco é de **2026-08-22 19:30**. O build de 28/10 foi incremental (o Gradle considerou `processReleaseMainManifest` atualizado e não reescreveu a saída). O conteúdo continua válido porque os insumos não mudaram, e o `aapt2` sobre o APK de 28/10 confirma. **Consequência para o desenho:** um guarda por `mtime` contra `pubspec.lock` daria falso positivo para sempre (o Gradle não reescreve saída atualizada). O guarda compara só com `src/main/AndroidManifest.xml`, que é insumo direto da tarefa: mudou, o Gradle reexecuta e reescreve.
2. **Não há transição da FSM-B no `logcat`.** O app não tem nenhum `print`, `debugPrint` ou `dart:developer` em `lib/`. O `SyncReport` (com `state` e `rules`) existe "para o teste e o log local", mas `runPackSyncTask` (`lib/sync/pack_background_sync.dart:37-58`) o descarta. Acrescentar log foge ao escopo desta issue. A evidência de `COMMITTED` vem do **disco**, que é a própria definição do commit (o pack só fica ativo quando o `manifest.json` corrente aponta para ele, `pack_store.dart:7,123-125`). Recomendo abrir issue separada para registrar o `SyncReport` em log local.
3. **Não precisa de APK x86_64, e ele nem funcionaria.** O AVD em execução (`sinalacs_ci36`, API 36, `google_apis`, x86_64, `userdebug`) informa `ro.product.cpu.abilist = x86_64,arm64-v8a` e `ro.dalvik.vm.native.bridge = libndk_translation.so`. O APK release arm64 de hoje **instalou, abriu (pid vivo, Impeller rodando) e agendou o trabalho do WorkManager** neste AVD (feito durante o planejamento e desinstalado depois). Já `--target-platform=android-x64` em release não empacotaria x86_64: `defaultConfig` fixa `abiFilters` em `arm64-v8a` (`android/app/build.gradle.kts:40-41,49-50`) e o AGP faz união com o buildType, e só o `debug` acrescenta x86_64 (`:83,87`). Conclusão: usar o build da issue (arm64) sobre tradução ARM. Ressalva registrada: tradução ARM ≠ CPU arm64; a inferência (llama.cpp sob tradução) não é medida aqui, e não é critério desta issue.
4. **Assinatura do release.** `buildTypes.release` usa `signingConfigs.getByName("debug")` (`build.gradle.kts`, bloco `release`, com o `TODO` original). `apksigner` confirma `CN=Android Debug`, SHA-256 `62c33cab…46b2` = `~/.android/debug.keystore`. Instala no AVD sem nada extra. O APK **não** é `debuggable`: `run-as` falha ("package not debuggable"). Por isso a inspeção do disco usa `adb root`, que funciona porque a imagem é `google_apis userdebug`. Na imagem `google_apis_playstore` (`Medium_Phone`) isso **não** funcionaria; use `sinalacs_ci36`.
5. **Aparelho físico → emulador (decisão do dono, 2026-10-28).** `adb devices -l` mostra só `emulator-5554`. A issue pede "aparelho". **Decisão: a issue fecha com o registro do AVD.** O escopo 3 e o AC3 são cumpridos pela Task 4 no `sinalacs_ci36`, e §5.16 diz literalmente que a verificação foi em emulador com tradução ARM, sem apresentá-la como aparelho. A repetição em arm64 real (Task 6) é opcional, **não bloqueia o fechamento**, e só complementa o registro quando houver aparelho conectado.

## Decisão: onde mora o teste de lista fechada

**`app/tool/` para o que depende do build, `app/test/` para a lógica.**

- Em `app/test/`, um teste que lê `build/…/release/…` faria o `flutter test` do CI (que não gera release até a #14) ficar vermelho para todo mundo, ou, se "pulasse quando o arquivo não existe", ficaria verde com zero asserções, exatamente o padrão que o `CLAUDE.md` proíbe ("senão o teste rodaria zero asserções e ficaria verde").
- Por isso: a lógica pura (`declaredPermissions`, `diffPermissions`, a constante da lista) vive em `app/tool/release_permissions.dart` e é testada em `app/test/tool/release_permissions_test.dart` com XML inline. Isso roda no CI hoje. O CLI `app/tool/check_release_permissions.dart` aplica a mesma lógica ao manifest mesclado real e roda localmente (precedente: `tool/verify_manifest.dart`). Quando a #14 trouxer o build release ao CI, basta um passo `dart run tool/check_release_permissions.dart` depois do build.
- `package:xml` entra como `dev_dependency` (já é transitiva, 6.6.1 no lock). Não vai para o APK. Regex seria frágil a ordem de atributos (`android:maxSdkVersion` antes de `android:name`).

## Mapa de arquivos

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `app/tool/release_permissions.dart` | criar | lista fechada + extração + diff + checagem de desatualização (puro, sem I/O) |
| `app/tool/check_release_permissions.dart` | criar | CLI: lê o manifest mesclado, aplica a lógica, códigos de saída |
| `app/test/tool/release_permissions_test.dart` | criar | testes da lógica pura (rodam no CI) |
| `app/pubspec.yaml` | modificar | `xml: ^6.6.1` em `dev_dependencies` |
| `app/android/app/src/main/AndroidManifest.xml` | modificar | `uses-permission INTERNET` + comentário ADR-003 |
| `CLAUDE.md` | modificar | uma linha em §Comandos |
| `spec/arquitetura.md` | modificar | nova §5.16 com o registro |

## Foco de revisão

1. **Manifest mesclado desatualizado** (fonte editada, build não refeito, ex.: a sabotagem): o CLI precisa sair com 3, nunca com 0. Coberto por `isStale` na Task 2 e pelo Step 7 da Task 3.
2. **Ler o manifest de debug por engano**: ele tem `INTERNET` via `src/debug` e passaria mesmo com o release quebrado (a armadilha que criou esta issue). O teste fixa que o caminho padrão contém `/release/` e não contém `debug` (Task 2).
3. **`<uses-permission-sdk-23>`** concede permissão em API ≥ 23 e escaparia de um filtro só por `uses-permission` (Task 2).
4. **`<permission>` (declaração) e `android:permission="…DUMP"`/`BIND_JOB_SERVICE`** em componentes não são pedidos de permissão. Contá-los geraria falso vermelho que ensina a ignorar o guarda (Task 2).
5. **Permissão que some** (plugin removido, ou alguém tira `INTERNET`): "exatamente" também reprova a falta, não só o excesso (Task 2, e a Task 1 reproduz exatamente esse caso).

---

### Task 1: Linha de base vermelha em runtime (confirma a causa no AVD)

Sem mudança de código. Prova que, com o APK de hoje, nenhuma requisição sai do aparelho.

**Arquivos:** nenhum no repositório. Diretório de serviço: `$SCRATCH/serve` (scratchpad da sessão).

- [ ] **Step 1: Pack de referência e conferência da chave**
Run (raiz): `SOURCE_DATE_EPOCH=1787097600 PACK_SIGNING_KEY_PATH=contract/keys/dev-k1.pem PACK_VERSION=1 npm run pack:build`
Run (de `app/`): `dart run tool/verify_manifest.dart ../packer/out/manifest.json bbfd5b2b69d27c539a4d29a4167319508bbf36130590d22289676a0e7e237dfa`
Esperado: `pack-88c2c35a99e1.db` (160 KB) e `ok  manifest v1 aceito`. Essa chave é `devPackSigningKeyK1`, a que o APK release usa sem `--dart-define`. Hoje `packer/out/` está inconsistente (o manifest aponta para `pack-88c2…` e o diretório só tem `pack-29d9…`), por isso o rebuild é obrigatório.

- [ ] **Step 2: Servir o pack no caminho que o app espera**
O padrão de `PACK_MANIFEST_URL` é `http://127.0.0.1:9000/content-packs/0000000/manifest.json` e `pack.url` é relativo (`packs/pack-88c2c35a99e1.db`).
```sh
S=$SCRATCH/serve/content-packs/0000000; mkdir -p $S/packs
cp packer/out/manifest.json $S/ && cp packer/out/packs/pack-88c2c35a99e1.db $S/packs/
python3 -m http.server 9000 --bind 127.0.0.1 --directory $SCRATCH/serve 2>&1 | tee $SCRATCH/http.log   # em segundo plano
adb reverse tcp:9000 tcp:9000
```
Esperado: `curl -sI http://127.0.0.1:9000/content-packs/0000000/manifest.json` → `200`.

- [ ] **Step 3: Instalar o APK atual e forçar um ciclo**
```sh
adb root && adb install -r app/build/app/outputs/flutter-apk/app-release.apk
adb shell am start -W -n br.gov.exemplo.guia_ubs/.MainActivity
adb shell dumpsys jobscheduler br.gov.exemplo.guia_ubs | grep -E "JOB #|Required constraints"
adb shell cmd jobscheduler run -f br.gov.exemplo.guia_ubs <ID do job com CONNECTIVITY BATTERY_NOT_LOW e SEM STORAGE_NOT_LOW>
```
(Pack = `NET BATNOTLOW`; modelo = `NET BATNOTLOW STORENOTLOW`, conforme §5.8.)
Esperado: **zero** linhas novas em `$SCRATCH/http.log`; `adb shell ls /data/data/br.gov.exemplo.guia_ubs/files/packs/ /data/data/br.gov.exemplo.guia_ubs/files/models/` vazios; a tela de setup do modelo termina em `blocked`/offline. Guarde a saída: ela entra no registro (Task 5).

---

### Task 2: Lista fechada — lógica pura, testes e CLI (vermelho primeiro)

**Arquivos:**
- Criar: `app/tool/release_permissions.dart`, `app/tool/check_release_permissions.dart`
- Testar: `app/test/tool/release_permissions_test.dart`
- Modificar: `app/pubspec.yaml` (`dev_dependencies`: `xml: ^6.6.1`, com comentário de uma linha: "Lê o manifest mesclado de release (tool/check_release_permissions.dart).")

**Interfaces (produz):**
```dart
// app/tool/release_permissions.dart
const Set<String> releasePermissionAllowlist;            // as 8 de "Restrições globais"
const String defaultReleaseManifestPath =
    'build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml';
const String mainManifestSourcePath = 'android/app/src/main/AndroidManifest.xml';
Set<String> declaredPermissions(String manifestXml);      // uses-permission + uses-permission-sdk-23, valor de android:name
class PermissionDiff { final Set<String> unexpected; final Set<String> missing; bool get isClean; }
PermissionDiff diffPermissions(Set<String> declared, {Set<String> allowed = releasePermissionAllowlist});
bool isStale({required DateTime merged, required DateTime source}); // merged.isBefore(source)
```
`declaredPermissions` usa `XmlDocument.parse` e lê o atributo pelo nome qualificado `android:name` (namespace `http://schemas.android.com/apk/res/android`). Cada `<uses-permission>` sem `android:name` lança `FormatException` (manifest malformado não pode virar "zero permissões, ok").

- [ ] **Step 1: Escrever os testes que falham**
`app/test/tool/release_permissions_test.dart`, importando `'../../tool/release_permissions.dart'`, com um helper `manifest(String body)` que embrulha `body` em `<manifest xmlns:android="http://schemas.android.com/apk/res/android">…</manifest>`:
- `'lista fechada tem exatamente as 8 permissões da issue P0-1'`: `releasePermissionAllowlist` tem `length == 8` e contém `android.permission.INTERNET`.
- `'manifest com exatamente a lista passa'`: `diffPermissions(declaredPermissions(manifest(<8 uses-permission>))).isClean` é `true`.
- `'falta de INTERNET reprova'` (o estado de hoje): manifest com as 7 herdadas → `missing == {'android.permission.INTERNET'}`, `unexpected` vazio.
- `'permissão a mais reprova'`: as 8 + `android.permission.CAMERA` → `unexpected == {'android.permission.CAMERA'}`.
- `'uses-permission-sdk-23 conta como pedido'`: as 8 + `<uses-permission-sdk-23 android:name="android.permission.READ_CONTACTS"/>` → `unexpected == {'android.permission.READ_CONTACTS'}`.
- `'declaração e atributo android:permission não contam'`: as 8 + `<permission android:name="x.y.Z"/>` + `<application><service android:permission="android.permission.BIND_JOB_SERVICE"/></application>` → `isClean`.
- `'maxSdkVersion antes do name ainda é lido'`: `<uses-permission android:maxSdkVersion="32" android:name="android.permission.WAKE_LOCK"/>` → contém `WAKE_LOCK`.
- `'uses-permission sem android:name lança FormatException'`.
- `'caminho padrão é o de release, nunca o de debug'`: `defaultReleaseManifestPath` contém `/release/` e não contém `debug`.
- `'manifest mais antigo que a fonte é desatualizado'`: `isStale(merged: t, source: t.add(1s))` → `true`; `isStale(merged: t.add(1s), source: t)` → `false`.

- [ ] **Step 2: Rodar e ver falhar**
Run (de `app/`): `flutter pub get && flutter test test/tool/release_permissions_test.dart`
Esperado: falha de compilação, `release_permissions.dart` não existe.

- [ ] **Step 3: Implementar `app/tool/release_permissions.dart`** conforme as interfaces acima, com doc de biblioteca no estilo de `verify_manifest.dart`: por que lista fechada (LGPD-RF01, "permissões mínimas"), por que a justificativa de cada herdada mora na #28, e por que este arquivo vive em `tool/` e não em `lib/` (não vai para o APK).

- [ ] **Step 4: Rodar e ver passar**
Run: `flutter test test/tool/release_permissions_test.dart` → todos verdes. `flutter analyze --fatal-infos` → `No issues found!`

- [ ] **Step 5: Implementar o CLI `app/tool/check_release_permissions.dart`**
`Future<void> main(List<String> args)`; argumento opcional = caminho do manifest (padrão `defaultReleaseManifestPath`); mais de 1 argumento → uso em `stderr`, `exit(64)`. Códigos e mensagens:
- arquivo ausente → `exit(2)`: `FALHA  manifest mesclado de release não encontrado em <caminho>.` + `       Rode antes: flutter build apk --release --target-platform=android-arm64` + `       (caminho interno do AGP 9.0.1; se o AGP mudou, confira com find build/app/intermediates -path '*release*' -name AndroidManifest.xml)`.
- `isStale(merged: mtime do mesclado, source: mtime de mainManifestSourcePath)` → `exit(3)`: `FALHA  manifest mesclado é mais antigo que android/app/src/main/AndroidManifest.xml; refaça o build de release.`
- diff não vazio → `exit(1)`, uma linha por item: `  + <perm>  (fora da lista; LGPD-RF01 exige justificar — ver #28)` e `  - <perm>  (esperada e ausente)`.
- limpo → `exit(0)`: `ok  8 permissões, lista fechada (LGPD-RF01)`.

- [ ] **Step 6: Vermelho contra o build real**
Run (de `app/`): `dart run tool/check_release_permissions.dart; echo "exit=$?"`
Esperado: `  - android.permission.INTERNET  (esperada e ausente)` e `exit=1`. **Esta é a reprodução da issue pelo guarda.**
Run: `mv build/app/intermediates/merged_manifest build/mm.bak; dart run tool/check_release_permissions.dart; echo "exit=$?"; mv build/mm.bak build/app/intermediates/merged_manifest`
Esperado: mensagem de manifest ausente, `exit=2`.

- [ ] **Step 7: Suíte e commit**
Run: `flutter analyze --fatal-infos && flutter test` → verdes (532 + os novos).
```sh
git add app/tool/release_permissions.dart app/tool/check_release_permissions.dart app/test/tool/release_permissions_test.dart app/pubspec.yaml app/pubspec.lock
git commit -m "test(android): lista fechada de permissoes do APK release (P0-1)"
```

---

### Task 3: Correção no manifest, verificação no artefato e sabotagem

**Arquivos:** modificar `app/android/app/src/main/AndroidManifest.xml` (antes de `<application>`) e `CLAUDE.md` (§Comandos, bloco do app).

**Interfaces (consome):** CLI da Task 2 e seus códigos de saída.

- [ ] **Step 1: Declarar a permissão**
Inserir logo após a abertura de `<manifest …>`:
```xml
    <!-- Exigida pelas DUAS unicas chamadas de rede do app (spec/stack.md
         ADR-003; CLAUDE.md "Offline-only em runtime"), ambas fora do caminho
         do usuario, retomaveis por HTTP Range e conferidas por SHA-256:
           1. manifest e pack de conteudo, pelo WorkManager (FSM-B, RF-10);
           2. modelo SLM no 1o acesso (700 MB-1,2 GB).
         Ate a P0-1 so src/debug e src/profile a declaravam (para o flutter
         tool), e o release saia sem rede nenhuma. Qualquer outra permissao
         reprova tool/check_release_permissions.dart (LGPD-RF01). -->
    <uses-permission android:name="android.permission.INTERNET"/>
```
(Sem acentos, como os comentários de `build.gradle.kts`, para não depender do encoding do merger.)

- [ ] **Step 2: Rebuild de release**
Run (de `app/`): `rm -f android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java && flutter build apk --release --target-platform=android-arm64`
Esperado: `✓ Built build/app/outputs/flutter-apk/app-release.apk`. Anote o tamanho (≈25,6 MB).

- [ ] **Step 3: Critério "grep INTERNET"**
Run: `grep -n INTERNET build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`
Esperado: uma linha `<uses-permission android:name="android.permission.INTERNET" />`.

- [ ] **Step 4: Lista fechada verde**
Run: `dart run tool/check_release_permissions.dart; echo "exit=$?"` → `ok  8 permissões, lista fechada (LGPD-RF01)`, `exit=0`.

- [ ] **Step 5: Confirmação independente no APK**
Run: `~/Android/Sdk/build-tools/36.0.0/aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk`
Esperado: `uses-permission: name='android.permission.INTERNET'` mais as 7 da lista, e nada além (a linha `permission: br.gov…DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` é a declaração e é esperada).

- [ ] **Step 6: Commit da correção** (antes da sabotagem, para o `git checkout` restaurar a versão corrigida)
Acrescentar em `CLAUDE.md`, bloco do app em §Comandos, depois de `flutter build apk …`:
`dart run tool/check_release_permissions.dart   # lista fechada de permissoes do release (exige o build acima)`
```sh
git add app/android/app/src/main/AndroidManifest.xml CLAUDE.md
git commit -m "fix(android): declara INTERNET no manifest principal (P0-1, ADR-003)"
```

- [ ] **Step 7: Sabotagem 1 — fonte editada sem rebuild**
Acrescentar `<uses-permission android:name="android.permission.CAMERA"/>` depois da linha de `INTERNET` em `src/main/AndroidManifest.xml`.
Run: `dart run tool/check_release_permissions.dart; echo "exit=$?"` → mensagem de desatualizado, `exit=3` (**não** 0).

- [ ] **Step 8: Sabotagem 2 — permissão extra no build**
Run: `flutter build apk --release --target-platform=android-arm64 && dart run tool/check_release_permissions.dart; echo "exit=$?"`
Esperado: `  + android.permission.CAMERA  (fora da lista…)`, `exit=1`; o `aapt2 dump permissions` também mostra `CAMERA`.

- [ ] **Step 9: Reverter e confirmar**
Run: `git checkout -- android/app/src/main/AndroidManifest.xml && git status --short` (vazio) `&& flutter build apk --release --target-platform=android-arm64 && dart run tool/check_release_permissions.dart; echo "exit=$?"` → `ok …`, `exit=0`. O APK final é o que segue para a Task 4.

---

### Task 4: Verificação em runtime no AVD (APK release)

**Ambiente:** AVD `sinalacs_ci36` (API 36, `google_apis`, x86_64, `userdebug`, tradução ARM), servidor da Task 1 no ar, `adb reverse tcp:9000 tcp:9000` ativo, rede Wi-Fi `NOT_METERED` (a política do modelo exige não medida, e o AVD tem `wlan0` não medida; não mexer na política), `/data` com ≥ 3 GB livres (hoje 4,3 GB; RNF-03).

- [ ] **Step 1: Instalação limpa**
Run: `adb root && adb uninstall br.gov.exemplo.guia_ubs; adb install app/build/app/outputs/flutter-apk/app-release.apk && adb logcat -c`
Run: `adb shell dumpsys package br.gov.exemplo.guia_ubs | grep -A1 "android.permission.INTERNET"` → `granted=true` (permissão normal, concedida na instalação).

- [ ] **Step 2: FSM-B até `COMMITTED`**
Abrir o app (`am start -W …`), concluir o onboarding e forçar o job de pack (mesmo `cmd jobscheduler run -f` da Task 1). Também vale ir para segundo plano e voltar, o que dispara o ciclo de primeiro plano.
Evidência objetiva (as três são necessárias):
  - (a) Rede: `$SCRATCH/http.log` mostra `GET /content-packs/0000000/manifest.json` → `200` e `GET /content-packs/0000000/packs/pack-88c2c35a99e1.db` → `200`.
  - (b) Commit no disco (definição de P5, `pack_store.dart:123-125`): `adb shell sha256sum /data/data/br.gov.exemplo.guia_ubs/files/packs/manifest.json` = `sha256sum packer/out/manifest.json`, **e** `adb shell sha256sum /data/data/br.gov.exemplo.guia_ubs/files/packs/pack-88c2c35a99e18609f6c6a476e495dd91240c6749bbf5ec07dade2614592f4d71.db` = `88c2c35a…f4d71`. Sem `manifest.json.novo` sobrando. Registrar também `cat …/packs/state.json`.
  - (c) Execução do trabalho: `adb logcat -d | grep -E "WM-WorkerWrapper|WM-SystemJobService"` mostra `Worker result SUCCESS`. Isso é **auxiliar**: `runPackSyncTask` devolve `true` mesmo em falha (`pack_background_sync.dart:44-55`), então SUCCESS sozinho não prova commit.
  - Complemento visual: conteúdo clínico aparece ("Onde ir", documentos) no app.
  - Filtro do `logcat`: `adb logcat -v time WM-WorkerWrapper:D WM-SystemJobService:D WM-Processor:D flutter:I AndroidRuntime:E *:S` (o WorkManager já loga em D neste app, observado no planejamento). Não há tag de FSM-B; ver a Divergência 2.

- [ ] **Step 3: Provisionamento do modelo — download com `Range`**
Na tela de setup, aceitar o download (`awaitingConsent` → `downloading`). Com ~200 MB baixados:
```sh
P=/data/data/br.gov.exemplo.guia_ubs/files/models/gemma-3-1b-q4.gguf.parcial
adb shell stat -c %s $P            # S1
adb shell cmd connectivity airplane-mode enable; sleep 5; adb shell stat -c %s $P   # S2 >= S1, tela em blocked/interrupted
adb shell cmd connectivity airplane-mode disable
# repetir a cada ~3 s por 30 s:
adb shell stat -c %s $P            # S3, S4, …
```
Esperado: a sequência **nunca cai abaixo de S2** e volta a crescer. É a prova objetiva de que o servidor respondeu `206` ao `Range: bytes=S2-`: se tivesse respondido `200`, o downloader descartaria o parcial e recomeçaria do zero (`resumable_downloader.dart:204-218`), e o tamanho despencaria. Não temos log do lado do servidor (Hugging Face), então essa é a evidência disponível. Se a UI pedir "tentar de novo", tocar; o parcial é o mesmo arquivo.

- [ ] **Step 4: Provisionamento do modelo — SHA-256 aprovado**
Esperado ao fim (`verifying` → `ready`):
  - `…/models/gemma-3-1b-q4.gguf` existe, com 806058240 bytes, e **não** existe `….parcial` (o rename só acontece depois do SHA conferir, `resumable_downloader.dart:163-176`);
  - `adb shell sha256sum …/models/gemma-3-1b-q4.gguf` = `8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135` (`model_catalog.dart:26`);
  - `…/models/gemma-3-1b-q4.gguf.verificado` existe com `806058240:<µs>` (`model_provisioning.dart:178-187`);
  - a tela clínica libera.
  Se o motor llama.cpp falhar sob tradução ARM, isso é registrado mas **não** reprova esta issue: o critério é baixar e verificar, e a degradação para `RuleOnlyEngine` é o comportamento especificado.

- [ ] **Step 5: Limpeza**
`adb unroot`; `adb reverse --remove tcp:9000`; parar o `http.server`. Manter o app instalado só se o dono quiser repetir a verificação.

---

### Task 5: Registro em `spec/arquitetura.md` §5

**Arquivos:** modificar `spec/arquitetura.md`, nova subseção logo depois de §5.15 (antes de `### Fase 3.5`).

- [ ] **Step 1: Escrever §5.16** com o título `#### 5.16 Resultado da P0-1 (issue #1) — \`INTERNET\` no APK release (AAAA-MM-DD)`, no estilo de §5.15 (parágrafos curtos com o porquê em negrito), contendo:
  - **Causa**: só `src/debug`/`src/profile` declaravam `INTERNET`; release com 7 permissões e nenhuma rede; reprodução pelo guarda (`exit=1`, `- INTERNET`) e em runtime (Task 1: zero requisições, `packs/` e `models/` vazios).
  - **Correção e guarda**: a linha no manifest; a lista fechada de 8; por que a lógica está em `tool/` com testes em `test/tool/` (CI sem build release até a #14); os códigos de saída 0/1/2/3; o `mtime` comparado só com a fonte do manifest (Divergência 1).
  - **Sabotagem: 2 proteções, 2 pegas** (fonte sem rebuild → 3; `CAMERA` no build → 1), revertidas.
  - **Verificado em emulador** — linha de ambiente literal: `AVD sinalacs_ci36 · system-image android-36 google_apis x86_64 (userdebug) · API 36 · APK arm64-v8a sob libndk_translation · Guia UBS 0.1.0+1 (<hash do commit da Task 3>) · release assinado com debug.keystore (CN=Android Debug) · <data>`. Resultados: (a)/(b)/(c) da Task 4 Step 2 com os hashes; S1/S2/S3… do Step 3; hash e marcador do Step 4; tamanho do APK.
  - **Escopo da verificação**: feita em emulador por decisão do dono (Divergência 5), e é com ela que a issue fecha. Escrever que tradução ARM não é CPU arm64 (a inferência não foi medida aqui) e que, se houver repetição em aparelho físico, ela entra como complemento nesta mesma subseção.
  - **Lacuna aberta**: transições da FSM-B não vão para log (Divergência 2), com a referência à issue nova, se aberta.

- [ ] **Step 2: Commit**
```sh
git add spec/arquitetura.md
git commit -m "docs(arquitetura): registra a P0-1 verificada em AVD (5.16)"
```

- [ ] **Step 3: Fechar a issue**
Comentar na #1 com o link para os commits das Tasks 2, 3 e 5, a linha de ambiente de §5.16 e as três evidências da Task 4 (pack `COMMITTED`, `Range`, SHA-256). Depois `gh issue close 1 --reason completed`. Confirmar com o dono antes de rodar, porque é ação externa.

---

### Task 6 (OPCIONAL, pós-fechamento — não bloqueia a #1): mesma verificação em arm64 real

Fora do caminho de fechamento (Divergência 5). Só quando houver aparelho (`adb devices -l` mostrando o Motorola Edge 40 Neo ou outro arm64). Repetir a Task 4 com o mesmo APK, com duas diferenças: sem `adb root` (APK release não é `debuggable` e aparelho de produção não tem root), então a evidência (b) vira a observação de "conteúdo presente com rádio ligado após o sync" mais o log do servidor, e a do Step 3/4 vira o progresso da tela de setup interrompido e retomado sem voltar a zero, mais a tela clínica liberada com o selo de assistente disponível. Para o servidor local, o aparelho precisa alcançar o host (`adb reverse tcp:9000 tcp:9000` funciona por USB). Acrescentar a §5.16 um parágrafo "Complemento em aparelho" com a linha de ambiente (modelo, SoC, Android, API), sem reabrir a issue.

---

## Rastreabilidade (passo → critério de aceite)

| Critério de aceite / item do escopo | Passos |
|---|---|
| Escopo 1 — `INTERNET` no manifest principal com comentário ADR-003 e as duas chamadas | Task 3 Step 1, 6 |
| AC1 — `grep INTERNET` no manifest mesclado de release | Task 3 Step 2, 3 (+ Step 5, `aapt2` no APK) |
| Escopo 2 / AC2 — lista fechada verde | Task 2 Step 1–5, 7; Task 3 Step 4 |
| AC2 — sabotagem reprova | Task 3 Step 7, 8, 9; testes `permissão a mais`, `sdk-23` (Task 2 Step 1) |
| AC4 — roda localmente até a #14 | Task 2 Step 5–6 (CLI local, falha alta sem build); lógica no `flutter test` do CI |
| Reprodução (vermelho primeiro) | Task 1 Step 3 (runtime); Task 2 Step 6 (guarda) |
| Escopo 3 — FSM-B até `COMMITTED` com APK release | Task 4 Step 1–2 (AVD, aceito pelo dono no lugar do aparelho) |
| Escopo 3 — modelo com `Range` e SHA-256 | Task 4 Step 3–4 (AVD, aceito pelo dono no lugar do aparelho) |
| Escopo 4 / AC3 — registro em §5 com aparelho e versão | Task 5 Step 1–2 (AVD + versão); fechamento na Task 5 Step 3 |
| Complemento em arm64 real (não é critério) | Task 6, opcional |
| Fora do escopo respeitado | Restrições globais; nenhum passo toca scheduler, backup ou #28 |

## Riscos

- **HTTP sem TLS no release.** O manifest local é `http://127.0.0.1:9000`. Com `targetSdk 36`, o Android bloqueia cleartext por padrão, mas o `HttpClient` do `dart:io` não consulta essa política nas versões atuais do Flutter. Se aparecer `Insecure HTTP is not allowed by platform`, **não** acrescentar `usesCleartextTraffic` (seria mudança de manifest fora do escopo): registrar como achado e servir via o `Caddyfile.dev` com TLS, ou passar `--dart-define=PACK_MANIFEST_URL=https://…` num build só de verificação, anotando isso em §5.16.
- **Tempo do download do modelo** (806 MB pelo emulador): reservar a janela; o passo de interrupção usa o próprio download.
- **Tradução ARM**: instala e abre (verificado), mas a carga do GGUF pelo llama.cpp sob tradução pode falhar ou demorar. Fora do critério; registrar.
