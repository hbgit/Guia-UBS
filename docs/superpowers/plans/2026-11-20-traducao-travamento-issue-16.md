# Travamento otimista na tradução (issue #16) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `PUT /api/content/<entidade>/<chave>/traducoes/<lang>` passa a seguir o mesmo contrato do `PATCH` do CRUD (428 sem pré-condição, 409 com `versaoAtual`, `ETag` na resposta), e a SPA lê a versão antes de gravar e trata o 409.

**Architecture:** A rota continua sendo `PUT`, mas deixa de ser upsert cego. Criação exige `If-None-Match: *` (RFC 9110: "grave só se não existir"); atualização exige `If-Match: "<n>"` e reaproveita `atualizarComVersao` de `cms/src/services/optimistic-lock.ts`. Nenhum dos dois cabeçalhos ⇒ 428; os dois juntos ⇒ 400. Ganha um `GET` irmão que devolve a linha com `ETag`, porque sem leitura a SPA não tem versão para mandar. Na SPA, uma função nova `substituir(lido | null, …)` em `cms/web/src/api/api.ts` sempre envia exatamente um dos dois cabeçalhos — o 428 continua inalcançável pela SPA por construção, como já é para `gravar`.

**Tech Stack:** Hono, Drizzle (libSQL), drizzle-zod, React (SPA em `cms/web/`), `node:test` via `npm test`.

**Spec:** issue #16 (`gh issue view 16`); `spec/arquitetura.md` §5.13, lacuna 2; contrato existente do CRUD em `cms/src/content/crud.ts` (`PATCH`) e `cms/src/services/optimistic-lock.ts`. CLAUDE.md §"CRUD e editor de regras" fixa: `version` chega por `If-Match`, nunca no corpo; ausente ⇒ **428**; o 409 carrega a versão atual.

## Global Constraints

- `version` nunca no corpo; só `If-Match` (e `If-None-Match: *` para criação).
- Sem pré-condição ⇒ status **428**, corpo `{ error: string }`. Não 400.
- Conflito ⇒ status **409**, corpo `{ error: 'a linha mudou desde a leitura', versaoAtual: number }` — mesma mensagem e mesma forma do `PATCH`, para que `classificar` em `cms/web/src/api/api.ts` o reconheça como `conflito_versao` sem mudança. **409, e não o 412 da RFC, é escolha deliberada** (convenção do `PATCH`, da qual `classificar` depende); o manual diz isso por escrito.
- Toda resposta 200/201 de escrita e todo GET de linha levam `ETag: "<n>"`.
- Escrita recusada (400/404/409/428) **não** entra na trilha. Escrita aceita registra `content_translate`; a de atualização com `before`. `entity_id` da tradução é `Object.values(chaveTraducao).join('/')`, com `lang` primeiro (ex.: `pt/fever`, `pt/mun-1/srv-1`).
- `audioRef` é FK nulável para `asset` e está em `CAMPOS_DE_TRADUCAO` das seis entidades: `''` nunca chega ao servidor — vazio vai como `null`.
- Gatilho do item 16: `NEW.version = OLD.version + 1` — não contornar (`atualizarComVersao` já respeita).
- Tudo em pt-BR, sem acento em identificadores/comentários de código (padrão do arquivo). Commits sem atribuição de IA.
- Rota nova recebe linha em `docs/operacao.md`. **Nada a protege:** `doc-operacao.test.ts` pula rotas de conteúdo (`ehRotaDeConteudo`) e o verbo `GET` já aparece no manual — a linha é responsabilidade da revisão.
- Branch: `fix/16-traducao-travamento` a partir de `develop`; PR com base `develop`.

## Review Focus

1. **Tradução sem áudio regravada pela SPA** — esperado 200; `audioRef: null` lido do banco não pode voltar como `''` (FK recusaria e o editor veria "Nao foi possivel gravar"). Teste na Task 2 (`paraEnvio`/`paraFormulario`).
2. **Troca rápida de idioma na SPA** — a resposta do idioma A chegando depois da de B não pode instalar a versão de A. Coberto na Task 2 pelo sinalizador `cancelado` no `useEffect` (verificação manual no Step 6; a SPA não tem harness de componente).
3. **`If-None-Match: *` quando outra pessoa criou primeiro** — esperado 409 com `versaoAtual: 1`, e o texto dela intacto no banco. Teste na Task 1.
4. **Chave composta (`services`, `documents`, `flow-steps`, com `municipalityId`)** — criar e atualizar com 409 funcionam igual à chave simples. Teste na Task 1 com `services`.
5. **`If-Match` em tradução inexistente / malformado / junto de `If-None-Match`** — 404 (não cria em silêncio), 428 e 400, respectivamente. Testes na Task 1.

