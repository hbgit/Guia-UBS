# Issue 31 — Um único escritor por `.parcial` — Plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar tarefa a tarefa. Passos usam checkbox (`- [ ]`).

**Objetivo:** (a) confirmar ou refutar que o download de primeiro plano e o job do WorkManager escreveram juntos no mesmo `.parcial` do modelo; (b) garantir um único escritor por destino, para que o cenário "perdi rede no setup" termine com o modelo verificado sem recomeçar do zero.

**Arquitetura:** uma trava por destino, em arquivo criado com `exclusive: true` (`O_EXCL`), que exclui também isolates do mesmo processo. O dono mantém a trava viva com batimento (`mtime` renovado). Trava órfã é tomada por dois critérios: dono em processo morto (pid sem `/proc/<pid>`) ou batimento parado. O `ResumableDownloader` toma a trava antes de olhar o disco e a solta depois do `rename`. O primeiro plano espera com a barra de progresso viva; o worker desiste sem tocar no `.parcial`. O agendamento do WorkManager não muda. Um rastro de diagnóstico mínimo (`debugPrint`, sem PII) dá a evidência no `logcat`.

**Stack:** Dart 3 / Flutter 3.44.8, `dart:io`, `dart:isolate`, `workmanager_android` 0.10.7, `adb`, AVD `sinalacs_ci36`.

**Spec:** issue #31 (transcrita no pedido); `spec/arquitetura.md` §5.16 ("Achado fora do escopo: dois escritores no mesmo `.parcial`", l. 1177); `CLAUDE.md` "Offline-only em runtime" e "Background e sync"; ADR-003 (`spec/stack.md` §10).

## Restrições globais

- A verificação de SHA-256 não enfraquece. Nada não conferido assume o nome definitivo, e o `rename` continua sendo o único caminho de aceite.
- A política de rede do WorkManager fica intocada (`model_sync_scheduler.dart`, `_constraintsFrom`, `scheduleModelSync`, `cancelModelSync`). Esta correção não precisa mudar o agendamento (ver "Decisão").
- Mudanças restritas a: `lib/sync/resumable_downloader.dart`, `lib/sync/destination_lock.dart` (novo), `lib/sync/model_background_sync.dart` (construção do downloader), `lib/main.dart` (construção do downloader do primeiro plano) e testes.
- O rastro não leva dado pessoal (INV-2): só rótulo do escritor, tamanhos, offsets, status HTTP e o hash do artefato, que é público e está em `model_catalog.dart`.
- `flutter analyze --fatal-infos` limpo e `flutter test` verde ao fim de cada tarefa que toca Dart (rodar de `app/`).
- Textos, comentários e mensagens em pt-BR. Commits no estilo `tipo(escopo): descrição`, **sem atribuição de IA**.
- Branch: `fix/31-escritor-unico-parcial`, a partir de `main`.
- `$SCRATCH` é um diretório de evidências fora do repositório (`export SCRATCH=$(mktemp -d)`). O que vai para o §5.16 é copiado de lá.

## Estado confirmado no código (2026-10-28)

| Item | Achado | Bate com a issue? |
|---|---|---|
| `resumable_downloader.dart:243-245` | `partial.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write)`, sem trava | sim |
| `resumable_downloader.dart:135` | `resumeFrom` é lido **antes** de qualquer exclusão: dois escritores leem o mesmo N e pedem o mesmo `Range: bytes=N-` | sim; agrava: não é intercalação eventual, é **duplicação garantida** de `total − N` bytes |
| `resumable_downloader.dart:165-167` | divergência de SHA-256 ⇒ `partial.delete()` + `DownloadRejected(digestMismatch)` | sim |
| `resumable_downloader.dart:179-181` | exceção (p.ex. o parcial sumiu sob o perdedor) ⇒ `DownloadInterrupted(bytesSoFar: 0)` | explica o sintoma secundário |
| `main.dart`, listener do setup | `SetupStage.blocked` ⇒ `scheduleModelSync(...)` | sim |
| `model_background_sync.dart` `runModelSyncTask` | `ModelDownloader` com um `ResumableDownloader()` **próprio**, no mesmo destino | sim |
| `workmanager_android-0.10.7/.../BackgroundWorker.kt:101` | `engine = FlutterEngine(applicationContext)`; o manifest do plugin não declara `android:process` | — |
| `BackgroundWorker.kt:200-225, 254-309` | `onStopped()` ⇒ `stopEngine` ⇒ `engine?.destroy()` | — |
| SDK Dart, `lib/io/file.dart:935-940` (`RandomAccessFile.lock`) | *"advisory locks are on a process level. This means that several isolates in the same process can obtain an exclusive lock on the same file."* | — |
| `onboarding_screen.dart:314` | o percentual só aparece com `receivedBytes > 0` | explica "sem percentual" |
| `resumable_downloader.dart:240` | `var received = offset;` — `received` é **absoluto** (já inclui o `resumeFrom`) | — (base do detector de anomalia, Task 1) |
| `resumable_downloader.dart:260` | `sha256.bind(file.openRead())`: hash por stream assíncrono, blocos de leitura de arquivo entregues como eventos separados | — (o batimento dispara entre blocos; Task 5 testa hash lento) |
| `grep -rn "listSync\|\.list(" app/lib` | só `pack_store.dart:138` (`dropUnreferenced`). Nada lista nem limpa `models/`; os únicos `delete` ali são o do `fetch` (destino/parcial) e o do `importFromLocalFile` (destino) | — (achado 4 cobre o único varredor) |
| `model_provisioning.dart:330-331` | só o primeiro plano grava `.verificado`; `runModelSyncTask` **não** grava marcador | corrige uma suposição da revisão: o re-hash do primeiro plano depois do worker não ignora um marcador — ele nunca existiu ali |

**O worker roda no mesmo processo do app, em outro isolate (outro `FlutterEngine`).** Toda a escolha da correção parte disso.

### Divergências e achados além da issue

