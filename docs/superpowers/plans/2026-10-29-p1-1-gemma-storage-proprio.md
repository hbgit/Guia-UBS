# P1-1 (issue #3) — Gemma servido do storage próprio — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** decidir, por ADR aprovado pelo dono, se o Gemma 3 1B pode ser usado no caso de uso do Guia UBS e, se puder, servir o `.gguf` do MinIO/Caddy próprio cumprindo a §3.1 e a §4.2 dos Gemma Terms of Use, com `huggingface.co` fora de `app/lib`. **Enquanto não houver servidor do projeto, o app baixa direto do huggingface.co, como exceção do ADR-004** (seção "Exceção").

**Enquadramento (decisão do dono, 2026-10-29):** o Guia UBS é um projeto open source de pesquisa e extensão do grupo de pesquisa PRISM, com ambiente de produção do próprio grupo, sem vínculo formal com a UFRR, e com apoio de colaboradores do curso de Medicina na revisão clínica. Nesta fase não há parecer jurídico formal: a licença do modelo é cumprida por obrigação, e J1–J3 viram regras de produto e implementação, com gatilhos registrados para revisitar a parte formal.

**Architecture:** a Task 0 é um **portão**: ela só redige o ADR-004 e para. Depois da aprovação, o host sai do código e entra por `--dart-define=MODEL_URL` (sem valor padrão; ausência vira estado explícito, não host escondido). O objeto `models/<nome>-<sha256>.gguf` vai para o bucket `content-packs` com o Notice e a cópia do Agreement ao lado, publicado por um script que recusa arquivo cujo SHA-256 não seja o de `model_catalog.dart`. O Notice, a cópia em inglês e a cláusula nos termos chegam ao usuário pelo APK (assets), por uma tela "li e concordo" na primeira abertura e a cada versão nova dos termos, pelos dois pontos de distribuição do onboarding e pela tela "Sobre". **Recusar os termos desliga só o assistente**: sem aceite, o Gemma não é baixado nem carregado, e o app segue completo pelo `RuleOnlyEngine` e pelo conteúdo estático.

**Tech Stack:** Flutter/Dart 3 (Riverpod, GoRouter, `flutter_test`), Bash + `mc` (imagem MinIO já fixada no compose), Caddy 2.9, Node `node:test` (testes do `cms/` e do `packer/`).

**Spec:** issue #3 (`docs/superpowers/issues/2026-10-28/P1-1.md`), `spec/stack.md` §1.1/§9/§10 (ADR-003), `spec/PRD.md` §4.1, `spec/lgpd.md` RF04/RF17/RT11. Termos externos lidos em **2026-10-29**: `ai.google.dev/gemma/terms` e `gemma.ai/resources/terms` (ambos "Last modified: April 1, 2026"), `ai.google.dev/gemma/prohibited_use_policy` e `gemma.ai/resources/prohibited-use/` (ambos "Last modified: February 21, 2024").

## Global Constraints

- **Portão em dois níveis.** As Tasks 1 e 2 começam depois de o ADR-004 ser **submetido** (Task 0 commitada e entregue ao dono); as Tasks 0b, 3, 4, 4b e 5, só depois de ele ser **aprovado**. Consequência aceita: com a Task 1 no ar e o `model_url_check` recusando `huggingface.co`, builds novos saem **sem assistente** (estado "não configurado", orientação pelo `RuleOnlyEngine`) até o modelo estar publicado no storage próprio. Antes do piloto isso é aceitável e coerente com "verificar primeiro".
- **Sem parecer jurídico nesta fase** (decisão do dono, 2026-10-29, que substitui a anterior). O ADR-004 é aprovado pelo dono sobre o texto, e registra os **gatilhos** que reabrem a parte formal: publicar em loja, parceria formal com Secretaria ou UBS, crescer além do piloto, ou coletar dados de participantes para publicação (este último vai a Comitê de Ética em Pesquisa).
- **Nenhum texto sugere vínculo institucional.** Nem com o Google (§4.2), nem com a UFRR, nem com o curso de Medicina. "Grupo de pesquisa PRISM" identifica o projeto; o curso só é citado como "conteúdo clínico revisado por colaboradores do curso de Medicina", e **só depois de os colaboradores concordarem com a menção**.
- **Recusar os termos nunca bloqueia orientação.** A tela de aceite tem saída "usar sem o assistente" que leva direto à inicial; o gate de red flags, o `RuleOnlyEngine` e o conteúdo estático não dependem de aceite (INV-1, INV-8).
- Fora do escopo: troca de modelo, bench da #18 (P2-5), allowlist de endpoints em CI da #4 (P1-2).
- Nenhum host em `app/lib`, nem como `defaultValue`, **inclusive com a exceção do HF** (o host entra pelo build). Critério: `grep -r huggingface.co app/lib` vazio, e `grep -rn "https\?://" app/lib/sync/model_catalog.dart` vazio.
- O texto do Notice e todo trecho exigido pelos termos ficam **literais, em inglês**. Traduções são cortesia e dizem, por escrito, que a versão em inglês prevalece.
- O SHA-256 publicado é **exatamente** `8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135` (806 058 240 B), o mesmo de `model_catalog.dart:26`. Conferido no Hugging Face em 2026-10-29: o `lfs.oid` de `gemma-3-1b-it-Q4_K_M.gguf` é esse valor.
- `network_security_config` do release **não muda** (hoje não existe arquivo; não criar um que afrouxe nada).
- Documentos novos em pt-BR; commits sem atribuição de IA (CLAUDE.md).
- Rota, variável de ambiente ou script novo exige linha em `docs/operacao.md` no mesmo commit (`cms/test/doc-operacao.test.ts`).
- Branch: `feat/3-gemma-storage-proprio`, a partir de `develop`.

## Exceção: o modelo baixado direto do huggingface.co (decisão do dono, 2026-10-29)

**Esta seção prevalece sobre o resto do plano onde houver conflito.** Enquanto não houver domínio nem servidor do projeto, o app baixa o modelo **direto do Hugging Face**, como **exceção registrada no ADR-004**, e não do storage próprio. As Tasks 0, 1 e 2 já entregues ficam: a exceção usa o mesmo mecanismo (`MODEL_URL` por `--dart-define`), e o storage próprio vira a **saída da exceção**, pronta para quando houver servidor.

**Como a exceção entra sem reabrir o que já foi feito:**
- **A URL continua fora de `app/lib`.** O host entra pelo build (`config/defines.<modo>.json`), então o critério da issue `grep -r huggingface.co app/lib` vazio continua valendo e o app continua sem host padrão escondido.
- **Revisão fixa, não `main`.** A URL da exceção é `https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/f9c28bcd85737ffc5aef028638d3341d49869c27/gemma-3-1b-it-Q4_K_M.gguf`: o commit `f9c28bc` do repositório da `ggml-org` (último em 2025-03-12). Com `resolve/main/`, um push da `ggml-org` poderia trocar o arquivo sob o mesmo nome; o SHA-256 do app recusaria, mas a frota ficaria sem modelo sem ninguém ter mudado nada aqui.
- **A exceção é uma URL só, não um host.** `tool/model_url_check.dart` aceita `huggingface.co` só para essa URL exata, e só enquanto o catálogo for o Gemma 3 1B Q4_K_M (`8ccc5cd1…a135`). Outro repositório, `resolve/main/` ou outro modelo continuam reprovando (Task 1b).
- **Integridade não muda.** O SHA-256 está no app; o HF não consegue entregar outro arquivo como se fosse este.

**Medido em 2026-10-29:** a URL fixada responde `302` para `us.aws.cdn.hf.co` (CDN na AWS, EUA), que honra `Range` (`206`, `Content-Range: bytes 100-199/806058240`, `Content-Length: 100`). No emulador, a #31 já registrou `206` com offset maior que zero seguindo esse redirecionamento (`spec/arquitetura.md`, resultado da issue 31). São **dois hosts** no caminho, `huggingface.co` e o da CDN, e a allowlist da #4 precisa dos dois (o nome da CDN pode variar: a #4 decide se fixa o domínio `hf.co`).

**O que a exceção custa, e o ADR-004 registra:**
1. **Diverge de três decisões**, agora de propósito e com prazo: §9 (100% self-host), PRD §4.1 e LGPD-RF17(d)/RT11 (fornecedor inventariado, endpoint fixo).
2. **Transferência internacional de dado pessoal.** Cada aparelho entrega ao Hugging Face (EUA/França) e à CDN (AWS, EUA) o **IP** e o `User-Agent` na hora do download. Não é sintoma nem identificador do app, mas IP é dado pessoal, e a LGPD trata a transferência internacional nos arts. 33 a 36. É o mesmo motivo pelo qual o ADR-001 rejeitou o Vercel. Exige: linha no inventário de fornecedores da `spec/lgpd.md` (RF06, RT11), menção no aviso de privacidade pt/es (hoje ele diz só "para baixar o modelo de linguagem no primeiro acesso", sem dizer de quem) e **validação pelo encarregado (DPO)**, marcada como pendente como as outras do documento.
3. **Disponibilidade de terceiro.** Se a `ggml-org` apagar o repositório, ou o HF mudar a URL, o download falha e o app segue pelo `RuleOnlyEngine` (INV-8). Nenhum aparelho recebe arquivo errado.
4. **Termos do Gemma.** Com o arquivo vindo do HF, quem transmite é o HF, não o projeto, e a §3.1 (*Distribution*) fica em dúvida. **O plano mantém tudo o que já foi decidido** (Notice, cópia dos termos, cláusula, "li e concordo"), por três motivos: a §3.2 (restrições de uso) vale para o uso pelo projeto de qualquer jeito; o repasse por pendrive continua sendo distribuição; e a saída da exceção volta a ser distribuição. O que muda: o Notice e as cópias **não** vão ao lado do arquivo no HF (o projeto não controla aquele repositório); vão no app, que é por onde a pessoa recebe o aviso.

**Fim da exceção (gatilhos, no ADR-004):** domínio e servidor do projeto definidos (então publicar pela Task 2 e trocar o `MODEL_URL`; os aparelhos já provisionados **não** baixam de novo, porque a identidade é o SHA-256); a `ggml-org` ou o HF tirarem o arquivo do ar; objeção do encarregado (DPO) à transferência internacional; ou o app crescer além do piloto.

## Divergências encontradas (issue × código × termos vigentes)

Registradas aqui em vez de seguidas às cegas. Cada uma tem destino no plano.