---

### Task 1: Contrato de travamento na rota de tradução (servidor)

**Files:**
- Modify: `cms/src/content/crud.ts:290-354` (bloco `// --- traducao, aninhada`)
- Modify: `cms/test/support/app.ts:257-276` (`pedido`)
- Modify: `cms/test/crud-registry.test.ts:186-200` (teste que usa PUT sem pré-condição)
- Test: `cms/test/optimistic-lock.test.ts` (acrescentar ao fim)
- Modify: `docs/operacao.md:709` (tabela de rotas), `:751` (exemplo `curl`), `:792` (seção de travamento)

**Interfaces:**
- Consumes: `atualizarComVersao`, `versaoAtual`, `condicaoDaChave`, `coluna` de `cms/src/services/optimistic-lock.ts`; `versaoEsperada(header)`, `colunasLegiveis` e `respostaDeIntegridade` já em `crud.ts`.
- Produces (HTTP, usado pela Task 2):
  - `GET  …/:chave/traducoes/:lang` — `content:read`; 200 com a linha (colunas legíveis) e `ETag: "<version>"`; 404 `{ error: 'nao encontrado' }`.
  - `PUT  …/:chave/traducoes/:lang` — `content:write`, nesta ordem:
    1. `If-Match` **e** `If-None-Match` presentes ⇒ 400 `{ error: 'envie so um: If-Match para atualizar, ou If-None-Match: * para criar' }`.
    2. `If-Match: "<n>"` válido ⇒ `atualizarComVersao`; 200 `{ ok: true, versao }` + `ETag`; `ausente` ⇒ 404; `conflito` ⇒ 409 `{ error, versaoAtual }`.
    3. `If-None-Match` aparado igual a `*` ⇒ insert com `.onConflictDoNothing().returning()`; 201 `{ ok: true, versao: 1 }` + `ETag: "1"`; zero linhas ⇒ 409 com `versaoAtual` lida por `versaoAtual(...)`.
    4. senão (ausente ou `If-Match` malformado) ⇒ 428 `{ error: 'informe If-Match com a versao lida, ou If-None-Match: * para criar' }`.
  - `pedido(fixture, cookie, metodo, caminho, corpo?, ifMatch?: string | number, ifNoneMatch?: string)` — sétimo parâmetro novo, envia `if-none-match` literal (sem aspas).

- [ ] **Step 1: Escrever os testes que falham**

Atualizar `pedido` em `cms/test/support/app.ts` com `ifNoneMatch`. Em `cms/test/optimistic-lock.test.ts`, acrescentar (o `before` existente já criou `fever`). Helper local:

```ts
async function traducaoDe(token: string) {
  const r = await f.client.execute({
    sql: 'SELECT label, version FROM token_translation WHERE token_id = ? AND lang = ?',
    args: [token, 'pt'],
  });
  return r.rows[0] && { label: r.rows[0].label, version: Number(r.rows[0].version) };
}

const TRAD = '/api/content/symptom-tokens/fever/traducoes/pt';
```

Testes, na ordem (dependem do estado do anterior):

```ts
test('traducao: PUT sem pre-condicao recebe 428', ...)
  // status 428; traducaoDe('fever') === undefined
test('traducao: If-Match malformado e 428, como no PATCH', ...)
  // para 'abc', '0', '-1': status 428
test('traducao: If-Match e If-None-Match juntos recebem 400', ...)
  // pedido(..., 1, '*') => 400; traducaoDe('fever') === undefined
test('traducao: If-Match em traducao inexistente e 404, nao cria', ...)
  // pedido(..., { label: 'Febre' }, 1) => 404; traducaoDe('fever') === undefined
test('traducao: If-None-Match * cria com ETag "1"', ...)
  // { label: 'Febre' }, undefined, '*' => 201, etag '"1"'
test('traducao: segunda criacao recebe 409 com versaoAtual e nao sobrescreve', ...)
  // { label: 'Calor' }, undefined, '*' => 409, versaoAtual 1
  // assert.deepEqual(await traducaoDe('fever'), { label: 'Febre', version: 1 })
test('traducao: GET devolve a linha com ETag', ...)
  // 200, etag '"1"', corpo.label === 'Febre'
test('traducao: duas escritas a partir da mesma leitura — a segunda recebe 409', ...)
  // { label: 'Febre alta' }, 1 => 200, etag '"2"'
  // { label: 'Quentura' }, 1 => 409, versaoAtual 2
  // assert.deepEqual(await traducaoDe('fever'), { label: 'Febre alta', version: 2 })
test('traducao: so as escritas aceitas entram na trilha', ...)
  // const t = (await auditRows(f)).filter(l => l.action === 'content_translate' && l.entity_id === 'pt/fever')
  // t.length === 2; t.filter(l => l.before_json).length === 1
  // JSON.parse(atualizacao.before_json).label === 'Febre'
test('traducao: pai inexistente com If-None-Match * e erro de integridade, nao 500', ...)
  // PUT /api/content/symptom-tokens/nao-existe/traducoes/pt, { label: 'X' }, undefined, '*'
  // assert.ok(status === 409 || status === 422); corpo sem versaoAtual
test('traducao: chave composta (services) cria e detecta conflito', ...)
```