1. **`RandomAccessFile.lock` não serve.** A issue o lista como opção, mas a documentação do próprio SDK diz que dois isolates do mesmo processo obtêm o mesmo lock exclusivo, e o worker é exatamente isso. No Android o `fcntl` do bionic tem a mesma semântica por processo. A Task 4 começa com um experimento descartável que confirma isso no host, e o resultado vai para o §5.16.
2. **Há um caminho pior que o descrito na issue.** Se o escritor A conferir e fizer `rename` enquanto B ainda tem o descritor aberto em append, B continua anexando bytes **ao arquivo definitivo**, que já passou pela verificação. O marcador `.verificado` (tamanho + mtime) acusaria na abertura seguinte, mas entre o `rename` e o marcador há uma janela em que o modelo final contém bytes não conferidos. Hoje é só teórico, mas viola a restrição "nada não conferido chega ao disco como modelo final". A trava cobre esse caminho, porque o `rename` acontece dentro da seção crítica, e o teste verde confere o SHA do arquivo final **depois** que os dois escritores terminam.
3. **O mesmo defeito existe no pack, e com consequência pior.** `sync_service.dart:330` usa o mesmo downloader. O ciclo de primeiro plano (`didChangeAppLifecycleState`) e o job de pack podem baixar o mesmo `pack-<sha>.db.parcial`. Uma divergência ali vira `digestMismatch`, e a FSM-B (linha B10) **põe na blacklist um pack legítimo**. A trava no componente compartilhado cobre o caso. Para não mudar o comportamento do pack além disso, a espera padrão é zero: o perdedor desiste com `DownloadInterrupted`, que hoje conta no circuito. Isso é melhor que blacklistar, mas ainda conta como falha um adiamento, e fica como candidato a issue própria.
4. **`PackStore.dropUnreferenced` apagaria a trava de pack** se ela se chamasse `pack-….trava`. O filtro `startsWith('pack-')` + `replaceAll('.parcial'/'.db')` não remove o sufixo `.trava`, e o hash resultante nunca bate com `keep` (`pack_store.dart:133-153`). Por isso o nome da trava começa com ponto: `.<nome-do-destino>.trava`. Há teste para isso.
5. **`importFromLocalFile` é um terceiro escritor.** O método copia para `<destino>.parcial` **fora** do `fetch` (`model_provisioning.dart:406-408`), sem passar pela trava. Corrigir isso muda `model_provisioning.dart`, que fica fora do perímetro "downloader e agendamento". **Recomendo uma issue separada**, e não está no escopo deste plano.
6. **Forçar job periódico pode ser adiado.** O §5.16 registrou *"being executed before schedule"* ao forçar o job de pack. O roteiro da Task 6 prevê isso: o disparo natural ao sair do modo avião (restrição de rede satisfeita) é o mesmo gatilho que, ao que tudo indica, rodou o worker às 17:06:56 no incidente.

## Decisão: trava em arquivo exclusivo, sem mexer no agendamento

| Opção | Exclui o worker (outro isolate, mesmo processo)? | Cobre "worker já rodando quando o usuário toca"? | Trava órfã | Veredito |
|---|---|---|---|---|
| `RandomAccessFile.lock` | **não** (por processo; SDK `file.dart:935-940`) | — | o kernel solta ao morrer o processo, mas não ao morrer o isolate | rejeitada |
| `cancelByUniqueName` ao iniciar o primeiro plano + reagendar ao falhar | só se o cancelamento chegar antes da 1ª escrita | **não**: `onStopped` ⇒ `engine.destroy()` mata o isolate no meio do `sink.add`, sem `finally`; não há garantia de ordem entre o `destroy` e a abertura do `.parcial` pelo primeiro plano | — | rejeitada sozinha: não dá exclusão, só reduz a chance |
| Trava em arquivo `O_EXCL` + batimento + pid | **sim** (`O_EXCL` é atômico no sistema de arquivos, independe de isolate e de processo) | **sim**: o primeiro plano espera; o worker desiste | pid morto ⇒ tomada imediata; isolate morto ⇒ batimento para ⇒ tomada após `staleAfter` | **adotada** |
| Trava + cancelamento | sim | sim | o cancelamento **cria** trava órfã (isolate destruído), forçando o primeiro plano a esperar `staleAfter` | rejeitada: piora a latência e mexe no agendamento sem ganho de correção |

**Por que esperar no primeiro plano e desistir no worker.** O usuário está olhando a tela. Se o worker já baixa, a melhor resposta é mostrar o progresso dele (o `.parcial` cresce, e o `onProgress` reporta o tamanho em disco enquanto espera) e aceitar o arquivo quando ele terminar: o `fetch` do primeiro plano, ao obter a trava, encontra o destino pronto e só confere o hash. Se o worker cair, a trava é solta e o primeiro plano **continua do offset em disco** via `Range`. O worker que perde desiste com `DownloadInterrupted`, `runModelSyncTask` devolve `false`, e o WorkManager reagenda com o backoff que já existe. O agendamento não muda.

**Correção ≠ eficiência.** O SHA-256 continua sendo a garantia de integridade. A trava existe para não baixar 800 MB duas vezes. O limite conhecido dela fica documentado no código: dois candidatos que julgam órfã a **mesma** trava no **mesmo** microssegundo podem, em tese, ambos tomá-la. A cerca (`isHeld`, conferido a cada bloco e antes do `rename`) derruba o perdedor no batimento seguinte, e o SHA-256 cobre o resto. Isso exige dono morto e dois disputantes simultâneos.

## Revisão: onde a especificação silencia

1. **Escritor B anexando depois do `rename` de A** altera o modelo já aceito. Teste: `dois escritores no mesmo destino…` confere `sha256(destino) == esperado` depois dos dois `fetch` terminarem (Task 5).
2. **Isolate do dono destruído com a trava ativa** (`engine.destroy()` no `onStopped`). Teste: `trava de isolate morto é tomada só depois de staleAfter` (Task 4).
3. **App reaberto após crash** encontra trava de pid morto, e o usuário não pode esperar `staleAfter`. Teste: `trava de processo morto é tomada na hora` (Task 4).
4. **Dono vivo e lento** (rede parada até o `idleTimeout` de 30 s, SHA de ~12 s em Dart puro) não pode ser tratado como órfão. Teste: `batimento mantém a trava viva além de staleAfter, entre isolates` (Task 4).
5. **Dono calculando o SHA-256 por mais que `staleAfter`** (806 MB em Dart puro sob `libndk_translation` ou em aparelho de entrada). O batimento só dispara se o hash ceder o event loop entre blocos. Se não ceder, o outro escritor toma a trava de um dono vivo, refaz o hash e pede `Range: bytes=<total>-`, que pode voltar 416 e descartar o parcial. Teste: `dono com hash mais lento que staleAfter mantém a trava` (Task 5), e o tempo do hash vai para o rastro e é medido no emulador (Task 6).
6. **Trava usurpada entre o último bloco e o `rename`.** A cerca por bloco não vê isso, só o `confirmHeld()`. Teste: `trava usurpada durante o hash: não renomeia` (Task 5).
7. **Falha ao criar a trava** (disco cheio, diretório sem escrita) não pode virar "escreve sem trava". Teste: `sem trava, nada é escrito` (Task 5).
8. **Disputa no pack** deixa de terminar em blacklist (B10) e passa a terminar em B7, que conta no circuito. Teste: `trava ocupada no pack: B7, sem blacklist` (Task 5). O "adiamento contando como falha" vira issue própria na Task 5.
9. **Worker que roda depois de o primeiro plano concluir** precisa devolver sucesso sem rede, e não entrar em retry indefinido. Teste: `destino já verificado: worker conclui sem rede` (Task 5).

---