| # | Divergência | Onde | Destino |
|---|---|---|---|
| D1 | **A frase do Notice tem duas versões vigentes.** `ai.google.dev/gemma/terms` exige *"…found at ai.google.dev/gemma/terms"*; `gemma.ai/resources/terms`, com a mesma data (April 1, 2026), exige *"…found at gemma.ai/resources/terms"*. As páginas `ai.google.dev` mostram o banner *"This documentation is deprecated. Please visit the new documentation at gemma.ai."* A issue cita só a primeira. | termos | ADR-004, decisão D-A (Task 0) |
| D2 | **A §3.1(2) pede "a copy of this Agreement"**, que é o texto em inglês. A issue lista só `gemma_terms_{pt,es}.md`; uma tradução não é cópia. | issue | Task 3 cria `gemma_terms_en.md` e `gemma_prohibited_use_en.md` (literais); pt/es viram cortesia |
| D3 | **`PACK_MANIFEST_URL` tem host padrão escondido** (`http://127.0.0.1:9000/…`, `pack_background_sync.dart:28-31`). O pedido "mesmo comportamento de `PACK_MANIFEST_URL` quando não fornecido (falha clara)" descreve o que ele **não** faz. `MODEL_URL` segue o *mecanismo* (`String.fromEnvironment`), não o padrão. | código | Task 1 para o modelo; o pack é a **#45** (P1), que reaproveita o guarda de build da Task 1 |
| D4 | **`stack.md` §1.1 diz "Gemma 3 1B QAT int4"**; o artefato é o **Q4_K_M não-QAT** convertido pela `ggml-org`. | spec | Task 0b corrige a linha ao referenciar o ADR |
| D5 | **"O gate decide a severidade" é impreciso.** `mergeVerdict` (`app/lib/triage/domain/severity.dart:93-109`) devolve o **desfecho do modelo** (`outcomeId`, `source: engine`) quando a severidade dele é maior: o cartão e o local mostrados passam a ser os que o Gemma nomeou. O modelo só escolhe desfecho revisado e só para cima, mas escolhe. | issue | ADR-004, análise do item 3.4 |
| D6 | **Não há política de leitura anônima do bucket versionada** no repositório (nenhum `mc anonymous` em `infra/`, `packer/` ou `docs/`). O edge serve GET anônimo hoje por configuração feita fora do repo, ou não serve. **Medido em 2026-10-29** num MinIO descartável com a imagem do compose: `mc anonymous set download <bucket>/<prefixo>` **mescla** (os statements anteriores ficam), mas (a) libera **listagem** anônima (`GET /content-packs?prefix=models` → 200 com as chaves) e (b) gera o recurso `models*`, sem barra, que liberou `models-x/leak.bin` (200). | infra | Task 2 aplica política **explícita** só em `models/*`, sem listagem, conferindo antes/depois; a política dos packs é a **#46** (P2) |
| D7 | **LGPD-RF04 cobre aceite do piloto e do CMS, não do usuário final.** O app não tem identidade de usuário (INV-2), então não há registro de aceite **por titular**. | lgpd | Task 4b: aceite com clique, marca guardada só no aparelho, sem identificar ninguém e sem sair dele. Não é um registro RF04 e o ADR diz isso |
| D8 | **`PRD.md` §4.1 ("única superfície de rede do app") e `lgpd.md` RF17(e) ("a única integração de rede permitida é o download de manifest/pack") já estavam desatualizados desde o ADR-003**, que acrescentou o download do modelo. | spec | Task 0b propaga |
| D9 | **`termos_{pt,es}.md` têm "Responsável: A ser preenchido".** | legal | Task 0 Step 5: "Guia UBS, projeto de pesquisa e extensão desenvolvido pelo grupo de pesquisa PRISM" + `prismufrr@gmail.com`. Um grupo de pesquisa não tem personalidade jurídica: a linha **identifica** quem mantém, não cria parte que assina contrato. Registrado no ADR como decisão consciente, com gatilhos |
| D11 | **A issue pede "cópia dos termos" em pt/es.** | escopo | Decisão do dono, **publicada na #3 em 2026-10-29**: cópia literal só em inglês; Política traduzida em `gemma_prohibited_use_{pt,es}.md`; `gemma_terms_{pt,es}.md` vira resumo em linguagem simples |
| D12 | **A marca local de aceite é coluna nova no `user.db`**, e coluna nova custa quatro coisas no mesmo commit (CLAUDE.md): migração com teste v2→v3, lista de `lgpd_surface_test.dart`, entrada na tela de privacidade pt/es e linha em `spec/lgpd.md`. São duas colunas (versão respondida e resposta). | código | Task 4b |
| D13 | **Gemma 4, conferido em 2026-10-29.** A licença é Apache 2.0 (`gemma.ai/resources/apache-2/`) e o Appendix dos Gemma Terms of Use não o lista. Há **cinco** modelos, não quatro: E2B (2,3 B efetivos, 5,1 B com embeddings), E4B, 12B, 26B-A4B (MoE) e 31B. **O E2B não cabe no ADR-003:** o `gemma-4-E2B-it-Q4_0.gguf` da `ggml-org` tem **2,84 GB** e o QAT Q4_0 do próprio Google, **3,35 GB**, contra teto de 1,2 GB para APK + modelo + pack. O llama.cpp está fixado em `b6100` (ADR-002, agosto de 2025), anterior ao Gemma 4 (repositórios de abril de 2026), então a troca exige subir a tag e revalidar o shim. Apache 2.0 tira a Política de Uso e a cláusula, mas não zera as obrigações: a §4 pede cópia da licença, aviso em arquivo modificado e o NOTICE de origem, se houver. O "Intended Use Statement" de `gemma.ai` não é condição de licença. | modelo | ADR-004, seção "Alternativa de licença": registrada e **não perseguida** (decisão do dono); a #18 segue em ~1 B |
| D14 | **O app ainda soa como classificação de risco.** O cartão `card.routine` do pack semente diz *"Não é emergência."* (`seed/002_content.sql`), ou seja, uma afirmação de classificação negativa, contra a regra "direção única". `privacidade_pt.md:14` diz "quando a **triagem** termina". As strings de UI (`app_pt.arb`) já não usam "triagem": só as chaves usam. | conteúdo | **#48** (P1), aberta em 2026-10-29; o conteúdo do pack muda pelo portão de revisão clínica da #2, não neste branch |
| D15 | **A tela "Sobre" mostra o logo do Telessaúde UFRR** (`aboutLogos`, `assets/branding/about_telessaude_ufrr.png`) sob "Realização". Com "sem vínculo formal com a UFRR", logotipo de instituição ao lado de orientação de saúde pode ser lido como aval. | UI | **Decisão do dono: fica**, com justificativa no ADR-004 (Task 0 Step 3). O e-mail `prismufrr@gmail.com` também carrega "ufrr" e entra na mesma justificativa |
| D17 | **A issue pede "download no aparelho a partir do endpoint próprio"**; com a exceção, o download é do HF. | escopo | Critério alterado para "a partir da URL da exceção, com SHA-256 conferido"; texto para a #3 em "Pendências" |
| D18 | **O ADR-004 já commitado (`6d98617`) diz "origem: bucket `content-packs`"** e não prevê a exceção. | ADR | Task 0c |
| D19 | **`model_url_check` recusa `huggingface.co`** (Task 1, já entregue). | código | Task 1b: exceção de uma URL exata |
| D20 | **O aviso de privacidade não diz de quem o modelo é baixado**, e o download do HF leva o IP para fora do país. | lgpd | Task 4c |
| D16 | **O ADR atribuía a responsabilidade da §3.3 ao "operador (município)".** Não há município operador: quem distribui é o projeto. | ADR | Task 0 Step 3 |
| D10 | `app/tool/fetch_model.sh` também cita `huggingface.co`. Fica: é ferramenta de bancada fora de `app/lib`, e é a origem *upstream* do script de publicação. | código | nenhum (registrado) |

## Review Focus

1. **`Accept-Encoding: gzip` no caminho Caddy → MinIO.** O `HttpClient` do `dart:io` envia `Accept-Encoding: gzip` por padrão e o site de conteúdo tem `encode zstd gzip`. Se o `.gguf` sair comprimido, o `Content-Length` some e o `Range` deixa de ter sentido. Esperado: sem `Content-Encoding` no `.gguf`. Coberto pelo `check-model-endpoint.sh` da Task 2, que manda o mesmo cabeçalho.
2. **Build sem `MODEL_URL` num aparelho que já tem o modelo.** Esperado: `ModelReady` sem rede, e não "não configurado". Teste na Task 1.
3. **`.parcial` começado no Hugging Face e retomado do storage próprio.** Os bytes são idênticos (mesmo SHA-256), então o `Range` anexado é válido; se o servidor responder `200`, o downloader recomeça do zero. Esperado: conclui com `sha ok`. Teste na Task 1.
4. **URL apontando para o objeto de outro modelo** (o `MODEL_URL` de um build antigo depois de trocar o catálogo). Esperado: o build recusa antes de compilar, porque a URL precisa terminar em `-<sha256 do catálogo>.gguf`. Teste na Task 1 (`model_url_check_test.dart`).
5. **Abrir o app numa emergência depois de uma atualização dos termos.** Esperado: o portão de termos custa um toque ("Usar sem o assistente" vai direto à inicial) e nunca exige ler nada para chegar ao "Estou com sintomas". Teste na Task 4b (`recusar nao bloqueia a orientacao`).
6. **Notice desatualizado depois de troca de modelo.** Esperado: teste reprova quando o Notice não cita o `fileName` de origem e o SHA-256 de `activeModel`. Teste na Task 3.

---

## Mapa de arquivos

| Arquivo | Responsabilidade | Task |
|---|---|---|
| `spec/stack.md` §10 (ADR-004), §1.1, §9 | decisão, referência, nota de licença | 0, 0b |
| `spec/PRD.md` §4.1, `spec/lgpd.md` RF17 | propagação (D8) | 0b |
| `app/lib/sync/model_catalog.dart` | `modelUrl` por `String.fromEnvironment`, sem host | 1 |
| `app/lib/sync/model_downloader.dart` | `ModelUnavailableReason.notConfigured`; `ModelArtifact.isConfigured` | 1 |
| `app/lib/sync/model_provisioning.dart` | `SetupBlockReason.notConfigured` | 1 |
| `app/lib/ui/onboarding/onboarding_screen.dart` | estado bloqueado "não configurado"; Notice no passo de download (Task 4) | 1, 4 |
| `app/tool/model_url_check.dart` + `app/tool/build_apk.sh` | guarda de build: `MODEL_URL` presente, `https` no release, nome casa com o SHA | 1 |
| `app/config/defines.example.json` | modelo do arquivo de `--dart-define-from-file` | 1 |
| `infra/Caddyfile`, `infra/Caddyfile.dev` | `models/` na classe imutável | 2 |
| `infra/scripts/publish-model.sh`, `infra/scripts/check-model-endpoint.sh` | publicar e conferir o objeto | 2 |
| `package.json` (raiz) | `model:publish`, `model:check` | 2 |
| `app/assets/legal/gemma_notice.txt` | Notice literal | 3 |
| `app/assets/legal/gemma_terms_en.md`, `gemma_prohibited_use_en.md` | cópia literal do Agreement e da Política | 3 |
| `app/assets/legal/gemma_terms_{pt,es}.md` | resumo dos Terms of Use (cortesia) | 3 |
| `app/lib/ui/legal/terms_gate_screen.dart` + `gubsRedirect` | "li e concordo" na 1ª abertura e a cada versão nova | 4b |
| `app/lib/prefs/user_database.dart` (`termsVersionAnswered`, `termsAccepted`), tela de privacidade, `spec/lgpd.md` | a marca local e seus quatro custos | 4b |
| `app/assets/legal/gemma_prohibited_use_{pt,es}.md` | Política traduzida (cortesia) | 3 |
| `README.md` | responsabilidade de quem distribui | 0 |
| `app/lib/ui/more/legal_document.dart` | `gemmaAssetsFor`, `loadGemmaDocuments` | 3 |
| `app/lib/ui/more/gemma_documents_screen.dart` + rota `/mais/sobre/gemma` | leitura do Notice e dos termos | 3 |
| `app/lib/ui/more/about_screen.dart` + ARB | seção "Modelo de linguagem" | 3 |
| `app/assets/legal/termos_{pt,es}.md` | cláusula vinculante (§3.1(1)) | 4 |
| `docs/operacao.md` | seção "Publicar o modelo" | 2 |
| `spec/arquitetura.md` §5 (próxima livre, hoje 5.18) | evidência em emulador | 5 |

---

### Task 0: ADR-004 — redigir e PARAR (portão)

**Files:**
- Modify: `spec/stack.md` (novo `### ADR-004` depois do ADR-003, antes do `---` da linha 383)

