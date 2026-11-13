# Plano B — host de conteúdo, URL do modelo no manifest e assinatura provisória — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tirar a primeira tag do bloqueio. Para isso, o plano:
- põe o conteúdo assinado num host estático com TLS;
- move a URL do modelo para o manifest assinado, presa ao sha do catálogo e à origem do manifest;
- torna executável a assinatura provisória por dois mantenedores;
- fecha a brecha da chave de desenvolvimento no APK e no AAB de release.

**Architecture:**
- **Manifest:** ganha um campo opcional e assinado, `model: {url, sha256}`. O app só usa a URL se o `sha256` for igual ao do modelo compilado **e** se ela resolver para a origem do manifest (ou para o host do `MODEL_URL` compilado). A identidade do modelo continua no binário (`model_catalog.dart`), e o `MODEL_URL` compilado vira fallback.
- **Host provisório:** só de conteúdo, na VPS do PRISM. É um **Caddy `file_server` sobre um diretório, sem MinIO**. A publicação é por `rsync` via SSH, feita por um usuário Unix `publisher` preso ao diretório (`rrsync -no-del`). O item 27 escolhe o object store do CMS/worker e decide se o conteúdo migra para ele, sem mudar a URL.
- **Assinatura:** o procedimento da Revisão do ADR-001 ganha as duas verificações que o §J exigia, um verificador do pack publicado escrito sobre o mesmo código do app, um runbook com a ordem de publicação e o registro do que foi publicado numa GitHub Release.

**Tech Stack:** TypeScript (contract, packer; `node:test`), Dart/Flutter 3.44.8 (`flutter test`), Caddy 2.10 fixado por digest, rsync/OpenSSH (`rrsync`), Docker Compose, Bash.

**Spec:**
- [`spec/stack.md`](../../../spec/stack.md):
  - a Revisão do ADR-001 (assinatura provisória);
  - a Revisão 2026-11-02 do ADR-004, condições 1, 3 e 4 (URL do modelo no manifest, os três riscos do espelho, o gatilho de custo);
  - o ADR-007, Decisões 2, 3, 4 e 9.
- [`docs/superpowers/plans/2026-11-02-realinhamento-institucional-implantacao.md`](2026-11-02-realinhamento-institucional-implantacao.md) §J.3: "Plano B: o TLS do host de conteúdo" e "onde o pack é assinado".
- [`docs/dados-do-usuario.md`](../../dados-do-usuario.md) §3: a promessa de que o modelo vem "do Hugging Face ou do host do PRISM", que a Task 4 passa a garantir no código.

## Global Constraints

- **A chave privada Ed25519 nunca vai para CI**, nem para segredo do GitHub, nem para disco persistente da máquina do mantenedor (Revisão do ADR-001). **Nenhum agente gera, lê ou guarda a chave de produção**: ela é gerada pelo mantenedor A, offline, e só a **pública** (32 bytes em hex) entra no repositório. Chaves descartáveis de ensaio vivem só no scratchpad.
- **A borda não é confiável** (INV-3): o app confere a assinatura do manifest e o SHA-256 de tudo o que baixa. Nada neste plano afrouxa essas verificações.
- **O app continua com exatamente duas chamadas de rede** (manifest e pack; modelo). A URL do modelo vir do manifest não cria uma terceira, e nunca aponta para um host fora dos dois já declarados: a origem do manifest e o host do `MODEL_URL` compilado.
- **Falha de sync ou de modelo nunca bloqueia o app** (INV-8). Um manifest sem `model`, ou com `model` inválido, deixa o app como está hoje: usa o `MODEL_URL` compilado ou fica "não configurado". Um 429 é "tente depois", nunca "arquivo inválido".
- **O manifest é `additionalProperties: false`, e todo campo fora de `signature` é assinado** (`canonicalPayload`). O campo `model` entra no Zod (`contract/src/manifest.ts`), no schema gerado e no parser Dart escrito à mão (`app/lib/sync/pack_manifest.dart`) no mesmo commit.
- **Ordem de publicação:** primeiro os packs e os assets, depois o manifest. Nenhum arquivo em `packs/`, `assets/` ou `models/` é sobrescrito, porque o `Cache-Control: immutable` exige isso e os nomes já carregam o sha (`packs/pack-<sha12>.db`, `models/<nome>-<sha>.gguf`). O `manifest.json` é o único arquivo que muda.
- **Domínio de conteúdo:** `guiasaude.conteudo.prismrr.com.br` (Q-B4 respondida em 2026-11-12). A URL embarcada é `https://<CONTENT_DOMAIN>/content-packs/0000000/manifest.json`. O caminho `content-packs/0000000/` é preservado do layout do MinIO para que o item 27 possa trocar o backend sem mudar a URL.
- **O host de conteúdo serve só manifest, packs, assets e o modelo** (`content-packs/models/`), e só GET/HEAD (ADR-007, Decisão 4). Ele não proxia o CMS e não lista diretórios.
- **Datacenter no Brasil** (ADR-007, Decisão 2). Imagem de produção fixada por digest, com `linux/arm64` (F-1). Nunca emulação.
- **O padrão do repositório vale:**
  - variável de ambiente nova citada no `docs/operacao.md` entra em `infra/.env.example` ou em `NAO_SAO_ENV` (`cms/test/doc-operacao.test.ts`);
  - script npm citado precisa existir no `package.json` da raiz;
  - nenhum commit nem PR leva atribuição de IA;
  - nome de provedor e dado pessoal do titular do domínio não entram no repositório, e números da VPS vêm do registro operacional;
  - uma branch `feat/plano-b`, criada do `origin/develop`, com **uma** PR para o `develop`.
- **Nenhum texto legal muda** (`app/assets/legal/*`). O aviso "servidor fora do Brasil" é do E7, não deste plano.

## Decisões do plano (respondidas antes da Task 1)