## Mapa de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `app/lib/sync/destination_lock.dart` (novo) | `DestinationLock` e `LockTiming`: aquisição exclusiva, batimento, cerca, detecção de órfã, liberação. Sem HTTP. |
| `app/lib/sync/resumable_downloader.dart` | toma a trava em volta de todo o `fetch`; rastro de diagnóstico; espera com progresso; cerca por bloco e antes do `rename`. |
| `app/lib/sync/model_background_sync.dart` | worker constrói `ResumableDownloader(writerLabel: 'worker', trace: debugPrint)`, com espera zero (padrão). |
| `app/lib/main.dart` | primeiro plano injeta `ResumableDownloader(writerLabel: 'primeiro-plano', trace: debugPrint, writerWait: Duration(minutes: 30))` no `ModelProvisioning`. |
| `app/test/sync/destination_lock_test.dart` (novo) | exclusão entre isolates, órfãs, cerca, liberação, convivência com `dropUnreferenced`. |
| `app/test/sync/resumable_downloader_test.dart` | `_FakeOrigin` ganha intercalação forçada e contadores; testes de dois escritores (mesmo isolate e `Isolate.spawn`), rastro, espera e desistência. |
| `spec/arquitetura.md` §5.16 | causa confirmada, correção, resultado em emulador. |
| `CLAUDE.md` "Background e sync" | um item: `lock()` do Dart não exclui isolates; um escritor por destino é trava `O_EXCL`. |

---

### Task 1: Rastro de diagnóstico no downloader (sem mudar comportamento)

**Files:**
- Modify: `app/lib/sync/resumable_downloader.dart` (construtor, `fetch`, `_download`)
- Modify: `app/lib/sync/model_background_sync.dart` (construção do downloader)
- Modify: `app/lib/main.dart` (construção do `ModelProvisioning`)
- Test: `app/test/sync/resumable_downloader_test.dart`

**Interfaces:**
- Produces:
  - `typedef DownloadTrace = void Function(String line);`
  - `ResumableDownloader({HttpClient? client, Duration idleTimeout, Duration connectTimeout, String writerLabel = '?', DownloadTrace? trace})`.
  - Linhas, sempre com o prefixo `gubs-dl w=<writerLabel> ` (são o contrato com o `grep` do `logcat` das Tasks 3 e 6):
    - `inicio off=<resumeFrom> destino=<basename>`
    - `http status=<code> range=<resumeFrom ou ->`
    - `progresso recebidos=<received> disco=<partial.lengthSync()>` a cada 64 MiB (`1 << 26`) recebidos
    - `ANOMALIA recebidos=<received> disco=<len>`, emitida **uma vez por fetch**, quando, depois de um `sink.add`, `partial.lengthSync() > received`. Aqui `received` é o **total absoluto** esperado no disco, ou seja, `offset + bytes desta resposta`: é como o código já conta (`var received = offset;`, l. 240), e o implementador **não** pode trocar por um contador só da requisição, porque a condição viraria verdadeira em toda retomada. Equivalente explícito: `disco > offset + bytesDestaResposta`. O buffer do `IOSink` só deixa o disco **atrás** desse total; o disco à frente é prova de outro escritor.
    - `sha ok bytes=<n> ms=<duração do hash>` / `sha divergente bytes=<n> ms=<…>` (o tempo alimenta a escolha de `staleAfter`, ver Revisão 5)
    - `fim desfecho=<Completed|Interrupted|Rejected> bytes=<n>`

- [ ] **Step 0: Branch**

```bash
git switch main && git pull && git switch -c fix/31-escritor-unico-parcial
```

- [ ] **Step 1: Testes que falham**

Em `resumable_downloader_test.dart`, grupo `rastro`, com `ResumableDownloader(writerLabel: 't', trace: lines.add, …)`:
- `retomada registra o offset de partida`: semeia `.parcial` com 4096 bytes; após `fetch`, `lines` contém `'gubs-dl w=t inicio off=4096 destino=m.gguf'`, um item que começa com `'gubs-dl w=t sha ok'` e `'gubs-dl w=t fim desfecho=Completed bytes=${payload.length}'`.
- `download solitário não acusa anomalia`: download completo, sem `.parcial` prévio; nenhum item contém `'ANOMALIA'`.
- `retomada solitária não acusa anomalia`: `.parcial` semeado com 4096 bytes, um único `fetch` até o fim; nenhum item contém `'ANOMALIA'`. É este teste que pega um detector que compara o disco com os bytes só desta requisição.
- `sha registra a duração`: o item `sha ok` casa com `RegExp(r'^gubs-dl w=t sha ok bytes=\d+ ms=\d+$')`.
- `hash divergente aparece no rastro`: `expectedSha256: '00'*32`; há um item que começa com `'gubs-dl w=t sha divergente'` e `fim desfecho=Rejected`.

- [ ] **Step 2: Rodar e ver falhar**

Run (de `app/`): `flutter test test/sync/resumable_downloader_test.dart --plain-name rastro`
Expected: erro de compilação, porque `writerLabel`/`trace` não existem.

- [ ] **Step 3: Implementar**

Em `ResumableDownloader`: campos `writerLabel` e `trace`, e `void _t(String s) => trace?.call('gubs-dl w=$writerLabel $s');`. O `fim` é emitido num único ponto, envolvendo o corpo atual de `fetch` (renomear o corpo para `_fetchUnlocked` já prepara a Task 5). A checagem de anomalia vai no `forEach` de `_download`, depois de `sink.add(chunk)`.

Wiring:
- `model_background_sync.dart`: `ModelDownloader(…, downloader: ResumableDownloader(writerLabel: 'worker', trace: debugPrint))` (`import 'package:flutter/foundation.dart' show debugPrint;`).
- `main.dart`: `ModelProvisioning(…, downloader: ResumableDownloader(writerLabel: 'primeiro-plano', trace: debugPrint))`.