O último cria, dentro do próprio teste, `POST /api/content/venues` `{ id: 'UBS', iconRef: 'icon.exemplo', colorToken: 'green', sortOrder: 0 }` e `POST /api/content/services` `{ municipalityId: 'mun-1', id: 'srv-1', venueId: 'UBS', iconRef: 'icon.exemplo', sortOrder: 0 }` (`seedConteudo` já deu `mun-1` e `icon.exemplo`), e então em `/api/content/services/mun-1/srv-1/traducoes/pt`: `'*'` ⇒ 201; `If-Match 1` ⇒ 200 com etag `"2"`; `If-Match 1` de novo ⇒ 409 com `versaoAtual 2`; `SELECT label, version FROM service_translation WHERE municipality_id='mun-1' AND service_id='srv-1' AND lang='pt'` bate com a escrita vencedora; a trilha tem `entity_id === 'pt/mun-1/srv-1'`.

Ajustar `crud-registry.test.ts:186` ("a traducao aninhada grava e sobrescreve pela mesma rota"): primeira chamada com `ifNoneMatch '*'` (espera 201), a segunda com `ifMatch 1` (espera 200); as asserções finais (`label 'Torax'`, versão) ficam.

- [ ] **Step 2: Rodar e ver falhar**

Run: `npm --workspace @guia-ubs/cms test`
Expected: FAIL — o PUT atual responde 200 sem pré-condição, e não há GET (404 de rota).

- [ ] **Step 3: Implementar em `cms/src/content/crud.ts`**

Dentro do `if (entidade.traducao)`: extrair `chaveDaTraducao(params): Chave` (o laço `forEach` atual, `lang` primeiro; usado pelas duas rotas); acrescentar o `GET` (mesmo padrão do GET de linha, com `colunasLegiveis(traducao.tabela)`); trocar o corpo do `PUT` pelos quatro ramos da seção Interfaces, nessa ordem. A validação com `entradaTraducao.omit(...)` fica depois do 400/428 e antes da escrita (como no PATCH). O ramo de atualização lê o `antes` e chama `atualizarComVersao({ client, tabela: traducao.tabela, chave: chaveTraducao, versaoEsperada, valores: validado.data, atorId })`; `recordAudit` só no sucesso. O ramo de criação passa o `insert` por `respostaDeIntegridade` no `catch`. Remover o `onConflictDoUpdate` e o comentário dele — o incremento agora vem de `atualizarComVersao`.

- [ ] **Step 4: Atualizar `docs/operacao.md`**

- Linha 709: o `PUT` passa a "gravar tradução — **exige `If-Match`**, ou `If-None-Match: *` para criar"; nova linha `GET` "ler tradução — devolve `ETag` com a versão".
- Linha 751: o `curl` de exemplo ganha `-H 'If-None-Match: *'`.
- Seção da linha ~792 ("Toda escrita usa travamento otimista"): uma frase dizendo que a tradução segue o mesmo contrato, criando com `If-None-Match: *` (os dois cabeçalhos juntos ⇒ 400), e outra dizendo que pré-condição falha responde **409 com `versaoAtual`, não 412**, de propósito: é a forma que a interface usa para mostrar contra o que se perdeu.

- [ ] **Step 5: Rodar e ver passar**

Run: `npm test && npm run typecheck`
Expected: PASS em `contract`, `cms`, `packer`.

- [ ] **Step 6: Commit**

```bash
git add cms/src/content/crud.ts cms/test/support/app.ts cms/test/optimistic-lock.test.ts cms/test/crud-registry.test.ts docs/operacao.md
git commit -m "fix(cms): traducao exige If-Match ou If-None-Match e devolve ETag (#16)"
```