| ID | Pergunta | Decisão | Alternativas descartadas |
|---|---|---|---|
| **Q-B1** | Onde fica o host de conteúdo antes do item 27, e sobre o quê? | **Na VPS do PRISM** (F-1: já contratada, no Brasil), por um compose próprio (`infra/compose.content.yaml`) com **um só serviço**: o `edge`, um Caddy `file_server` sobre um diretório do host. A publicação é por **`rsync` via SSH**, pelo usuário Unix `publisher`, com escrita só no diretório de conteúdo (`rrsync -no-del`). A imutabilidade de `packs/` vem do `--ignore-existing`, mais uma conferência remota antes do manifest. A #46 vira configuração: `file_server` sem `browse`, com dotfiles ocultos. Os packs são reconstruíveis, e o backup grátis fora da VPS é a GitHub Release da Task 8. **Pendência do item 27, registrada na Revisão do ADR-007:** o CMS/worker precisa de outro object store (Garage, SeaweedFS ou o que o grupo escolher), porque o MinIO community entrou em modo de manutenção. Isso não se reabre na 1ª tag. | **MinIO como no `compose.yaml`:** o repositório upstream declarou "maintenance mode" (dez./2025) e depois "não mantido" (fev./2026). A última imagem pública é de 2025-09-07, e a correção da CVE-2025-62506 não existe em imagem oficial. Para um host só de GET/HEAD, é peso morto e superfície sem patch. A Task 7, Passo 1, confere essas datas com fonte antes de citá-las. **GitHub Pages:** fora do Brasil, sem controle de `Cache-Control` e contrário ao ADR-007. **Esperar o item 27:** põe Ansible, CMS, backup e monitoramento no caminho da 1ª tag. |
| **Q-B2** | O que o manifest carrega sobre o modelo? | **`model: {url, sha256}`**, opcional. O app usa a `url` só se: (a) o `sha256` for igual ao do `activeModel`; (b) a URL resolvida (relativa ao manifest) passar em `isUsableEndpoint`; (c) a **origem** for a do manifest, ou o **host** for exatamente o do `MODEL_URL` compilado. Sem (c), um manifest assinado poderia mandar o IP do usuário a um terceiro, e o `dados-do-usuario.md` §3 prometeria algo que o código não garante. O artefato efetivo é calculado no `main` e no worker, então **a troca de host vale na próxima abertura do app** (ou no próximo disparo do worker). O parcial (`.parcial`) é por arquivo, não por URL: um download pela metade continua por `Range` contra o host novo, já que os bytes são os mesmos e o sha é conferido no fim. Trocar de **modelo** continua exigindo release. | **Só `url`:** um manifest de outro modelo gastaria 806 MB à toa. **`url + sha256 + bytes` como identidade:** troca de modelo sem release, contra a condição 1 do ADR-004. **Qualquer host https:** ver (c). |
| **Q-B3** | O que dispara tirar o modelo do Hugging Face, e o que impede que a saída estoure a VPS? | **Saída**, qualquer um destes: um **429** na medição (Task 9) ou em teste; **dois relatos** de QA ou dogfooding de download do modelo que falhou na mesma semana; ou o espelho sumir. **Ação:** `npm run content:publish -- --model <gguf>` e um manifest novo com `model.url = ../models/<nome>-<sha>.gguf` (mesma origem), sem release. **Calibragem:** usuário anônimo tem 3.000 requisições ao resolver por IP a cada janela fixa de 5 min, limite "sujeito a mudança", e o Hub devolve `RateLimit` e `RateLimit-Policy`. Um aparelho isolado não esbarra nisso. O risco real é o **CGNAT** das operadoras e cada retomada de `Range` contando como resolve. Por isso a Task 9 mede também de uma rede móvel brasileira, e a Task 5 trata 429 como "tente depois", honrando `Retry-After`/`RateLimit`. **Teto de custo:** o modelo na VPS custa ~0,806 GB de egress por instalação. A saída só é aceita enquanto `instalações/mês × 0,806 GB ≤ 50 % da franquia mensal da VPS`. Acima disso, o modelo fica no HF ou ganha um segundo espelho, e isso é decisão registrada na Revisão do ADR-004 (Task 9). | Telemetria de falhas: proibida pelo ADR-010, Decisão 5. |
| **Q-B4** | `guiasaude.conteudo.prismrr.com.br` ou `conteudo.guiasaude.prismrr.com.br`? | **Manter `guiasaude.conteudo`**, salvo resposta contrária do mantenedor antes da Task 10, que é quando o nome entra no APK e passa a ser permanente. O nome já está no ADR-007 (Decisão 4), no `implantacao.md` §3.2 e no `stack.md`, e faz par com `guiasaude.cms`. A forma hierárquica leria melhor e agruparia tudo sob `guiasaude.prismrr.com.br`, onde já está o Pages, mas exige uma Revisão do ADR-007 para os **dois** nomes. Se for escolhida, a Task 10 ganha essa Revisão e a Task 7 muda só o `.env` da VPS. | **Respondida em 2026-11-12: manter `guiasaude.conteudo`.** O ADR-007 não muda. |

Se a resposta a alguma for outra, mude só a task correspondente (Q-B1 → Tasks 7 e 8; Q-B2 → Tasks 2 a 4; Q-B3 → Tasks 5 e 9; Q-B4 → Task 10).

## Review Focus

1. **Manifest assinado com `model.url` em outra origem.** Num build de release, o app ignora a URL e segue com o fallback; o IP do usuário nunca vai a um terceiro host. Pin: Task 4, `recusa url de outra origem`.
2. **429 do Hugging Face.** Hoje cai no ramo 4xx: `DownloadRejected`, a tela diz "falha de integridade" e o worker não reagenda. O esperado é interrupção, com o parcial preservado e a próxima tentativa só depois do `Retry-After`. Pin: Task 5.
3. **Manifest com `model.sha256` diferente do modelo compilado.** O app ignora a URL e não baixa nada a mais. Pin: Task 4, `ignora url de outro modelo`.
4. **Release, APK **ou AAB**, com a chave de desenvolvimento ou sem chave.** A guarda reprova nos dois caminhos do `app-release.yml`, e hoje o AAB não passa pela guarda. Pin: Task 1.
5. **Republicar um pack com o mesmo nome e bytes diferentes.** O `content:publish` aborta **antes** de enviar o manifest. Pin: Task 7, `publicar pack divergente aborta sem manifest`.

---

## Mapa de arquivos

| Arquivo | Papel | Task |
|---|---|---|
| `app/tool/model_url_check.dart`, `.github/workflows/app-release.yml` | `packSigningKeyProblem`; guarda antes do AAB; chave descartável no ensaio | 1 |
| `contract/src/manifest.ts`, `contract/manifest-schema.json` | campo `model` | 2 |
| `packer/src/release.ts`, `packer/src/cli.ts`, `packer/src/worker.ts` | `ManifestInput.model`; `--model-url`/`--model-sha256`; env `PACK_MODEL_URL`/`PACK_MODEL_SHA256` | 2 |
| `app/lib/sync/pack_manifest.dart` | `ManifestModel`, `PackManifest.model` | 3 |
| `app/lib/sync/model_source.dart` (novo), `main.dart`, `model_background_sync.dart`, `app_scope.dart` | `resolveModelUri`, `effectiveModel` | 4 |
| `app/lib/sync/resumable_downloader.dart`, `model_downloader.dart`, `model_background_sync.dart` | 429/503 transitórios com `retryAfter` | 5 |
| `packer/src/release.ts`, `packer/src/cli.ts` | chave lida uma vez; `build` deixa a árvore publicável em `out/`; `resolveFromRepo` exportado | 6 |
| `app/tool/verify_published.dart` (novo) | conferência do mantenedor B | 6 |
| `infra/compose.content.yaml`, `infra/Caddyfile.content`, `infra/scripts/publish-content.sh`, `infra/scripts/test-content-host.sh` (novos) | host só de conteúdo e publicação por rsync | 7 |
| `infra/scripts/check-model-endpoint.sh` | listagem negada aceita 403 ou 404 | 7 |
| `docs/operacao.md`, `spec/stack.md` (ADR-001, ADR-007) | runbook, ensaio, registro e Revisões | 8 |
| `spec/arquitetura.md` §5.x, `spec/stack.md` (ADR-004) | medição do HF e teto de custo | 9 |
| `app/config/defines.release.json`, `contract/keys/README.md` | `PACK_MANIFEST_URL` real e chave pública de produção | 10 |
| `spec/implantacao.md`, `docs/dados-do-usuario.md`, `CLAUDE.md`, `spec/arquitetura.md` | propagação | 11 |