`debugPrint` chega ao `logcat` (`I flutter`) também em release; `dart:developer.log` não chega.

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/sync/ && flutter analyze --fatal-infos`
Expected: tudo verde; a suíte antiga do downloader inalterada.

- [ ] **Step 5: Commit**

```bash
git add app/lib/sync/resumable_downloader.dart app/lib/sync/model_background_sync.dart app/lib/main.dart app/test/sync/resumable_downloader_test.dart
git commit -m "feat(sync): rastro de diagnostico do download retomavel (sem PII)"
```

---

### Task 2: Reprodução determinística (vermelho)

**Files:**
- Modify: `app/test/sync/resumable_downloader_test.dart` (`_FakeOrigin` + grupo `dois escritores`)

**Interfaces:**
- Consumes: `ResumableDownloader(writerLabel:, trace:)` da Task 1; **só a API que já existe** em `fetch`, para que o teste compile e fique vermelho em runtime.
- Produces (no `_FakeOrigin`):
  - `int inFlight`, `int maxConcurrent`, `int bytesServed`, `List<String?> ranges`
  - `bool interleave`: quando ligado, cada resposta (1) espera `Future.any([_twoInFlight.future, Future.delayed(const Duration(seconds: 1))])`, o que garante a sobreposição sem travar quando houver só um cliente; (2) envia o corpo em blocos de 4 KiB, com `await request.response.flush()` e `await Future<void>.delayed(Duration.zero)` entre blocos, o que força a alternância.
  - Payload deste grupo: 256 KiB determinísticos (`List<int>.generate(1 << 18, (i) => (i * 31) & 0xff)`), `.parcial` semeado com os primeiros 64 KiB.

- [ ] **Step 1: Escrever os testes**

`group('dois escritores no mesmo destino', …)`, cada teste com `origin.interleave = true` e dois downloaders (`writerLabel: 'a'` e `'b'`, `trace` num `lines` compartilhado):

1. `mesmo isolate: um baixa, o outro aceita o mesmo arquivo`. `Future.wait([a.fetch(...), b.fetch(...)])` no mesmo `destination`. Asserções:
   - os dois desfechos são `DownloadCompleted`;
   - `sha256.convert(destination.readAsBytesSync()).toString() == goodHash`, conferido **depois** dos dois terminarem (achado 2);
   - `File('${destination.path}.parcial').existsSync()` é `false`;
   - `origin.maxConcurrent == 1`;
   - `origin.bytesServed == payload.length - 65536`: nada baixado em dobro, nada recomeçado do zero;
   - `origin.ranges` não contém `null` nem `'bytes=0-'`;
   - nenhum item de `lines` contém `'ANOMALIA'`.
2. `outro isolate (Isolate.spawn): mesmas garantias`. O escritor `b` roda em `Isolate.spawn(_fetchInIsolate, [sendPort, url.toString(), destination.path, goodHash])`, uma função top-level que cria seu próprio `ResumableDownloader`, faz o `fetch` e devolve pelo `SendPort` o `runtimeType.toString()` do desfecho e as linhas do rastro dela. Mesmas asserções do teste 1.

**Por que os dois.** O defeito aparece já no mesmo isolate: são dois descritores em append, e o laço de eventos intercala. Por isso o teste 1 é o vermelho mais barato. O teste 2 existe para a correção: uma "trava" guardada em memória (campo estático, `Set`) passaria no teste 1 e falharia no aparelho, porque o worker é outro isolate. Com `Isolate.spawn` a estática não é compartilhada, e só uma exclusão no sistema de arquivos passa.

- [ ] **Step 2: Rodar e ver falhar, guardando a saída**

Run: `flutter test test/sync/resumable_downloader_test.dart --plain-name "dois escritores" 2>&1 | tee "$SCRATCH/31-vermelho.txt"`
Expected: os 2 testes FALHAM. Esperado no texto: pelo menos um desfecho `DownloadRejected` (`SHA-256 nao confere`) ou `DownloadInterrupted` (parcial sumiu sob o perdedor), `maxConcurrent` 2 e `ANOMALIA` no rastro. Copie as linhas `gubs-dl` do arquivo: elas são a prova do mecanismo em host e vão para o §5.16.

**Regra do portão (única):** este vermelho de host é o que **libera a correção** (Tasks 4–5). Ele prova que o defeito existe no código, independentemente de ter sido ele o responsável pelo incidente. A Task 3 diz se foi a causa do incidente e o resultado vai para o §5.16, mas ela só bloqueia o plano se der **refutada**.

Se os testes **passarem** aqui, o mecanismo não se reproduz no host. Pare, abra `superpowers:systematic-debugging` e reporte antes de seguir.

- [ ] **Step 3: Não commitar ainda**

O vermelho fica registrado em `$SCRATCH/31-vermelho.txt`. O teste entra no commit da Task 5 junto com a correção, para o CI da branch não ficar vermelho entre commits.

---

### Task 3: Confirmar a causa no emulador (build sem correção, com rastro)

Esta task não muda código: é o build da Task 1, ainda sem trava, reproduzindo o incidente.

**Files:** nenhum (evidência em `$SCRATCH/31-causa-logcat.txt`).

- [ ] **Step 1: Build e instalação**

```bash
cd app && flutter build apk --release --target-platform=android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb root && adb shell pm clear br.gov.exemplo.guia_ubs
adb logcat -c && adb logcat -v time flutter:I WM-WorkerWrapper:I '*:S' | tee "$SCRATCH/31-causa-logcat.txt"   # em outro terminal
```

- [ ] **Step 2: Reproduzir**

Siga o roteiro A da Task 6, passos 2 a 6, sobre este build.

- [ ] **Step 3: Julgar**

Três desfechos, e a sobreposição define qual se aplica:

- **Confirmada:** há sobreposição (linhas `inicio` de `w=primeiro-plano` **e** de `w=worker` sem `fim` entre elas) **e** `ANOMALIA` e/ou `sha divergente`, e o parcial some (`fim desfecho=Interrupted bytes=0` ou `Rejected`).
- **Inconclusiva:** não houve sobreposição. O job não disparou, ou disparou depois do `fim`. Isso diz só que a reprodução não aconteceu, não que a hipótese é falsa. Repita até **3 vezes**, alternando os roteiros A e B da Task 6. Persistindo, registre "inconclusiva no emulador; mecanismo provado em host (Task 2)" no §5.16 e **siga** para a Task 4.
- **Refutada:** há sobreposição **sem** `ANOMALIA` **e sem** `sha divergente`, e mesmo assim o parcial some. Então a causa é outra. Pare, registre as linhas no §5.16, abra `superpowers:systematic-debugging` e reporte antes da Task 4.

Regra do portão: a da Task 2. O vermelho de host libera a correção; só "refutada" bloqueia.

---

### Task 4: `DestinationLock`

**Files:**
- Create: `app/lib/sync/destination_lock.dart`
- Test: `app/test/sync/destination_lock_test.dart`

**Interfaces:**
- Produces:

```dart
@immutable
class LockTiming {
  const LockTiming({
    this.staleAfter = const Duration(seconds: 60),
    this.heartbeat = const Duration(seconds: 10),
    this.poll = const Duration(milliseconds: 500),
  });
  final Duration staleAfter, heartbeat, poll;
}

final class DestinationLock {
  /// `<dir>/.<basename>.trava`. Começa com ponto: ver achado 4 (dropUnreferenced).
  static File fileFor(File destination);

  /// `null` se não obteve dentro de [wait]. Lança só erro de E/S que não seja
  /// "já existe" (o chamador trata como interrupção — nunca escreve sem trava).
  static Future<DestinationLock?> acquire(
    File destination, {
    Duration wait = Duration.zero,
    LockTiming timing = const LockTiming(),
    void Function()? onWaiting,          // a cada `poll` enquanto espera
    void Function(String event)? onEvent, // 'aguardando dono=<pid:token6>' (1x), 'orfa tomada motivo=pid|batimento'
  });

  /// `false` assim que o batimento descobrir que o arquivo não é mais nosso (cerca).
  bool get isHeld;

  /// Releitura síncrona do arquivo: ainda é nosso? Usado antes do `rename`.
  bool confirmHeld();

