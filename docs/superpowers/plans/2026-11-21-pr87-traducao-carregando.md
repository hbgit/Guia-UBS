# Tradução travada enquanto carrega (ajuste da PR #87) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enquanto a tradução de um idioma está sendo lida, o formulário fica vazio, travado e mostra "Carregando", para que nada digitado seja descartado em silêncio quando o `GET` voltar.

**Architecture:** O ajuste fica todo no componente `Traducoes` de `cms/web/src/telas/conteudo.tsx`, na branch `fix/16-traducao-travamento` (worktree `../Guia-UBS-16`), e entra na própria PR #87. A regra "o formulário aceita edição?" vira uma função pura em `cms/web/src/conteudo/traducao.ts`. A SPA não tem harness de componente, então esse é o único pedaço testável sem navegador, e é ele que o seletor, os campos e o botão consultam: uma fonte só para "travado".

**Tech Stack:** React (SPA em `cms/web/`), `node:test` via `npm test`.

**Spec:** a revisão da PR #87 (achado P2, `conteudo.tsx` 423–435 e 497–505); o contrato da issue #16 e o plano `docs/superpowers/plans/2026-11-20-traducao-travamento-issue-16.md`, Task 2.

## Global Constraints

- O ajuste entra na branch `fix/16-traducao-travamento`. Nada de PR nova.
- Identificadores e comentários de código em pt-BR sem acento, como no resto do arquivo. Commits sem atribuição de IA.
- `audioRef` continua passando por `paraFormulario`/`paraEnvio`. O vazio nunca vai como `''`.
- Nenhuma mudança de servidor ou de contrato HTTP.

## Review Focus

1. **Digitar durante a leitura de outro idioma.** Os campos estão desabilitados e vazios, então não há texto para perder. Coberto por `formularioTravado` (Task 1) e conferido no navegador (Task 2).
2. **A leitura falha (servidor fora).** Os campos continuam travados, aparecem a mensagem de erro e "Reler esta traducao", e não sobra "Carregando" ao lado do erro. Teste do estado `erro` na Task 1, mais conferência na Task 2.
3. **"Reler" depois de um 409.** O formulário limpa, trava, recarrega e mostra o texto que venceu. Conferido na Task 2.
4. **Tradução inexistente (`lido === null`).** O formulário fica editável e vazio, e a gravação cria. Teste na Task 1.
5. **Gravação em curso.** Tudo fica travado, como já era. O teste na Task 1 mantém isso.

---

### Task 1: Formulário vazio e travado durante a leitura

**Files:**
- Modify: `cms/web/src/conteudo/traducao.ts` (nova `formularioTravado`)
- Modify: `cms/web/src/telas/conteudo.tsx` (componente `Traducoes`: efeito de leitura, `<select>`, `<textarea>`, botão, indicador)
- Test: `cms/test/web-api-traducao.test.ts` (acrescentar)

**Interfaces:**
- Produces: `export function formularioTravado(lido: unknown | null | undefined, salvando: boolean): boolean` em `traducao.ts`. Devolve `true` quando `lido === undefined` (lendo, ou a leitura falhou) ou quando `salvando`. `null` (tradução ainda não existe) não trava.

- [ ] **Step 1: Escrever o teste que falha**

```ts
test('formularioTravado: trava lendo e salvando; nao trava em traducao inexistente', () => {
  assert.equal(formularioTravado(undefined, false), true, 'lendo');
  assert.equal(formularioTravado({ dados: {}, versao: 1 }, true), true, 'salvando');
  assert.equal(formularioTravado({ dados: {}, versao: 1 }, false), false, 'lida');
  assert.equal(formularioTravado(null, false), false, 'inexistente: a gravacao cria');
});
```

Importar `formularioTravado` junto de `paraEnvio`/`paraFormulario`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd cms && node --import tsx --test test/web-api-traducao.test.ts`
Expected: FAIL, `formularioTravado` não exportado.

- [ ] **Step 3: Implementar `formularioTravado` e usá-la em `Traducoes`**

- No efeito de leitura, junto de `setLido(undefined)`: `setTexto({})`.
- `const travado = formularioTravado(lido, salvando)` é a única condição de travamento:
  - `<select disabled={travado}>`;
  - `<textarea disabled={travado}>`;
  - `<button type="submit" disabled={travado}>`.

  Isso substitui as condições `salvando` e `lido === undefined || salvando` de hoje. O seletor também trava durante a leitura, de propósito: cada troca dispara uma leitura, e não há motivo para enfileirar várias.
- Indicador: `{lido === undefined && !erro && <p role="status">Carregando traducao…</p>}`, logo acima dos campos. Com `erro`, o que aparece é o erro e "Reler".
- Comentário de uma linha no `setTexto({})`: texto de outro idioma na tela convida a digitar sobre ele, e o `GET` descartaria o que fosse digitado.

- [ ] **Step 4: Rodar e ver passar**

Run: `npm test && npm run typecheck && (cd cms/web && npx vite build)`
Expected: PASS (contract 49, cms 426, packer 83, 0 falhas); build sem erro.

- [ ] **Step 5: Commit**

```bash
git add cms/web/src/conteudo/traducao.ts cms/web/src/telas/conteudo.tsx cms/test/web-api-traducao.test.ts
git commit -m "fix(cms/web): traducao vazia e travada enquanto carrega (#16)"
```

---

### Task 2: Verificação no navegador, condição da aprovação

Sem mudança de código, a menos que algo falhe aqui. Exige navegador e o CMS de pé: sqld, um operador com 2FA ativo e o Termo aceito (`docs/operacao.md` §2.3, 2.4, 2.4.1, 2.5 e 2.9). **Quem executa:** a pessoa que mantém o projeto, ou o agente, se a sessão tiver ferramenta de navegador. Sem navegador, o agente para aqui e devolve o roteiro.

- [ ] **Step 1: Subir o CMS em modo de desenvolvimento** (`docs/operacao.md` §2.9) e criar um `symptom-token` com tradução `pt` por `curl` (§4.1, com `If-None-Match: *`).

- [ ] **Step 2: Conferir, com o DevTools em "Slow 3G" para a leitura demorar:**
  1. Trocar `pt` para `es`. Os campos ficam vazios e desabilitados, aparece "Carregando traducao…", e o seletor e o botão ficam travados até o `GET` voltar.
  2. `es` inexistente: o formulário volta vazio e editável, e gravar cria (201).
  3. Duas abas no mesmo item e idioma, gravando nas duas. A segunda mostra o conflito, e "Reler" traz o texto da primeira sem perder o idioma escolhido.
  4. Com o CMS parado, trocar de idioma. Aparecem a mensagem de erro e "Reler", os campos ficam travados e não sobra "Carregando".
  5. Regravar uma tradução sem áudio passa.

- [ ] **Step 3: Registrar o resultado na PR #87**

Comentar na PR com os cinco itens marcados. Se algum falhar, abrir o defeito como passo novo da Task 1, com teste que falhe antes, e repetir a Task 2.

- [ ] **Step 4: Push**

```bash
git push
```