---

### Task 1: a guarda de build recusa a chave de desenvolvimento, nos dois caminhos do release

**Files:**
- Modify: `app/tool/model_url_check.dart` (função nova, chamada no `main` junto das outras guardas)
- Modify: `.github/workflows/app-release.yml`:
  - um passo `Guarda dos defines` roda `dart run tool/model_url_check.dart --config config/defines.release.json --mode release` **antes** do passo `AAB`, porque o `flutter build appbundle` não passa pelo `build_apk.sh`;
  - no ramo do ensaio, o heredoc ganha `"PACK_SIGNING_KEY_K1": "<pub>"`, com a pública de uma chave descartável gerada no próprio job com o mesmo `openssl` do job `interop`. Sem isso, a guarda nova reprova o ensaio.
- Test: `app/test/tool/model_url_check_test.dart`, `app/test/tool/release_workflow_test.dart` (novo)

**Interfaces:**
- Produz: `String? packSigningKeyProblem(String? k1, {required bool release})`. Devolve `null` quando aceita e uma mensagem quando reprova.

- [ ] **Passo 1: testes que falham.**
  - Em `model_url_check_test.dart`, grupo `packSigningKeyProblem`:
    - `reprova ausente em release`: `packSigningKeyProblem(null, release: true)` e `packSigningKeyProblem('', release: true)` não são nulos.
    - `reprova a chave de desenvolvimento em release`: `packSigningKeyProblem(devPackSigningKeyK1, release: true)` contém `desenvolvimento`.
    - `reprova formato`: `'abc'`, um hex de 63 caracteres e um de 64 com `g` não são nulos.
    - `aceita hex de 64 que não é a de dev`: `packSigningKeyProblem('a' * 64, release: true)` é nulo.
    - `debug aceita ausente`: `packSigningKeyProblem(null, release: false)` é nulo.
    - `o main reprova defines de release sem a chave`: o `main` com `--config` apontando para um JSON temporário que tem `MODEL_URL` e `PACK_MANIFEST_URL` válidos e não tem `PACK_SIGNING_KEY_K1` sai com código 1.
  - Em `release_workflow_test.dart`, lendo `.github/workflows/app-release.yml` como texto:
    - `a guarda roda antes do AAB`: o índice de `model_url_check.dart` é menor que o de `flutter build appbundle`;
    - `o ensaio define PACK_SIGNING_KEY_K1`: o heredoc do ramo `else` contém `PACK_SIGNING_KEY_K1`.

- [ ] **Passo 2:** `cd app && flutter test test/tool/`. O esperado é FAIL nos testes novos.

- [ ] **Passo 3: implemente.**
  - Importe `devPackSigningKeyK1` de `package:guia_ubs/sync/pack_signing_keys.dart`. O formato é `^[0-9a-f]{64}$`, aceitando minúscula depois de `trim()`. No `main`, leia `PACK_SIGNING_KEY_K1` do mesmo JSON de defines e reprove em release.
  - Edite o `app-release.yml` conforme os Files.

- [ ] **Passo 4:** rode o mesmo comando do Passo 2. O esperado é PASS. Depois, `flutter analyze --fatal-infos` sem achados.

- [ ] **Passo 5: confira o efeito real.** `dart run tool/model_url_check.dart --config config/defines.release.json --mode release` continua saindo com 1. Agora são **duas** mensagens: a do manifest `.invalid` e a da chave.

- [ ] **Passo 6: commit.** `git commit -m "fix(build): release (APK e AAB) recusa a chave de assinatura de desenvolvimento ou ausente"`

---

### Task 2: o contrato e o packer ganham `model: {url, sha256}`

**Files:**
- Modify: `contract/src/manifest.ts` (`manifestSchema`), `contract/manifest-schema.json` (gerado)
- Modify: `packer/src/release.ts` (`ManifestInput`, `buildManifest`), `packer/src/cli.ts`, `packer/src/worker.ts`
- Modify: `infra/.env.example` (`PACK_MODEL_URL=`, `PACK_MODEL_SHA256=`, vazios e comentados)
- Test: `contract/test/contract.test.ts`, `packer/test/packer.test.ts`, `packer/test/cli.test.ts`

**Interfaces:**
- Produz, no Zod: `model: z.object({ url: z.string().min(1), sha256: z.string().regex(/^[0-9a-f]{64}$/) }).strict().optional()`.
- Produz: `ManifestInput.model?: { url: string; sha256: string }`. O `buildManifest` só emite a chave `model` quando ela for definida, para que um manifest sem modelo fique byte a byte igual ao de hoje.
- CLI: `--model-url <url>` e `--model-sha256 <hex>`, com fallback nas envs `PACK_MODEL_URL` e `PACK_MODEL_SHA256`. O worker lê as mesmas envs. Informar só um dos dois é erro de uso (saída 64), com a mensagem `--model-url e --model-sha256 vão juntos`.
- Forma canônica do `model.url` no host de conteúdo: `../models/<nome>-<sha>.gguf`, relativa ao manifest em `content-packs/0000000/`. É a chave que o `publish-model.sh` já usa (`models/$OBJECT_NAME-$SHA`).

- [ ] **Passo 1: testes que falham.**
  - `contract.test.ts`:
    - `aceita manifest com model`;
    - `aceita manifest sem model`;
    - `recusa model com campo extra`;
    - `recusa model.sha256 fora de hex64`.
  - `packer.test.ts`:
    - `a assinatura cobre model.url`: adulterar `model.url` depois de assinar faz a verificação falhar;
    - `sem model, o manifest é igual ao de antes`: o mesmo `SOURCE_DATE_EPOCH` sem `model` gera o mesmo `sha256` de `manifest.json` que o build anterior. Fixe o hash atual no teste antes de mexer.
  - `cli.test.ts`: `model-url sem model-sha256 é erro de uso`.

- [ ] **Passo 2:** `npm test --workspace contract && npm test --workspace @guia-ubs/packer`. O esperado é FAIL nos testes novos.

- [ ] **Passo 3: implemente** conforme as Interfaces, e rode `npm run contract:generate`.