  /// Para o batimento e apaga o arquivo SÓ se o conteúdo ainda for o nosso.
  Future<void> release();
}
```

Conteúdo do arquivo: `'$pid:$token'`. O `pid` vem de `dart:io` e o `token` são 16 bytes de `Random.secure()` em hex.

**Algoritmo de `acquire`** (os testes não o determinam por inteiro):

```
prazo = agora + wait
laço:
  tenta File.create(exclusive: true); grava conteúdo com flush; inicia Timer.periodic(heartbeat) → devolve
  em PathExistsException:
    lê conteúdo e stat.modified
    órfã se  (pid ≠ pid atual  E  /proc existe  E  /proc/<pid> não existe)
          ou (agora − modified > staleAfter)
    se órfã: relê; se conteúdo E modified iguais aos lidos → delete; volta ao laço SEM dormir
    se agora ≥ prazo → devolve null
    onWaiting?.call(); dorme poll
batimento: lê o arquivo; se ≠ nosso conteúdo → isHeld = false, cancela o timer; senão setLastModifiedSync(agora)
```

Conteúdo vazio ou ilegível (janela entre `create` e a gravação) conta só pelo critério de `mtime`.

- [ ] **Step 1: Experimento descartável: `RandomAccessFile.lock` entre isolates**

Script em `$SCRATCH/lock_spike.dart`. O isolate principal faz `open(mode: FileMode.write)` + `lock(FileLock.exclusive)` e mantém. Um `Isolate.spawn` tenta `lock(FileLock.exclusive)` (não bloqueante) no mesmo arquivo e devolve se conseguiu.
Run: `dart run "$SCRATCH/lock_spike.dart"`
Expected: o segundo isolate **consegue** o lock, confirmando `file.dart:935-940`. Anote a saída para o §5.16. Não vai para o repositório.

- [ ] **Step 2: Testes que falham**

Em `destination_lock_test.dart`, com `timing = LockTiming(staleAfter: 300ms, heartbeat: 50ms, poll: 20ms)`:

1. `exclui outro isolate enquanto o dono vive`: um `Isolate.spawn` adquire, sinaliza e segura. O principal chama `acquire(wait: 200ms)` e recebe `null`.
2. `batimento mantém a trava viva além de staleAfter, entre isolates`: como o 1, mas com `wait: 900ms` (3× `staleAfter`), e o resultado continua `null`. Depois o isolate chama `release()`, e o principal adquire com `wait: 500ms` (não nulo).
3. `trava de isolate morto é tomada só depois de staleAfter`: o isolate adquire e é morto com `Isolate.kill(priority: Isolate.immediate)`. O principal adquire com `wait: 2s`, e o tempo decorrido (`Stopwatch`) fica `>= 200ms` e `< 2s`.
4. `trava de processo morto é tomada na hora`: grava à mão `'999999999:deadbeef'` em `fileFor(dest)` com `mtime` atual. `acquire(wait: Duration.zero)` não é nulo, e `onEvent` recebeu `'orfa tomada motivo=pid'`.
5. `trava velha é tomada`: conteúdo `'$pid:outro'` com `setLastModifiedSync(now - 1s)`. `acquire()` não é nulo, com `motivo=batimento`.
6. `cerca: dono que perdeu o arquivo sabe disso`: adquire, sobrescreve o arquivo com outro conteúdo e espera 120 ms. `isHeld == false` e `confirmHeld() == false`.
7. `release não apaga trava alheia`: adquire, sobrescreve com outro conteúdo e chama `release()`. O arquivo continua existindo, com o conteúdo alheio.
8. `release libera para o próximo`: adquire e solta. `fileFor(dest).existsSync() == false` e um novo `acquire()` não é nulo.
9. `trava de pack sobrevive a dropUnreferenced`: `PackStore(dir)` e `dest = store.packFile('ab'*32)`. Adquire e chama `store.dropUnreferenced(keep: 'cd'*32)`. `fileFor(dest).existsSync() == true`.

- [ ] **Step 3: Rodar e ver falhar**

Run: `flutter test test/sync/destination_lock_test.dart`
Expected: erro de compilação (`destination_lock.dart` não existe).

- [ ] **Step 4: Implementar `destination_lock.dart`**

O comentário de cabeçalho no estilo do repositório deve dizer quatro coisas:
- por que não se usa `RandomAccessFile.lock` (citar o SDK);
- por que o batimento existe (`engine.destroy()` mata o isolate sem `finally`);
- qual é o limite conhecido da tomada simultânea, coberto pela cerca e pelo SHA-256;
- **por que o critério de pid é confiável no Android.** O `/proc` é montado com `hidepid`, mas processos do **mesmo UID** continuam visíveis. Então um pid do próprio app vivo sempre aparece, e um ausente está morto ou foi reusado por outro UID, que é invisível e, para nós, equivale a morto. Sem `/proc` (outro SO), o critério se desliga e vale só o batimento.

- [ ] **Step 5: Rodar e ver passar**

Run: `flutter test test/sync/destination_lock_test.dart && flutter analyze --fatal-infos`
Expected: 9 testes verdes, análise limpa.

- [ ] **Step 6: Commit**

```bash
git add app/lib/sync/destination_lock.dart app/test/sync/destination_lock_test.dart
git commit -m "feat(sync): trava de escritor unico por destino, entre isolates"
```

---

### Task 5: Integrar a trava no `ResumableDownloader` (vermelho → verde)

**Files:**
- Modify: `app/lib/sync/resumable_downloader.dart`
- Modify: `app/lib/main.dart` (só `writerWait` no downloader do primeiro plano)
- Test: `app/test/sync/resumable_downloader_test.dart`
- Test: `app/test/sync/sync_service_test.dart` (disputa no pack)

**Interfaces:**
- Consumes: `DestinationLock`, `LockTiming` (Task 4); rastro (Task 1); testes da Task 2.
- Produces:
  - `ResumableDownloader({…, Duration writerWait = Duration.zero, LockTiming lockTiming = const LockTiming(), @visibleForTesting Future<String> Function(File file)? digestOf})`. `digestOf` substitui `_sha256Of` quando informado e existe só para os testes de hash lento e de usurpação durante o hash.
  - `fetch`: (1) chama `DestinationLock.acquire(destination, wait: writerWait, timing: lockTiming, onWaiting: …, onEvent: (e) => _t('trava $e'))`; (2) se o resultado for `null`, faz `_t('trava ocupada desiste')` e devolve `DownloadInterrupted(bytesSoFar: <tamanho do .parcial ou 0>, reason: 'outro escritor ativo neste destino')`, **sem abrir nem apagar o `.parcial`**; (3) com a trava, `_t('trava obtida espera=<ms>')` e roda o corpo atual (`_fetchUnlocked`) **inteiro**, desde `destination.existsSync()` até o `rename`, para que `resumeFrom` seja lido já com exclusão; (4) `release()` no `finally`.
  - `onWaiting`: se o `.parcial` existir, `onProgress?.call(partial.lengthSync(), fallbackTotalBytes)`, o que mantém o percentual na tela enquanto o outro escritor trabalha.
  - Cerca: no `forEach` de `_download`, `if (!lock.isHeld) throw StateError('trava perdida')`, que cai no `catch` ⇒ `DownloadInterrupted`. Antes de **cada** `rename` (os dois que existem), `if (!lock.confirmHeld())` ⇒ `DownloadInterrupted` sem renomear.
  - Erro ao criar a trava ⇒ cai no `catch` existente ⇒ `DownloadInterrupted`. Nunca escreve sem trava.
  - `main.dart`: `ResumableDownloader(writerLabel: 'primeiro-plano', trace: debugPrint, writerWait: const Duration(minutes: 30))`. O worker (`model_background_sync.dart`) e o `SyncService` ficam com o padrão `Duration.zero`.

- [ ] **Step 1: Testes novos que falham**

No mesmo arquivo, grupo `escritor unico`:
1. `quem desiste não toca no parcial`: segura a trava com `DestinationLock.acquire(dest)` no teste e chama `fetch` com `writerWait: Duration.zero`. O desfecho é `DownloadInterrupted`, com `reason` contendo `'outro escritor'`, `bytesSoFar == 65536`; o tamanho e o `mtime` do `.parcial` ficam iguais; `origin.requestCount == 0`.
2. `quem espera retoma do offset em disco`: `_FakeOrigin` ganha `bool cutFirstRequestOnly`, e com ele ligado `cutAfterBytes = 32768` vale só para a 1ª requisição. O escritor A dispara primeiro. O B (`writerWait: 5s`) só é disparado depois do 1º `onProgress` de A, o que garante que A detém a trava. A termina `DownloadInterrupted` e B termina `DownloadCompleted`. `origin.ranges == ['bytes=65536-', 'bytes=98304-']`, e o hash final confere.
3. `espera reporta progresso do parcial alheio`: segura a trava no teste, dispara `fetch(writerWait: 1s, onProgress: calls.add…)` e solta depois de 100 ms. `calls` contém `(65536, payload.length)` antes de qualquer valor maior.
4. `sem trava, nada é escrito`: diretório de destino com `chmod 0555` (`Process.runSync('chmod', …)`). O desfecho é `DownloadInterrupted`, sem `.parcial` e com `origin.requestCount == 0`. Restaure `0755` no `tearDown`. Use `skip` em duas situações:
   - fora do Linux;
   - quando `Process.runSync('id', ['-u']).stdout.toString().trim() == '0'`, porque root ignora o `0555`, e containers de CI costumam rodar como root.
5. `cerca: trava perdida no meio interrompe sem renomear`: `origin.interleave = true`. Após o 1º `onProgress`, o teste sobrescreve `DestinationLock.fileFor(dest)` com conteúdo alheio. O desfecho é `DownloadInterrupted` e `destination.existsSync() == false`. Use `LockTiming(heartbeat: 20ms, …)` no downloader.
6. `trava usurpada durante o hash: não renomeia`: `LockTiming(heartbeat: 10s)`, para que o batimento não perceba antes e só o `confirmHeld()` possa pegar. O `digestOf` sobrescreve `DestinationLock.fileFor(dest)` com conteúdo alheio e devolve o hash **correto**. O desfecho é `DownloadInterrupted`, com `destination.existsSync() == false` e o `.parcial` intacto.
7. `dono com hash mais lento que staleAfter mantém a trava`: o downloader A usa `LockTiming(staleAfter: 300ms, heartbeat: 50ms)` e um `digestOf` que faz `await Future<void>.delayed(const Duration(milliseconds: 900))` (3× `staleAfter`, cedendo o event loop como o hash real cede) e depois devolve o hash verdadeiro. Durante esse intervalo, `DestinationLock.acquire(dest, wait: 600ms, timing: mesmo LockTiming)` no teste devolve `null`. A termina `DownloadCompleted`.
8. `destino já verificado: worker conclui sem rede`: destino válido já em disco e downloader com a configuração do worker (`writerWait: Duration.zero`). O desfecho é `DownloadCompleted` e `origin.requestCount == 0`. No `model_downloader_test.dart`, o equivalente (`ModelReady`, zero requisições) confere que `runModelSyncTask` devolveria `true`, e não retry.

No `sync_service_test.dart`, grupo `falhas de rede e circuito`:

9. `trava ocupada no pack: B7, sem blacklist`: segura `DestinationLock.acquire(store.packFile(packV1Hash))` no teste e chama `service.runCycle()`. Asserções:
   - `report.state == SyncState.f1Retryable`;
   - `report.rules` contém um item `startsWith('B7')`;
   - `await store.isPackRejected(packV1Hash)` é `false`;
   - `store.packFile(packV1Hash).existsSync()` é `false`;
   - `await store.loadActive()` é `null`.

   O teste registra o comportamento atual: a disputa conta no circuito (`incrementCircuitCounter` da B7). O comentário do teste cita a issue aberta no Step 7.

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/sync/resumable_downloader_test.dart --plain-name "escritor unico"`
Expected: erro de compilação (`writerWait`/`lockTiming`).