---

### Task 2: SPA lê a versão e trata o 409

**Files:**
- Modify: `cms/web/src/api/api.ts` (`Opcoes`, `bruto`, nova `substituir`)
- Create: `cms/web/src/conteudo/traducao.ts` (conversão linha ↔ formulário)
- Modify: `cms/web/src/telas/conteudo.tsx:395-466` (componente `Traducoes`)
- Test: `cms/test/web-api-traducao.test.ts` (novo; `web-conformance.test.ts` continua puramente estático)

**Interfaces:**
- Consumes: as rotas `GET`/`PUT` da Task 1; `ler`, `ErroApi`, `Lido` existentes; `CAMPOS_DE_TRADUCAO` de `cms/web/src/conteudo/campos.ts`.
- Produces:
  - `export async function substituir(lido: Lido<unknown> | null, caminho: string, corpo: unknown): Promise<number>` em `api.ts` — `PUT`; com `lido` envia `if-match: "<lido.versao>"`, com `null` envia `if-none-match: *`; devolve a versão do `ETag` (mesma lógica de `gravar`, incluindo o recuo para `corpo.versao`). `Opcoes` ganha `ifNoneMatch?: '*'`.
  - Em `cms/web/src/conteudo/traducao.ts`:
    - `paraFormulario(linha: Record<string, unknown>, campos: readonly string[]): Record<string, string>` — só os `campos`; `null`/`undefined` viram **ausentes** (chave omitida), nunca `''`.
    - `paraEnvio(texto: Record<string, string>, campos: readonly string[]): Record<string, string | null>` — todo campo de `campos`; `''` (ou ausente) vira `null`.

- [ ] **Step 1: Escrever os testes que falham**

Em `cms/test/web-api-traducao.test.ts`:

- Testes puros:
  - `paraFormulario({ label: 'Febre', audioRef: null, version: 3, tokenId: 'x' }, ['label', 'audioRef'])` ⇒ `deepEqual { label: 'Febre' }`.
  - `paraEnvio({ label: 'Febre', audioRef: '' }, ['label', 'audioRef'])` ⇒ `deepEqual { label: 'Febre', audioRef: null }`; `paraEnvio({ label: 'Febre' }, ['label', 'audioRef'])` ⇒ o mesmo.
- Ponta a ponta, `substituir` contra o servidor real: `freshApp`, `sessaoDe(f, 'editor')`, `seedConteudo`, um `symptom-token`. Trocar `globalThis.fetch` por um stub que repassa para `f.app.request(caminho, init)` juntando `cookie` e `origin: TEST_ENV.authBaseUrl` aos cabeçalhos que o `bruto` montou (o mesmo que `pedido` faz); restaurar o original no `after`.