- [ ] **Passo 4: verifique.**
  - `npm test --workspace contract && npm test --workspace @guia-ubs/packer && npm run contract:check && npm run typecheck`. O esperado é PASS, com o `contract:check` limpo depois do commit do schema gerado.
  - `npm --workspace @guia-ubs/cms test`. O esperado é PASS: as duas envs novas estão no `.env.example`.

- [ ] **Passo 5: commit.** `git commit -m "feat(contract): manifest assinado carrega model {url, sha256} opcional"`

---

### Task 3: o app lê `model` do manifest verificado

**Files:**
- Modify: `app/lib/sync/pack_manifest.dart` (`class PackManifest`, `parseVerifiedManifest`)
- Create: `app/test/fixtures/sync/manifest-v3-model.json`, gerada pelo packer real com `contract/keys/dev-k1.pem` e `SOURCE_DATE_EPOCH`, conforme o `README.md` da pasta, com `--model-url ../models/gemma-3-1b-it-Q4_K_M-<sha>.gguf --model-sha256 <sha do catálogo>`
- Test: `app/test/sync/manifest_verifier_test.dart`

**Interfaces:**
- Consome: o formato da Task 2.
- Produz:
  - `class ManifestModel { final String url; final String sha256; }`;
  - `PackManifest.model`, do tipo `ManifestModel?`, nulo quando o manifest não traz `model`.

- [ ] **Passo 1: testes que falham.**
  - `aceita manifest-v3-model e expõe model`: `model!.url` termina em `.gguf`, e `model!.sha256 == activeModel.sha256`.
  - `manifest-v1 continua aceito, com model nulo`.
  - `campo extra não assinado em model é recusado`: acrescentar `model.extra` aos bytes faz a verificação falhar.

- [ ] **Passo 2:** `cd app && flutter test test/sync/manifest_verifier_test.dart`. O esperado é FAIL.

- [ ] **Passo 3: implemente.**
  - Ao fazer o parse, recuse um `model` que não seja um objeto com exatamente `url` (string não vazia) e `sha256` (hex64). A recusa usa a mesma exceção dos outros campos inválidos.
  - Atualize o `README.md` das fixtures com o comando que gerou a v3.

- [ ] **Passo 4:** rode o comando do Passo 2 e depois `flutter test test/sync/`. O esperado é PASS.

- [ ] **Passo 5: commit.** `git commit -m "feat(sync): PackManifest expõe model assinado"`

---

### Task 4: a URL efetiva do modelo vem do manifest ativo, presa ao sha e à origem

**Files:**
- Create: `app/lib/sync/model_source.dart`
- Modify: `app/lib/main.dart:85-86`, `app/lib/sync/model_background_sync.dart:56-57` e o `assistant:` de `app/lib/ui/app_scope.dart:417`, que passa a receber o artefato efetivo calculado no `main`
- Modify: `app/lib/sync/model_downloader.dart`: `ModelArtifact.withUrl(String url) → ModelArtifact`, que preserva `sha256`, `sizeBytes` e `fileName`
- Test: `app/test/sync/model_source_test.dart`, `app/test/sync/resumable_downloader_test.dart`

**Interfaces:**
- Consome: `PackManifest.model` (Task 3), `PackStore.loadActive()` (`app/lib/sync/pack_store.dart:92`), `parseEndpoint` e `isUsableEndpoint` (`endpoint_config.dart`).
- Produz:
  - `Uri? resolveModelUri({required ModelArtifact compiled, required ManifestModel? fromManifest, required Uri manifestUrl, required bool requireHttps})`. Seja `r = manifestUrl.resolve(fromManifest.url)`:
    1. o manifest prevalece quando:
       - `fromManifest != null`;
       - `fromManifest.sha256 == compiled.sha256`;
       - `r` passa em `isUsableEndpoint(…, requireHttps: requireHttps)`;
       - **e** `r.origin == manifestUrl.origin`, ou `compiled.isConfigured && r.host == compiled.uri.host`;
    2. senão, vale `compiled.uri` quando `compiled.isConfigured`;
    3. senão, `null`.

    A regra de origem vale em debug e em release: o servidor local de teste serve manifest e modelo na mesma origem.
  - `Future<ModelArtifact> effectiveModel({required PackStore store, required Uri manifestUrl, ModelArtifact compiled = activeModel})`: lê o manifest ativo pelo `loadActive()`, aplica o `resolveModelUri` e devolve `compiled.withUrl(...)`, ou o `compiled` sem mudança quando o resultado é `null`. Nunca lança: erro de leitura vale como manifest ausente (INV-8). O comentário de doc diz que o valor é calculado **uma vez por processo** (no `main` e em cada disparo do worker), então um manifest novo só muda o host do modelo na próxima abertura.

- [ ] **Passo 1: testes que falham.**
  - Em `model_source_test.dart`:
    - `sem manifest, usa o compilado`;
    - `usa a url do manifest quando o sha confere`;
    - `ignora url de outro modelo`: um `sha256` diferente devolve `compiled.uri`;
    - `resolve url relativa contra o manifest`: `../models/x-<sha>.gguf` com manifest em `https://h/content-packs/0000000/manifest.json` dá `https://h/content-packs/models/x-<sha>.gguf`;
    - `recusa url insegura em release`: `http://h/m.gguf` com `requireHttps: true` cai no compilado;
    - `recusa url de outra origem`: `https://terceiro.example/m.gguf`, com sha certo e manifest em `https://h/...`, cai no compilado;
    - `aceita o host do MODEL_URL compilado`: uma URL em `huggingface.co` com outro caminho, sha certo e compilado em `huggingface.co`, é aceita;
    - `sem manifest e sem MODEL_URL, devolve null`;
    - `effectiveModel não lança com store ilegível`: um `PackStore` sobre um diretório em que o arquivo do manifest ativo (`_activeManifestName` em `pack_store.dart`) está corrompido devolve o `compiled`.
  - Em `resumable_downloader_test.dart`: `retoma o parcial contra outro host com os mesmos bytes`. Dois `HttpServer` locais servem os mesmos bytes. O primeiro corta a conexão depois de N bytes. O `fetch` seguinte, com a URL do segundo e o mesmo `destination`, envia `Range: bytes=N-` e termina em `DownloadCompleted` com o sha conferido.

- [ ] **Passo 2:** `cd app && flutter test test/sync/model_source_test.dart test/sync/resumable_downloader_test.dart`. O esperado é FAIL: o `model_source.dart` não existe. O teste de retomada pode já passar; se passar, ele fica como pin.

- [ ] **Passo 3: implemente** e ligue o `main.dart` e o `model_background_sync.dart`. O `ModelProvisioning` e o destino do worker recebem o artefato devolvido pelo `effectiveModel`. A identidade do arquivo em disco (`fileName`, `sha256`) não muda, então um modelo já instalado não é baixado de novo.