**Interfaces:**
- Produces: ADR-004 com status **PROPOSTO**, com as decisões do dono já escritas (D-A…D-C, responsável, regras de produto R1–R3, A-1 como #47, gatilhos, alternativa Gemma 4). Depois do commit e da entrega, as Tasks 1 e 2 podem começar; as demais esperam o dono aprovar o texto.

- [ ] **Step 1: Criar o branch**

```bash
git switch develop && git pull && git switch -c feat/3-gemma-storage-proprio
```

- [ ] **Step 2: Reler as quatro páginas e registrar a leitura**

Abrir, nesta data, `https://ai.google.dev/gemma/terms`, `https://gemma.ai/resources/terms/`, `https://ai.google.dev/gemma/prohibited_use_policy`, `https://gemma.ai/resources/prohibited-use/`. Conferir que as datas continuam "April 1, 2026" e "February 21, 2024". Se alguma mudou, a análise abaixo é refeita contra o texto novo antes de escrever o ADR. Ler também, no texto oficial vigente, as duas normas brasileiras que o dono citou e que o ADR vai citar com link e artigo: a **Resolução Cofen nº 661/2021** (classificação de risco como atividade privativa do enfermeiro na equipe de enfermagem) e a **RDC Anvisa nº 657/2022** (software como dispositivo médico, e a exclusão de software de bem-estar não destinado a prevenção, diagnóstico ou tratamento). O ADR cita o dispositivo exato; se o texto não disser o que se espera, o ADR registra a divergência em vez de repetir a paráfrase. Conferir de novo os fatos de D13 (licença e tamanhos do Gemma 4).

- [ ] **Step 3: Redigir o ADR-004 com esta estrutura e este conteúdo**

Título: `### ADR-004 — Gemma 3 1B no caso de uso do Guia UBS e redistribuição pelo storage próprio: **PROPOSTO** (2026-10-29)`.

**Contexto.** O modelo é baixado de `huggingface.co/ggml-org/…` (`model_catalog.dart:24-25`), contra §9, PRD §4.1 e LGPD-RT11/RF17. Servir do storage próprio é *Distribution* pela §1.1(b). O Gemma 3 está no Appendix dos termos (§1.1(c): vale "regardless of the source"). Datas lidas e as duas URLs de cada documento.

**Leitura da Política de Uso Proibido contra o caso de uso.** Tabela com as colunas *item · o que diz (citação curta em inglês) · o caso de uso · o argumento arquitetural responde? · onde não responde*. Conteúdo:

| Item | Caso de uso | Responde? | Onde não responde |
|---|---|---|---|
| **3.4** *"Making automated decisions in domains that affect material or individual rights or well-being (e.g., … healthcare …)"* | O SLM recebe os tokens de sintoma e pode nomear um desfecho revisado de severidade maior que a do gate; `mergeVerdict` então mostra o cartão e o local do modelo (D5). Nada é concedido ou negado: a pessoa recebe orientação e decide. | **Parcialmente.** `max(gate, llm)` elimina o dano de falsa tranquilização, e o espaço de ação é um conjunto de desfechos com dual review. | Hoje o Gemma **participa** da escolha de para onde a pessoa vai, num domínio listado literalmente ("healthcare"). "Só escala" limita a direção, não tira a natureza de decisão automatizada. **Resposta do projeto (J1):** regras de produto R1–R3 e a #47 (A-1), com a qual o modelo deixa de escolher desfecho. |
| **2.2 / 3.6** exercício ilegal/não licenciado de profissão, *"medical/health"* | O cartão diz onde ir, sem diagnóstico nem prescrição; regras e textos são autorados e revisados por profissionais. | **Para diagnóstico e prescrição, sim** (atos privativos da Lei 12.842/2013). | Classificar gravidade e encaminhar se parece com classificação de risco, privativa do enfermeiro (Res. Cofen 661/2021). **Resposta do projeto (J2):** o app não se apresenta nem funciona como classificação de risco (R1, R2), e o conteúdo é revisado por colaboradores do curso de Medicina pelo portão da #2 (R3). |
| **3.3** *"Misleading claims of expertise or capability … (e.g. health …)"* | Textos dizem "não faz diagnóstico", "revisão clínica pendente"; o selo de procedência (RF-15) diz quando o assistente contribuiu. | **Sim**, desde que os textos continuem assim. | Depende de texto, não de arquitetura: a Task 3 revisa "Sobre"; a página da loja não está no repositório e entra como checklist em `docs/operacao.md`. |
| **3.1** proveniência de conteúdo gerado | O app não mostra texto gerado: mostra um desfecho do pack. O selo de procedência informa a origem. | **Sim.** | — |
| **2.5** (inferir dado sensível sem consentimento; PII) | Sintomas são dado sensível, processados no aparelho, para a própria pessoa, sem persistência nem transmissão (INV-2/INV-5). | **Sim**, quanto à política. | A base legal LGPD é outra questão, já tratada em `lgpd.md`. |
| 1, 2.1, 2.3, 2.4, 3.2, 3.5, 4 | Não aplicáveis ao caso de uso (uma linha cada, dizendo por quê). | — | — |

Mais três pontos dos termos, sem ser da Política: **§3.2** reserva ao Google o direito de restringir uso ("remotely or otherwise"); o app offline não pode ser desligado à distância, mas a obrigação contratual de parar existe. **§3.3**: *"You and your users are solely responsible for Outputs"*, o que coloca a responsabilidade sobre a saída em quem distribui o app: o projeto, para o build que ele distribui (D16). **§3.1(3)**: o `.gguf` foi modificado (convertido para GGUF e quantizado em Q4_K_M) pela `ggml-org` a partir de `google/gemma-3-1b-it`. O README do repositório da `ggml-org` não traz aviso de modificação, e o arquivo não pode receber um sem mudar o SHA-256. O aviso vai no Notice ao lado e no app (D-B).

**Obrigatório × boa prática.** O ADR separa as duas coisas.
- *Obrigatório, de qualquer jeito:* cumprir a licença do modelo que o projeto redistribui. É a condição para redistribuir o Gemma 3, e não depende de formalidade jurídica: Notice (Task 3), cópia do Agreement (Task 3), cláusula nos termos (Task 4) e aviso de modificação (D-B).
- *Boa prática, que mantém o projeto honesto quanto ao que ele é:* as respostas a J1–J3 abaixo.

**Respostas do projeto, sem parecer formal nesta fase:**
- **J3 vira implementação.** Tela "li e concordo" na primeira abertura e a cada versão nova dos termos, com a marca guardada só no aparelho (Task 4b), mais a identificação do projeto (Step 5). É cumprimento de boa-fé da §3.1(1) para um projeto educacional. Recusar desliga só o assistente.
- **J1 e J2 viram regras de produto**, sustentadas pela revisão clínica:
  - **R1, linguagem:** o app explica sinais de alerta e onde procurar atendimento; não se apresenta como "triagem" nem "classificação de risco" (Res. Cofen 661/2021).
  - **R2, direção única:** o app diz "procure atendimento" ou "procure atendimento urgente", nunca "você não precisa procurar atendimento". O conteúdo semente ainda viola isso (D14).
  - **R3, revisão:** todo conteúdo exibido é autorado e revisado clinicamente; o portão da #2 já garante isso, e a revisão pelos colaboradores do curso de Medicina se encaixa ali.
  - Consequência regulatória registrada: a RDC Anvisa 657/2022 não alcança software de bem-estar não destinado a prevenção, diagnóstico ou tratamento (dispositivo exato citado após a leitura do Step 2). Isso só vale enquanto produto, textos, onboarding e página da loja forem coerentes com o rótulo educacional.
- **A-1 vira decisão de design, não jurídica: [#47](https://github.com/hbgit/Guia-UBS/issues/47).** O modelo só sinaliza "escalar" e o desfecho exibido vem da regra. Tudo o que a pessoa vê passa a ser conteúdo revisado pela equipe clínica, o que torna "educacional" uma descrição verdadeira. Custos registrados na issue: perde-se a escolha fina entre desfechos de mesma severidade, a bancada de §5.1 é refeita e o contrato de `decodeSuggestion`/`mergeVerdict` muda.
- *Resolvidas por escolha conservadora:* J4, frase do Notice → D-A usa as duas; J5, §3.1(3) para arquivo modificado por terceiro → D-B põe o aviso de qualquer forma; J6, aparelhos que baixaram do Hugging Face → são de desenvolvimento, e **todo aparelho do piloto é provisionado do zero a partir do storage próprio**; J7, repasse por pendrive → tratado como distribuição, com Notice no fluxo OTG (Task 4) e os arquivos ao lado do `.gguf` (Task 2).

**Responsável (decisão consciente).** "Guia UBS, projeto de pesquisa e extensão desenvolvido pelo grupo de pesquisa PRISM", com o e-mail compartilhado do projeto (`prismufrr@gmail.com`). Um grupo de pesquisa não tem personalidade jurídica: a linha identifica quem mantém o app, mas não cria uma parte que assina contrato. Para uma iniciativa educacional open source nesta fase, é escolha razoável e comum. O app distribuído pelo projeto é responsabilidade do projeto; quem compilar e distribuir a própria versão responde por ela (frase também no README, Step 5).

**Logo do Telessaúde UFRR e e-mail com "ufrr" (decisão do dono: ficam).** O ADR registra por quê, sem afirmar vínculo que não existe. Papel do PET Telessaúde UFRR, nas palavras do dono (2026-10-29), transcrito literalmente no ADR: *"O PET Telessaúde UFRR atuou no diagnóstico da necessidade social e no desenvolvimento de uma solução direcionada à comunidade, articulando ações entre docentes e monitores discentes."* Daí: o logo está sob "Realização", isto é, crédito por essa participação, e não aval nem responsabilidade institucional pelo app distribuído; a mesma tela traz o aviso de que o conteúdo ainda não passou por revisão clínica (`aboutClinicalNotice`), que existe justamente para impedir a leitura de logotipo como endosso (comentário de `about_screen.dart`); nenhum texto do app ou dos termos afirma vínculo institucional, e o guarda da Task 3 impede que algum passe a afirmar; e o responsável declarado nos termos é o grupo PRISM. O ADR distingue a participação de um programa (o PET) de um vínculo formal da universidade com o app, que não existe. Gatilho próprio: se a UFRR ou o Telessaúde pedirem a retirada, ou se surgir vínculo formal, o logo e o e-mail são revistos.

**Gatilhos para revisitar a parte formal** (qualquer um reabre este ADR, e com ele parecer jurídico e entidade com personalidade jurídica): publicar o app em loja; parceria formal com Secretaria de Saúde ou UBS; crescer além do piloto; coletar dados de participantes para publicação. O último é ética em pesquisa: num projeto de pesquisa e extensão, avaliar o uso com pessoas passa por Comitê de Ética em Pesquisa antes de começar.

**Alternativa de licença: Gemma 4 (Apache 2.0).** Num projeto sem estrutura jurídica, o Gemma 3 é a única peça com política de uso e obrigações contratuais próprias. O Gemma 4 sai sob Apache 2.0, a mesma família do resto do ecossistema, e trocar eliminaria J1, J3, a Política, a cláusula e o Notice do Gemma de uma vez (a §4 da Apache continua pedindo cópia da licença e aviso de modificação, bem mais leves). **O obstáculo é técnico e já está medido (D13):** o menor modelo, o E2B, tem 2,84 GB em Q4_0, 2,4 vezes o teto de 1,2 GB do ADR-003, e exige subir o llama.cpp da tag `b6100` (ADR-002). A troca depende de: (a) a bancada da #18 com o E2B no aparelho de referência; (b) reabrir o ADR-003 (footprint, disco livre de 3 GB, RAM), porque nenhum quantizado publicado do E2B cabe na régua atual; (c) nova tag do llama.cpp com o shim revalidado. **Decisão do dono (2026-10-29): não perseguir agora.** A #18 continua mirando modelos de ~1 B de parâmetros com licença OSI; o ADR-003 não é reaberto por causa do Gemma 4. A alternativa fica registrada para o caso de surgir um quantizado do Gemma 4 dentro do orçamento.

**Decisões do dono (2026-10-29), registradas no ADR:**
- **D-A (Notice):** um arquivo com **as duas frases**, ambas literais: primeiro a de `gemma.ai/resources/terms`, depois a de `ai.google.dev/gemma/terms`. As duas versões têm a mesma data e não há como saber qual o Google trata como canônica; repetir cumpre as duas.
- **D-B (aviso de modificação):** aprovada. O Notice acrescenta um parágrafo em inglês dizendo que o arquivo não é o original do Google, quem converteu e quantizou, de qual repositório, e que o Guia UBS o redistribui sem outra modificação, com o SHA-256.
- **D-C (notificação e aceite):** a cláusula entra nos termos do app (nova versão datada). O app pede **"li e concordo"** na primeira abertura e a cada versão nova dos termos (Task 4b, que substitui o aviso passivo da versão anterior do plano); a resposta fica só no aparelho, sem identificar ninguém e sem sair dele (D7, INV-2). Recusar desliga só o assistente. O Notice e o link para os termos também aparecem nos **dois** pontos de distribuição do onboarding, o download (`_Consent`) e a importação por pendrive (oferecida no `_Blocked`), e na tela "Sobre".
- **Origem e espelho:** origem = bucket `content-packs`, chave `models/gemma-3-1b-it-Q4_K_M-<sha256>.gguf`, no edge `{$CONTENT_DOMAIN}`; espelhos federados também recebem Notice e Agreement (o script publica os três juntos), e quem opera espelho redistribui e fica sujeito à §3.1.

**Desfecho desfavorável (ADR REJEITADO).**
- *Fica pronto e entra mesmo assim:* Task 1 (`MODEL_URL`, guarda de build, estado "não configurado"), que é independente de modelo e cumpre o critério `grep huggingface.co app/lib`; Task 2 (Caddy `models/`, scripts de publicação e de conferência de `Range`), parametrizada por arquivo e SHA.
- *Descartado:* Tasks 3 e 4 como estão (Notice, cópias, cláusula, seção do "Sobre") e a publicação do Gemma no storage (Task 2, Step 6). A Task 4b ("li e concordo" por versão dos termos) **fica**: vale para qualquer mudança dos termos do app, só perde a parte que liga a resposta ao modelo. A Task 5 espera o modelo novo.
- *Consequência que não pode ficar implícita:* a Política restringe **uso**, não só distribuição. Se o uso for vetado, baixar o Gemma do Hugging Face também fica vetado no piloto. Até a troca, builds de piloto saem **sem** `MODEL_URL` e a triagem roda pelo `RuleOnlyEngine` (o estado "não configurado" da Task 1 oferece "continuar sem o assistente").
- *Issue P0:* aberta com `gh issue create` **depois de o dono confirmar o texto** (é publicação externa): título "P0: trocar o modelo SLM (ADR-004 rejeitado)", corpo com link para o ADR-004, escopo (escolher por benchmark entre candidatos OSI, como Qwen2.5 Apache-2.0 e Phi-3.5-mini MIT de §9; conferir a licença Apache-2.0 que `gemma.ai` indica para o Gemma 4 e se há tamanho compatível com o ADR-003; trocar `activeModel` e o SHA; revisar o ADR-003), dependência da #18 (P2-5), que **deixa de ser contingência**. Atualizar `docs/superpowers/issues/2026-10-28/P2-5.md` e `_index.json` com a nova prioridade.

**Revisão.** Reabrir se os termos ou a Política mudarem (a data de "Last modified" é conferida a cada troca de modelo), se o papel do SLM no `mergeVerdict` mudar (a #47 muda), se a troca para o Gemma 4 passar nas três condições da "Alternativa de licença", ou em qualquer gatilho da parte formal.

- [ ] **Step 4: Commit do ADR como proposto**

```bash
git add spec/stack.md
git commit -m "docs(adr): ADR-004 propoe uso e redistribuicao do Gemma 3 1B (#3)"
```

- [ ] **Step 5: Responsável nos termos e responsabilidade no README**

E-mail compartilhado do projeto: `prismufrr@gmail.com` (decisão do dono, 2026-10-29). Em `app/assets/legal/termos_{pt,es}.md`, trocar "A ser preenchido antes da publicação." / "Para completar antes de la publicación." por:
- pt: *"Guia UBS, projeto de pesquisa e extensão desenvolvido pelo grupo de pesquisa PRISM. Contato: prismufrr@gmail.com."*
- es: *"Guia UBS, proyecto de investigación y extensión desarrollado por el grupo de investigación PRISM. Contacto: prismufrr@gmail.com."*

Sem menção à UFRR. O curso de Medicina **não** entra agora: só entra, como "conteúdo clínico revisado por colaboradores do curso de Medicina", depois de os colaboradores concordarem, e esse acréscimo é um commit próprio. Avançar a data do cabeçalho `<!-- versao -->`.

No `README.md`, seção "Licença", acrescentar: *"O grupo de pesquisa PRISM responde pelo aplicativo que ele distribui. Quem compilar e distribuir a própria versão a partir deste código responde por ela, inclusive pelo cumprimento dos termos do modelo de linguagem que embarcar ou redistribuir."*

Teste em `legal_documents_test.dart`: `'termos identificam o projeto, sem e-mail pessoal nem vinculo institucional'` → os dois `termos_*.md` contêm "grupo de pesquisa PRISM" / "grupo de investigación PRISM", contêm `prismufrr@gmail.com`, **não** contêm "A ser preenchido" nem "Para completar", e, **fora do endereço de e-mail**, não contêm "UFRR" nem "Universidade" (o teste remove o endereço antes de procurar). Ver falhar antes da troca, passar depois.

```bash
git add app/assets/legal/termos_pt.md app/assets/legal/termos_es.md app/test/ui/more/legal_documents_test.dart README.md
git commit -m "docs(legal): identifica o projeto PRISM como responsavel pelo app (#3)"
```

- [ ] **Step 6: Submeter e parar a parte que depende de aprovação.** Entregar ao dono o ADR-004 para aprovação do texto. A partir daqui as Tasks 1 e 2 podem começar; 0b, 3, 4, 4b e 5 esperam a aprovação. Se for rejeitado, seguir o ramo "Desfecho desfavorável".

---

### Task 0b: ADR aprovado — status, referência e propagação

*Só depois da aprovação.* Atende ao critério "ADR aprovado pelo dono e referenciado em `spec/stack.md` §1.1".

**Files:**
- Modify: `spec/stack.md` (título do ADR-004; §1.1 linha 16; §9, nota "Modelo (Gemma 3 1B)")
- Modify: `spec/PRD.md` §4.1 (linha da tabela "`GET manifest.json`")
- Modify: `spec/lgpd.md` LGPD-RF17 (e)

- [ ] **Step 1:** Trocar `**PROPOSTO**` por `**ACEITO**`, com a data e qualquer ajuste que o dono tenha pedido ao aprovar o texto.
- [ ] **Step 2:** §1.1, linha "Inferência local": `Gemma 3 1B QAT int4 (GGUF)` → `Gemma 3 1B Q4_K_M (GGUF, ggml-org), servido do storage próprio — ver [ADR-004](#10-registro-de-decisões-arquiteturais-adr)` (D4).
- [ ] **Step 3:** §9, nota do modelo: acrescentar que redistribuir obriga a §3.1 (Notice, cópia do Agreement, cláusula nos termos), que o Gemma 4 é Apache 2.0 mas o E2B não cabe no ADR-003 e não é perseguido agora (D13), e apontar o ADR-004.
- [ ] **Step 4:** PRD §4.1 e LGPD-RF17(e): incluir o download do modelo pelo edge próprio como segunda chamada (ADR-003/ADR-004), mantendo "qualquer nova chamada exige revisão de privacidade em PR" (D8).
- [ ] **Step 5: Verificar e commitar**

Run: `grep -n "ADR-004" spec/stack.md spec/PRD.md spec/lgpd.md`
Expected: a linha do §1.1, o título do ADR, a nota do §9, a linha do PRD e a do RF17.

```bash
git add spec/
git commit -m "docs: ADR-004 aceito e propagado para PRD e LGPD (#3)"
```

---

### Task 1: `MODEL_URL` por `--dart-define`, sem host no código

Independente do desfecho do ADR. Critérios: `grep -r huggingface.co app/lib` vazio; aparelhos que já têm o modelo não baixam de novo.

**Files:**
- Modify: `app/lib/sync/model_catalog.dart`
- Modify: `app/lib/sync/model_downloader.dart`
- Modify: `app/lib/sync/model_provisioning.dart:68-80, 339-347`
- Modify: `app/lib/ui/onboarding/onboarding_screen.dart` (`_Blocked`)
- Create: `app/tool/model_url_check.dart`, `app/tool/build_apk.sh`, `app/config/defines.example.json`
- Modify: `app/.gitignore` (`config/defines.*.json`, exceto `defines.example.json`)
- Test: `app/test/sync/model_catalog_test.dart` (novo), `app/test/sync/model_downloader_test.dart`, `app/test/sync/model_provisioning_test.dart`, `app/test/tool/model_url_check_test.dart` (novo)

**Interfaces:**
- Produces:
  - `const String modelUrl = String.fromEnvironment('MODEL_URL');` em `model_catalog.dart`, sem `defaultValue`. `gemma3_1bQ4` passa `url: modelUrl`.
  - `bool get isConfigured` em `ModelArtifact`: `true` quando `url` é URI absoluta com esquema `http`/`https` e host não vazio.
  - `ModelUnavailableReason.notConfigured`, com `detail: 'MODEL_URL ausente ou invalida neste build'`.
  - `SetupBlockReason.notConfigured`.
  - `String? modelUrlProblem(String? url, {required bool release, required String expectedSha256})` em `app/tool/model_url_check.dart`: `null` = ok; senão a mensagem.

- [ ] **Step 1: Escrever os testes que falham**

`app/test/sync/model_catalog_test.dart`:
```dart
test('o catalogo nao carrega host nenhum', () {
  final fonte = File('lib/sync/model_catalog.dart').readAsStringSync();
  expect(fonte, isNot(contains('huggingface.co')));
  expect(RegExp(r'https?://').hasMatch(fonte), isFalse);
});
test('sem --dart-define, o artefato se declara nao configurado', () {
  // `flutter test` roda sem MODEL_URL: este e o build "esquecido".
  expect(modelUrl, isEmpty);
  expect(activeModel.isConfigured, isFalse);
});
test('a identidade do modelo e o SHA-256 e o nome, nao a URL', () {
  expect(activeModel.sha256, '8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135');
  expect(activeModel.fileName, 'gemma-3-1b-q4.gguf');
});
```

`model_downloader_test.dart` (acrescentar, usando o `artifact()` local com `url` parametrizável):
- `'URL ausente e sem arquivo: notConfigured sem nenhum byte de rede'` → `ModelUnavailable(reason: notConfigured)`; servidor local de controle recebe zero requisições.
- `'URL ausente com modelo ja verificado: ModelReady sem rede'` → grava arquivo de teste com o SHA do artefato no destino; `ModelReady`.
- `'URL ausente com parcial completo (OTG): ModelReady sem rede'` → `.parcial` com exatamente `sizeBytes` e o SHA certo; `ModelReady`; zero requisições.
- `'parcial incompleto sem URL: notConfigured, zero requisicoes'` → `.parcial` com metade de `sizeBytes`; `ModelUnavailable(reason: notConfigured)`; o `.parcial` continua no disco com o mesmo tamanho (uma URL futura retoma dele); zero requisições.
- `'parcial de outro host retoma no novo host com o mesmo conteudo'` → `.parcial` com os primeiros N bytes, servidor local que honra `Range` (206) servindo o mesmo conteúdo; resultado `ModelReady` e SHA confere.

`model_provisioning_test.dart`: `'build sem MODEL_URL bloqueia com notConfigured e oferece seguir sem o assistente'` → `SetupState(stage: blocked, blockReason: notConfigured)`; a ação de degradar (linha ~374) leva a `readyDegraded`.

`app/test/tool/model_url_check_test.dart` (`sha = activeModel.sha256`):
```dart
expect(modelUrlProblem(null, release: false, expectedSha256: sha), contains('MODEL_URL'));
expect(modelUrlProblem('', release: false, expectedSha256: sha), contains('MODEL_URL'));
expect(modelUrlProblem('models/x.gguf', release: false, expectedSha256: sha), contains('absoluta'));
expect(modelUrlProblem('http://10.0.2.2:8081/content-packs/models/gemma-3-1b-it-Q4_K_M-$sha.gguf',
    release: true, expectedSha256: sha), contains('https'));
expect(modelUrlProblem('https://huggingface.co/ggml-org/x/gemma-3-1b-it-Q4_K_M-$sha.gguf',
    release: true, expectedSha256: sha), contains('storage proprio'));
expect(modelUrlProblem('https://c.exemplo.invalid/content-packs/models/gemma-3-1b-it-Q4_K_M-${'0' * 64}.gguf',
    release: true, expectedSha256: sha), contains(sha));
expect(modelUrlProblem('https://c.exemplo.invalid/content-packs/models/gemma-3-1b-it-Q4_K_M-$sha.gguf',
    release: true, expectedSha256: sha), isNull);
expect(modelUrlProblem('http://10.0.2.2:8081/content-packs/models/gemma-3-1b-it-Q4_K_M-$sha.gguf',
    release: false, expectedSha256: sha), isNull);
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd app && flutter test test/sync/model_catalog_test.dart test/sync/model_downloader_test.dart test/sync/model_provisioning_test.dart test/tool/model_url_check_test.dart`
Expected: FAIL (`modelUrl` e `isConfigured` não definidos; o catálogo ainda contém `huggingface.co`).

- [ ] **Step 3: Implementar**

- `model_catalog.dart`: `modelUrl` como na Interface; doc comment diz que não há padrão de propósito (D3) e que o valor chega pelo `--dart-define-from-file` de `tool/build_apk.sh`. O isolate do WorkManager não precisa de nada: `--dart-define` é constante de compilação do snapshot AOT, que é o mesmo para `main` e para `gubsCallbackDispatcher`. Dizer isso no comentário.
- `ModelDownloader.ensureAvailable`: regra **sem URL configurada, só seguem os caminhos que resolvem sem rede**. Antes do portão de disco: `if (!artifact.isConfigured && !_resolvesOffline()) return const ModelUnavailable(ModelUnavailableReason.notConfigured, detail: …)`, com `bool _resolvesOffline() => destination.existsSync() || _partialLength() == artifact.sizeBytes`. São exatamente os dois atalhos do `ResumableDownloader` que não tocam a rede: destino existente (`resumable_downloader.dart:276-285`) e `.parcial` com o tamanho anunciado (298-304). Qualquer outro caso, inclusive `.parcial` incompleto, vira `notConfigured` e **não apaga** o parcial. Se o atalho resolver mas o hash divergir, o `fetch` devolve `Rejected` sem requisição (linhas 307-312), o que continua correto.
- `model_background_sync.dart`: `ModelUnavailable()` já devolve `true` (não reagendar); conferir que `notConfigured` cai ali. Sem mudança de código.
- `model_provisioning.dart`: mapear `notConfigured → SetupBlockReason.notConfigured`. `onboarding_screen.dart` `_Blocked`: mensagem "Este aparelho não tem de onde baixar o assistente. O atendimento funciona sem ele." (tela é de agente; segue o padrão de string em código da própria tela) com as saídas já existentes: importar por pendrive e seguir sem o assistente.
- `app/tool/model_url_check.dart`: `modelUrlProblem` com as regras do teste, nesta ordem: ausente → absoluta → host `huggingface.co` ("o modelo vem do storage proprio (ADR-004)") → `https` quando `release` → caminho termina em `-$expectedSha256.gguf`. `main(args)` lê `--config <json>` e `--mode <debug|profile|release>`, importa `activeModel` de `package:guia_ubs/sync/model_catalog.dart`, imprime o problema e sai com 1.
- `app/tool/build_apk.sh <debug|profile|release> [config]` (padrão `config/defines.<modo>.json`): roda `dart run tool/model_url_check.dart` e só então `flutter build apk --<modo> --target-platform=android-arm64 --dart-define-from-file=<config>`. Para `flutter run`, o mesmo arquivo: `flutter run --dart-define-from-file=config/defines.debug.json`.
- `app/config/defines.example.json`: `{"MODEL_URL": "https://conteudo.exemplo.invalid/content-packs/models/gemma-3-1b-it-Q4_K_M-8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135.gguf"}`. É exemplo, fora de `app/lib`, com domínio `.invalid`.

- [ ] **Step 4: Rodar e ver passar; análise**

Run: `cd app && flutter test test/sync/ test/tool/ && flutter analyze --fatal-infos && grep -r huggingface.co lib; echo "grep exit=$?"`
Expected: testes PASS, análise limpa, `grep exit=1` (nada encontrado).

- [ ] **Step 5: Sabotagem**

Recolocar temporariamente a URL do Hugging Face como `defaultValue` em `modelUrl`: `model_catalog_test` reprova nos dois primeiros testes. Remover a checagem de `isConfigured` do downloader: o teste "notConfigured sem nenhum byte de rede" reprova. Trocar `_resolvesOffline` por "existe `.parcial`" (a versão anterior deste plano): reprova "parcial incompleto sem URL". Reverter.

- [ ] **Step 6: Comandos de build documentados**

Acrescentar à seção "Comandos" do `CLAUDE.md`: `tool/build_apk.sh release` (exige `config/defines.release.json`) e `flutter run --dart-define-from-file=config/defines.debug.json`. Em `.github/workflows/app.yml` nada muda: `flutter test` roda sem `MODEL_URL` de propósito, e é o caso "não configurado" que os testes cobrem.

- [ ] **Step 7: Commit**

```bash
git add app/lib/sync app/lib/ui/onboarding app/tool app/config/defines.example.json app/.gitignore app/test CLAUDE.md
git commit -m "feat(app): MODEL_URL por dart-define, sem host no catalogo (#3)"
```

---

### Task 2: objeto `models/` no MinIO, Caddy e conferência de `Range`

Independente do desfecho do ADR, exceto o Step 6 (publicar o Gemma). Critério: `doc-operacao.test.ts` verde.

**Files:**
- Modify: `infra/Caddyfile:37`, `infra/Caddyfile.dev:21` (regex `@immutable`: `(packs|assets|models)`)
- Create: `infra/scripts/publish-model.sh`, `infra/scripts/check-model-endpoint.sh`, `infra/scripts/merge-models-policy.mjs`
- Modify: `infra/.env.example` (`MODEL_CHECK_MANIFEST_URL`), `.gitignore` (`infra/scripts/.policy-backup/`)
- Modify: `package.json` (raiz): `"model:publish": "bash infra/scripts/publish-model.sh"`, `"model:check": "bash infra/scripts/check-model-endpoint.sh"`
- Modify: `docs/operacao.md` (nova `### 2.10 Publicar o modelo SLM`; linha em §6 se algo ficar manual)
- Test: `cms/test/infra-topologia.test.ts`, `packer/test/publish-model.test.ts` (novo)

**Interfaces:**
- Produces:
  - `publish-model.sh <arquivo.gguf> [--check-only]`: lê o SHA-256 e o `sizeBytes` de `app/lib/sync/model_catalog.dart` (regex sobre `sha256: '…'` e `sizeBytes: …`), recusa se o arquivo divergir (sai 1, antes de qualquer rede), e publica na ordem `NOTICE` → cópias do Agreement → `.gguf`. Chaves: `models/gemma-3-1b-it-Q4_K_M-<sha>.gguf`, `models/gemma-3-1b-it-Q4_K_M-<sha>.NOTICE.txt`, `models/gemma-terms-of-use.md`, `models/gemma-prohibited-use-policy.md`. As três últimas saem de `app/assets/legal/` (fonte única, Task 3).
  - `check-model-endpoint.sh <url> <sha256> <bytes> [--manifest <url>]`: sai 0 só se todas as conferências do Step 4 passarem.
  - `infra/scripts/merge-models-policy.mjs <antes.json>` → imprime a política com o statement de `models/` acrescentado; `--verify <antes.json> <depois.json>` sai 1 se algum statement de `antes` não estiver em `depois`. Node puro (já é dependência do repositório), testado sem MinIO.

- [ ] **Step 1: Testes que falham**

`cms/test/infra-topologia.test.ts`: `'o site de conteudo trata models/ como imutavel nos dois Caddyfiles'` → para `infra/Caddyfile` e `infra/Caddyfile.dev`, a linha `@immutable path_regexp` contém `models`.

`packer/test/models-policy.test.ts` (sobre `merge-models-policy.mjs`, com as políticas **medidas em 2026-10-29** como fixture):
- `'acrescenta so GetObject em content-packs/models/*'` → o statement novo tem `Action: ["s3:GetObject"]`, `Resource: ["arn:aws:s3:::content-packs/models/*"]` (com barra) e nenhum `s3:ListBucket`.
- `'preserva todo statement anterior'` → com a política dos packs gerada pelo `mc` (`GetBucketLocation`, `ListBucket` com `s3:prefix: ["0000000"]`, `GetObject` em `content-packs/0000000*`), o resultado contém os três, intactos.
- `'e idempotente'` → aplicar duas vezes dá o mesmo JSON.
- `'--verify reprova se um statement anterior sumir'` → `depois` sem o `GetObject` dos packs → status 1, mensagem cita o recurso.
- `'politica vazia vira so o statement de models'` → bucket sem política (o `get-json` do `mc` devolve vazio).

`packer/test/publish-model.test.ts`: roda `bash infra/scripts/publish-model.sh <tmp>/falso.gguf --check-only` via `spawnSync` com um arquivo de 16 bytes; espera `status === 1`, stderr com `SHA-256 nao confere` e com o SHA do catálogo; espera também que nenhum `docker` tenha sido chamado: o teste passa `DOCKER=<script que grava um marcador e sai 99>` e confere que o marcador não existe.

- [ ] **Step 2:** `npm test` → FAIL nos dois testes novos.

- [ ] **Step 3: Implementar**

- Caddyfiles: acrescentar `models` ao regex e atualizar o comentário das "duas classes de cache": nomeado por hash ⇒ imutável. Não mexer em `encode`: o padrão do Caddy 2.9 só comprime `text/*`, JSON, JS, XML e SVG, e o objeto sobe como `application/octet-stream` (o Step 4 confere).
- `publish-model.sh`: `set -euo pipefail`; todo `docker` passa por `${DOCKER:-docker}`; `sha256sum` e `stat -c %s` contra o catálogo; sem `--check-only`, sobe pelo `mc` da **imagem do serviço `storage`**, sem serviço novo e sem adivinhar nome de rede: `$DOCKER compose -f infra/compose.yaml run --rm --no-deps -T -v "$arquivo:/in/model.gguf:ro" -v "$ROOT/app/assets/legal:/in/legal:ro" --entrypoint sh storage -c '…'`. Dentro: `mc alias set local http://storage:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"` (as variáveis já estão no ambiente do serviço, vindas de `infra/.env`; nada de credencial na linha de comando do host), `mc cp --attr "Content-Type=text/plain; charset=utf-8"` para os três textos, `mc cp --attr "Content-Type=application/octet-stream"` para o `.gguf` e `mc stat` conferindo o tamanho.
- **Política, sem `mc anonymous set download`.** Medido (D6): ele mescla, mas libera listagem anônima do prefixo e usa recurso `models*` sem barra, que vaza qualquer chave começando com `models`. Em vez dele: (1) `mc anonymous get-json local/content-packs > antes.json`, salvo em `infra/scripts/.policy-backup/<timestamp>.json` (no `.gitignore`); (2) `node infra/scripts/merge-models-policy.mjs antes.json > nova.json`; (3) `mc anonymous set-json nova.json local/content-packs`; (4) `get-json` de novo para `depois.json` e `merge-models-policy.mjs --verify antes.json depois.json`, que **falha** se algum statement anterior sumiu. Na falha, o script reaplica `antes.json` e sai 1. Sem listagem, ninguém enumera `models/` pelo edge; o nome do objeto é publicado só pelo `MODEL_URL` do build e pelo `docs/operacao.md`.
- Por fim o script chama `check-model-endpoint.sh "$EDGE_URL/content-packs/models/<chave>" <sha> <bytes>`. O SHA-256 publicado é verificado **duas vezes**: no arquivo local antes do upload, e no download completo pelo edge depois, que é o que o aparelho vai receber.
- `docs/operacao.md` §2.10: obter o arquivo (`app/tool/fetch_model.sh gemma-3-1b`, que já confere o SHA), `npm run model:publish -- app/assets/models/gemma-3-1b.gguf`, `npm run model:check -- <url> <sha> <bytes>`, a URL resultante para `config/defines.release.json`, e quatro avisos: espelho federado recebe os quatro objetos juntos; cópia por pendrive (OTG) leva o `.NOTICE.txt` e as duas cópias do Agreement junto com o `.gguf`; a página da loja não pode sugerir endosso do Google (§4.2; a loja não está no repo, então é checklist); o backup da política em `.policy-backup/` e como restaurá-lo (`mc anonymous set-json`), e que a política dos packs continua fora do repositório até a #46.

- [ ] **Step 4: `check-model-endpoint.sh`. As conferências, todas com `-H 'Accept-Encoding: gzip'` (o que o `dart:io` manda)**

```bash
# HEAD: 200, Content-Length exato, Accept-Ranges: bytes, sem Content-Encoding
curl -sSI -H 'Accept-Encoding: gzip' "$URL"
# Range no meio: 206, Content-Range: bytes 100-199/<bytes>, Content-Length: 100
curl -sS -o /dev/null -D - -H 'Accept-Encoding: gzip' -H 'Range: bytes=100-199' "$URL"
# Range aberto a partir do fim menos 1: 206, Content-Length: 1
curl -sS -o /dev/null -D - -H 'Range: bytes='"$((BYTES-1))"'-' "$URL"
# Range além do fim: 416 (o downloader descarta o parcial)
curl -sS -o /dev/null -w '%{http_code}' -H 'Range: bytes='"$BYTES"'-' "$URL"
# Escrita recusada: 405 no Caddyfile de producao (o .dev nao tem a guarda; o script so avisa la)
curl -sS -o /dev/null -w '%{http_code}' -X PUT "$URL"
# Listagem anonima do prefixo recusada: 403 (sem ListBucket na politica)
curl -sS -o /dev/null -w '%{http_code}' "${URL%/models/*}?list-type=2&prefix=models"
# Chave vizinha fora de models/ continua fechada: 403 (o recurso tem barra)
curl -sS -o /dev/null -w '%{http_code}' "${URL%/models/*}/models-x/nao-existe"
# Com --manifest: o manifest do pack continua servido (200, JSON) — a politica nova nao derrubou os packs
curl -sS -o /dev/null -w '%{http_code} %{content_type}' "$MANIFEST"
# Download completo pelo edge e SHA-256 conferido
curl -sS -H 'Accept-Encoding: gzip' "$URL" | sha256sum
```
O `publish-model.sh` sempre chama o check com `--manifest`, apontando para o `manifest.json` do município publicado (lido de `infra/.env`, `MODEL_CHECK_MANIFEST_URL`, acrescentada ao `.env.example`); sem manifest publicado (ambiente novo), o script avisa e não reprova, porque não há o que preservar.
Cada linha vira uma asserção com mensagem própria; o script imprime `ok  <conferência>` ou `FALHOU <conferência>: <obtido>`.

- [ ] **Step 5: Verificar local com objeto sintético (sem Gemma)**

Run: `docker compose -f infra/compose.yaml up -d`; publicar um manifest de pack (`npm run pack:publish`, ou um `manifest.json` qualquer em `content-packs/0000000/`) e aplicar `mc anonymous set download local/content-packs/0000000`, reproduzindo o estado medido; depois rodar o caminho de política do `publish-model.sh` sobre um arquivo aleatório de 8 MiB numa chave de teste `models/teste-<sha>.bin` e `npm run model:check -- http://127.0.0.1:8081/content-packs/models/teste-<sha>.bin <sha> 8388608 --manifest http://127.0.0.1:8081/content-packs/0000000/manifest.json`.
Expected: todas as linhas `ok`, exceto o 405, que só avisa em dev; `--verify` ok; o manifest responde 200. Apagar a chave de teste e restaurar a política do backup.

- [ ] **Step 6 (só no fim da exceção do HF, com servidor do projeto): publicar o Gemma**

Run: `npm run model:publish -- app/assets/models/gemma-3-1b.gguf`
Expected: `ok` em todas as conferências e `sha256 8ccc5cd1…a135` no download pelo edge.

- [ ] **Step 7:** `npm test && npm run typecheck` → PASS (inclui `doc-operacao.test.ts`, que cobra `npm run model:publish` e `npm run model:check`).

- [ ] **Step 8: Commit**

```bash
git add infra/ package.json docs/operacao.md cms/test/infra-topologia.test.ts packer/test/publish-model.test.ts packer/test/models-policy.test.ts .gitignore
git commit -m "feat(infra): objeto models/ no storage, com publicacao e conferencia de Range (#3)"
```

---

### Task 0c: ADR-004 registra a exceção do huggingface.co

*Antes da aprovação: o ADR ainda está PROPOSTO, e é sobre este texto que o dono decide.*

**Files:**
- Modify: `spec/stack.md` (ADR-004)

- [ ] **Step 1:** Acrescentar ao ADR-004 a seção **"Exceção: download direto do huggingface.co"**, com o conteúdo da seção homônima deste plano: motivo (não há domínio nem servidor), URL fixada na revisão `f9c28bcd85737ffc5aef028638d3341d49869c27`, a regra "uma URL, não um host", a medição de 302/206, os dois hosts, os custos 1 a 4 e os gatilhos de fim.
- [ ] **Step 2:** Ajustar o que a exceção torna impreciso no texto já commitado: em "Decisões → Origem e espelho", dizer que a origem **durante a exceção** é o HF e que o bucket `content-packs` é a origem **ao fim dela**; em "Contexto", trocar "contraria três decisões" por "contraria três decisões; a exceção mantém a divergência, com prazo"; em "Desfecho desfavorável", acrescentar que o Task 2 continua sendo a saída.
- [ ] **Step 3:** Registrar na seção LGPD do ADR que a validação do encarregado (DPO) sobre a transferência internacional está **pendente**, como as demais pendências de DPO de `spec/lgpd.md`.
- [ ] **Step 4: Commit**

```bash
git add spec/stack.md
git commit -m "docs(adr): ADR-004 registra o download direto do huggingface.co como excecao (#3)"
```

---

### Task 1b: `model_url_check` aceita a URL da exceção, e só ela

*Pode começar junto com a 0c: não depende da aprovação, como a Task 1.*

**Files:**
- Modify: `app/tool/model_url_check.dart`, `app/config/defines.example.json`, `app/lib/sync/model_catalog.dart` (só o comentário: "storage do projeto" → "storage do projeto, ou a exceção do ADR-004")
- Modify: `docs/operacao.md` §2.10 (a exceção e como sair dela)
- Test: `app/test/tool/model_url_check_test.dart`

**Interfaces:**
- Produces:
  - `const String huggingFaceExceptionUrl = 'https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/f9c28bcd85737ffc5aef028638d3341d49869c27/gemma-3-1b-it-Q4_K_M.gguf';` e `const String huggingFaceExceptionSha256 = '8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135';` em `app/tool/model_url_check.dart` (fora de `app/lib`, de propósito).
  - `modelUrlProblem` passa a aceitar `huggingFaceExceptionUrl` **exatamente**, e só quando `expectedSha256 == huggingFaceExceptionSha256`. A regra do sufixo `-<sha256>.gguf` continua valendo para o storage próprio.

- [ ] **Step 1: Testes que falham**

```dart
test('a URL da excecao passa, no release', () {
  expect(problem(huggingFaceExceptionUrl), 'ok');
});
test('huggingface em resolve/main reprova: a excecao e uma revisao fixa', () {
  expect(problem(huggingFaceExceptionUrl.replaceFirst(RegExp('resolve/[0-9a-f]{40}'), 'resolve/main')),
      contains('revisao fixa'));
});
test('outro repositorio do huggingface reprova', () {
  expect(problem(huggingFaceExceptionUrl.replaceFirst('ggml-org', 'outra-org')), contains('ADR-004'));
});
test('a excecao nao vale para outro modelo', () {
  expect(modelUrlProblem(huggingFaceExceptionUrl, release: true, expectedSha256: '0' * 64),
      contains('ADR-004'));
});
test('a excecao e do modelo ativo', () {
  expect(huggingFaceExceptionSha256, activeModel.sha256);
});
```
O teste `'huggingface reprova: o modelo vem do storage proprio'`, já existente, continua passando (ele usa outro caminho).

- [ ] **Step 2:** `cd app && flutter test test/tool/model_url_check_test.dart` → FAIL (`huggingFaceExceptionUrl` indefinido).
- [ ] **Step 3: Implementar.** A checagem da exceção vem logo depois de "absoluta": URL igual à constante e SHA igual → `null`. Host `huggingface.co` em qualquer outra forma: mensagem que cita a exceção (*"huggingface.co só na URL exata da exceção do ADR-004, fixada numa revisão"*), com "revisao fixa" quando o caminho tem `resolve/main`. `config/defines.example.json` passa a trazer a URL da exceção, que é a que os builds usam enquanto ela durar.
- [ ] **Step 4:** `flutter test test/tool/ && flutter analyze --fatal-infos && grep -r huggingface.co lib; echo "grep exit=$?"` → PASS e `grep exit=1`.
- [ ] **Step 5: Sabotagem.** Trocar a revisão na constante por `main` → reprova "revisão fixa" (o teste de `resolve/main` passaria a aceitar). Mudar o SHA da constante → reprova "a exceção é do modelo ativo". Reverter.
- [ ] **Step 6: Manual.** Em `docs/operacao.md` §2.10, antes da publicação: *"Enquanto não há servidor do projeto, os builds usam a exceção do ADR-004 (`MODEL_URL` = a URL fixada do Hugging Face, em `app/config/defines.example.json`). Para sair dela: publicar com `npm run model:publish` e trocar o `MODEL_URL`; aparelhos já provisionados não baixam de novo."*
- [ ] **Step 7: Commit**

```bash
git add app/tool/model_url_check.dart app/test/tool/model_url_check_test.dart app/config/defines.example.json app/lib/sync/model_catalog.dart docs/operacao.md
git commit -m "feat(app): model_url_check aceita a URL fixada do huggingface.co como excecao (#3)"
```

---

### Task 3: Notice, cópia do Agreement e seção do "Sobre"

*Só com ADR aprovado.* Critérios: `legal_documents_test.dart` cobre os documentos novos; `about_screen_test.dart` lista os dois.

**Files:**
- Create: `app/assets/legal/gemma_notice.txt`, `gemma_terms_en.md`, `gemma_prohibited_use_en.md`, `gemma_terms_pt.md`, `gemma_terms_es.md`, `gemma_prohibited_use_pt.md`, `gemma_prohibited_use_es.md`
- Modify: `app/lib/ui/more/legal_document.dart`
- Create: `app/lib/ui/more/gemma_documents_screen.dart`
- Modify: `app/lib/ui/app_router.dart` (rota `/mais/sobre/gemma`, `Routes.gemmaDocuments`), `app/lib/ui/more/about_screen.dart`, `app/lib/l10n/app_{pt,es}.arb`
- Test: `app/test/ui/more/legal_documents_test.dart`, `app/test/ui/more/about_screen_test.dart`, `app/test/ui/more/no_endorsement_test.dart` (novo)

**Interfaces:**
- Consumes: `activeModel` (Task 1).
- Produces:
  - `const String gemmaNoticeAsset = 'assets/legal/gemma_notice.txt';`
  - `List<String> gemmaAssetsFor(String languageCode)` → `[gemma_terms_<pt|es>.md, gemma_prohibited_use_<pt|es>.md, gemma_terms_en.md, gemma_prohibited_use_en.md]`: resumo, Política traduzida, os dois originais (idioma sem tradução recua para `pt`, como `legalAssetsFor`).
  - `Future<({String notice, List<LegalDocument> documents})> loadGemmaDocuments(String languageCode, {AssetBundle? bundle})`, que nunca lança: Notice ausente vira `''` e a tela mostra indisponível.

**Conteúdo dos assets:**
- `gemma_notice.txt`, literal, sem cabeçalho de versão (é o arquivo que a §3.1(4) pede, e o texto não muda):
  ```
  Gemma is provided under and subject to the Gemma Terms of Use found at gemma.ai/resources/terms
  Gemma is provided under and subject to the Gemma Terms of Use found at ai.google.dev/gemma/terms

  Notice of modification: gemma-3-1b-it-Q4_K_M.gguf is not an original Google file. It was converted to the GGUF format and quantized to Q4_K_M by ggml-org (https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF) from google/gemma-3-1b-it, and Guia UBS downloads or redistributes it without further modification.
  SHA-256: 8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135
  ```
  (Duas frases: decisão D-A. Parágrafo de modificação: decisão D-B, com "downloads or redistributes" por causa da exceção: o app baixa do HF e o pendrive redistribui.)
- `gemma_terms_en.md` / `gemma_prohibited_use_en.md`: `<!-- versao: <data da leitura> -->`, uma linha `Source: <URL> — Last modified: <data> — retrieved <data>`, e o texto **integral e literal**, só convertido para o markdown mínimo do parser (`#`, `##`, parágrafo, `- `). Obter salvando o HTML num diretório próprio do scratchpad e convertendo; conferir à mão contra a página que nenhuma cláusula ficou de fora (§1 a §5 mais o Appendix; itens 1 a 4 da Política).
- Escopo alterado (D11, publicado na #3). Os quatro arquivos de cortesia começam com `<!-- versao -->`, a marca MINUTA e o aviso de prevalência: *"Este texto é cortesia. O que vale é o original em inglês, que está logo abaixo nesta tela e em gemma.ai/resources/terms; em caso de divergência, prevalece a versão em inglês."* (es: *"…prevalece la versión en inglés."*).
  - `gemma_terms_{pt,es}.md`: título "Gemma: resumo dos termos de uso (cortesia)", seção `## Resumo dos termos` (es `## Resumen de los términos`), em linguagem simples e **explicitamente não tradução**: o que o modelo é, que o uso segue os termos do Google, que as restrições valem para quem usa e para quem repassa, que o Google pode restringir o uso, que a responsabilidade pela saída é de quem distribui e usa, e que não há endosso.
  - `gemma_prohibited_use_{pt,es}.md`: título "Política de Uso Proibido do Gemma (tradução de cortesia)" / "Política de Uso Prohibido de Gemma (traducción de cortesía)", **tradução integral** dos itens 1 a 4, com a numeração do original.

- [ ] **Step 1: Testes que falham** (em `legal_documents_test.dart`, novo `group('documentos do Gemma')`)

```dart
test('o Notice traz as duas frases literais da §3.1(4), na ordem da D-A', () async {
  final linhas = (await rootBundle.loadString(gemmaNoticeAsset)).split('\n');
  const frase = 'Gemma is provided under and subject to the Gemma Terms of Use found at ';
  expect(linhas[0], '${frase}gemma.ai/resources/terms');
  expect(linhas[1], '${frase}ai.google.dev/gemma/terms');
});
test('o Notice acompanha o modelo ativo', () async {
  final notice = await rootBundle.loadString(gemmaNoticeAsset);
  expect(notice, contains(activeModel.sha256));
  expect(notice, contains('gemma-3-1b-it-Q4_K_M.gguf'));
  expect(notice, contains('modif'));
});
for (final idioma in ['pt', 'es']) {
  test('os documentos do Gemma em $idioma carregam, com versao', () async {
    final r = await loadGemmaDocuments(idioma);
    expect(r.notice, isNotEmpty);
    expect(r.documents, hasLength(4));
    for (final d in r.documents) {
      expect(d.versionDate, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')), reason: d.asset);
      expect(d.blocks, isNotEmpty, reason: d.asset);
    }
  });
}
test('a copia em ingles e integral', () async {
  final t = await rootBundle.loadString('assets/legal/gemma_terms_en.md');
  expect(t, contains('Last modified: April 1, 2026'));
  for (final trecho in ['Distribution and Redistribution', 'Use Restrictions', 'Generated Output', 'Appendix']) {
    expect(t, contains(trecho));
  }
  final p = await rootBundle.loadString('assets/legal/gemma_prohibited_use_en.md');
  expect(p, contains('Making automated decisions in domains that affect material or individual rights or well-being'));
});
for (final arquivo in ['gemma_terms', 'gemma_prohibited_use']) {
  test('$arquivo: a cortesia diz que o ingles prevalece', () async {
    expect(await rootBundle.loadString('assets/legal/${arquivo}_pt.md'), contains('prevalece a versão em inglês'));
    expect(await rootBundle.loadString('assets/legal/${arquivo}_es.md'), contains('prevalece la versión en inglés'));
  });
}
for (final (idioma, resumo, clausula, automatizada) in [
  ('pt', '## Resumo dos termos', 'Distribuição e Redistribuição', 'decisões automatizadas'),
  ('es', '## Resumen de los términos', 'Distribución y Redistribución', 'decisiones automatizadas'),
]) {
  test('o resumo em $idioma resume, e nao traduz, os termos', () async {
    final t = await rootBundle.loadString('assets/legal/gemma_terms_$idioma.md');
    expect(t, contains(resumo));
    // Resumo, nao traducao: o titulo da secao contratual traduzido nao aparece.
    expect(t.toLowerCase(), isNot(contains(clausula.toLowerCase())));
  });
  test('a Politica em $idioma e traduzida inteira', () async {
    final p = await rootBundle.loadString('assets/legal/gemma_prohibited_use_$idioma.md');
    // Os quatro itens de topo, na numeracao do original, e o item 3.4.
    for (final n in ['1.', '2.', '3.', '4.']) {
      expect(RegExp('^(- )?${RegExp.escape(n)} ', multiLine: true).hasMatch(p), isTrue, reason: n);
    }
    expect(p.toLowerCase(), contains(automatizada));
  });
}
```

`about_screen_test.dart`:
- `'lista o Notice e os termos do Gemma'` → `reveal` até `ValueKey('about-gemma')`; `find.text('Gemma Terms of Use')` e `find.text('Notice')` dentro da seção; tocar o botão `ValueKey('about-gemma-open')` abre `/mais/sobre/gemma`, que mostra a frase do Notice (`find.textContaining('Gemma is provided under and subject to')`).
- `'a tela Sobre continua dentro do teto de elementos'` → `OutlinedButton`/`FilledButton`/`TextButton` acionáveis + `gubsTabCount` ≤ `maxElementsPerScreen`.
- `'o credito ao modelo nega endosso'` → o texto da seção contém "não desenvolveu, não revisou e não endossa".

`no_endorsement_test.dart`: percorre `lib/l10n/app_pt.arb` e `app_es.arb` e os `.md` de `assets/legal/` que não são `gemma_*`. Duas listas nomeadas, cada entrada com o motivo escrito:
- `mencaoNeutra` — o nome aparece só como **título de documento** ou rótulo de botão (`aboutModelDocuments`, `onboardingGemmaTerms`, `termsGateOpenTerms`). Exigência: o valor **não** contém `Google` (só o nome do documento, "Gemma Terms of Use") e tem no máximo 40 caracteres, para não virar texto descritivo disfarçado.
- `textoDescritivo` — o texto fala do modelo ou da relação com o Google (`aboutModelCredit`, `termsGateBody`, `termos_pt.md`, `termos_es.md`). Exigência: contém a frase de não endosso do idioma ("não desenvolveu, não revisou e não endossa" / "no desarrolló, no revisó y no respalda").
- Qualquer valor com `Google` ou `Gemma` fora das duas listas reprova. `aboutLogos` não contém nada com `google`.
- Nenhum valor de ARB nem documento legal contém `UFRR` ou `Universidade Federal` (o projeto não tem vínculo formal). **Única exceção nomeada:** o endereço `prismufrr@gmail.com`, removido do texto antes da busca; o motivo fica escrito ao lado da exceção, e `Medicina` só aparece na chave `aboutClinicalReviewCredit`, que **não existe** até os colaboradores concordarem com a menção.
Testes do próprio guarda: um ARB em memória com `"x": "Gemma"` fora das listas reprova; `aboutModelDocuments` com "parceria com o Google" reprova a regra de menção neutra.

- [ ] **Step 2:** `cd app && flutter test test/ui/more/` → FAIL (assets e símbolos ausentes).

- [ ] **Step 3: Implementar**

- Assets como descrito; o `pubspec.yaml` já declara `assets/legal/` (linha 108) e o `.txt` entra junto.
- `legal_document.dart`: as Interfaces acima, reaproveitando `parseLegalDocument`; atualizar o comentário "Os quatro arquivos" (passam a ser onze).
- `GemmaDocumentsScreen` (padrão de `LegalDocumentsScreen`: `FutureProvider.family` por idioma, `SizedBox.shrink` no loading, nunca `CircularProgressIndicator`): Notice em bloco destacado com cor de **informação** (azul; nunca lilás nem verde), aviso de prevalência do inglês, resumo, Política traduzida, depois os dois originais.
- Rota `GubsRouteSpec(path: '/mais/sobre/gemma', name: Routes.gemmaDocuments, tab: GubsTab.more, …)`, profundidade 3 ≤ `maxNavigationDepth` (4); o teste de estrutura percorre sozinho.
- "Sobre": seção `ValueKey('about-gemma')` depois dos créditos institucionais e antes de "Licenças", com título "Modelo de linguagem", ARB `aboutModelCredit`: *"O assistente usa o modelo Gemma, do Google, sob os Gemma Terms of Use. O Google não desenvolveu, não revisou e não endossa este aplicativo."* (es: *"…no desarrolló, no revisó y no respalda esta aplicación."*), `aboutModelDocuments`: "Notice · Gemma Terms of Use" (nomes em inglês por serem títulos dos documentos), e **um** botão `about-gemma-open` de 64 dp. Sem logotipo do Google (§4.2).
- As chaves das Tasks 4 e 4b entram nas listas do `no_endorsement_test` junto com as chaves, nas tasks que as criam.
- **Logo do Telessaúde UFRR (D15): fica** (decisão do dono). Nada muda em `aboutLogos`; a justificativa está no ADR-004.

- [ ] **Step 4:** `flutter test test/ui/ && flutter analyze --fatal-infos` → PASS.

- [ ] **Step 5: Sabotagem (cada proteção, uma vez)**

Apagar qualquer uma das duas primeiras linhas do `gemma_notice.txt`, ou trocar a ordem → reprova "duas frases literais". Trocar o SHA no Notice → "acompanha o modelo ativo". Remover `## 3.1` da cópia → "integral". Tirar "prevalece" do `gemma_prohibited_use_pt.md` → "o inglês prevalece". Colar a tradução da §3.1 no `gemma_terms_es.md` → "resume, e não traduz". Apagar o item 3 de `gemma_prohibited_use_es.md` → "traduzida inteira". Remover a seção do "Sobre" → "lista o Notice e os termos". Escrever "em parceria com o Google" num ARB → `no_endorsement_test`. Reverter cada uma e anotar o resultado para o §5.

- [ ] **Step 6: Verificar em aparelho** (CLAUDE.md: mudança de UI). Instalar debug, abrir Mais → Sobre → Modelo de linguagem em retrato e paisagem, com fonte 2x, em pt e es.

- [ ] **Step 7: Commit**

```bash
git add app/assets/legal app/lib/ui app/lib/l10n app/test/ui
git commit -m "feat(app): Notice e copia dos termos do Gemma na tela Sobre (#3)"
```

---

### Task 4: cláusula nos termos do app e notificação no ponto de distribuição

*Só com ADR aprovado.* Critério: teste de que `termos_{pt,es}.md` contêm a seção. Atende à §3.1(1) pela decisão D-C.

**Files:**
- Modify: `app/assets/legal/termos_pt.md`, `termos_es.md`
- Modify: `app/lib/ui/onboarding/onboarding_screen.dart` (`_Consent`)
- Test: `app/test/ui/more/legal_documents_test.dart`, `app/test/ui/onboarding/onboarding_notice_test.dart` (novo)

- [ ] **Step 1: Testes que falham**

`legal_documents_test.dart`:
```dart
for (final idioma in ['pt', 'es']) {
  test('termos_$idioma incorporam as restricoes de uso do Gemma como clausula', () async {
    final t = await rootBundle.loadString('assets/legal/termos_$idioma.md');
    expect(t, contains(idioma == 'pt' ? '## Modelo de linguagem (Gemma)' : '## Modelo de lenguaje (Gemma)'));
    expect(t, contains('Gemma Prohibited Use Policy'));
    expect(t, contains('Gemma is provided under and subject to the Gemma Terms of Use found at '));
    expect(t, contains(idioma == 'pt' ? 'fazem parte destes termos' : 'forman parte de estos términos'));
  });
}
test('a versao dos termos avancou com a clausula', () async {
  for (final d in await loadLegalDocuments('pt')) {
    if (d.asset.endsWith('termos_pt.md')) expect(d.versionDate!.compareTo('2026-08-22'), greaterThan(0));
  }
});
```

`onboarding_notice_test.dart`, os dois pontos de distribuição, cada um com teste próprio:
- `'download: Notice e Termos do Gemma antes de Baixar agora'` → `OnboardingScreen` com `ModelProvisioning` falso em `awaitingConsent`; a primeira linha do Notice e o botão `ValueKey('onboarding-gemma-terms')` (≥ 64 dp) aparecem acima de "Baixar agora"; tocar o botão abre os documentos da Task 3.
- `'pendrive: Notice e Termos do Gemma antes de escolher o arquivo'` → provisionamento em `blocked` (`offline`) com `pickLocalModel` injetado; tocar "Importar de um pendrive" **não** chama o seletor de imediato: abre um passo de confirmação com a primeira linha do Notice, o mesmo botão de termos e "Escolher arquivo". O seletor falso registra zero chamadas até "Escolher arquivo".
- `'pendrive: a confirmacao cabe no teto de elementos'` → acionáveis ≤ `maxElementsPerScreen`.

- [ ] **Step 2:** `flutter test test/ui/more/legal_documents_test.dart test/ui/onboarding/` → FAIL.

- [ ] **Step 3: Implementar**

- `termos_{pt,es}.md`: nova versão no cabeçalho (data da execução), seção `## Modelo de linguagem (Gemma)` / `## Modelo de lenguaje (Gemma)` antes de "Responsável", dizendo: que o assistente usa o Gemma; que as restrições de uso da Seção 3.2 dos Gemma Terms of Use e a Gemma Prohibited Use Policy **fazem parte destes termos** e valem para quem usa o aplicativo e para quem o repassa; que não é permitido usar o aplicativo ou o modelo para os usos ali proibidos; onde ler o texto (Mais → Sobre → Modelo de linguagem); que o texto em inglês prevalece; que o Google não desenvolveu, não revisou e não endossa o aplicativo; e a linha do Notice, literal, em inglês. O "MINUTA" continua.
- Widget `_GemmaNotice` (primeira linha de `gemmaNoticeAsset`, literal, mais o botão "Termos do Gemma", ARB `onboardingGemmaTerms`), usado nos **dois** pontos de distribuição do onboarding: no `_Consent`, abaixo do texto de tamanho; e num passo `_ImportConfirm`, que passa a ficar entre o botão "Importar de um pendrive" do `_Blocked` (e do `_Consent`) e a chamada a `pickLocalModel`. Entre os dois, cobrem todo aparelho que recebe o modelo pelo app, antes do primeiro byte ou do primeiro arquivo lido. Quem já tinha o app, e todo mundo antes do onboarding, passa pelo "li e concordo" da Task 4b.
- Piloto UAT (LGPD-RF02): o termo de consentimento do piloto não está no repositório. Registrar em `docs/operacao.md` §6 que a mudança dos termos precisa ser lida aos participantes já inscritos.

- [ ] **Step 4:** `flutter test && flutter analyze --fatal-infos` → PASS (suíte completa: `no_endorsement_test` agora lê os termos alterados).

- [ ] **Step 5: Sabotagem.** Remover a seção de `termos_es.md` → reprova o teste de `es`. Voltar a data da versão → reprova "a versão avançou". Tirar o Notice do `_Consent` → reprova "download". Ligar "Importar de um pendrive" direto ao seletor → reprova "pendrive". Reverter.

- [ ] **Step 6: Verificar em aparelho** os dois fluxos (download e pendrive com um arquivo qualquer), retrato e paisagem.

- [ ] **Step 7: Commit**

```bash
git add app/assets/legal/termos_pt.md app/assets/legal/termos_es.md app/lib/ui/onboarding app/lib/l10n app/test docs/operacao.md
git commit -m "feat(app): termos incorporam as restricoes de uso do Gemma, com Notice no download e no pendrive (#3)"
```

---

### Task 4b: "li e concordo" na primeira abertura e a cada versão nova dos termos

*Só com ADR aprovado.* É a resposta do projeto ao J3 (decisão do dono, 2026-10-29) e substitui o aviso passivo da versão anterior do plano. Cumpre a §3.1(1) para quem instala e para quem já tinha o app.

**Regra que não se negocia:** recusar desliga **só o assistente**. Sem aceite, o Gemma não é baixado, não é carregado e o job do WorkManager é cancelado; o gate de red flags, o `RuleOnlyEngine`, "Onde ir", "Documentos" e o fluxo da UBS funcionam igual (INV-1, INV-8). A tela de aceite é um portão como o de idioma, mas com saída imediata para a inicial: quem abre o app numa emergência toca um botão e segue.

**Files:**
- Modify: `app/lib/prefs/user_database.dart` (colunas `termsVersionAnswered` e `termsAccepted`, `schemaVersion` 2 → 3), `app/lib/prefs/preferences_repository.dart`
- Create: `app/lib/ui/legal/terms_gate_screen.dart` (fora da casca, como os portões de idioma e de modelo)
- Modify: `app/lib/ui/router_provider.dart` (`gubsRedirect` ganha o portão), `app/lib/ui/app_scope.dart` (`assistantAllowedProvider`), `app/lib/main.dart` (`_startEngine` e o agendamento do modelo respeitam o aceite), `app/lib/ui/more/legal_document.dart` (`currentTermsVersion`), `app/lib/ui/more/gemma_documents_screen.dart` (mudar a resposta depois)
- Modify: tela de privacidade (lista do que o `user.db` guarda, pt e es), `app/lib/l10n/app_{pt,es}.arb`, `spec/lgpd.md` (inventário do `user.db`)
- Test: `app/test/prefs/migration_test.dart` (v2→v3), `app/test/prefs/lgpd_surface_test.dart`, `app/test/ui/privacy/privacy_screen_test.dart`, `app/test/ui/redirect_test.dart`, `app/test/ui/legal/terms_gate_test.dart` (novo)

**Interfaces:**
- Produces:
  - `TextColumn get termsVersionAnswered => text().nullable()();`: a data `AAAA-MM-DD` do cabeçalho `<!-- versao -->` dos termos que a pessoa respondeu.
  - `BoolColumn get termsAccepted => boolean().withDefault(const Constant(false))();`: a resposta dada àquela versão.
  - `Future<String?> currentTermsVersion(String languageCode, {AssetBundle? bundle})`: a `versionDate` de `termos_<idioma>.md`; nunca lança.
  - `const String termsGatePath = '/termos';`
  - `gubsRedirect(..., required String? termsAnswered, required String? termsCurrent)`: depois do idioma e **antes** do setup, `termsCurrent != null && termsAnswered != termsCurrent` → `termsGatePath`. `termsCurrent == null` (asset ilegível) deixa passar: falha de leitura não pode travar o app (INV-8).
  - `final assistantAllowedProvider = Provider<bool>(...)`: `true` só com `termsAccepted && termsVersionAnswered == termsCurrent`.
- Comportamento:
  - "Li e concordo" grava `(termsCurrent, true)` e segue para o setup (instalação nova) ou para `/`.
  - "Usar sem o assistente" grava `(termsCurrent, false)`, leva o provisionamento a `readyDegraded` (sem download), chama `cancelModelSync()` e vai para `/`. Não pergunta de novo até a próxima versão dos termos.
  - `_startEngine` não sobe o motor sem `assistantAllowed`; `scheduleModelSync` não agenda sem ele. Um modelo já baixado fica no disco, sem uso.
  - Em Mais → Sobre → Modelo de linguagem, quem recusou vê "Li e concordo" e quem aceitou vê "Parar de usar o assistente". As duas ações gravam a resposta para a versão vigente; aceitar ali reabre o setup do modelo.

**Conteúdo da tela** (≤ 8 acionáveis, alvos ≥ 64 dp, cor de **informação**): título "Termos de uso" (ou "Os termos de uso mudaram" quando `termsVersionAnswered` não é nulo); resumo em três frases (o que o app é e não é, que o assistente usa o Gemma e as restrições de uso dele fazem parte dos termos, que recusar só desliga o assistente); a primeira linha do Notice, literal; botões "Ouvir" (TTS do resumo pelo `speakerProvider`, porque o público tem baixo letramento, como a leitura em voz alta da LGPD-RF02), "Ler os termos" (abre `/mais/privacidade/documentos`), "Li e concordo" e "Usar sem o assistente". As chaves ARB novas entram no `no_endorsement_test` (`termsGateBody` em `textoDescritivo`, `termsGateOpenTerms` em `mencaoNeutra`).

**As duas colunas custam quatro coisas, no mesmo commit (CLAUDE.md, precedente `theme_mode`/`font_scale`):**
1. `schemaVersion` 3 + `onUpgrade` com `addColumn` das duas e teste de migração v2→v3 (sem ele, todo aparelho instalado quebra no boot).
2. Entrada em `lgpd_surface_test.dart` para cada uma, com a justificativa: *"versão dos termos respondida e a resposta (sim/não); não identifica a pessoa, não sai do aparelho; existe para cumprir a §3.1(1) dos Gemma Terms of Use e para não carregar o modelo sem aceite (ADR-004). Não é registro de consentimento da LGPD-RF04, que pressupõe titular identificado."*
3. Linhas na tela de privacidade, pt e es ("Qual versão dos termos você respondeu e se aceitou").
4. Linhas no inventário do `user.db` em `spec/lgpd.md`.
"Apagar meus dados" (LGPD-RF03) apaga as duas junto com o resto, e a próxima abertura pergunta de novo: comportamento esperado, com teste.

- [ ] **Step 1: Testes que falham**
- `'migracao v2 para v3 preserva as preferencias e cria as colunas de termos vazias'`.
- `gubsRedirect`: sem resposta → `/termos`; resposta da versão vigente (aceita **ou** recusada) → segue; resposta de versão anterior → `/termos`; `termsCurrent: null` → segue; idioma ausente continua vencendo o portão de termos.
- `terms_gate_test`:
  - `'li e concordo grava a versao e segue para o setup'`.
  - `'usar sem o assistente vai para a inicial, sem download e sem motor'` → provisionamento falso não recebe `startDownload`; `assistantAllowedProvider` é `false`; `cancelModelSync` é chamado (injetado).
  - `'recusar nao bloqueia a orientacao'` → depois de recusar, `/triagem` (rota `requiresModel`) abre pelo caminho degradado e o gate de red flags devolve emergência para um token de red flag do pack de fixture.
  - `'abrir de novo nao pergunta outra vez'`, para as duas respostas.
  - `'termos novos perguntam de novo, mesmo para quem aceitou'`.
  - `'a tela cabe no teto de elementos e tem alvos de 64 dp'`; `'o botao Ouvir fala o resumo'` (speaker falso).
  - `'falha do user.db nao trava o app'` → repositório que lança: o redirect deixa passar e o assistente fica desligado (fail-closed para o modelo, aberto para a orientação).
- `about_screen_test`: `'quem recusou pode aceitar depois, e quem aceitou pode parar'`.
- `lgpd_surface_test` e `privacy_screen_test` passam a enumerar as colunas novas.

- [ ] **Step 2:** `cd app && flutter test test/prefs/ test/ui/` → FAIL.

- [ ] **Step 3: Implementar** as Interfaces, o comportamento e os quatro custos. `gubsRedirect` continua função pura.

- [ ] **Step 4:** `dart run build_runner build && flutter test && flutter analyze --fatal-infos` → PASS.

- [ ] **Step 5: Sabotagem.** Remover a entrada da tela de privacidade → reprova a comparação de listas. Remover o `onUpgrade` → reprova a migração. Subir o motor sem olhar `assistantAllowed` → reprova "sem motor". Fazer "Usar sem o assistente" voltar ao setup → reprova "vai para a inicial". Reverter.

- [ ] **Step 6: Verificar em aparelho.** (a) Instalação limpa: idioma → termos → recusar → inicial, sem download; Sobre → aceitar → setup do modelo. (b) Atualização: instalar o APK de `develop` (termos 2026-08-22, modelo já baixado), instalar por cima o APK do branch com a mesma chave: a tela aparece uma vez; recusar não apaga o modelo e não sobe o motor; aceitar sobe o motor sem baixar de novo. Retrato, paisagem e fonte 2x.

- [ ] **Step 7: Commit**

```bash
git add app/lib app/test spec/lgpd.md
git commit -m "feat(app): li e concordo a cada versao dos termos; recusar desliga so o assistente (#3)"
```

---

### Task 4c: aviso de privacidade e inventário LGPD dizem de quem vem o modelo

*Só com ADR aprovado.* Atende a D20.

**Files:**
- Modify: `app/assets/legal/privacidade_{pt,es}.md` (seção "Uso da rede"; nova versão datada), `spec/lgpd.md` (inventário de fornecedores, RF06/RT11, com "pendente de validação do encarregado (DPO)")
- Test: `app/test/ui/more/legal_documents_test.dart`

- [ ] **Step 1: Teste que falha:** `'privacidade_$idioma diz de quem vem o modelo e que o IP sai do pais'` → o texto (espaços normalizados) contém `Hugging Face`, contém `fora do Brasil` / `fuera de Brasil`, e contém `endereço IP` / `dirección IP`.
- [ ] **Step 2:** `flutter test test/ui/more/legal_documents_test.dart` → FAIL.
- [ ] **Step 3:** Em "Uso da rede", no item do modelo: *"para baixar o modelo de linguagem no primeiro acesso. Enquanto o projeto não tem servidor próprio, ele vem do Hugging Face, um serviço fora do Brasil, que recebe o endereço IP do aparelho no momento do download, como qualquer site. Nenhum sintoma nem dado de uso vai junto."* (es equivalente). Em `spec/lgpd.md`: Hugging Face Inc. e a CDN (AWS) como fornecedores do download do modelo, dado tratado (IP e `User-Agent`, no download), transferência internacional (arts. 33 a 36), prazo (até o fim da exceção do ADR-004), **pendente de validação do encarregado (DPO)**.
- [ ] **Step 4:** `flutter test test/ui/more/` → PASS. **Sabotagem:** remover "fora do Brasil" do `privacidade_pt.md` → reprova o teste de `pt`. Reverter.
- [ ] **Step 5: Commit**

```bash
git add app/assets/legal/privacidade_pt.md app/assets/legal/privacidade_es.md app/test/ui/more/legal_documents_test.dart spec/lgpd.md
git commit -m "docs(lgpd): aviso de privacidade diz que o modelo vem do Hugging Face, fora do Brasil (#3)"
```

---

### Task 5: verificação em emulador com HTTPS de verdade e registro no §5

*Só com ADR aprovado e Tasks 1–4c no branch.* **Não depende mais do domínio:** com a exceção, o endpoint é a URL fixada do HF, que já tem certificado público. Critério (D17): download no aparelho a partir da URL da exceção, com SHA-256 conferido, registrado em `spec/arquitetura.md` §5.

**Files:**
- Modify: `spec/arquitetura.md` (nova `#### 5.18 Resultado da P1-1 (issue #3) — modelo pela exceção do Hugging Face, sem host no código (<data>)`, ou a próxima livre)

**Como o teste usa HTTPS sem afrouxar o release.** Durante a exceção, trivialmente: `huggingface.co` e a CDN têm certificado público, que o trust store do sistema já aceita, e o `network_security_config` não muda. O texto abaixo vale para a **saída da exceção** (storage próprio), e fica aqui para quando houver domínio:

**Caminho escolhido pelo dono: staging com certificado público.** Um subdomínio **do domínio que será usado em produção** (ex.: `conteudo-staging.<domínio>`), servido pelo `infra/Caddyfile` de **produção** com certificado Let's Encrypt. O emulador resolve DNS público, confia na CA pública pelo trust store do sistema, e o APK release é o mesmo que iria para a loja. Nenhum arquivo do app muda.

- **Emissão do certificado.** Se o DNS apontar para um VPS, basta o compose com 80/443 abertos. Se apontar para a máquina de desenvolvimento, a emissão HTTP-01/TLS-ALPN-01 exige **80 e 443 alcançáveis pela internet** (encaminhamento no roteador, e IP público que não seja CGNAT); sem isso, usar **DNS-01**, que exige uma imagem do Caddy com o módulo do provedor de DNS (`xcaddy build --with github.com/caddy-dns/<provedor>`) e um token da API do DNS no `infra/.env`. DNS-01 é mudança de imagem do `edge`; se for o caminho, fica restrito a um `compose.staging.yaml`, sem tocar o de produção.
- **Pré-requisito em aberto:** hoje **não existe domínio** (`infra/.env` tem `CONTENT_DOMAIN=conteudo.exemplo.invalid`). A Task 5 não começa sem ele. Recomendação do dono, registrada em `docs/operacao.md` §2 ("Antes de implantar"):
  - domínio **fora de `.br`** (`.org` ou `.dev`), num registrador com proteção de WHOIS. Registro `.br` exige CPF ou CNPJ e expõe o nome do titular;
  - conta do registrador **do grupo**, com pelo menos dois administradores, para o domínio não sair do grupo com quem o registrou;
  - **dois nomes desde já**, produção e staging, e o servidor definido (máquina do laboratório ou VPS);
  - banda de saída: cada aparelho baixa ~806 MB uma vez. Exemplo de conta para o registro: 50 aparelhos ≈ 40 GB; numa saída de 100 Mbit/s isso leva ~1 h de saturação. Retomada por `Range` e o WorkManager em rede não tarifada espalham a carga, mas um provisionamento em mutirão na UBS concentra tudo num dia.
  - A URL entra embutida em cada build (`MODEL_URL` e, com a #45, `PACK_MANIFEST_URL`): trocar de domínio depois exige distribuir builds novos para toda a frota.
- Descartado: Caddy local com `tls internal` e CA de sistema no AVD. É frágil no API 36 (Conscrypt em APEX) e prova menos, porque o aparelho do piloto não terá essa CA.

`http://` não é usado: o `model_url_check` recusa `http` no release (Task 1).

- [ ] **Step 1: Endpoint pronto.** Conferir a URL da exceção com o mesmo `Accept-Encoding: gzip` do app, seguindo o redirecionamento: `curl -sS -o /dev/null -D - -L -H 'Accept-Encoding: gzip' -H 'Range: bytes=100-199' 'https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/f9c28bcd85737ffc5aef028638d3341d49869c27/gemma-3-1b-it-Q4_K_M.gguf'`.
Expected: `302` para a CDN, depois `206`, `Content-Range: bytes 100-199/806058240`, `Content-Length: 100`, sem `Content-Encoding`. (O `model:check` da Task 2 é para o storage próprio: as conferências de listagem, chave vizinha e escrita não se aplicam a um terceiro.)

- [ ] **Step 2: Build release.** `config/defines.release.json` com a URL da exceção (copiar de `config/defines.example.json`); `cd app && tool/build_apk.sh release`.
Expected: `model_url_check` ok; APK gerado. Anotar o SHA-256 do APK e o commit.

- [ ] **Step 3: Aparelho limpo.** `adb uninstall` do pacote, `adb install`, `adb logcat -c`, abrir o app, concluir idioma e tocar "Baixar agora" no onboarding (ver o Notice na tela antes, Task 4).

- [ ] **Step 4: Evidência.** `adb logcat -d | grep gubs-dl > <scratchpad>/p1-1-logcat.txt` (fora do repositório, como as evidências da #31; as linhas relevantes vão citadas no §5).
Expected: `w=primeiro-plano inicio off=0`, `http status=200 range=-`, `sha ok bytes=806058240`, `fim desfecho=Completed`. Com `adb root`: `ls -l` em `files/models/` mostra `gemma-3-1b-q4.gguf` com 806 058 240 B e `.verificado`, sem `.parcial` nem `.trava`. A tela clínica libera.

- [ ] **Step 5: Retomada pela URL da exceção.** Reinstalar, cortar a rede do AVD (`adb shell svc wifi disable; svc data disable`) durante o download, religar.
Expected: segunda linha `http status=206 range=<offset > 0>`, `sha ok bytes=806058240`, sem `ANOMALIA`.

- [ ] **Step 6: Aparelho que já tem o modelo não baixa de novo.** Construir um APK **sem** `MODEL_URL` (`flutter build apk --release --target-platform=android-arm64` direto, sem o `build_apk.sh`, que recusaria) **assinado com a mesma chave** do APK do Step 2 (hoje `debug.keystore`, como na P0-1; conferir com `apksigner verify --print-certs` nos dois). Com chave diferente, o `adb install -r` falha com `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, e desinstalar apagaria o modelo que o passo quer preservar. Instalar por cima com `adb install -r`: o boot vai a `ready` sem linha `http status`, porque o `.verificado` confere (Review Focus 2).

- [ ] **Step 7: Registrar no §5.18:** AVD, system image, nível de API, ABI, build (modo, commit, SHA-256 do APK, certificado de assinatura), data, a URL da exceção e a revisão fixada, os hosts vistos no caminho (`huggingface.co` e a CDN, para a #4), as linhas do logcat, o resultado das sabotagens das Tasks 1, 3, 4 e 4b, o resultado da Task 4b no aparelho, a medição da política do MinIO (D6) e as pendências: #45, #46, o destino da A-1, o checklist da loja (§4.2).

- [ ] **Step 8: Verificação final**

Run: `grep -r huggingface.co app/lib; echo "exit=$?"; cd app && flutter test && flutter analyze --fatal-infos; cd .. && npm test && npm run typecheck`
Expected: `exit=1`; tudo verde.

- [ ] **Step 9: Commit**

```bash
git add spec/arquitetura.md
git commit -m "docs(arquitetura): download do modelo pela excecao do huggingface.co verificado em emulador (#3)"
```

---

## Rastreabilidade

| Critério de aceite da issue | Tasks e passos |
|---|---|
| ADR aprovado pelo dono e referenciado em `spec/stack.md` §1.1 | 0 (redação e submissão), 0b Steps 1–2 |
| Download no aparelho, com SHA-256 conferido, registrado em `arquitetura.md` §5 — **pela URL da exceção do HF (D17)** | 1b; 5 Steps 1–7 |
| `grep -r huggingface.co app/lib` vazio | 1 Steps 1, 4 e 5; 5 Step 8 |
| `legal_documents_test.dart` cobre os documentos novos | 0 Step 5; 3 Steps 1 e 5 |
| Teste de que `termos_{pt,es}.md` contém a seção | 4 Steps 1 e 5 |
| `about_screen_test.dart` lista os dois | 3 Step 1 |
| `doc-operacao.test.ts` verde | 2 Steps 3 e 7 |
| Escopo 2 (objeto + Notice ao lado, só GET/HEAD) | 2 |
| Escopo 3 (`MODEL_URL`, catálogo sem host) | 1 |
| Escopo 4 (cláusula, cópia, Notice em inglês, "Sobre"), **alterado por D11 na #3** | 3, 4, 4b |
| Escopo 5 (publicação documentada) | 2 Step 3 |
| Pedidos do prompt: identidade por SHA-256 | 1 Steps 1 e 3; 5 Step 6 |
| Pedidos do prompt: §4.2 endosso | 3 (`no_endorsement_test`), 2 Step 3 (loja) |
| Pedidos do prompt: HTTPS no emulador sem afrouxar o release | 5 (durante a exceção, certificado público do HF; staging só na saída) |
| Pedidos do prompt: vermelho primeiro e sabotagem | Steps 1–2 e de sabotagem das Tasks 0, 1, 2, 3, 4 e 4b |
| Revisão 1: não endosso com menção neutra × texto descritivo | 3 (`no_endorsement_test`) |
| Revisão 2: sem URL, só caminhos sem rede | 1 Steps 1, 3 e 5 |
| Revisão 3: política do bucket preservada, manifest servido, sem listagem | 2 Steps 1, 3, 4 e 5 |
| Revisão 4: Notice no fluxo do pendrive | 4 Steps 1, 3 e 5 |
| Revisão 5 + J3: "li e concordo" por versão, recusa só desliga o assistente | 4b |
| Revisão 6: resumo dos termos, tradução só da Política | 3 |
| Revisão 7: portão em dois níveis | Global Constraints, 0 Step 6 |
| Revisão 8 → #47: o modelo só sinaliza escalada | 0 Step 3; implementação na #47 |
| Revisão 9: mesma chave de assinatura; emissão do certificado | 5 Step 6 e "Como o teste usa HTTPS" |
| Responsável PRISM, sem vínculo institucional; README | 0 Step 5; `no_endorsement_test` (UFRR) |
| J1/J2 como regras de produto R1–R3 | 0 Step 3; aplicação ao conteúdo na #48 |
| Gatilhos para revisitar a parte formal | 0 Step 3 |
| Gemma 4 como alternativa de licença (registrada, não perseguida) | 0 Step 3, 0b Step 3 |
| Domínio e servidor | saída da exceção (Task 2 Step 6); `docs/operacao.md` |
| Exceção do huggingface.co (URL fixada, só ela; custos e fim registrados) | 0c, 1b, 4c; seção "Exceção" |

## Decisões do dono (2026-10-29)

| Decisão | Efeito no plano |
|---|---|
| **Sem parecer jurídico nesta fase** (substitui "PROPOSTO até haver parecer") | O dono aprova o texto do ADR; J1–J3 viram R1–R3, Task 4b e #47; gatilhos registrados |
| Responsável: "Guia UBS, projeto de pesquisa e extensão desenvolvido pelo grupo de pesquisa PRISM", e-mail compartilhado | Task 0 Step 5; ADR registra que não cria parte contratual |
| Sem sugerir vínculo com a UFRR; curso de Medicina só com a concordância dos colaboradores | Global Constraints; `no_endorsement_test`; D15 |
| README: o projeto responde pelo app que distribui | Task 0 Step 5 |
| Domínio fora de `.br`, conta do grupo, dois nomes, servidor definido antes da Task 5 | Task 5, pré-requisito |
| Mudança de escopo dos documentos | Publicada na #3 ([comentário](https://github.com/hbgit/Guia-UBS/issues/3#issuecomment-6500666141)); Task 3 |
| J3: "li e concordo" com marca local | Task 4b |
| J1/J2: regras de produto R1–R3 | ADR; **#48** |
| A-1 como decisão de design | **#47** (P1), aberta em 2026-10-29 |
| D-A: Notice com as duas frases, `gemma.ai` primeiro | Task 3 |
| D-B: aprovada | Task 3 |
| HTTPS: staging com certificado público, subdomínio do domínio de produção | Task 5 na saída da exceção |
| D3 e D6 em issues próprias | **#45** (P1) e **#46** (P2) |
| E-mail do projeto: `prismufrr@gmail.com` | Task 0 Step 5; exceção nomeada no guarda de "UFRR" |
| Logo do Telessaúde UFRR fica; papel do PET Telessaúde UFRR: diagnóstico da necessidade social e desenvolvimento da solução, articulando docentes e monitores discentes | ADR-004 transcreve a frase literalmente; Task 3 não mexe em `aboutLogos` |
| #18 continua em ~1 B; Gemma 4 não perseguido agora | ADR-004, "Alternativa de licença"; D13 |
| Issue de enquadramento educacional | **#48** (P1), aberta em 2026-10-29 |
| Domínio e servidor: a definir | Exceção do HF até lá; Task 5 não espera mais por eles |
| **Modelo baixado direto do huggingface.co, como exceção** | Seção "Exceção"; Tasks 0c, 1b e 4c; D17–D20 |

## Pendências do dono (bloqueiam passos específicos)

1. **Domínio e servidor** (ainda a definir). Não bloqueiam mais esta issue: definem o **fim da exceção**.
2. **Texto para a #3 (critério de aceite que muda, D17):** *"Exceção (decisão do dono, 2026-10-29, ADR-004): enquanto o projeto não tem domínio nem servidor, o modelo é baixado direto do Hugging Face, numa URL fixada na revisão `f9c28bc` do repositório da `ggml-org`, passada por `--dart-define` (o host continua fora de `app/lib`). O critério 'download a partir do endpoint próprio' passa a ser 'download a partir da URL da exceção, com SHA-256 conferido'. O storage próprio (já implementado) é a saída da exceção."* Publico quando você confirmar.
3. **Validação do encarregado (DPO)** sobre a transferência internacional do IP no download (Task 4c a registra como pendente; não bloqueia o plano, mas é gatilho de fim da exceção se houver objeção).