```ts
test('SPA: traducao gravada a partir da mesma leitura recebe conflito_versao', async () => {
  const caminho = '/api/content/symptom-tokens/<id>/traducoes/pt';
  assert.equal(await substituir(null, caminho, { label: 'A', audioRef: null }), 1);
  await assert.rejects(substituir(null, caminho, { label: 'B' }), (e) =>
    e instanceof ErroApi && e.falha.tipo === 'conflito_versao' && e.falha.versaoAtual === 1);

  const lido = await ler<Record<string, unknown>>(caminho);
  assert.equal(lido.versao, 1);
  // o ciclo real da tela: linha lida -> formulario -> envio, com audioRef nulo
  const corpo = paraEnvio(paraFormulario(lido.dados, ['label', 'audioRef']), ['label', 'audioRef']);
  assert.equal(await substituir(lido, caminho, corpo), 2, 'regravar traducao sem audio precisa passar');
  await assert.rejects(substituir(lido, caminho, { label: 'D' }), (e) =>
    e instanceof ErroApi && e.falha.tipo === 'conflito_versao' && e.falha.versaoAtual === 2);
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `npm --workspace @guia-ubs/cms test`
Expected: FAIL — `substituir`, `paraFormulario` e `paraEnvio` não existem (erro de import).

- [ ] **Step 3: Implementar `substituir` em `api.ts` e `traducao.ts`**

Comentário de cabeçalho de `substituir` no mesmo espírito do de `gravar`: o parâmetro `Lido | null` obriga quem chama a decidir entre "atualizo o que li" e "crio porque li 404"; não há terceira forma, logo o 428 (e o 400 dos dois cabeçalhos) segue inalcançável. Em `traducao.ts`, uma linha de comentário dizendo por que `''` vira `null`: `audioRef` é FK para `asset`.

- [ ] **Step 4: Reescrever `Traducoes` em `conteudo.tsx`**

- `const caminho = \`${caminhoDaLinha(entidade, chave)}/traducoes/${lang}\`` — **string**; é ela (e não `chave`, um objeto novo a cada render) que entra nas dependências do efeito.
- Estado `lido: Lido<Record<string, unknown>> | null | undefined` (`undefined` = carregando) e uma função `carregar` que o efeito e o botão "Reler" usam.
- `useEffect(() => { let cancelado = false; setLido(undefined); limpa ok/erro; ler(caminho).then(r => { if (!cancelado) { setLido(r); setTexto(paraFormulario(r.dados, campos)); } }).catch(e => { if (cancelado) return; nao_encontrado ⇒ setLido(null), setTexto({}); outro ⇒ setErro('Nao foi possivel ler a traducao.') }); return () => { cancelado = true; }; }, [caminho])`. O `cancelado` impede que a resposta de um idioma anterior instale a versão errada.
- `enviar`: `const versao = await substituir(lido, caminho, paraEnvio(texto, campos))`; depois `setLido({ dados: paraEnvio(texto, campos), versao })` e `ok` "Traducao gravada.".
- `conflito_versao` ⇒ "Alguem gravou esta traducao antes de voce (versao N). Use "Reler esta traducao" para ver a versao atual — nada foi sobrescrito." e mostrar um botão **"Reler esta traducao"** que repete a leitura (sem recarregar a página: o idioma escolhido fica). Outros erros como hoje.
- Botão "Gravar traducao" `disabled={lido === undefined}`. Se a leitura falhou por outro motivo que não 404, a mensagem de erro e o botão "Reler" aparecem, então o botão desabilitado nunca fica sem explicação.
- `textarea` usa `value={texto[c] ?? ''}` (como hoje); o `''` só existe no formulário.
- Remover o `<p className="aviso">` "Esta gravacao nao tem travamento…" e o comentário JSX acima dele; trocar `criar` por `substituir` no import (remover `criar` se ficar sem uso).

- [ ] **Step 5: Rodar e ver passar**

Run: `npm test && npm run typecheck && npx tsc -p cms/web --noEmit`
Expected: PASS.

- [ ] **Step 6: Olhar a tela**

Subir o CMS (`npm --workspace @guia-ubs/cms run dev`) e conferir:
- duas abas no mesmo item, gravando nas duas: a segunda mostra o conflito; "Reler" traz o texto da primeira, sem perder o idioma escolhido;
- regravar uma tradução sem áudio passa;
- trocar de idioma várias vezes, rápido, e gravar: passa, sem 409 espúrio;
- com o servidor parado, abrir as traduções: aparece mensagem de erro, não um botão travado e mudo.

- [ ] **Step 7: Commit**

```bash
git add cms/web/src/api/api.ts cms/web/src/conteudo/traducao.ts cms/web/src/telas/conteudo.tsx cms/test/web-api-traducao.test.ts
git commit -m "fix(cms/web): traducao le a versao antes de gravar e trata o 409 (#16)"
```

---

### Task 3: Fechar a lacuna nos documentos

**Files:**
- Modify: `cms/test/doc-operacao.test.ts:238` (remover a entrada de `LACUNAS_ABERTAS`; a regex `/travamento otimista/i` casava com outras partes do manual e nunca acusaria nada)
- Modify: `docs/operacao.md:1159` (remover a linha "Tradução não tem travamento otimista" da tabela de lacunas)
- Modify: `spec/arquitetura.md:1128` (lacuna 2 do §5.13 riscada e marcada "Fechada pela #16", no formato da lacuna 1 do mesmo bloco: `~~…~~ **Fechada pela #16.** Texto original: …`)

- [ ] **Step 1: Remover a entrada `'traducao nao tem travamento otimista'` de `LACUNAS_ABERTAS`**

- [ ] **Step 2: Editar os dois documentos conforme a lista acima**

Conferir que nenhuma outra frase ainda afirma que a tradução se sobrescreve em silêncio: `grep -rn "vence a [uú]ltima\|sem travamento\|n[aã]o tem travamento" docs/ spec/ cms/web/src` não deve achar nada sobre tradução.

- [ ] **Step 3: Rodar**

Run: `npm test`
Expected: PASS, incluindo `doc-operacao.test.ts`.

- [ ] **Step 4: Commit**

```bash
git add cms/test/doc-operacao.test.ts docs/operacao.md spec/arquitetura.md
git commit -m "docs: fecha a lacuna de travamento da traducao (#16)"
```