- [ ] **Passo 4:** `flutter test`, a suíte inteira, e `flutter analyze --fatal-infos`. O esperado é PASS, com `model_catalog_test` e `model_provisioning_test` sem mudança.

- [ ] **Passo 5: confira no emulador** (CLAUDE.md, "Verificação em aparelho"), porque a mudança é de I/O.
  - Instale o build de debug com o `defines.debug.json` e um manifest local cujo `model.url` aponte para o mesmo servidor local.
  - Confira no `logcat` (`gubs-dl`) que o download pede a URL do manifest **só depois de reabrir o app**.
  - Troque o `model.sha256` por outro valor e confira que o download volta para o `MODEL_URL` compilado.

- [ ] **Passo 6: commit.** `git commit -m "feat(model): URL do modelo vem do manifest assinado, presa ao sha e a origem"`

---

### Task 5: 429 e 503 são "tente depois", honrando `Retry-After` e `RateLimit`

Hoje, em `resumable_downloader.dart:393-403`, todo 4xx vira `DownloadRejected(permanentHttpError)`. Para um 429 isso causa três coisas:
- o `model_provisioning.dart:392` mostra `SetupBlockReason.integrityFailed`;
- o worker devolve `true` e não reagenda;
- o parcial fica, mas a pessoa lê que o arquivo é inválido.

**Files:**
- Modify: `app/lib/sync/resumable_downloader.dart` (`DownloadInterrupted`, `_download`)
- Modify: `app/lib/sync/model_downloader.dart` (`ModelUnavailable` carrega `retryAfter`), `app/lib/sync/model_background_sync.dart`
- Test: `app/test/sync/resumable_downloader_test.dart`, `app/test/sync/model_background_sync_test.dart`, `app/test/sync/model_provisioning_test.dart`

**Interfaces:**
- Produz:
  - `DownloadInterrupted.retryAfter`, do tipo `Duration?` (padrão `null`);
  - `ModelUnavailable.retryAfter`, do tipo `Duration?`;
  - `Duration? parseRetryAfter(HttpHeaders headers, DateTime now)`. A ordem é:
    1. `Retry-After` em segundos;
    2. `Retry-After` como data HTTP (`HttpDate.parse`), menos `now`;
    3. o parâmetro `t=<segundos>` do cabeçalho `RateLimit` (formato `"<política>";r=<n>;t=<s>`);
    4. senão, `null`.

    O resultado é limitado a `[0, 24 h]`, e um valor inválido dá `null`.
- Comportamento:
  - 429 e 503 viram `DownloadInterrupted(bytesSoFar: resumeFrom, reason: 'HTTP <code>', retryAfter: parseRetryAfter(...))`, e o parcial fica;
  - os outros 4xx continuam `DownloadRejected`;
  - no worker, um `interrupted` com `retryAfter` maior que `ModelSyncPolicy.backoff` devolve `true` (espera a próxima janela periódica, sem um backoff curto que desrespeite o servidor); senão, `false`, como hoje.

- [ ] **Passo 1: testes que falham.**
  - `resumable_downloader_test.dart`:
    - `429 é interrupção, não rejeição`;
    - `preserva o parcial no 429`;
    - `503 é interrupção`;
    - `404 continua rejeição permanente`.
  - Em `parseRetryAfter`:
    - `lê Retry-After em segundos` (`120` dá 120 s);
    - `lê Retry-After como data HTTP`;
    - `lê t= do RateLimit` (`"anon";r=0;t=180` dá 180 s);
    - `limita a 24 h`;
    - `inválido dá null`.
  - `model_background_sync_test.dart`: `retryAfter maior que o backoff não pede reagendamento curto`.
  - `model_provisioning_test.dart`: `429 aparece como interrompido, não como integridade`.

- [ ] **Passo 2:** `cd app && flutter test test/sync/`. O esperado é FAIL nos testes novos.

- [ ] **Passo 3: implemente** conforme as Interfaces. O trace (`_t`) registra o `retryAfter` lido.

- [ ] **Passo 4:** `flutter test` e `flutter analyze --fatal-infos`. O esperado é PASS.

- [ ] **Passo 5: commit.** `git commit -m "fix(model): 429 e 503 sao interrupcao que honra Retry-After, nao arquivo invalido"`

---

### Task 6: as verificações do §J, a árvore publicável e o verificador do pack publicado

**Files:**
- Modify: `packer/src/release.ts`: a chave privada é lida **uma vez** por `carregarChavePrivada(path: string): KeyObject`, e o `KeyObject` vai para a assinatura e para o `chavePublicaDe`. Hoje há duas leituras (`release.ts:74` e `release.ts:91`), e com `/dev/fd/3` a segunda leria um pipe já consumido.
- Modify: `packer/src/cli.ts`:
  - exporta `resolveFromRepo(repoRoot: string, path: string): string`;
  - o `build` também deixa o pack em `out/<pack.url>` e os assets em `out/<asset.path>`, como o `publish` já faz (`cli.ts:189-204`). Assim `out/` espelha o diretório da edição no host, e o `content:publish` (Task 7) envia `out/` sem saber nada do packer.
- Create: `app/tool/verify_published.dart`
- Test: `packer/test/cli.test.ts`, `packer/test/packer.test.ts`, `app/test/tool/verify_published_test.dart`

**Interfaces:**
- Produz:
  - `carregarChavePrivada(path: string): KeyObject` (`release.ts`); `chavePublicaDe` e a assinatura passam a aceitar `KeyObject`.
  - `Future<List<String>> verifyPublished(Uri manifestUrl, String publicKeyHex, {String keyId = 'k1', HttpClient? client})`, que devolve a lista de problemas (vazia significa ok). Confere:
    - a assinatura, com `ManifestVerifier` e `{keyId: publicKeyHex}`, o mesmo código do app;
    - o `pack` baixado em `manifestUrl.resolve(pack.url)`, cujo `sha256` e `bytes` precisam bater com o manifest;
    - o `Cache-Control` do manifest contém `max-age=60` e o do pack, `immutable`.

    Quando houver `model`, o verificador confere que a URL resolvida tem a mesma origem do manifest ou o host do `MODEL_URL` (a regra da Task 4), e faz só um `HEAD`, que precisa dar 200 com `Content-Length` igual ao do catálogo, sem baixar 806 MB.
  - A CLI é `dart run tool/verify_published.dart <manifest-url> <pubkey-hex> [keyId]`, com saída 0 (ok), 1 (problemas) ou 64 (uso).