- [ ] **Step 3: Implementar** conforme o bloco Interfaces.

Nos testes da Task 2, os downloaders `b` (e o do isolate) passam a usar `writerWait: const Duration(seconds: 5)`. A espera faz parte do contrato verificado, não é afrouxamento: com espera zero, o certo é `b` desistir, e isso é o teste 1 acima.

- [ ] **Step 4: Verde**

Run: `flutter test test/sync/ 2>&1 | tee "$SCRATCH/31-verde.txt" && flutter analyze --fatal-infos`
Expected: os grupos `dois escritores` (Task 2) e `escritor unico` passam, e a suíte de sync inteira (incluindo `sync_service_test` e `model_provisioning_test`) continua verde.

- [ ] **Step 5: Sabotagem (cada uma precisa reprovar; reverta logo depois de cada uma)**

| # | Edição exata | Deve reprovar |
|---|---|---|
| S1 | em `destination_lock.dart`, `create(exclusive: true)` → `create(exclusive: false)` | `dois escritores…` (os 2), `exclui outro isolate…`, `quem desiste…` |
| S2 | em `resumable_downloader.dart`, apagar a linha `if (!lock.isHeld) throw StateError('trava perdida');` | `cerca: trava perdida no meio…` |
| S3 | em `destination_lock.dart`, o corpo do batimento vira `{}` | `batimento mantém a trava viva…` |
| S4 | em `destination_lock.dart`, remover o critério de pid da órfã | `trava de processo morto é tomada na hora` |
| S5 | em `destination_lock.dart`, `release()` apaga o arquivo sem conferir o conteúdo | `release não apaga trava alheia` |
| S6 | em `resumable_downloader.dart`, apagar o `if (!lock.confirmHeld())` antes do `rename` do caminho com rede | `trava usurpada durante o hash: não renomeia` |
| S7 | em `resumable_downloader.dart`, no ramo `trava ocupada desiste`, acrescentar `if (partial.existsSync()) await partial.delete();` antes do `return` | `quem desiste não toca no parcial` |

