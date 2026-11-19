# Imagem própria do `packer` (issue #44) — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** fazer o serviço `packer` do `infra/compose.yaml` subir e construir, assinar e publicar releases de dentro do container. Hoje a imagem não contém `packer/` nem `seed/`.

**Architecture:** o `cms/Dockerfile` ganha um estágio comum `runtime` (node_modules + `contract/`), do qual saem dois alvos: `packer` (só `packer/src`, `seed/assets/` e `seed/golden/atestados.yaml`, com `packer/out` gravável por `node`) e `production` (o CMS, que continua sendo o último estágio). O compose escolhe o alvo de cada serviço. Duas guardas: um teste estático em `packer/test/`, que confere os `COPY` do estágio contra os caminhos que o worker lê, e um smoke no job `infra` do CI. O smoke roda o worker e a leitura do registro de atestados dentro do container, contra um `sqld` migrado.

**Tech Stack:** Docker multi-stage, Docker Compose, `node:test` + `yaml` (já dependência do packer), GitHub Actions.

**Spec:** issue #44 (`gh issue view 44`); contexto em `spec/arquitetura.md` §5.12 e §5.17 (observação final).

## Global Constraints

- A chave Ed25519 **nunca** entra em imagem. Ela continua montada em `/run/secrets/pack_signing_key:ro` (issue #44, escopo 3; Revisão do ADR-001) e **nunca vai para o CI** (`.env.example`). Por isso nenhum passo de CI constrói ou assina pack.
- O `packer` continua **sem `ports:`**. `cms/test/infra-topologia.test.ts` precisa seguir verde sem edição.
- A imagem do `packer` não leva `cms/` (código que atende HTTP), e a do `cms` não leva `packer/src` nem `seed/`.
- "Sem copiar o que não é usado" (issue): de `packer/`, só `package.json` (o `"type": "module"` é necessário) e `src/`. De `seed/`, só `assets/` e `golden/atestados.yaml`.
- Fora do escopo (issue): mudanças em `packer/src/worker.ts`, e a revisão golden (#2).
- Commits sem atribuição de IA (CLAUDE.md). Branch a partir de `develop`; o PR tem base `develop`.
- Nunca sobrescrever `infra/.env`: localmente, use `--env-file /tmp/env44`.
- Se mudar comando, variável ou rota, acrescentar a linha em `docs/operacao.md` (`doc-operacao.test.ts` reprova se o manual ficar para trás).

## Review Focus

1. **`packer/out` sem permissão de escrita.** O estágio roda como `USER node`, e `/app` pertence ao root; `.dockerignore` exclui `packer/out`. O esperado é que `buildPack` crie `packer/out/content.db` sem `EACCES`. O teste está na Task 3 (`test -w`).
2. **Chave privada de desenvolvimento dentro da imagem, sobretudo na do CMS.** `contract/keys/dev-k1.pem` existe na máquina do mantenedor (fora do git), e `COPY contract/` a levaria às **duas** imagens. O risco maior é a do `cms`, que atende HTTP. O esperado é que nenhum `*.pem` entre no contexto. Os testes estão na Task 2 (`.dockerignore`) e na Task 3, com `test ! -e` nas **duas** imagens.
3. **Reenvio de asset pelo CMS publica o placeholder do seed, assinado e sem aviso.** O CMS grava o binário em `assets/${ref}.${ext}` (`cms/src/content/binario.ts:127`), o mesmo caminho do seed. O worker não passa `assetBytes` ao `buildPack`, então lê `seed/<path>`, e a conferência "conferir em vez de corrigir" (`build-pack.ts`) só roda quando há `assetBytes`. Resultado: reenviar um ícone que já existe faz o worker **sobrescrever o `sha256`** com o do placeholder e assinar o placeholder. Só um `ref` novo falha, e falha com uma mensagem enganosa (`generate-placeholders.mjs`). **É a própria #44 que torna esse caminho alcançável em produção.** A correção mexe no worker e fica fora do escopo. A Task 4 abre a issue antes do merge, a §5.20 a descreve com essa gravidade, e a #2 **não pode fechar antes dela**: hoje nada é publicado só porque a suíte golden bloqueia tudo.
4. **Chave montada ilegível para `node` na VPS.** O `packer` roda como `node` (uid 1000). Na máquina do mantenedor o PEM costuma pertencer ao uid 1000, e a Task 4 passaria por coincidência. Na VPS, uma chave `root:root 0600` dá `EACCES` ao assinar. O problema é anterior a este plano e fica **fora do escopo do código**: entra como lacuna na §5.20 e ganha uma linha em `docs/operacao.md` (Task 4, passo 5).
5. **Alvo padrão do `docker build`.** Quem roda `docker build -f cms/Dockerfile .` sem `--target` precisa continuar recebendo o CMS. Por isso `production` é o **último** estágio, e o teste da Task 2 confere essa ordem.

---

### Task 1: Reproduzir o defeito

**Files:** nenhum arquivo do repositório muda. A saída vai para o rascunho da §5.20 (Task 4).

- [ ] **Step 1: Criar a branch**

```bash
git switch develop && git pull && git switch -c fix/44-imagem-packer
```

- [ ] **Step 2: Construir e subir o serviço como está hoje**

```bash
cp infra/.env.example /tmp/env44 && cd infra
docker compose -f compose.yaml --env-file /tmp/env44 build packer
docker compose -f compose.yaml --env-file /tmp/env44 run --rm packer node --import tsx packer/src/worker.ts --once
```

Esperado: falha com `ERR_MODULE_NOT_FOUND` (ou equivalente) em `/app/packer/src/worker.ts`. Guarde a mensagem exata para a §5.20.

---

### Task 2: Estágio `packer` no Dockerfile, alvos no compose e a guarda estática

**Files:**
- Create: `packer/test/imagem-docker.test.ts`
- Modify: `cms/Dockerfile` (estágio `production` inteiro, hoje no fim do arquivo)
- Modify: `infra/compose.yaml:56-59` (`cms.build`), `:96-101` (`packer.build` e `command`) e `:119-120` (comentário do `depends_on: cms` do `packer`)
- Modify: `.dockerignore` (cabeçalho e `**/*.pem`)

**Interfaces:**
- Produces: os estágios `runtime`, `packer` e `production` em `cms/Dockerfile`. O estágio `packer` tem `CMD ["node", "--import", "tsx", "packer/src/worker.ts", "--interval", "60"]`, e o compose deixa de declarar `command:` no `packer`, para o comando ter uma única fonte. As Tasks 3 e 4 usam `docker compose … run --rm packer <cmd>`.

- [ ] **Step 1: Escrever o teste que falha** em `packer/test/imagem-docker.test.ts`, no estilo de `cms/test/infra-topologia.test.ts` (`node:test`, `assert/strict`, `RAIZ = join(import.meta.dirname, '..', '..')`).

Helper `fontesCopiadas(dockerfile: string, estagio: string): string[]`:

- Divide o arquivo por `^FROM\s+(\S+)(?:\s+AS\s+(\S+))?` (sem distinguir maiúsculas) e segue a cadeia `FROM <estágio>` até a imagem base.
- Devolve as **fontes** de cada `COPY` sem `--from`: descarta **todo** argumento que começa com `--` (`--chown`, `--link`, `--chmod`…) e depois o último argumento, que é o destino. Normaliza tirando o `./` inicial e a `/` final.
- **Lança erro com mensagem clara** quando um `COPY` usa a forma JSON (`COPY [...]`) ou termina em `\` (continuação de linha). O helper não as interpreta, e ignorá-las faria o teste passar por vacuidade.
- Uma fonte cobre o caminho `p` quando `p === fonte` ou `p.startsWith(fonte + '/')`.

```ts
const NECESSARIOS = [
  'package.json',
  'packer/package.json',
  'packer/src/worker.ts',
  'contract/ddl',                 // readDdl
  'contract/src/index.ts',        // @guia-ubs/contract (main)
  'seed/golden/atestados.yaml',   // lerAtestadosDoYaml
  // + todo 'assets/...' citado em seed/000_assets.sql, prefixado com 'seed/'
];

test('a imagem do packer contem o que o worker le', () => {
  // faltando = NECESSARIOS sem fonte que os cubra
  assert.deepEqual(faltando, []);
});
test('a imagem do packer nao leva o cms, a do cms nao leva packer/src nem seed', () => {
  assert.ok(!fontesCopiadas(df, 'packer').some((f) => f === 'cms' || f.startsWith('cms/')));
  assert.ok(!fontesCopiadas(df, 'production').some((f) => /^(seed|packer\/src)(\/|$)/.test(f)));
});
test('production e o ultimo estagio: docker build sem --target entrega o CMS', () => {
  assert.equal(ultimoEstagio(df), 'production');
});
test('nenhuma chave privada entra no contexto de build', () => {
  assert.ok(linhasDoDockerignore.includes('**/*.pem'));
});
test('o compose constroi cada servico do seu alvo', () => {
  assert.equal(compose.services.packer.build.target, 'packer');
  assert.equal(compose.services.cms.build.target, 'production');
});
test('fontesCopiadas ignora flags e recusa forma JSON e continuacao', () => {
  assert.deepEqual(fontesCopiadas('FROM x AS a\nCOPY --chown=node:node --link seed/assets/ ./seed/assets/\n', 'a'), ['seed/assets']);
  assert.throws(() => fontesCopiadas('FROM x AS a\nCOPY ["a", "b"]\n', 'a'), /JSON/);
  assert.throws(() => fontesCopiadas('FROM x AS a\nCOPY a \\\n  b\n', 'a'), /continua/);
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `npm --workspace @guia-ubs/packer test`
Esperado: FAIL nos testes novos. O primeiro lista `packer/src/worker.ts`, `seed/golden/atestados.yaml` e os assets como faltando.

- [ ] **Step 3: Reestruturar o fim de `cms/Dockerfile`**

Troque o estágio `production` atual por três estágios:

- `runtime`: `FROM node:22-bookworm-slim`, `WORKDIR /app`, `ENV NODE_ENV=production`, `COPY --from=deps /app/node_modules ./node_modules`, `COPY package.json package-lock.json ./`, `COPY contract/ ./contract/`.
- `packer` (`FROM runtime`): `COPY packer/package.json packer/`, `COPY packer/src/ ./packer/src/`, `COPY seed/assets/ ./seed/assets/`, `COPY seed/golden/atestados.yaml ./seed/golden/`, `RUN mkdir -p packer/out && chown node:node packer/out`, `USER node` e o `CMD` do bloco Interfaces.
- `production` (`FROM runtime`, **por último**): o restante do estágio atual, com os comentários.

Escreva em uma linha de comentário no estágio `packer` o porquê do `chown` e o porquê de o registro de atestados ir junto. Ele é público, e trocá-lo exige redeploy do worker (§5.17).

No `.dockerignore`:
- acrescente `**/*.pem`, com uma linha de comentário ("chave privada nunca entra em imagem; a do pack é montada como segredo");
- reescreva o cabeçalho, que hoje diz que "o mesmo `cms/Dockerfile` constrói os serviços `cms` E `packer`". Agora o arquivo é o mesmo, mas os **alvos** são distintos.

- [ ] **Step 4: Ajustar o compose**

- Em `cms.build`, acrescente `target: production`.
- Em `packer.build`, acrescente `target: packer` e remova a linha `command:` (agora vale o `CMD` da imagem).
- No comentário do serviço `packer`, acrescente uma linha dizendo que a imagem é outra e não contém `cms/`.
- Corrija o comentário do `depends_on: cms` do `packer` (l. 119-120), que hoje fala do `edge`: o motivo dessa dependência é outro. Se não houver motivo, remova a dependência e o comentário.

- [ ] **Step 5: Rodar os testes**

Run: `npm --workspace @guia-ubs/packer test && npm --workspace @guia-ubs/cms test`
Esperado: PASS, inclusive `infra-topologia.test.ts` e `doc-operacao.test.ts` sem edição.

- [ ] **Step 6: Sabotagem local** (registrar o resultado para a §5.20)

Comente a linha `COPY seed/golden/atestados.yaml …` e rode `npm --workspace @guia-ubs/packer test`. Esperado: FAIL citando `seed/golden/atestados.yaml`. Desfaça o comentário.

- [ ] **Step 7: Commit**

```bash
git add cms/Dockerfile infra/compose.yaml .dockerignore packer/test/imagem-docker.test.ts
git commit -m "fix(infra): imagem propria do packer com packer/src e o minimo de seed/ (#44)"
```

---

### Task 3: Smoke do container no CI

**Files:**
- Modify: `.github/workflows/contract.yml`, job `infra` (depois do passo "Compose valido", hoje na l. 108). Os testes do packer, inclusive o estático da Task 2, já rodam no job `contract` via `npm test`.

**Interfaces:**
- Consumes: o alvo `packer` e o `CMD` da Task 2; `cms/scripts/migrate.ts` (aplica migrações e gatilhos usando `CMS_DATABASE_URL`); `lerAtestadosDoYaml(repoRoot: string): unknown[]` de `packer/src/validate.ts`.

- [ ] **Step 1: Rodar o smoke localmente antes de escrever o passo do CI**

```bash
cd infra
C="docker compose -f compose.yaml --env-file /tmp/env44"
$C build packer cms
$C run --rm -T cms node --import tsx cms/scripts/migrate.ts
$C run --rm -T packer node --import tsx packer/src/worker.ts --once | tee /tmp/smoke44
grep -q 'fila vazia' /tmp/smoke44
$C run --rm -T --no-deps packer test -w packer/out
$C run --rm -T --no-deps packer test -r seed/golden/atestados.yaml
$C run --rm -T --no-deps packer node --import tsx -e \
  "import('/app/packer/src/validate.ts').then(m => { if (!Array.isArray(m.lerAtestadosDoYaml('/app'))) process.exit(1) })"
$C run --rm -T --no-deps packer test ! -e contract/keys/dev-k1.pem
$C run --rm -T --no-deps cms    test ! -e contract/keys/dev-k1.pem
$C down -v
```

Esperado: cada comando sai com 0 e o log contém `fila vazia`. Os dois `test ! -e` só provam alguma coisa numa máquina que **tem** o `dev-k1.pem`, e é por isso que rodam aqui, localmente. Um detalhe do runner: lá, `PACK_SIGNING_KEY_HOST_PATH` aponta para um arquivo inexistente, e o compose cria um **diretório** root em `contract/keys/dev-k1.pem`. É inofensivo, porque o `**/*.pem` o tira do contexto de build.

- [ ] **Step 2: Acrescentar o passo "Packer sobe dentro do container" ao job `infra`**

- **Comandos:** os mesmos do Step 1 menos os dois `test ! -e`, com `working-directory: infra`, depois do `cp .env.example .env` que o job já faz. Sem `--env-file`, porque no runner o `.env` é o do exemplo.
- **Encerramento:** termine com `docker compose -f compose.yaml down -v`, em `if: always()`.
- **Comentário** dizendo o que o passo prova e o que não prova: "prova que o worker carrega todos os módulos, alcança o sqld, lê o registro de atestados e tem onde escrever o pack. Não prova build, assinatura nem publicação: isso exige a chave, que nunca vai para CI. A presença de `seed/assets/` é coberta pelo teste estático `packer/test/imagem-docker.test.ts`."

- [ ] **Step 3: Sabotagem no CI, numa branch descartável**

```bash
git switch -c tmp/44-sabotagem
# comente `COPY packer/src/ ./packer/src/` em cms/Dockerfile
git commit -am "tmp: sabotagem #44" && git push -u origin tmp/44-sabotagem
```

Esperado: o run fica vermelho no passo novo do job `infra` e no teste estático do job `contract`. Anote o link do run e apague a branch (`git push origin --delete tmp/44-sabotagem && git switch fix/44-imagem-packer && git branch -D tmp/44-sabotagem`). O commit sabotado não entra na branch do PR.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/contract.yml
git commit -m "ci(infra): packer roda --once dentro do container contra sqld migrado (#44)"
```

---

### Task 4: Verificação ponta a ponta pelo container, issue do asset e registro

**Files:**
- Modify: `spec/arquitetura.md`. Acrescente a subseção `#### 5.20 Resultado da #44 — packer publica de dentro do container`, depois da §5.19. A observação final da §5.17 (l. 1249) ganha "fechada na §5.20".
- Modify: `docs/operacao.md` (a linha sobre a permissão da chave montada; a seção da chave está perto da l. 278)

- [ ] **Step 1: Montar o estado de partida dentro do compose.** Use `up -d db storage cms packer` com `--env-file /tmp/env44` e siga o §4 do `docs/operacao.md` (operador, release, dual review, até `approved`), mais estas pré-condições, **antes** do passo 2:
  - a chave pública de dev registrada em `signing_key` (`cms/scripts/register-signing-key.ts`; o worker recusa uma chave fora da tabela, `docs/operacao.md` l. 278-294);
  - um atestado de teste cadastrado no CMS (`POST /api/golden-cases/atestados`), com um `AT-NNNN` que **não** está no registro da imagem;
  - casos golden importados (`cms:import-golden`, rodado do host, porque a imagem do `cms` não leva `seed/`), ativos, com `reviewed_by` apontando para esse atestado (`MIN_REVISORES = 1`, `contract/src/golden.ts:28`) e passando no modelo de regras da release.

- [ ] **Step 2: Com o registro real da imagem** (`atestados: []`), esperado no `docker compose logs packer`: `BLOQUEADO <id>` com "atestado AT-NNNN do CMS nao consta em seed/golden/atestados.yaml". Isso prova que o arquivo é lido **dentro** do container. Esperado também: nenhum `ENOENT`. (Sem as pré-condições do passo 1, o bloqueio viria como "suíte golden vazia" ou "caso X sem revisão clínica" e não provaria a leitura do registro.)

- [ ] **Step 3: Com um registro de teste montado por cima** (só nesta verificação; nunca commitado: um atestado de teste no registro público seria falso):

```bash
docker compose -f compose.yaml --env-file /tmp/env44 run --rm \
  -v /tmp/atestados-teste.yaml:/app/seed/golden/atestados.yaml:ro \
  packer node --import tsx packer/src/worker.ts --once
```

Antes, use `POST /api/releases/:id/reenfileirar` para limpar o `blocked_at`. `/tmp/atestados-teste.yaml` contém o mesmo atestado do passo 1 (ID, conselho, uf, categoria, `termo_sha256`). Esperado: `ok <id>`, release `published`, e `manifest.json` + `content.db` + assets no bucket (confira no console do MinIO ou com `curl` no `edge`).

- [ ] **Step 4: Abrir a issue do asset, antes do merge**

```bash
gh issue create --label bug,backend,P1 \
  --title "packer: worker ignora o binario enviado pelo CMS e assina o placeholder de seed/assets/" \
  --body "..."
```

O corpo traz o mecanismo do Review Focus 3: o mesmo caminho `assets/${ref}.${ext}`, o worker sem `assetBytes`, o `sha256` sobrescrito sem conferência e o `ref` novo falhando com a mensagem enganosa. Diga que a #44 torna o caminho alcançável em produção, e que **a #2 não pode fechar antes desta**. Comente na #2 citando a issue nova.

- [ ] **Step 5: Escrever a §5.20 e a linha em `docs/operacao.md`.** A §5.20 traz:
  - o erro da Task 1;
  - a decisão: estágio no mesmo Dockerfile em vez de um Dockerfile próprio, porque `deps` é compartilhado e um segundo arquivo duplicaria o `npm ci`;
  - as duas sabotagens (local e o link do run do CI) com seus resultados;
  - o que o smoke do CI prova e o que não prova;
  - as lacunas declaradas, nesta ordem:
    1. **Reenvio de asset pelo CMS publica o placeholder do seed, assinado e sem aviso** (gravidade do Review Focus 3). Link para a issue do passo 4; bloqueia o fechamento da #2.
    2. **A chave montada precisa ser legível pelo uid 1000 (`node`).** Na VPS, uma chave `root:root 0600` dá `EACCES` na hora de assinar. O problema é anterior à #44. Em `docs/operacao.md`, na seção da chave (perto da l. 278), acrescente a linha: dono uid 1000, ou grupo legível com `0640`.
    3. Trocar o registro de atestados exige rebuild e redeploy da imagem do `packer`.
    4. `cms:import-golden` não roda de dentro do container do `cms`: ele lê `seed/golden/clinical_cases.yaml`, que a imagem não leva. Roda do host, como os demais scripts `cms:*`.
    5. `seed/assets/generate-placeholders.mjs` viaja junto (pasta inteira, para não quebrar quando entrar PNG ou áudio).

- [ ] **Step 6: Commit e PR**

```bash
npm --workspace @guia-ubs/cms test   # doc-operacao.test.ts segue verde
git add spec/arquitetura.md docs/operacao.md
git commit -m "docs(arquitetura): resultado da #44 — packer publica de dentro do container"
gh pr create --base develop --title "fix(infra): imagem do packer contém o que o worker lê (#44)" --body "Closes #44. ..."
```

Confira o `--base develop` (memória: PR empilhado não chega ao develop). O corpo do PR cita a issue do passo 4.