- [ ] **Passo 1: testes que falham.**
  - `cli.test.ts`:
    - `pack:check e pack:build geram o mesmo content.db`: com o mesmo `SOURCE_DATE_EPOCH`, o `--dry-run` e o build assinado (chave de dev, golden do caso de teste com revisão válida, como os testes de pipeline já montam) deixam o `content.db` no mesmo caminho relativo e com o mesmo sha256;
    - `resolveFromRepo aceita /dev/fd/3`: `resolveFromRepo('/repo', '/dev/fd/3') === '/dev/fd/3'`;
    - `build lê a chave uma vez só`: `PACK_SIGNING_KEY_PATH` aponta para um FIFO (`mkfifo` no diretório temporário do teste) em que o teste escreve a chave de dev **uma** vez. O build termina em até 60 s, e o manifest verifica com a pública de dev. Hoje ele trava ou falha na segunda leitura;
    - `build deixa o pack em out/<pack.url>`: o arquivo existe e o sha bate com `manifest.pack.sha256`.
  - `verify_published_test.dart`, com um `HttpServer` local servindo a fixture `manifest-v1.json`, o pack dela e os cabeçalhos de cache do host:
    - `ok com a fixture e a chave de dev`;
    - `pack adulterado reprova`;
    - `chave errada reprova`;
    - `404 no pack reprova`;
    - `manifest sem max-age=60 reprova`;
    - `model em outra origem reprova` (com a fixture v3 da Task 3, reescrita para apontar para outro host e assinada de novo com a chave de dev).

- [ ] **Passo 2:** `npm test --workspace @guia-ubs/packer` e `cd app && flutter test test/tool/verify_published_test.dart`. O esperado é FAIL.

- [ ] **Passo 3: implemente.** Se o primeiro teste do `cli.test.ts` falhar por um motivo **real** (o `content.db` muda com a assinatura), **pare**: o procedimento da Revisão do ADR-001 não vale como está, e o §J manda ajustá-lo antes do 1º pack. Registre como Ruling e leve ao mantenedor.

- [ ] **Passo 4:** rode os comandos do Passo 2 e `npm run typecheck`. O esperado é PASS.

- [ ] **Passo 5: commit.** `git commit -m "feat(packer): chave lida uma vez, arvore publicavel em out/ e verify_published para o mantenedor B"`

---

### Task 7: host só de conteúdo, Caddy `file_server` e publicação por rsync (Q-B1)

**Files:**
- Create: `infra/compose.content.yaml`, com **um** serviço, o `edge`:
  - `image: caddy:2.10.<patch>-alpine@sha256:<digest>`, fixada no Passo 1;
  - `restart: unless-stopped`;
  - portas `80:80` e `443:443`;
  - `CONTENT_DOMAIN` e `ACME_EMAIL` obrigatórios (`:?`), sem `CMS_DOMAIN`;
  - volumes:
    - `./Caddyfile.content:/etc/caddy/Caddyfile:ro`;
    - `${CONTENT_ROOT:?defina em infra/.env}:/srv/conteudo:ro`;
    - **`caddydata:/data` e `caddyconfig:/config`**, volumes nomeados. Sem eles, cada recriação pede certificado novo e esbarra no limite de certificados duplicados do Let's Encrypt;
  - `security_opt: [no-new-privileges:true]`.
- Create: `infra/Caddyfile.content`:
  - o bloco global (`email {$ACME_EMAIL}`);
  - `{$CONTENT_DOMAIN}`, com os mesmos `encode`, `header`, `@manifest`, `@immutable` e `@mutating`/405 do `infra/Caddyfile`;
  - no lugar do `reverse_proxy`: `root * /srv/conteudo` e `file_server { hide .* }`, sem `browse`. `hide .*` impede servir os temporários do rsync (`.manifest.json.XXXXXX`).

  O cabeçalho do arquivo explica por que ele **não** importa um bloco comum com o `infra/Caddyfile`: lá o conteúdo vem do MinIO por proxy, e aqui de um diretório.

  O `infra/Caddyfile` e o `infra/compose.yaml` **não mudam**; a troca do object store é do item 27.
- Create: `infra/scripts/publish-content.sh` (npm `content:publish`):
  - `content:publish -- <out-dir> <edição>` publica um pack:
    1. confere o manifest com `dart run tool/verify_manifest.dart <out>/manifest.json "$PACK_PUBKEY_HEX"` e o sha de cada arquivo que ele referencia em `<out>`; qualquer falha aborta antes da rede;
    2. faz `rsync -a --ignore-existing --chmod=D755,F644` de `packs/` e `assets/` para `$CONTENT_TARGET/content-packs/<edição>/`;
    3. faz `rsync -a --checksum --dry-run --itemize-changes` dos mesmos diretórios; qualquer linha de mudança significa um arquivo remoto com o mesmo nome e bytes diferentes, e o script aborta **sem enviar o manifest**;
    4. por último, faz `rsync` do `manifest.json`.
  - `content:publish -- --model <gguf>` publica o modelo: roda `infra/scripts/publish-model.sh <gguf> --check-only` (sha e tamanho contra o catálogo, NOTICE e termos) e então faz `rsync --ignore-existing` do `.gguf`, do `.NOTICE.txt` e dos termos para `content-packs/models/`, com os mesmos nomes do `publish-model.sh`.
  - `CONTENT_TARGET` é um destino rsync: `publisher@<host>:` (o `rrsync` no servidor fixa a raiz) ou um diretório local, para os testes.
- Create: `infra/scripts/test-content-host.sh` (npm `content:test`): sobe o `compose.content.yaml` com `CONTENT_DOMAIN=localhost` e `CONTENT_ROOT` num diretório temporário, publica uma árvore de teste com o `publish-content.sh` (alvo local), confere tudo do Passo 2 e derruba o compose.
- Modify: `infra/scripts/check-model-endpoint.sh`: a listagem negada aceita 403 (MinIO) **ou** 404 (`file_server` sem `browse`).
- Modify: `infra/.env.example`: `CONTENT_ROOT`, `CONTENT_TARGET` e `PACK_PUBKEY_HEX`, vazios e comentados.
- Modify: `package.json` da raiz:
  - `infra:validate` também valida o `compose.content.yaml`;
  - scripts novos `content:publish` e `content:test`.
- Modify: o job `infra` do CI:
  - `caddy validate` no `Caddyfile.content` com a mesma imagem fixada;
  - `npm run content:test`, já que o runner tem docker.

- [ ] **Passo 1: fixe a imagem e confira as premissas, com fonte.**
  - `docker buildx imagetools inspect caddy:2.10-alpine`: anote a tag de patch e o digest, e confira que a lista inclui `linux/arm64` (F-1).
  - Confira e anote os links de três fatos: o aviso de manutenção do repositório `minio/minio`, a data da última imagem community no Docker Hub e o advisory da CVE-2025-62506. Eles vão para a Revisão do ADR-007 (Task 8).
  - **Se algum fato não se confirmar, pare** e leve ao mantenedor antes de seguir sem MinIO.