Run, após cada edição: `flutter test test/sync/ 2>&1 | tail -5`, que deve mostrar falha. Depois `git checkout -- app/lib/sync/` e de novo `flutter test test/sync/`, que deve ficar verde. Guarde as 7 saídas em `$SCRATCH/31-sabotagem.txt`. Commite **antes** de sabotar, para que o `git checkout` não apague trabalho.

- [ ] **Step 6: Commit** (antes do Step 5)

```bash
git add app/lib/sync/resumable_downloader.dart app/lib/main.dart app/test/sync/resumable_downloader_test.dart app/test/sync/model_downloader_test.dart app/test/sync/sync_service_test.dart
git commit -m "fix(sync): um unico escritor por .parcial; primeiro plano espera, worker desiste (#31)"
```

- [ ] **Step 7: Abrir as duas issues derivadas (precisa do OK do dono antes, porque é publicação externa)**

```bash
gh issue create --title "sync: disputa de escritor no pack conta como falha no circuito da FSM-B" \
  --body "Desde a #31, um pack com trava ocupada termina em B7 (F1, incrementCircuitCounter). Adiar por outro escritor nao e falha de rede, como o adiamento por triagem (B11). Teste que fixa o comportamento atual: sync_service_test 'trava ocupada no pack: B7, sem blacklist'."
gh issue create --title "model: importFromLocalFile escreve o .parcial fora da trava de escritor unico" \
  --body "model_provisioning.dart:406-408 copia para <destino>.parcial sem DestinationLock. Com a #31 em vigor, e o unico escritor sem exclusao: um worker em append no mesmo .parcial corromperia a copia (o SHA-256 recusa, mas o usuario perde o download)."
```

Anote os dois números. Eles entram no comentário do teste 9, no §5.16 (Task 7) e no corpo do PR. A #31 não fecha sem eles.

---

### Task 6: Verificação no emulador

**Files:** nenhum (evidência em `$SCRATCH/31-emulador-*.txt`).

Ambiente de referência, o mesmo do §5.16: AVD `sinalacs_ci36`, `system-image android-36 google_apis x86_64` (userdebug), APK release arm64-v8a sob `libndk_translation`, modelo do Hugging Face (`model_catalog.dart`). O espelho precisa ser remoto: com servidor local via `adb reverse`, o modo avião não corta o download.

- [ ] **Step 1: Build, instalação e registro do ambiente**

```bash
cd app && flutter build apk --release --target-platform=android-arm64
# Se falhar com "dev.flutter.plugins.integration_test does not exist": apagar
# android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java e repetir.
sha256sum build/app/outputs/flutter-apk/app-release.apk; git rev-parse --short HEAD
adb shell getprop ro.build.version.sdk; adb shell getprop ro.product.cpu.abilist
adb shell getprop ro.dalvik.vm.native.bridge; emulator -version | head -1
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb root && adb shell pm clear br.gov.exemplo.guia_ubs
adb logcat -c && adb logcat -v time flutter:I WM-WorkerWrapper:I WM-DiagnosticsWrkr:I '*:S' | tee "$SCRATCH/31-emulador-A.txt"
```

Atalhos usados abaixo: `M=/data/data/br.gov.exemplo.guia_ubs/files/models` e `P=$M/gemma-3-1b-q4.gguf.parcial`.

**Custo e atalho.** Do zero, cada execução baixa ~806 MB do Hugging Face. A Task 3 (até 3 tentativas) mais os roteiros A e B somam pelo menos 2,4 GB. No §5.16 a taxa medida foi de ~4,5 MB/s, ou seja, uns 3 min por download completo, mais o hash. Para começar no meio, **semeie o `.parcial`**:

```bash
curl -L -r 0-629145599 -o "$SCRATCH/seed.parcial" "<url de model_catalog.dart>"   # 600 MiB, uma vez
# app aberto até a tela de consentimento (cria files/), depois:
adb shell am force-stop br.gov.exemplo.guia_ubs
adb shell mkdir -p $M && adb push "$SCRATCH/seed.parcial" $P
U=$(adb shell stat -c %u:%g /data/data/br.gov.exemplo.guia_ubs/files); adb shell chown -R $U $M
adb shell restorecon -R $M
```

Com a semente, cada execução baixa ~200 MB e o passo 2 do roteiro já começa acima de 150 MB. A semente **não** dispensa o roteiro: o offset retomado continua tendo de aparecer no log. Registre no §5.16 se a semente foi usada.

- [ ] **Step 2 (roteiro A, primeiro plano antes do worker):**
  1. `adb shell am start -W -n br.gov.exemplo.guia_ubs/.MainActivity`, aceitar o download.
  2. Esperar `adb shell stat -c %s $P` passar de ~150 MB.
  3. `adb shell cmd connectivity airplane-mode enable`. A tela vai para "Conexão interrompida — N% já baixado", e o listener chama `scheduleModelSync`.
  4. Descobrir o `jobId`: `adb shell dumpsys jobscheduler br.gov.exemplo.guia_ubs | grep -E "JOB #|Required constraints"`. O job do modelo é o que tem `STORAGE_NOT_LOW` (o de pack não tem; ver o plano da P0-1, l. 97). Opcional: `adb shell am broadcast -a androidx.work.diagnostics.REQUEST_DIAGNOSTICS -p br.gov.exemplo.guia_ubs` despeja o estado do WorkManager em `WM-DiagnosticsWrkr`.
  5. `adb shell cmd connectivity airplane-mode disable` e, **em seguida**, tocar "Tentar novamente".
  6. Com `gubs-dl w=primeiro-plano trava obtida` já no log, rodar `adb shell cmd jobscheduler run -f br.gov.exemplo.guia_ubs <jobId>`. Se o WorkManager adiar (*"being executed before schedule"*), registre isso; o disparo natural pela volta da rede também serve, desde que apareça `w=worker` no log.
  7. Esperar a tela clínica liberar.

- [ ] **Step 3 (roteiro B, worker antes do primeiro plano):** `pm clear` e repetir 1 a 4. No passo 5, **não** tocar logo. Forçar o job (ou esperar o disparo natural) até aparecer `w=worker inicio off=…`, e então tocar "Tentar novamente". A tela deve mostrar "Baixando… X%" subindo, porque o primeiro plano espera e reporta o parcial do worker. Log em `$SCRATCH/31-emulador-B.txt`.

**Comportamentos esperados que não são falha:**
- **Limite de ~10 min do WorkManager.** Se o worker passar disso, o `onStopped` destrói a engine e a trava fica órfã por batimento. O log mostra o `WM-WorkerWrapper` parando o worker, a barra **parada** por até `staleAfter` (60 s) e depois `w=primeiro-plano trava orfa tomada motivo=batimento`, seguida de `inicio off=<N>` com N igual ao tamanho do `.parcial` naquele instante. Registre se aconteceu.
- **Worker que roda depois do primeiro plano concluir** (o `cancelModelSync` do listener pode chegar depois do disparo). O log mostra `w=worker trava obtida`, `sha ok`, `fim desfecho=Completed`, nenhuma linha `http` e `Worker result SUCCESS`, em vez de RETRY. Para provocar: concluído o roteiro, rodar de novo o `cmd jobscheduler run -f` com o mesmo `jobId`, se o job ainda constar no `dumpsys`.