- [ ] **Passo 2: testes que falham.** `npm run infra:validate` e `npm run content:test` falham, porque os arquivos não existem. O `content:test` confere:
  - `PUT` e `DELETE` dão `405`;
  - `GET /content-packs/0000000/` dá `404`: não lista, e isso fecha a #46;
  - `GET /content-packs/0000000/.manifest.json.tmp` (um dotfile plantado) dá `404`;
  - o `manifest.json` vem com `Cache-Control: public, max-age=60, must-revalidate` e `ETag`, e um `If-None-Match` com esse ETag dá `304` (o sync do app depende disso);
  - `packs/` vem com `immutable`;
  - `Range: bytes=0-9` num pack dá `206`;
  - `publicar pack divergente aborta sem manifest`: um segundo `publish-content.sh` com o mesmo nome de pack e bytes diferentes sai com código ≠ 0, e o `manifest.json` remoto continua o da primeira publicação.

- [ ] **Passo 3: implemente** os arquivos e rode os dois comandos do Passo 2 de novo, mais o `caddy validate`. O esperado é PASS.

- [ ] **Passo 4: commit.** `git commit -m "feat(infra): host so de conteudo com Caddy file_server e publicacao por rsync (#46)"`

- [ ] **Passo 5: implantação na VPS (ação do administrador, fora do agente).** O registro operacional guarda os dados da VPS.
  1. DNS: um registro `A`/`AAAA` para o nome da Q-B4 apontando para a VPS.
  2. Firewall com 22, 80 e 443 abertas.
  3. Diretório `CONTENT_ROOT` (sugestão: `/srv/guia-ubs/conteudo`), do usuário Unix `publisher`, com `0755`.
  4. Usuário `publisher`:
     - sem senha, sem shell interativo;
     - `authorized_keys` só com a chave SSH do mantenedor A, no formato `command="rrsync -no-del /srv/guia-ubs/conteudo",restrict ssh-ed25519 …`;
     - `-no-del` exige rsync ≥ 3.2.4: confira com `rsync --version`.

     O `publisher` escreve e não apaga. Apagar (o prefixo do ensaio, um pack retirado) é só do administrador, pela própria conta.
  5. `infra/.env` com permissão 600, contendo `CONTENT_DOMAIN`, `ACME_EMAIL` e `CONTENT_ROOT`.
  6. `docker compose -f compose.content.yaml up -d`, sempre com `-f`.

  **Pronto quando:**
  - `curl -sI https://<CONTENT_DOMAIN>/content-packs/0000000/manifest.json` responde com TLS válido (404 antes do 1º pack);
  - um `PUT` responde 405;
  - `docker compose -f compose.content.yaml up -d --force-recreate edge` **não** emite certificado novo (o log do Caddy não mostra `obtaining certificate`).

---

### Task 8: o runbook, o ensaio no host real e o registro do que foi publicado

**Files:**
- Modify: `docs/operacao.md`, com a seção nova "Publicar um pack pela assinatura provisória (dois mantenedores)", logo depois da §2.7, e uma linha na §6 "O que ainda não dá" removida ou ajustada se ficar desatualizada
- Modify: `spec/stack.md`:
  - um parágrafo **"Revisão 2026-11-12 (plano B)"** no fim do ADR-001, com o resultado das verificações da Task 6, a publicação por rsync e o registro em GitHub Release;
  - uma **Revisão 2026-11-12** no ADR-007: o host de conteúdo provisório é um Caddy `file_server` sem MinIO, pelos três fatos com links da Task 7, Passo 1;
  - a **pendência do item 27** no mesmo ADR: o CMS/worker precisa de outro object store (Garage, SeaweedFS ou outro), e o `compose.yaml` segue com MinIO até lá. Se o grupo mantiver o MinIO no item 27, isso fica escrito ali, com a imagem fixada por digest e a aceitação explícita de que não há patch.

- [ ] **Passo 1: escreva o runbook.** São os passos 1 a 5 da Revisão do ADR-001, com os comandos exatos e a ordem.
  1. **B:** `SOURCE_DATE_EPOCH=… PACK_VERSION=… npm run pack:check` e `sha256sum packer/out/content.db`. Publica o hash como comentário na PR da release de conteúdo.
  2. **A:** `PACK_SIGNING_KEY_PATH=/dev/fd/3 npm run pack:build 3< <(comando-do-cofre)`. Confere que o `sha256sum` do `content.db` é igual ao de B; se divergir, **nada é enviado**.
  3. **A:** `PACK_PUBKEY_HEX=<pública> CONTENT_TARGET=publisher@<host>: npm run content:publish -- packer/out 0000000`. O script garante a ordem: packs e assets, a conferência de divergência, e o manifest por último.
  4. **B:** `cd app && dart run tool/verify_published.dart https://<CONTENT_DOMAIN>/content-packs/0000000/manifest.json <pub-hex>`, com saída 0.
  5. **A, o registro:** `gh release create conteudo-0000000-p<PACK_VERSION> packer/out/manifest.json packer/out/packs/pack-*.db --latest=false --title "Conteúdo 0000000 p<PACK_VERSION>" --notes "<hash publicado por B; saída do verify_published>"`.
     - É o backup fora da VPS e a evidência do que foi assinado.
     - `--latest=false` impede que a release de conteúdo tome o lugar da release do APK como "latest".
     - O prefixo `conteudo-` não casa com o `v*` do `app-release.yml` nem com o ruleset de tags. Confira com `/usr/bin/grep -rn "tags:" .github/workflows/` que nenhum workflow dispara nele.

  Toda variável citada já está no `.env.example` ou em `NAO_SAO_ENV`.

- [ ] **Passo 2: ensaio no host real, com chave descartável, sem a chave de produção e sem esperar a #2.**
  - Gere a chave descartável no scratchpad, nunca no repositório.
  - Gere o manifest **sintético** com `packer/test/support/manifest-interop.ts`.
  - Publique-o com `content:publish` na edição `ensaio-plano-b`. Isso exercita o `rrsync` e o `-no-del`.
  - Rode o `verify_published.dart` contra ele com a pública descartável. O esperado é a saída 0.
  - Rode o `content:publish` uma segunda vez e confira que nenhum pack é reenviado.
  - Peça ao administrador que apague `content-packs/ensaio-plano-b/`: o `publisher` não apaga, e isso também é verificado (`rsync --delete` pelo `publisher` falha).
  - Não crie GitHub Release no ensaio.

  Registre a data e o resultado no parágrafo de Revisão do Passo 3.

- [ ] **Passo 3: escreva as Revisões** no `stack.md`.

- [ ] **Passo 4:** `npm --workspace @guia-ubs/cms test`. O esperado é PASS: o `doc-operacao.test.ts` confere as envs e os scripts citados.

- [ ] **Passo 5: commit.** `git commit -m "docs(operacao): runbook da assinatura provisoria, ensaio no host real e registro em release"`

---

### Task 9: medição do Hugging Face e o teto de custo (Q-B3)

**Files:**
- Modify: `spec/arquitetura.md`, com a subseção nova §5.x "Medição do Hugging Face (plano B)"
- Modify: `spec/stack.md`, com uma Revisão 2026-11-12 no ADR-004 que registra:
  - a Q-B2 (URL presa ao sha e à origem, e o sha fica no app);
  - a Q-B3 (gatilhos, ação de saída, tratamento do 429 pela Task 5);
  - o teto de custo.

- [ ] **Passo 1: confira os números oficiais com fonte.** Busque na documentação do Hub os limites de usuário anônimo (resolver: 3.000 requisições por IP a cada 5 min, "sujeito a mudança") e o formato dos cabeçalhos `RateLimit` e `RateLimit-Policy`. Anote o link e a data da consulta. Se o número for outro, use o da fonte.

- [ ] **Passo 2: meça, de duas redes.** Em cada rede:
  - rode `npm run model:check -- <URL da exceção do HF> 8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135 806058240` (a URL é a `huggingFaceExceptionUrl` de `app/tool/model_url_check.dart`);
  - registre:
    - o status do HEAD;
    - o `206` do Range;
    - o tempo do download completo;
    - todo cabeçalho `RateLimit`, `RateLimit-Policy`, `X-RateLimit*` ou `Retry-After`, com `curl -sI -L` na mesma URL.

  As duas redes:
  - **a fixa**, três vezes no mesmo dia;
  - **uma rede móvel brasileira** (aparelho compartilhando dados, atrás do CGNAT da operadora), pelo menos uma vez completa e três `HEAD`.

  Registre qualquer 429.

- [ ] **Passo 3: escreva a §5.x.** Inclua:
  - os números, a data e a origem (cidade e tipo de rede, sem IP e sem nome de operadora);
  - o limite da medição: três downloads não medem uma frota atrás de CGNAT. Por isso o gatilho da Q-B3 também usa os relatos de QA, e o 429 é tratado no app (Task 5).

- [ ] **Passo 4: defina o teto de custo**, com a fórmula: `instalações/mês máximas no host do PRISM = 0,5 × franquia mensal de egress da VPS (GB) ÷ 0,806 GB`.
  - A franquia vem do registro operacional (F-1), sem nome de provedor. O mantenedor informa o número; o agente não o inventa.
  - Escreva o resultado e a regra na Revisão do ADR-004:
    - abaixo do teto, a saída do HF é só uma edição do manifest;
    - acima dele, o modelo fica no HF ou ganha um segundo espelho, e isso é decisão nova.
  - Inclua a conferência mensal do egress no painel da VPS, junto da §3.6 do `implantacao.md`.

- [ ] **Passo 5: escreva a Revisão do ADR-004**, com a Q-B2, a Q-B3, o teto e a ação de saída: `content:publish -- --model`, mais um manifest com `model.url` relativo e o mesmo sha, sem release.

- [ ] **Passo 6: commit.** `git commit -m "docs(adr-004): URL do modelo presa ao sha e a origem; medicao do HF e teto de custo"`

---

### Task 10: `defines.release.json` real e a guarda verde

**Pré-requisitos (fora do agente):**
- **Q-B4 respondida.** Depois desta task, o nome está no APK e não muda.
- **Mantenedor A:** gerar o par Ed25519 de produção **offline** e guardá-lo no cofre, com custódia dupla junto do mantenedor B (ADR-007, Decisão 1). Depois, entregar ao executor **só** a pública em hex, extraída com o comando do cabeçalho de `pack_signing_keys.dart`.

**Files:**
- Modify: `app/config/defines.release.json`:
  - `PACK_MANIFEST_URL` = `https://<CONTENT_DOMAIN>/content-packs/0000000/manifest.json`;
  - `PACK_SIGNING_KEY_K1` = a pública em hex;
  - o `MODEL_URL` fica igual (exceção do HF, como fallback e como host aceito pela regra de origem).
- Modify: `contract/keys/README.md`: a pública de produção, com o `keyId` `k1`, e a diferença para a chave de dev.
- Se a Q-B4 escolheu `conteudo.guiasaude`: uma Revisão do ADR-007 para os dois nomes, mais `spec/implantacao.md` §3.2.

- [ ] **Passo 1:** `cd app && dart run tool/model_url_check.dart --config config/defines.release.json --mode release`. O esperado **antes** da edição é saída 1, com as duas mensagens.

- [ ] **Passo 2: edite**, e rode o comando do Passo 1 de novo. O esperado é saída 0.

- [ ] **Passo 3: confira.**
  - A pública **não** é a de dev: `/usr/bin/grep -c bbfd5b2b app/config/defines.release.json` imprime `0`.
  - O host responde: `curl -sI <PACK_MANIFEST_URL>` dá TLS válido.

- [ ] **Passo 4: commit.** `git commit -m "build(release): manifest de conteudo real e chave publica de producao"`

---

### Task 11: propagação e revisão cruzada

**Files:**
- Modify:
  - `spec/implantacao.md`:
    - nos passos do release (§2.5/§2.6), a chave de produção passa a ser exigida no defines, e a guarda vale para APK e AAB;
    - na §3.2, o host de conteúdo provisório não usa MinIO.
  - `docs/dados-do-usuario.md` §3:
    - o host do PRISM agora existe, na VPS do Brasil;
    - a URL do modelo pode mudar por edição assinada, **só** para o host do manifest ou o do `MODEL_URL` compilado, e o código garante isso (Task 4);
    - a mudança vale na abertura seguinte do app.
  - `CLAUDE.md`, "Release e implantação", com as armadilhas novas:
    - um release sem `PACK_SIGNING_KEY_K1` real aceitaria pack assinado com a chave de dev, e a guarda reprova, inclusive no AAB;
    - o host de conteúdo é `file_server` com `rrsync -no-del`, e o pack vai antes do manifest.

    A linha "R2/CDN→MinIO+Caddy" ganha a ressalva da Revisão do ADR-007.
  - `spec/arquitetura.md`, Roadmap: o plano B entregue, e a pendência do object store no item 27.

- [ ] **Passo 1: edite.**

- [ ] **Passo 2: verifique.**
  - `npm test && npm run typecheck && npm run contract:check && npm run infra:validate && npm run content:test`;
  - `cd app && flutter analyze --fatal-infos && flutter test`;
  - `/usr/bin/grep -rn 'a-definir-no-plano-b' app spec docs CLAUDE.md --exclude-dir=superpowers` não devolve nada.

  O esperado é tudo verde.

- [ ] **Passo 3: commit e PR.**
  - Commit: `git commit -m "docs: propagacao do plano B"`.
  - PR para o `develop`:
    - com `Closes #46` (o fechamento automático não dispara num merge para o `develop`; feche à mão depois do merge, se preciso);
    - citando a #72, que fecha só na tag.
  - A PR lista o que ficou fora do agente:
    - a chave de produção;
    - a implantação na VPS e o usuário `publisher`;
    - a franquia de egress para o teto da Task 9;
    - a resposta da Q-B4.