- [ ] **Step 4: Evidência objetiva (os dois roteiros)**

`grep 'gubs-dl' $SCRATCH/31-emulador-{A,B}.txt` deve mostrar:
- **Offset retomado > 0:** o `inicio off=<N>` posterior ao modo avião tem `N` maior que zero e próximo do `stat` do passo 3, e `http status=206 range=<N>`.
- **Um escritor só:** nenhuma `ANOMALIA`. No A, `w=worker trava aguardando…`/`trava ocupada desiste` e `WM-WorkerWrapper … Worker result RETRY`. No B, `w=primeiro-plano trava aguardando dono=…` até o `fim` do worker. Em nenhum momento há duas linhas `inicio` sem `fim` entre elas.
- **SHA-256 aprovado:** `sha ok bytes=806058240 ms=<T>` e `fim desfecho=Completed`. **`T` medido sob `libndk_translation` vai para o §5.16.** Se `T` passar de metade de `staleAfter` (30 s), o critério de órfã continua correto, porque o batimento corre durante o hash (Task 5, teste 7). Mas registre o número: ele é a margem real do batimento neste ambiente.
- **Modelo gravado:** `adb shell sha256sum $M/gemma-3-1b-q4.gguf` = `8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135`; `adb shell cat $M/gemma-3-1b-q4.gguf.verificado` começa com `806058240:`; `adb shell ls -la $M` sem `.parcial` e sem `.gemma-3-1b-q4.gguf.trava`.
- **Sem recomeçar do zero:** a soma dos trechos baixados (`fim` − `inicio` de cada escritor que fez HTTP) ≈ 806.058.240 B, e não ≈ 806 MB + o já baixado.

---

### Task 7: Registro

**Files:**
- Modify: `spec/arquitetura.md` §5.16 (substitui o parágrafo "Achado fora do escopo: dois escritores…", l. 1177)
- Modify: `CLAUDE.md` (seção "Background e sync", um item)

- [ ] **Step 1: §5.16**

Escreva no estilo do registro existente (negrito no início do parágrafo, números exatos):
- **Causa:** confirmada ou refutada, com as linhas `gubs-dl` da Task 3 e o vermelho de host da Task 2 (`$SCRATCH/31-vermelho.txt`). Inclua o mecanismo exato: `resumeFrom` lido sem exclusão, dois `Range: bytes=N-`, e o achado 2 (append depois do `rename`).
- **Por que não `RandomAccessFile.lock`:** a saída do experimento da Task 4 e a citação do SDK.
- **Correção:** trava `O_EXCL` + batimento + pid; primeiro plano espera e o worker desiste; agendamento intocado; as 4 sabotagens e o que cada uma pegou.
- **Emulador:** a linha de ambiente (`AVD · API · ABI · build release · git SHA · SHA-256 do APK · data`) e os itens da Task 6, Step 4, para os roteiros A e B.
- **Sintoma secundário:** "Conexão interrompida" sem percentual era o perdedor caindo no `catch` com o `.parcial` já apagado pelo outro (`bytesSoFar: 0`, e a tela esconde o percentual com zero bytes, `onboarding_screen.dart:314`). **Some com a correção** neste cenário, e não precisa de issue nova. O texto "O progresso foi salvo" com zero bytes já está registrado como lacuna de UI no próprio §5.16.
- **Pendências abertas, com número:** as duas issues da Task 5, Step 7 (desistência de pack contando no circuito; `importFromLocalFile` fora da trava).
- **Rastro em produção: decisão.** O `gubs-dl` **fica em release, sem flag.** São ~20 linhas por download, sem PII (rótulo, tamanhos, offsets, status HTTP e o hash público do artefato), dentro da INV-2. Foi a falta de log que deixou o incidente "hipótese não provada", e uma flag desligada em produção reabriria essa lacuna justamente no aparelho que falha.
- **Candidato a issue de eficiência (não aberta):** ao obter a trava depois do worker, o primeiro plano refaz o hash de 806 MB (`T` medido acima), porque o `fetch` sempre confere um destino existente. O worker não grava `.verificado`; só o `ModelProvisioning` grava.

- [ ] **Step 2: `CLAUDE.md`**

Acrescente em "Background e sync": **Um escritor por destino é trava em arquivo `O_EXCL`, não `RandomAccessFile.lock`** (`app/lib/sync/destination_lock.dart`). O worker do WorkManager é outro isolate do MESMO processo, e o lock do Dart é por processo. O batimento existe porque `onStopped` destrói a engine sem `finally`. O nome começa com ponto para escapar do `dropUnreferenced`.

- [ ] **Step 3: Verificação final e commit**

Run (de `app/`): `flutter analyze --fatal-infos && flutter test`
Expected: limpo e verde.

```bash
git add spec/arquitetura.md CLAUDE.md
git commit -m "docs(arquitetura): registra a causa e a correcao dos dois escritores no .parcial (#31)"
```

---

## Rastreabilidade

| Critério / pedido | Tasks |
|---|---|
| Escopo 1: reproduzir com dois `fetch` concorrentes | 2 (mesmo isolate e `Isolate.spawn`) |
| Escopo 2: um único escritor por destino | 4, 5 |
| Escopo 3: teste que reprova com dois escritores | 2, 5 (Step 5, sabotagem S1) |
| AC1: teste vermelho antes, verde depois | 2 (Step 2, `31-vermelho.txt`) → 5 (Step 4, `31-verde.txt`) |
| AC2: no emulador, modo avião + "Tentar novamente" + job forçado ⇒ modelo verificado sem recomeçar do zero | 6 (roteiros A e B, Step 4) |
| Confirmar a causa antes de corrigir (instrumentação) | 1, 2, 3 |
| `RandomAccessFile.lock`: exclui isolates do mesmo processo? | 4 (Step 1) e "Decisão" |
| Trava órfã | 4 (testes 3, 4, 5), 6 (limite de 10 min) |
| Retomada preservada pelo `Range` | 5 (teste 2), 6 (Step 4) |
| Detector de anomalia sem falso positivo em retomada | 1 (`retomada solitária não acusa anomalia`) |
| Batimento durante hash lento | 5 (teste 7), 6 (`ms=` medido) |
| Efeito no pack | 5 (teste 9, Step 7) |
| Worker depois do primeiro plano concluir | 5 (teste 8), 6 (Step 3) |
| Varreduras do diretório de modelos | "Estado confirmado" (`grep`: nenhuma) |
| Sintoma secundário | 3 (`fim … bytes=0`), 7 (Step 1) |
| Registro no §5.16 | 7 |
