# Lançamento separado do estudo de impacto — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** As especificações deixam de tratar a publicação do app e o estudo com usuários como uma única etapa ("piloto"). Elas passam a ter duas etapas com portões próprios: **lançamento (Parte A)**, sem CEP, e **estudo de impacto (Parte B)**, com TCLE e parecer do CEP.

**Architecture:** Só documentos, sem código. Um ADR novo, o ADR-010 em `spec/stack.md` §10, registra a decisão e as decisões complementares (Q-A a Q-E). Cada ADR aceito que ela altera (004 a 009) recebe um parágrafo de Revisão próprio. O PRD, o `espec.md`, o `lgpd.md`, o `brainstorm.md` e os documentos de `docs/` são reescritos por referência ao ADR-010, e cada hipótese ou requisito movido diz de onde veio e para onde foi.

**Tech Stack:** Markdown em pt-BR. A verificação é feita por três scripts Python: o `piloto.py` (Global Constraints), o `inv.py` (Inventário) e o `links.py` (Task 7). Também roda o `npm test` do `cms`, por causa do `docs/operacao.md`.

**Spec:** a decisão da coordenação de 2026-11-09 (Decisões 1 a 6 do pedido) e a revisão do plano, também de 2026-11-09. A Task 1 transcreve as duas no ADR-010. Base factual: [`docs/dados-do-usuario.md`](../../dados-do-usuario.md).

## Global Constraints

- **Não alterar nada em `app/`, nem a INV-2.** O plano é só de especificações e documentos.
- **Não editar `app/assets/legal/*`.** Uma edição ali exige o bump legal triplo (`CLAUDE.md`, "Release e implantação"). O site em `guiasaude.prismrr.com.br` é gerado desses mesmos arquivos (`.github/workflows/pages.yml`, comentário das linhas 6-7; `app/tool/legal_pages.dart`, `buildLegalSite`), então ficam os dois como estão. A Task 6 confere.
- **Identificadores:** português, com os já usados nas specs: H, RF, RNF, INV, F, ADR, CAP.
- **Rastreabilidade:** todo item movido traz a origem no destino ("antiga H2", "Origem: …").
- **ADR aceito não é reescrito.** Toda mudança de mérito ou de leitura entra como parágrafo **"Revisão 2026-11-09 ([ADR-010](…))"** no fim do próprio ADR, no padrão de `spec/stack.md:503`. Não existe reinterpretação à distância: quem lê o ADR-008 precisa achar a mudança no ADR-008.
- **Âncoras de texto prevalecem sobre números de linha.** Os números são do `develop` em `7f00190`. Se o `develop` avançou, rode o `inv.py` (Inventário) de novo e localize cada ponto pelo trecho citado entre crases.
- **Menção histórica a "piloto".** "Piloto" deixa de nomear etapa. A palavra só pode aparecer em quatro situações:
  - **(a)** entre aspas retas, na mesma linha que `antiga`, `antes de 2026-11-09`, `Origem:` ou `lê-se`;
  - **(b)** no corpo dos ADR-004 a 009, aceitos antes desta data, fora dos parágrafos "Revisão 2026-11-09";
  - **(c)** no material histórico de `docs/superpowers/`: os planos antigos e os snapshots de issues de 2026-10-28;
  - **(d)** no nome do arquivo `docs/aprovacoes-piloto.md`, que fica como redirecionamento.

  Toda verificação usa este script, e nenhuma usa `grep -c piloto`:

```python
# piloto.py — python3 -I piloto.py [--stack] ARQUIVO...
# Sai 1 e lista cada "piloto" fora do padrão histórico (a).
# Com --stack, em spec/stack.md pula só o corpo dos ADR-004 a 009 (regra b), mas não
# os parágrafos "Revisão 2026-11-09" deles. O resto do arquivo (§1-9, ADR-001 a 003,
# ADR-010, §11) é conferido.
import re, sys
args = sys.argv[1:]
stack = '--stack' in args
args = [a for a in args if a != '--stack']
HIST = re.compile(r'"[^"]*piloto[^"]*"', re.I)
CTX = re.compile(r'antiga|antes de 2026-11-09|Origem:|lê-se', re.I)
ACEITO = re.compile(r'^### ADR-00[4-9]\b')
bad = 0
for f in args:
    no_aceito = False
    for i, l in enumerate(open(f, encoding='utf-8'), 1):
        if stack and f.endswith('stack.md'):
            if l.startswith('### ') or l.startswith('## '): no_aceito = bool(ACEITO.match(l))
            if no_aceito and not l.startswith('**Revisão 2026-11-09'): continue
        if re.search('piloto', l, re.I) and not (HIST.search(l) and CTX.search(l)):
            m = re.search('piloto', l, re.I)
            print(f"{f}:{i}: …{l[max(0, m.start() - 80):m.end() + 60].strip()}…"); bad += 1
sys.exit(1 if bad else 0)
```

- **TCLE e consentimento LGPD nunca aparecem como a mesma coisa.** Podem estar no mesmo documento, nunca na mesma cláusula. Toda linha que cita os dois casa com `distint|Não é o TCLE|separad|nunca .*mesma cláusula` (Task 7, Passo 2).
- **Marco legal da ética em pesquisa:** Lei 14.874/2024, ao lado das Resoluções CNS 466/2012 e 510/2016. O que o texto da lei diz (conferido no site do Planalto em 2026-11-09):
  - vale para pesquisa com seres humanos "em todas as áreas do conhecimento, no que couber, e conforme regulamento" (art. 63), e o regulamento das ciências humanas e sociais está pendente (art. 63, parágrafo único);
  - toda pesquisa passa por "análise ética prévia" (art. 6º), e o texto não lista hipóteses de dispensa;
  - o CEP é "vinculado à instituição que realiza a pesquisa" (art. 2º, X);
  - a participação depende de TCLE assinado (art. 18);
  - para dados de pesquisa, a LGPD se aplica de forma subsidiária (art. 61).

  Se a lei ou o regulamento mudar antes da execução, confira de novo.
- **Interpretação legal entra como postura do projeto, nunca como fato.** Os CEPs podem continuar aplicando as resoluções do CNS enquanto o sistema da Lei 14.874/2024 entra em vigor. Por isso nenhum texto afirma o que a lei "dispensa" ou "não dispensa", nem quem "é" órgão de pesquisa. O texto diz o que o projeto faz até haver a manifestação de quem é competente: o CEP/UFRR (F-20) ou o controlador e o parecer jurídico (F-11, T7-R).
- **Commits e PR:** nenhum commit ou PR leva atribuição de IA. Branch `docs/lancamento-e-estudo`, criada do `origin/develop`, com **uma** PR para o `develop` (sem PR empilhado). A PR só sai de rascunho depois do alinhamento com o PET-Saúde (Task 8, item 1).

## Perguntas abertas e decisões complementares

As respostas viram a subseção **"Decisões complementares"** do ADR-010 (Task 1), não só a descrição da PR.

| ID | Pergunta | Estado | Resposta / opções | Onde aparece |
|---|---|---|---|---|
| Q-A | O **RIPD** é exigido antes de quê? | **Aceita (2026-11-09)** | Antes do estudo de impacto. No lançamento, a evidência é o `docs/dados-do-usuario.md`, a confirmar com o encarregado (F-11). | ADR-010, Decisão 4 e Dec. compl.; `lgpd.md` (RIPD) |
| Q-B | Para onde vai o antigo **critério de saída** do piloto? | **Aceita (2026-11-09)** | Vira o **critério de promoção para produção** do lançamento (Decisão 3g). Os ADR-007, 008 e 009 recebem Revisões que apontam para ele. | ADR-010, 3g; Revisões dos ADR-007/008/009 |
| Q-C | M1/M2 hoje testam com o público-alvo, incluindo pessoas de baixo letramento. Como mitigar o R2 (crítico) sem pesquisa no lançamento? | **ABERTA — decisão da coordenação, bloqueia a Task 1.** A revisão de 2026-11-09 recomenda C1+C2. | Três variantes, escritas por extenso abaixo: C1, C2 e C1+C2. | ADR-010, 3f e Custo 1; `brainstorm.md` M1/M2; PRD §6.2 (Fase 1), R2 |
| Q-D | Quem são os **testadores do teste fechado** exigido pela Play para conta pessoal? | **Aceita (2026-11-09)** | São QA do lançamento: equipe, bolsistas e alunos, sem coleta. O mínimo lembrado é 12 testadores por 14 dias, mas a regra muda: confira no Play Console na hora. Se faltar gente interna, volta à coordenação. | ADR-010, 3f; `implantacao.md` §2.7 |
| Q-E | Quem é o **titular** do registro do software? | **Aceita (2026-11-09)** | Fica aberto como F-21, ligado à F-11 e à F-20: a resposta sobre o vínculo institucional provavelmente resolve as três. | ADR-010, Decisão 7 |

### Q-C: as três variantes

A proposta anterior, só QA interno, foi retirada. Ela esvaziava a mitigação do R2: equipe, bolsistas e alunos não representam o baixo letramento, e a revisão clínica e o prazo de correção medem se o conteúdo está correto, não se é compreendido.

**O que vale em qualquer variante:** QA interno com equipe, bolsistas e alunos (Decisão 2f do pedido).

**Bloco V — validação de produto com o público-alvo.** É a parte da C1.
- **Participantes:** pessoas indicadas pelo PET-Saúde como representativas do público-alvo. A caracterização fica com quem indica; o projeto não registra quem a pessoa é.
- **Informação oral, sem assinatura:** antes da tarefa, a pessoa ouve que é um teste do produto, voluntário e sem nenhum registro. Não assina nada, justamente para não se parecer com um TCLE.
- **Limites do desenho:**
  - sem hipótese e sem métrica de sucesso publicada;
  - sem registro identificável (nome, foto, áudio ou vídeo);
  - sem roteiro de entrevista, só a tarefa e a anotação de onde a interface travou;
  - o resultado serve só para iterar a interface, é descartado depois e nunca é usado em publicação.
- **Pré-condição:** manifestação escrita do CEP/UFRR de que esse desenho não é pesquisa (F-20 d). Até ela chegar, o bloco não se ativa. Se o CEP disser que é pesquisa, o bloco também não se ativa, e o teste com o público-alvo fica no M8.

**Bloco M — mitigações sem participante externo.** É a parte da C2.
- **Revisão de linguagem simples:** feita por profissionais do PET-Saúde que atendem essa população (ACS, enfermagem), com registro de quem revisou, qual versão e quando.
- **Índice de legibilidade em pt-BR:** critério de aceite dos textos e dos roteiros de áudio. O índice e o limiar ficam a definir (por exemplo, o Flesch adaptado ao português).
- **Escuta dos roteiros:** o TTS em pt e es é ouvido no aparelho, antes da promoção, por quem revisa a linguagem.

**As variantes:**

| Variante | Composição | Leitura |
|---|---|---|
| **C1** | QA interno + bloco V | A mais honesta com o problema, mas depende do CEP. Sem a manifestação, só resta o QA interno. |
| **C2** | QA interno + bloco M | A mais segura juridicamente. A compreensão pelo baixo letramento só é medida no M8. |
| **C1+C2** (recomendada) | QA interno + bloco M agora + bloco V condicionado à F-20 (d) | O bloco M não depende de ninguém de fora. Se o CEP disser que o bloco V é pesquisa, nada precisa ser reescrito: a cláusula condicional simplesmente não se ativa. |

Os cinco pontos afetados trazem as três variantes por extenso, marcadas **[C1]**, **[C2]** e **[C1+C2]**: o ADR-010 3f, o Custo aceito 1, a Fase 1 do PRD §6.2, a R2 e o brainstorm M1/M2. O executor mantém a escolhida e apaga as outras duas.

Novas perguntas no registro da T0 (Task 5):
- **F-20:** consulta prévia ao CEP/UFRR. Tem quatro pontos, listados na Task 8.
- **F-21:** titularidade do registro do software.

## Review Focus

1. **"Piloto" órfão significando publicação.** Um leitor acharia que o lançamento ainda depende do CEP. Coberto pelo `piloto.py`, nas Tasks 2, 5 e 7.
2. **TCLE e consentimento LGPD sem distinção.** Coberto pela Task 7, Passo 2.
3. **Texto dando a entender que o app coleta algo para o estudo.** Contradiz a INV-2 e o `dados-do-usuario.md`. Coberto pela Task 7, Passo 3.
4. **A H2 sumir sem destino.** Coberto pela Task 7, Passo 4.
5. **Link para o arquivo renomeado.** Coberto pelo redirecionamento em `docs/aprovacoes-piloto.md` e pela Task 7, Passo 5. O corpo da PR #78 aponta para o nome antigo.

---

## Inventário (busca de 2026-11-09, `develop` em `7f00190`)

Script (salve fora do repositório e rode da raiz):

```python
# inv.py — python3 -I inv.py spec README.md CLAUDE.md docs app/assets/legal app/lib/l10n PROGRESS.md CHANGELOG.md .github
import re, sys, pathlib
pat = re.compile(r'piloto|\bCEP\b|TCLE|participante|entrevista|observa[çc][ãa]o|\bH1b?\b|\bH2\b|\bH4\b|LGPD-RF02|port[ãa]o|portões|consentimento', re.I)
for r in sys.argv[1:]:
    p = pathlib.Path(r)
    fs = [p] if p.is_file() else [f for f in p.rglob('*') if f.suffix in ('.md', '.arb', '.html', '.yml') and f.is_file()]
    for f in sorted(fs):
        if 'superpowers/plans' in str(f): continue
        for i, l in enumerate(f.read_text(errors='ignore').splitlines(), 1):
            for m in pat.finditer(l):  # um resultado por ocorrência: linha longa não esconde a segunda
                print(f"{f}:{i}: …{l[max(0, m.start() - 80):m.end() + 80].strip()}…")
```

Ele encontrou 172 linhas. As que importam:

| Arquivo:linha | O que é | Tarefa |
|---|---|---|
| `spec/stack.md:312` | §8, **fora dos ADRs**: "O **F-Droid** fica como canal futuro, não previsto para o estudo piloto:" | 1 (edição direta) |
| `spec/stack.md:493,497,499,505,507,509` | ADR-004: gatilhos "crescer além do piloto", "builds de piloto", "estudo com participantes externos", CEP | 1 (Revisão no ADR-004) |
| `spec/stack.md:526` | ADR-005, Contexto: "o piloto 'em 2 UBS'", que é a premissa histórica que o ADR-005 derrubou | fica (regra b) |
| `spec/stack.md:465,516,517` | ADR-004: aparelhos do estudo provisionados do zero; falha de download "no estudo piloto" | 1 (Revisão no ADR-004) |
| `spec/stack.md:553-557,566,579,588,591` | ADR-005: Decisão 7, fundamentos, custo 4, métrica-norte, gatilho | 1 (Revisão no ADR-005) |
| `spec/stack.md:604,606,620` | ADR-006: "o estudo piloto roda na faixa de teste"; F-Droid | 1 (Revisão no ADR-006) |
| `spec/stack.md:665` | ADR-007: revisão "quando o estudo piloto atingir o critério de saída" | 1 (Revisão no ADR-007) |
| `spec/stack.md:698` | ADR-008: idem | 1 (Revisão no ADR-008) |
| `spec/stack.md:724,766` | ADR-009: "defeito achado no estudo piloto"; revisão pelo critério de saída | 1 (Revisão no ADR-009) |
| `spec/PRD.md:31-37` | H1, H1b, H2, H4 e "Evidência atual" | 2 |
| `spec/PRD.md:52` | North Star ligada ao estudo piloto e à telemetria | 2 |
| `spec/PRD.md:304,310-312` | corte do MVP; Fases 1 a 3 ("telemetria agregada ativa" na Fase 3) | 2 |
| `spec/PRD.md:319,325,332-341,346` | R2, R8, §6.4, aprovações | 2 |
| `spec/PRD.md:111` | CAP-10 "(H2)" | 2 |
| `spec/espec.md:3`, tabela RNF, `:538` | lista RNF-01…RNF-11; rastreabilidade | 2 (RNF-12) |
| `spec/espec.md:34` | RF-15, fim da célula: "Fechar esta lacuna é pré-requisito do estudo piloto do projeto, não de merge". A linha tem 1.311 caracteres, e o primeiro inventário a cortou antes dessa frase | 2 |
| `spec/lgpd.md:15,34-39,48-49,55-60,71,113,164,238,247,249,289,291,314` | titulares, RF02, RF04, RF05, RF07, RF13 (fim da descrição), DOC03, direitos, matriz, RIPD | 3 |
| `spec/lgpd.md:127-130,175,190,198,215,227,250,273,300,302` | consentimento de marketing, CMS e direitos em geral | falso positivo |
| `docs/dados-do-usuario.md` | não cita o estudo | 4 (§5 nova) |
| `spec/brainstorm.md:118-128,154-161,163-168,192-198` | M1, M2, M6, M7, métricas | 5 |
| `docs/aprovacoes-piloto.md` | quadro dos portões; citado no corpo da PR #78 | 5 (`aprovacoes.md` novo + redirecionamento) |
| `spec/implantacao.md:56,59,108,170`, §2.7 | faixa de teste "onde roda o estudo piloto"; nota de pre-release; checklist da Play | 5 |
| `.github/workflows/app-release.yml:233` | "Versão em teste no estudo piloto do projeto." | 5 |
| `CHANGELOG.md:15` | "Primeira versão para o estudo piloto (dogfooding interno)" | 5 |
| `spec/arquitetura.md:316,741` | "Fase 1 valida H2"; "revisão clínica do estudo piloto" | 5 |
| `spec/arquitetura.md:83,108,528,574,594,1037-1319` | "portão" técnico | falso positivo |
| `docs/operacao.md:1087` | termos mudaram "para o estudo piloto" | 5 |
| `docs/operacao.md:994,1080,1082`; `docs/revisao-golden.md:56` | portão golden; consentimento do CMS | falso positivo |
| `PROGRESS.md:8,10` | marco "Piloto" | 5 + Task 8 |
| `docs/superpowers/plans/2026-11-02-realinhamento-…md:470,476,491,499` | F-9, F-11, F-14 no registro | 5 (registro da T0) |
| `CLAUDE.md:19` | "Estudo piloto do projeto… dois portões" | 6 |
| `CLAUDE.md:125,130`; `README.md:284,308` | portão golden; LGPD-RF02 do CMS | falso positivo (conferir na Task 6) |
| `app/assets/legal/termos_*`, `privacidade_*` | nenhuma ocorrência | 6 (confirmar: sem bump) |
| `app/assets/legal/gemma_prohibited_use_pt.md:35,37`; `spec/design*.html` | texto do Gemma; `<h1>`…`<h4>` | falso positivo |

---

### Task 1: ADR-010 e as Revisões nos ADR-004 a 009

**Pré-requisito:** a Q-C respondida.

**Files:**
- Modify: `spec/stack.md`. O ADR-010 entra no fim do ADR-009, antes de `## 11.`. Os parágrafos de Revisão entram no fim de cada ADR, imediatamente antes do `### ADR-` seguinte, e o do ADR-009 antes do ADR-010.

**Interfaces:**
- Produz: `ADR-010, Decisão N`, com N de 1 a 7. Só a Decisão 3 tem alíneas, de `3a` a `3g`. A subseção "Decisões complementares" (DC-A a DC-E) corresponde às Q-A a Q-E. As outras tarefas citam exatamente esses números.

- [ ] **Passo 1:** `grep -rn 'ADR-010' spec/ CLAUDE.md README.md docs --exclude-dir=superpowers` não deve devolver nada.

- [ ] **Passo 2: insira o ADR-010.** Escolha a variante [C1]/[C2] conforme a Q-C:

```markdown
### ADR-010 Lançamento do app separado do estudo de impacto: **ACEITO** (2026-11-09)

**Contexto.** Antes de 2026-11-09, o [ADR-005](#10-registro-de-decisões-arquiteturais-adr), Decisão 7, juntava a publicação do app e o estudo com usuários numa única etapa, o "estudo piloto do projeto", com dois portões. O segundo exigia TCLE e parecer de Comitê de Ética em Pesquisa "se houver coleta de dados de participantes", o que punha a ética em pesquisa no caminho crítico da publicação. O app não coleta dado pessoal ([INV-2](espec.md); [`docs/dados-do-usuario.md`](../docs/dados-do-usuario.md)). A coleta que existe é a do estudo: observação de uso e respostas a entrevistas ([LGPD-RF02](lgpd.md)). Decisão da coordenação do projeto em 2026-11-09.

**Decisão.**
1. **Duas etapas, cada uma com seu portão.**
   - **Lançamento (Parte A):** a publicação do app. É produto, não pesquisa: não coleta dados de usuários, não mede hipótese e não observa nem entrevista pessoas externas para fins de pesquisa. Não depende de CEP.
   - **Estudo de impacto (Parte B):** pesquisa com seres humanos sobre o app **já publicado**.
2. **"Piloto", nome usado antes de 2026-11-09, deixa de nomear etapa.** Onde se referia à publicação, passa a ser "lançamento". Onde se referia a observar pessoas, passa a ser "estudo de impacto". O dogfooding interno é uma fase do lançamento.
3. **Portão do lançamento.** Substitui o portão "estudo com participantes externos" do ADR-005, Decisão 7.
   a. Conteúdo de saúde validado por profissionais com registro ativo, com registro de revisão (quem, qual versão, quando): o portão golden ([#2](https://github.com/hbgit/Guia-UBS/issues/2)) e os atestados `AT-NNNN`. O PET-Saúde/Telessaúde UFRR participa como parceiro, citado ao usuário conforme a F-13.
   b. Aviso de que o app não substitui atendimento ([RF-16](espec.md)) e encaminhamento explícito dos sinais de alarme para SAMU 192, UPA ou UBS (INV-1).
   c. Responsável institucional identificado (F-11). Continua no caminho crítico, junto com o parecer jurídico do ADR-004 (Revisão 2026-11-02).
   d. Política de privacidade e termos publicados em `guiasaude.prismrr.com.br` ([`implantacao.md`](implantacao.md) §2.9), mesmo sem coleta, e políticas da Google Play para apps de saúde conferidas (§2.7).
   e. Correção de conteúdo publicada em até 7 dias ([RNF-12](espec.md), a antiga H2 do PRD), pelo GitHub Releases e pela Google Play.
   f. Testes de usabilidade internos (equipe, bolsistas e alunos) são **QA**: não registram dado identificável, não medem hipótese e não são usados depois em publicação. O teste fechado da Play também é QA (DC-D).
      [C2] A ausência do público-alvo é compensada por três mitigações: revisão de linguagem simples por profissionais do PET-Saúde que atendem essa população (ACS, enfermagem), com registro de quem revisou, qual versão e quando; índice de legibilidade em pt-BR como critério de aceite dos textos e roteiros de áudio (índice e limiar a definir); e escuta do TTS em pt e es no aparelho antes da promoção.
      [C1] Além do QA, pode haver **validação de produto** com pessoas indicadas pelo PET-Saúde como representativas do público-alvo, cabendo a caracterização a quem indica. Antes da tarefa, a pessoa é informada oralmente de que é um teste do produto, voluntário e sem registro, e não assina nada, para não se parecer com um TCLE. O teste não tem hipótese, registro identificável nem roteiro de entrevista; o resultado serve só para iterar e é descartado. Só ocorre depois da manifestação escrita do CEP/UFRR de que esse desenho não é pesquisa (F-20 d). Sem ela, o lançamento conta só com o QA.
      [C1+C2] A ausência do público-alvo é compensada desde já por três mitigações: revisão de linguagem simples por profissionais do PET-Saúde que atendem essa população (ACS, enfermagem), com registro de quem revisou, qual versão e quando; índice de legibilidade em pt-BR como critério de aceite dos textos e roteiros de áudio (índice e limiar a definir); e escuta do TTS em pt e es no aparelho antes da promoção. **Se, e somente se**, o CEP/UFRR se manifestar por escrito de que o desenho não é pesquisa (F-20 d), soma-se a **validação de produto** com pessoas indicadas pelo PET-Saúde como representativas do público-alvo, cabendo a caracterização a quem indica. Antes da tarefa, a pessoa é informada oralmente de que é um teste do produto, voluntário e sem registro, e não assina nada. O teste não tem hipótese, registro identificável nem roteiro de entrevista; o resultado serve só para iterar e é descartado. Se o CEP entender que é pesquisa, a cláusula não se ativa, e o teste com o público-alvo fica no estudo de impacto.
   g. **Critério de promoção para produção:** nenhuma orientação clinicamente incorreta na revisão clínica, mais a aprovação da coordenação clínica do projeto (DC-B).
4. **Portão do estudo de impacto.**
   - **Pré-condição: instituição proponente.** A Plataforma Brasil recebe o protocolo de uma instituição proponente cadastrada, e o CEP é "vinculado à instituição que realiza a pesquisa" (Lei 14.874/2024, art. 2º, X). **Hipótese de trabalho, a confirmar na consulta prévia (F-20 b):** o pesquisador responsável é docente da UFRR, e o CEP/UFRR recebe protocolos de pesquisadores da casa tendo a UFRR como proponente. O "sem vínculo formal" do PRISM (ADR-005, Decisões 1 e 8) diz respeito à publicação do app, não à submissão de um estudo por um docente da UFRR. Se a hipótese não se confirmar, a Parte B passa a depender da formalização da cooperação (custo aceito 4).
   - **Base LGPD dos dados do estudo:** escolhida com o controlador (F-11). A hipótese de estudos por órgão de pesquisa (art. 7º, IV) só é usada se o controlador confirmar que se enquadra no art. 5º, XVIII. A proponente do estudo e o controlador dos dados do estudo podem ser respondidos juntos (F-11, F-20 b, F-21).
   - **TCLE e parecer do CEP/UFRR** (Plataforma Brasil) antes do primeiro participante externo. **Postura do projeto:** até manifestação escrita do CEP/UFRR, o projeto não se apoia em nenhuma hipótese de dispensa, porque a Lei 14.874/2024 (art. 6º) e a pendência do regulamento do art. 63, parágrafo único, tornam incerta a aplicação da Res. CNS 510/2016, art. 1º, parágrafo único. O entendimento de que uma atividade não é pesquisa também só vale com manifestação escrita do CEP/UFRR (F-20 c e d).
   - **Hipóteses:** H1, H1b e H4 do [PRD](PRD.md) §1.3.2.
   - **Método:** observação de uso e respostas a entrevistas, por canal próprio, fora do app ([LGPD-RF02](lgpd.md)). Os dados agregados da loja (instalações, versões ativas) podem ser insumo.
   - **Antes do primeiro participante, também:** a base LGPD dos dados do estudo escolhida com o controlador (consentimento, ou termo de informação se a base for o art. 7º, IV), o RIPD (DC-A) e o controlador (F-11).
5. **Regras de fronteira.**
   - Nada observado no lançamento vira dado de resultado no estudo de impacto. O CEP não aprova retroativamente.
   - TCC e relatório do PET-Saúde com dados de participantes só existem dentro do estudo de impacto. Relato de experiência de desenvolvimento, sem dados de pessoas, não entra no CEP. Da Parte A, o PET-Saúde pode reportar o produto, o alcance agregado da loja e o relato de experiência, mas nenhum dado de pessoa.
   - Telemetria futura é decisão separada, com ADR próprio, LGPD e revisão da INV-2. Não é consequência desta divisão.
6. **TCLE e consentimento LGPD são exigências distintas.**
   - O TCLE responde à ética em pesquisa (Lei 14.874/2024, art. 18; Res. CNS 466/2012 e 510/2016) e é exigido pelo CEP.
   - A base LGPD responde ao tratamento de dados (arts. 7º e 11). Para dados de pesquisa, a LGPD se aplica de forma subsidiária à Lei 14.874/2024 (art. 61).
   - Podem estar no mesmo documento, nunca na mesma cláusula.
   - O "li e concordo" dos termos do app não é nenhum dos dois (ADR-004).
7. **Registro do software** como produção técnica (e, opcionalmente, no INPI) é entregável do lançamento, independente do estudo. A titularidade fica aberta (F-21).

**Decisões complementares (revisão de 2026-11-09).**
- **DC-A (Q-A).** O RIPD é exigido antes do estudo de impacto. No lançamento, a superfície de dados é o `docs/dados-do-usuario.md`, a confirmar com o encarregado (F-11).
- **DC-B (Q-B).** O antigo critério de saída vira o critério de promoção para produção (Decisão 3g). Os ADR-007, 008 e 009 recebem Revisões que apontam para ele.
- **DC-C (Q-C).** [[DC-C-PENDENTE]] Registre a variante escolhida pela coordenação (C1, C2 ou C1+C2), a data e quem decidiu.
- **DC-D (Q-D).** Os testadores do teste fechado da Play são QA do lançamento: equipe, bolsistas e alunos, sem coleta. O mínimo de testadores e de dias é lido no Play Console na data. Se faltar gente interna, a decisão volta à coordenação.
- **DC-E (Q-E).** A titularidade do registro do software fica aberta (F-21), e a resposta sobre o vínculo institucional (Decisão 4, pré-condição) deve resolvê-la junto.

**Alternativas descartadas.**
- **Manter publicação e estudo juntos.** O CEP ficaria no caminho da publicação de um app que não coleta nada: semanas a meses de tramitação sem nenhuma proteção a mais para quem usa o app. E o "se houver coleta" continuaria ambíguo, sugerindo que o app é a fonte dos dados.
- **Remover o CEP de vez.** O estudo observa e entrevista pessoas de populações vulneráveis expostas a orientação de saúde, o que é pesquisa com seres humanos (Lei 14.874/2024, art. 2º, XXXIV). Sem o parecer, os resultados não são publicáveis, e o CEP não aprova retroativamente.

**Custos aceitos.**
1. [C2] A primeira evidência de compreensão por quem tem baixo letramento (H1, H1b; risco R2, crítico) só vem do estudo de impacto, depois da publicação. As mitigações da Decisão 3f reduzem o risco, mas medem a linguagem, não a compreensão.
   [C1] Enquanto o CEP não se manifestar, ou se entender que a validação de produto é pesquisa, o lançamento conta só com o QA interno, sem nenhuma mitigação para o baixo letramento, e a primeira evidência de compreensão vem do estudo de impacto. Se o CEP aceitar, a validação itera a interface, mas não produz evidência publicável.
   [C1+C2] As mitigações da Decisão 3f medem a linguagem, não a compreensão. A validação de produto, se o CEP a aceitar, itera a interface, mas não produz evidência publicável. Em qualquer caso, a evidência de compreensão por quem tem baixo letramento (H1, H1b; risco R2, crítico) só vem do estudo de impacto, depois da publicação.
2. A fronteira exige disciplina: toda observação precisa de data e de origem (lançamento ou estudo).
3. Ficam duas listas de aprovação para manter ([`docs/aprovacoes.md`](../docs/aprovacoes.md)).
4. Se a hipótese de trabalho da Decisão 4 não se confirmar (a UFRR como proponente de um estudo de docente da casa), a Parte B passa a depender da formalização da cooperação (ADR-005, Decisão 1).

**Relação com outros ADRs.** Prevalece sobre o ADR-005, Decisão 7, sobre os gatilhos do ADR-004 e sobre as menções ao estudo nos ADR-006 a 009. Cada um recebe uma Revisão 2026-11-09 que aponta para cá.

**Revisão.** Reabrir se:
- a consulta prévia ao CEP/UFRR (F-20) entender que o lançamento também precisa de protocolo;
- a UFRR não puder ser a proponente e não houver outra instituição;
- a coordenação do PET-Saúde/Telessaúde recusar a regra de fronteira (Decisão 5) ou a própria separação entre lançamento e estudo de impacto (Decisão 1). Ressalva sobre o cronograma da Parte B **não** reabre este ADR: ajusta-se o calendário do estudo de impacto em [`docs/aprovacoes.md`](../../aprovacoes.md);
- sair o regulamento do art. 63 da Lei 14.874/2024;
- surgir proposta de telemetria.
```

- [ ] **Passo 3: acrescente as seis Revisões**, cada uma no fim do seu ADR.

Antes das Revisões, uma edição direta fora dos ADRs, na §8 (linha 312): troque `não previsto para o estudo piloto:` por `não previsto para o lançamento ([ADR-010](#10-registro-de-decisões-arquiteturais-adr)):`.

ADR-004:
```markdown
**Revisão 2026-11-09 ([ADR-010](#10-registro-de-decisões-arquiteturais-adr)).** O "estudo com participantes externos" dos gatilhos passa a ser o **estudo de impacto**, e "crescer além do piloto" lê-se "promover para produção na Google Play ou iniciar o estudo de impacto"; "builds de piloto" lê-se "builds do lançamento". O parecer jurídico e o responsável (F-11) continuam como condição da promoção para produção. O CEP passa a ser condição só do estudo de impacto (ADR-010, Decisão 4). "Aparelho do estudo piloto" lê-se "aparelho do dogfooding ou do estudo de impacto". A taxa de falha de download é observada pela loja e pelos relatos de QA, nunca por telemetria (ADR-010, Decisão 5).
```

ADR-005:
```markdown
**Revisão 2026-11-09 ([ADR-010](#10-registro-de-decisões-arquiteturais-adr)).** A Decisão 7 foi dividida. O dogfooding interno e o portão de publicação formam o **lançamento**, e a exigência de TCLE e CEP sai dele para o **estudo de impacto**, que tem portão próprio. O critério de saída vira o critério de promoção para produção (ADR-010, Decisão 3g). O custo aceito 4 lê-se "a promoção para produção e o estudo de impacto esperam o controlador", e o estudo pode depender ainda da formalização da Decisão 1 (ADR-010, Decisão 4). A métrica-norte passa a ser do estudo de impacto. O gatilho de reabrir "se o estudo piloto mostrar que o público lê o app como serviço oficial" lê-se "se o estudo de impacto ou os relatos do lançamento mostrarem…".
```

ADR-006:
```markdown
**Revisão 2026-11-09 ([ADR-010](#10-registro-de-decisões-arquiteturais-adr)).** Na Decisão 2, a faixa de teste da Play e a *pre-release* do GitHub servem ao dogfooding e ao QA do lançamento, e "o estudo piloto roda na faixa de teste" lê-se assim. O estudo de impacto usa o app publicado. Na Decisão 4 e no custo 3, "estudo piloto" lê-se "lançamento".
```

ADR-007 e ADR-008, uma frase cada:
```markdown
**Revisão 2026-11-09 ([ADR-010](#10-registro-de-decisões-arquiteturais-adr)).** "Quando o estudo piloto atingir o critério de saída da Decisão 7 do ADR-005" lê-se "quando o lançamento for promovido para produção" (ADR-010, Decisão 3g).
```

ADR-009:
```markdown
**Revisão 2026-11-09 ([ADR-010](#10-registro-de-decisões-arquiteturais-adr)).** "Quando o estudo piloto atingir o critério de saída da Decisão 7 do ADR-005" lê-se "quando o lançamento for promovido para produção" (ADR-010, Decisão 3g), e "defeito achado no estudo piloto" lê-se "defeito achado no dogfooding ou no teste fechado".
```

- [ ] **Passo 4: confira.**
  - `grep -c '^\*\*Revisão 2026-11-09' spec/stack.md` deve dar `6`.
  - `python3 -I piloto.py --stack spec/stack.md` deve sair com 0.
  - `grep -nF -e '[C1]' -e '[C2]' -e '[C1+C2]' -e '[[DC-C-PENDENTE]]' spec/stack.md` não deve devolver nada: as variantes descartadas e o marcador foram apagados.

- [ ] **Passo 5: commit.** `git commit -am "docs(adr): ADR-010 separa o lancamento do app do estudo de impacto"`

---

### Task 2: PRD e espec — hipóteses, RNF-12, roadmap e riscos

**Files:**
- Modify: `spec/PRD.md`: §1.3 (linhas 27-37), §1.5 (52-54), CAP-10 (111), §6.1 (304), §6.2 (310-312, mais uma linha nova), §6.3 (319), §6.4 (332-341), aprovações (346).
- Modify: `spec/espec.md`: linha 3, tabela de RNF (depois da RNF-11) e linha 538.

**Interfaces:**
- Consome: ADR-010, Decisões 3e, 3f, 4 e 5.
- Produz: `RNF-12`, `PRD §1.3.1`, `§1.3.2` e `§1.3.3`.

- [ ] **Passo 1: §1.3.** Troque o título por `### 1.3 Hipóteses e requisito operacional` e a tabela por:

```markdown
O lançamento não mede hipótese com pessoas; o estudo de impacto mede ([ADR-010](stack.md#10-registro-de-decisões-arquiteturais-adr)).

#### 1.3.1 Hipótese técnica (validada sem pessoas)

| ID | Hipótese | Validação | Critério de sucesso |
|---|---|---|---|
| H3 | (linha atual da H3, sem mudança) |

#### 1.3.2 Hipóteses do estudo de impacto

Origem: antes de 2026-11-09, eram validadas no "estudo piloto do projeto" (M6) e no teste M2. Destino: o estudo de impacto, sob TCLE e parecer do CEP (ADR-010, Decisão 4). O que se observar no lançamento não conta como evidência (ADR-010, Decisão 5).

| ID | Hipótese | Validação | Critério de sucesso |
|---|---|---|---|
| H1 | (texto atual) | Estudo de impacto | ≥ 80% concluem os módulos educativos testados sem ajuda |
| H1b | (texto atual) | Estudo de impacto | ≥ 80% completam triagem sem ajuda |
| H4 | (texto atual) | Estudo de impacto; dados agregados da loja como insumo | Meta de alcance **provisória**, a fixar com o PET-Saúde antes do 1º participante do estudo de impacto (F-14) |

#### 1.3.3 Antiga H2, agora requisito operacional

A antiga H2 ("o sync de oportunidade converge a frota em ≤ 7 dias") não tem como ser medida no aparelho sem telemetria (INV-2). Virou o **RNF-12** ([espec.md](espec.md)): a correção de conteúdo é publicada em até 7 dias, e isso se mede do lado da publicação. O mecanismo de sync continua validado em rede instável simulada (M3).

Evidência atual: H1, H1b e H4 são **premissas** até o estudo de impacto; a H3 foi medida na PoC ([arquitetura.md](arquitetura.md) §5.1).
```

- [ ] **Passo 2: §1.5.** Troque a linha 52 e a frase da 54:

```markdown
**Métrica-norte do estudo de impacto (provisória — F-14):** **módulos educativos concluídos sem mediação** (proxy do valor: compreensão do SUS sem depender de quem leia por você). É medida no estudo de impacto, por observação sob TCLE, e não pelo app. A meta é fixada com o PET-Saúde antes do 1º participante do estudo; a métrica é revisada até 2027-05-01 ou no fim do estudo ([ADR-005](stack.md#10-registro-de-decisões-arquiteturais-adr), Revisão; [ADR-010](stack.md#10-registro-de-decisões-arquiteturais-adr)). Medi-la no app exigiria telemetria nova, que é decisão separada (ADR-010, Decisão 5).

As triagens completadas sem ajuda passam a métrica **secundária** do estudo (proxy do apoio: decisão de deslocamento informada).
```

- [ ] **Passo 3: CAP-10, §6.1 e §6.4.**
  - Na CAP-10 (linha 111), troque `**Alto** (H2)` por `**Alto** (RNF-12, antiga H2)`.
  - Em §6.1, troque a frase de `Corte: prova H1` até `(SLM em device de entrada).` por: `Corte: o lançamento entrega essas capacidades com a H3 validada e o RNF-12 operando; H1, H1b e H4 são provadas pelo estudo de impacto, depois da publicação ([ADR-010](stack.md#10-registro-de-decisões-arquiteturais-adr)).`
  - Em §6.4:
    - na linha da CAP-06, troque `(teste M2/M6)` por `(estudo de impacto)`;
    - na linha da CAP-10/11, troque os requisitos por `RF-10, RF-11, RNF-12; INV-3/7`, a hipótese `H2` por `RNF-12 (antiga H2)` e a métrica por `Correção publicada em ≤ 7 dias; zero pack inválido ativado`.

- [ ] **Passo 4: §6.2, nas colunas `Fase | Semanas | Entregas | Riscos que valida | Gate de saída`.**
  - **Fase 1:** na coluna de riscos, troque `H2 (sync)` por `sync em rede instável (RNF-12, antiga H2)`. Troque `H1 parcial (usabilidade de protótipo…)` por:
    - [C2] `usabilidade do protótipo como QA interno, com revisão de linguagem simples, legibilidade e escuta do TTS (ADR-010, 3f)`;
    - [C1] `usabilidade do protótipo como QA interno; validação de produto com pessoas indicadas pelo PET-Saúde, só depois da manifestação escrita do CEP (ADR-010, 3f)`;
    - [C1+C2] `usabilidade do protótipo como QA interno, com revisão de linguagem simples, legibilidade e escuta do TTS; validação de produto com pessoas indicadas pelo PET-Saúde, se e quando o CEP se manifestar por escrito (ADR-010, 3f)`.
  - **Fase 2:** troque o trecho de `**estudo piloto do projeto** (PRISM/PET-Saúde,` até o fim do parêntese por `**portão de lançamento** (dogfooding interno e QA; [ADR-010](stack.md#10-registro-de-decisões-arquiteturais-adr), Decisão 3); **protocolo do estudo de impacto submetido ao CEP em paralelo**`. No gate de saída, use o critério de promoção (Decisão 3g).
  - **Fase 3:** troque `telemetria agregada ativa` por `sem telemetria (decisão separada, ADR-010, Decisão 5)` e acrescente `registro do software como produção técnica (opcional: INPI; F-21)`.
  - **Linha nova, depois da Fase 3:**
    `| **Estudo de impacto** | Tramitação a partir da Fase 2, em paralelo; coleta só depois da 1ª versão em produção e do parecer | TCLE e parecer do CEP/UFRR; observação de uso e entrevistas fora do app; relatório | H1, H1b, H4 (§1.3.2) | Relatório final; dados descartados ou anonimizados conforme a LGPD-RF07(b) |`
  - **Nota logo abaixo da tabela:**
    `A tramitação do estudo de impacto (consulta prévia F-20, protocolo na Plataforma Brasil e parecer) leva de semanas a meses: o prazo legal de análise é de 30 dias úteis (Lei 14.874/2024, art. 14), sem contar as pendências. Por isso ela começa em paralelo com o lançamento, e não depois dele ([ADR-010](stack.md#10-registro-de-decisões-arquiteturais-adr)).`

- [ ] **Passo 5: §6.3 e aprovações.**
  - Na R2, troque `Detectar cedo (M1/M2 com usuários reais, incl. baixo letramento)` por:
    - [C2] `Reduzir antes da publicação (QA interno, revisão de linguagem simples por profissionais do PET-Saúde, legibilidade e escuta do TTS) e medir no estudo de impacto, que é onde H1/H1b são testadas com o público-alvo (ADR-010, 3f; custo aceito 1)`;
    - [C1] `Detectar cedo por validação de produto com pessoas indicadas pelo PET-Saúde, sem registro e sem hipótese, depois da manifestação escrita do CEP (ADR-010, 3f); até lá, só o QA interno. Medir no estudo de impacto`;
    - [C1+C2] `Reduzir antes da publicação (QA interno, revisão de linguagem simples por profissionais do PET-Saúde, legibilidade e escuta do TTS) e, se o CEP se manifestar por escrito, detectar cedo por validação de produto com pessoas indicadas pelo PET-Saúde, sem registro e sem hipótese (ADR-010, 3f). Medir no estudo de impacto, que é onde H1/H1b são testadas (custo aceito 1)`.
  - A R8 fica como está.
  - Na linha 346, depois de `encarregado (DPO; …F-11)`, acrescente `; o estudo de impacto exige ainda o parecer do CEP/UFRR e uma instituição proponente ([ADR-010](stack.md#10-registro-de-decisões-arquiteturais-adr), Decisão 4)`.

- [ ] **Passo 6: `espec.md`.**
  - Na linha 3, troque `RNF-01…RNF-11` por `RNF-01…RNF-12`.
  - Depois da linha da RNF-11, acrescente:
    `| RNF-12 | Prazo de correção de conteúdo (antiga H2 do PRD; [ADR-010](stack.md)) | Correção de conteúdo clínico aprovada no dual review chega aos canais em ≤ 7 dias corridos: pack assinado publicado no host de conteúdo e, quando exigir binário, APK no GitHub Releases e AAB enviado à Google Play (o prazo de análise da loja não conta) | Medido do lado da publicação: data da aprovação × data da publicação, registradas na trilha do CMS ou na nota da release; sem telemetria (INV-2) |`
  - Na linha 538, troque `RF-17, RNF-10 e RNF-11 vivem fora do aparelho` por `RF-17, RNF-10, RNF-11 e RNF-12 vivem fora do aparelho`.
  - Na RF-15 (linha 34, fim da célula), troque `pré-requisito do estudo piloto do projeto, não de merge` por `pré-requisito da promoção do lançamento para produção ([ADR-010](stack.md), Decisão 3g), não de merge`.

- [ ] **Passo 7: confira.**
  - `python3 -I piloto.py spec/PRD.md spec/espec.md` deve sair com 0. A única menção que sobra é a da §1.3.2, que casa com o padrão (a) por causa de `Origem:`.
  - `python3 -I -c "import re;print([l for l in open('spec/PRD.md') if re.search(r'\bH2\b',l) and not re.search('antiga|RNF-12',l)])"` deve imprimir `[]`.
  - `grep -nF -e '[C1]' -e '[C2]' -e '[C1+C2]' spec/PRD.md` não deve devolver nada.

- [ ] **Passo 8: commit.** `git commit -am "docs(prd): hipoteses do estudo de impacto; H2 vira RNF-12; roadmap em lancamento e estudo"`

---

### Task 3: `lgpd.md` — estudo de impacto, e TCLE separado da base LGPD

**Files:**
- Modify: `spec/lgpd.md`, linhas 15, 34-39, 49, 56, 60, 71, 164, 238, 247, 249, 289 e 314.

**Interfaces:**
- Consome: ADR-010, Decisões 4, 5 e 6; DC-A.
- Produz a frase-padrão **"dados do estudo (observações de uso, respostas a entrevistas)"**, que a Task 4 repete literalmente.

- [ ] **Passo 1: titulares (linha 15).**
  `2. **Participantes do estudo de impacto ([ADR-010](stack.md#10-registro-de-decisões-arquiteturais-adr))** (dados do estudo (observações de uso, respostas a entrevistas) de 20 a 30 pessoas, coletados fora do app): exige base LGPD própria (RF02), **distinta** do TCLE da ética em pesquisa. O lançamento do app não trata dado de usuário ([`docs/dados-do-usuario.md`](../docs/dados-do-usuario.md));`

- [ ] **Passo 2: LGPD-RF02.**
  - Título: `### LGPD-RF02 — Base legal e consentimento (estudo de impacto e operadores do CMS)`.
  - Na Descrição, troque o início do item (a), até `prazo de descarte;`, por:
    `(a) os dados do estudo (observações de uso, respostas a entrevistas) do estudo de impacto (ADR-010) são tratados sob uma de duas bases, escolhida com o controlador (F-11): **consentimento** livre, informado e inequívoco (art. 7º, I; art. 11, I), por escrito ou registro equivalente, destacado das demais cláusulas, com finalidade, dados coletados e prazo de descarte; ou **realização de estudos por órgão de pesquisa** (art. 7º, IV; art. 11, II, c), com **termo de informação** ao participante e anonimização sempre que possível. A segunda só é usada se o controlador confirmar que se enquadra como órgão de pesquisa (art. 5º, XVIII), a confirmar com o controlador (F-11) e o parecer jurídico (T7-R) (ADR-010, Decisão 4). Em qualquer caso, **Não é o TCLE:** o TCLE responde à ética em pesquisa (Lei 14.874/2024, art. 18; Res. CNS 466/2012 e 510/2016) e é exigido pelo CEP, e para dados de pesquisa a Lei 14.874/2024 manda aplicar a LGPD de forma subsidiária (art. 61). Podem estar no mesmo documento, em seções distintas (ADR-010, Decisão 6). O lançamento não tem dado de usuário a tratar, e o "li e concordo" dos termos do app não é consentimento LGPD (ADR-004);`
    Mantenha o resto do item e o item (b), do CMS.
  - Base legal: `consentimento (art. 7º, I; art. 11, I) ou estudos por órgão de pesquisa (art. 7º, IV; art. 11, II, c), este só se o controlador confirmar o enquadramento do art. 5º, XVIII (F-11): participantes do estudo de impacto; execução de contrato/procedimentos preliminares: admins. **Em revisão (T7-R).**`
  - Artigos: acrescente `art. 5º, XVIII; art. 7º, IV; art. 11, II, c` e troque `(se o estudo piloto registrar dados de saúde)` por `(se o estudo de impacto registrar dados de saúde)`.
  - Critério de aceitação:
    `existe, revisado juridicamente, o consentimento LGPD do estudo de impacto **ou**, se a base for o art. 7º, IV, o termo de informação ao participante, em seção distinta do TCLE; existe o TCLE aprovado pelo CEP; nenhum dado do estudo é coletado antes dos dois; o fluxo de primeiro login do CMS bloqueia o acesso até o aceite.`

- [ ] **Passo 2b: LGPD-RF13 (linha 113, fim da descrição).** Troque `O estudo piloto, se registrar queixas de saúde de participantes identificáveis, opera sob consentimento específico e destacado (RF02).` por `O estudo de impacto, se registrar queixas de saúde de participantes identificáveis, o faz fora do app, sob a base LGPD do RF02 (consentimento específico e destacado, ou a hipótese do art. 11, II, c, se confirmada com o controlador) e o protocolo aprovado pelo CEP, distinto do TCLE ([ADR-010](stack.md#10-registro-de-decisões-arquiteturais-adr)). A regra do aparelho não muda.`

- [ ] **Passo 3: RF04, RF05, RF07, DOC03 e direitos.**
  - Troque "estudo piloto" por "estudo de impacto" nas linhas 49, 56, 60, 71(b), 164, 238, 247 e 249.
  - **RF04 (linha 49):** acrescente `No estudo de impacto, vale para o consentimento LGPD quando for a base; sob o art. 7º, IV, registra-se a entrega do termo de informação.`
  - **RF05 (linha 56):** depois de "descarta os dados do participante", acrescente ` A retirada do TCLE e a revogação do consentimento LGPD têm o mesmo efeito prático, mas são registradas separadamente.`
  - **Linha 164:** `Obrigatório no estudo de impacto quando a base for o consentimento (RF02), separado do TCLE, e no primeiro login do CMS.`
  - **Linha 249:** `Os termos do estudo de impacto explicitam que a recusa não impede o uso do app, que é o mesmo publicado para todos.`

- [ ] **Passo 4: matriz e RIPD.**
  - **Linha 289:** troque `Consentimento no estudo piloto e no CMS` por `Base legal do estudo de impacto (distinta do TCLE) e consentimento no CMS`, e `multimodal no estudo piloto` por `multimodal no estudo de impacto`.
  - **Linha 314:** `**RIPD/Relatório de Impacto** (art. 38) elaborado antes do estudo de impacto (ADR-010, DC-A) e revisado a cada feature que toque dados (o modo ACS da v2 exigirá um novo). No lançamento, a superfície de dados é o [`docs/dados-do-usuario.md`](../docs/dados-do-usuario.md), a confirmar com o encarregado (F-11).`

- [ ] **Passo 5: confira.**
  - `python3 -I piloto.py spec/lgpd.md` deve sair com 0.
  - `grep -n TCLE spec/lgpd.md | grep -vE 'distint|Não é o TCLE|separad|nunca .*mesma cláusula'` não deve devolver nada.

- [ ] **Passo 6: commit.** `git commit -am "docs(lgpd): estudo de impacto; base legal do estudo separada do TCLE"`

---

### Task 4: `docs/dados-do-usuario.md` — o estudo tem canal próprio, fora do app

**Files:**
- Modify: `docs/dados-do-usuario.md`: §5 nova e uma frase na §4.

- [ ] **Passo 1: acrescente ao fim:**

```markdown
## 5. Estudo de impacto: canal próprio, fora do app

O estudo de impacto ([ADR-010](../spec/stack.md#10-registro-de-decisões-arquiteturais-adr)) coleta os dados do estudo (observações de uso, respostas a entrevistas) por um canal próprio, definido no protocolo aprovado pelo CEP, como um formulário ou um caderno de campo. **Nunca pelo app.**

- O app é o mesmo para quem participa do estudo e para o público: não há versão do estudo, nem identificador, nem telemetria. Tudo o que as §§1 a 3 listam vale também para quem participa.
- Os dados do estudo seguem a [LGPD-RF02, RF04 e RF05](../spec/lgpd.md), a Lei 14.874/2024 e o protocolo do CEP. O TCLE e a base LGPD (consentimento ou termo de informação) ficam em documentos ou seções distintos (ADR-010, Decisão 6).
- Os dados agregados da loja (instalações, versões ativas) podem ser insumo do estudo. Eles vêm do console da Play, não do app.
- Telemetria no app seria uma decisão separada, com ADR próprio e revisão da INV-2 (ADR-010, Decisão 5). Se ela vier, este levantamento precisa ser refeito.
```

- [ ] **Passo 2: na §4, ao fim do item "Google Play":** ` Os agregados do console podem ser insumo do estudo de impacto (§5).`

- [ ] **Passo 3: confira.** `grep -c 'dados do estudo (observações de uso, respostas a entrevistas)' spec/lgpd.md docs/dados-do-usuario.md` deve dar pelo menos 1 em cada arquivo.

- [ ] **Passo 4: commit.** `git commit -am "docs(dados): o estudo de impacto coleta por canal proprio, fora do app"`

---

### Task 5: roadmap e portões — brainstorm, aprovações, implantação, notas e registros

**Files:**
- Modify: `spec/brainstorm.md`: M1 e M2 (118-128), M6 (154-161), M7 (163-168), M8 novo e métricas (192-198).
- Create: `docs/aprovacoes.md`. Rewrite: `docs/aprovacoes-piloto.md`, que vira redirecionamento.
- Modify: `spec/implantacao.md` (56, 59, 108, 170 e §2.7), `.github/workflows/app-release.yml:233`, `CHANGELOG.md:15`, `spec/arquitetura.md:316,741`, `docs/operacao.md:1087`, `PROGRESS.md:8,10` e o registro da T0 em `docs/superpowers/plans/2026-11-02-realinhamento-institucional-implantacao.md`.

- [ ] **Passo 1: M1 e M2.**
  - [C2]
    - M1, critério de saída: `fluxos navegáveis em papel/Figma conferidos por 3 a 5 pessoas da equipe, bolsistas ou alunos, como QA, e revisados em linguagem simples por profissionais do PET-Saúde que atendem o público-alvo (ADR-010, Decisão 3f). O teste com o público-alvo, incluindo baixo letramento, é do estudo de impacto (M8).`
    - M2: mantenha a pergunta. Critério: `≥ 80% das tarefas-chave concluídas sem ajuda no QA interno; textos e roteiros de áudio dentro do limiar de legibilidade; TTS pt e es ouvido no aparelho. É sinal para iterar, não evidência de H1 (PRD §1.3.2).`
  - [C1]
    - M1, critério de saída: `fluxos conferidos em QA interno. Depois da manifestação escrita do CEP/UFRR (F-20 d), validados com 3 a 5 pessoas indicadas pelo PET-Saúde como representativas do público-alvo, cabendo a caracterização a quem indica, como validação de produto: a pessoa é informada oralmente de que é teste do produto, voluntário e sem registro, sem assinar nada; sem hipótese, sem registro identificável, sem roteiro de entrevista; resultado descartado depois da iteração (ADR-010, 3f).`
    - M2: mantenha a pergunta. Critério: `≥ 80% das tarefas-chave concluídas sem ajuda, no QA interno e, se ativada, na validação de produto. É sinal para iterar, não evidência de H1 (PRD §1.3.2).`
  - [C1+C2]
    - M1, critério de saída: `fluxos navegáveis em papel/Figma conferidos por 3 a 5 pessoas da equipe, bolsistas ou alunos, como QA, e revisados em linguagem simples por profissionais do PET-Saúde que atendem o público-alvo. Se, e somente se, o CEP/UFRR se manifestar por escrito de que o desenho não é pesquisa (F-20 d), também com 3 a 5 pessoas indicadas pelo PET-Saúde como representativas do público-alvo, como validação de produto: informação oral de que é teste do produto, voluntário e sem registro, sem assinatura; sem hipótese, registro identificável ou roteiro de entrevista; resultado descartado depois da iteração (ADR-010, 3f). Sem a manifestação, o teste com o público-alvo fica no M8.`
    - M2: mantenha a pergunta. Critério: `≥ 80% das tarefas-chave concluídas sem ajuda no QA interno e, se ativada, na validação de produto; textos e roteiros de áudio dentro do limiar de legibilidade; TTS pt e es ouvido no aparelho. É sinal para iterar, não evidência de H1 (PRD §1.3.2).`

- [ ] **Passo 2: M6 vira o portão de lançamento.**

```markdown
### M6 — Portão de Lançamento (Semanas 19–21)

Parte A do [ADR-010](stack.md): a publicação do app. É produto, não pesquisa: não coleta dados de usuários, não mede hipótese e não observa nem entrevista pessoas externas para fins de pesquisa. Não passa por unidade de saúde ([ADR-005](stack.md), Decisão 7) e não depende do CEP.

- **Dogfooding interno e QA:** equipe, bolsistas e alunos, sem dado identificável e sem uso posterior em publicação. O canal é a *pre-release* do GitHub ou a faixa de teste da Play; o teste fechado que a Play exige também é QA (ADR-010, DC-D).
- **Portão (ADR-010, Decisão 3):**
  - conteúdo validado, com registro de revisão;
  - aviso de que o app não substitui atendimento, e encaminhamento dos sinais de alarme para SAMU 192, UPA ou UBS;
  - responsável institucional (F-11);
  - política e termos publicados, com as políticas da Play para apps de saúde conferidas;
  - correção de conteúdo em ≤ 7 dias (RNF-12);
  - a mitigação do R2 da Decisão 3f.
- **Critério de promoção para produção:** nenhuma orientação clinicamente incorreta na revisão clínica, mais a aprovação da coordenação clínica do projeto.
- **Em paralelo:** a consulta prévia ao CEP (F-20) e o protocolo do estudo de impacto (M8).
```

- [ ] **Passo 3: M7 e M8.**
  - No M7, troque `Monitoramento pós-lançamento por telemetria anônima e agregada (enviada apenas nas janelas de sync).` por `Sem telemetria: o app não envia nada (INV-2), e uma telemetria exigiria ADR próprio ([ADR-010](stack.md), Decisão 5). O acompanhamento pós-lançamento usa os agregados da loja e os relatos de correção (RNF-12).`
  - No M7, acrescente o item `**Registro do software** como produção técnica (opcional: INPI; titularidade F-21).`
  - Depois do M7, acrescente:

```markdown
### M8 — Estudo de Impacto (coleta depois da 1ª versão em produção)

Parte B do [ADR-010](stack.md): pesquisa com seres humanos sobre o app já publicado, com voluntários da comunidade, fora de unidades de saúde. A tramitação começa em paralelo com o M6.

- **Instituição proponente:** a hipótese de trabalho é a UFRR, com o docente responsável como pesquisador. Ela é confirmada na consulta prévia (F-20 b; ADR-010, Decisão 4).
- **Antes do 1º participante:**
  - TCLE e parecer do CEP/UFRR (Plataforma Brasil);
  - base LGPD dos dados do estudo, distinta do TCLE ([lgpd.md](lgpd.md), RF02);
  - RIPD (ADR-010, DC-A);
  - controlador (F-11);
  - meta de alcance (F-14).
- **Hipóteses:** H1, H1b e H4 ([PRD](PRD.md) §1.3.2).
- **Método:** observação de uso e entrevistas, por canal próprio, fora do app ([`docs/dados-do-usuario.md`](../docs/dados-do-usuario.md) §5). Os agregados da loja são insumo.
- **Fronteira:** nada observado no lançamento vira resultado. TCC e relatório do PET-Saúde com dados de participantes só existem aqui (ADR-010, Decisão 5).
```

- [ ] **Passo 4: métricas (linhas 192-198).** Divida em duas listas:
  - **Lançamento:**
    - `100% dos casos com sinais de alarme direcionados corretamente à emergência (camada de regras)`;
    - `correção de conteúdo publicada em ≤ 7 dias (RNF-12, antiga H2)`.
  - **Estudo de impacto:**
    - a métrica-norte, com "fim do estudo de impacto";
    - `≥ 80% dos participantes do estudo de impacto completam uma triagem sem ajuda humana`;
    - `redução autodeclarada de deslocamentos inúteis entre os participantes do estudo de impacto`.
  - Apague a linha `≥ 90% dos dispositivos…`, que virou o RNF-12.

- [ ] **Passo 5: quadro de aprovações.**
  - Crie `docs/aprovacoes.md` com:
    - título `# Aprovações do lançamento e do estudo de impacto` e a nota de data (2026-11-09, ADR-010);
    - **"Parte A — Lançamento"**: tabela `Exigência | Base | Estado`, com dogfooding/QA, as sete condições da Decisão 3 (a a g) e o teste fechado da Play (DC-D);
    - **"Parte B — Estudo de impacto"**: instituição proponente, TCLE e parecer do CEP, base LGPD (consentimento ou termo de informação), RIPD, F-11, F-14 e a consulta prévia (F-20);
    - a seção **Anvisa**, igual à atual;
    - **o que o PET-Saúde pode reportar** de cada parte (ADR-010, Decisão 5);
    - **caminhos críticos**:
      - lançamento: **F-11 → parecer jurídico (T7-R) → revisão clínica (#2) → #47 e #48 → promoção**;
      - estudo: **consulta prévia ao CEP (F-20) → instituição proponente → protocolo na Plataforma Brasil → TCLE e base LGPD → RIPD → 1º participante**.
  - Substitua todo o conteúdo de `docs/aprovacoes-piloto.md` por uma linha só: `Este quadro passou para [`aprovacoes.md`](aprovacoes.md) em 2026-11-09 ([ADR-010](../spec/stack.md#10-registro-de-decisões-arquiteturais-adr)).` O redirecionamento existe porque o corpo da PR #78 aponta para o nome antigo; nenhuma issue aponta (busca de 2026-11-09).

- [ ] **Passo 6: implantação e nota de release.**
  - `implantacao.md:56`: `onde roda o estudo piloto` → `onde rodam o dogfooding e o QA do lançamento ([ADR-010](stack.md#10-registro-de-decisões-arquiteturais-adr))`.
  - Linhas 59 e 108: `o estudo piloto roda` → `o dogfooding roda`.
  - Linha 170: `que a versão está em teste no estudo piloto do projeto` → `que a versão está em teste, ainda não promovida para produção`.
  - §2.7:
    - acrescente `- [ ] **Teste fechado da conta pessoal:** número mínimo de testadores e de dias exigido pela Play antes da produção (conferir no Play Console em ____-__-__). Os testadores são QA do lançamento (ADR-010, DC-D), sem coleta.`;
    - ao fim do item da declaração de app de saúde, acrescente ` Conferir também a política de conteúdo e serviços de saúde da Play.`
  - `app-release.yml:233`: `> **Versão em teste no estudo piloto do projeto.**` → `> **Versão em teste, ainda não promovida para produção.**`, igual à linha 170.
  - `CHANGELOG.md:15`: `Primeira versão para **teste interno** (dogfooding), antes do lançamento ([ADR-010](spec/stack.md)).`

- [ ] **Passo 7: arquitetura, operação, PROGRESS e registro da T0.**
  - `arquitetura.md:316`: `(valida R1, H2, H3 — PRD §6.2)` → `(valida R1, H3 e o sync em rede instável — RNF-12, antiga H2; PRD §6.2)`.
  - `arquitetura.md:741`: `revisão clínica do estudo piloto do projeto` → `revisão clínica do portão de lançamento`.
  - `operacao.md:1087`:
    - título `**Termos de uso mudaram antes do lançamento**`;
    - no texto, troque `o termo de consentimento do estudo piloto do projeto (LGPD-RF02) não está no repositório: a mudança precisa ser lida em voz alta aos participantes já inscritos, no idioma de cada um` por `o app reabre o "li e concordo" a cada versão nova dos termos (\`app/lib/ui/router_provider.dart\`, comentário da linha 59), então quem fez o dogfooding com a versão anterior responde de novo; os documentos do estudo de impacto (TCLE e base LGPD, LGPD-RF02) não estão no repositório e seguem o protocolo do CEP`.
    - Esse comportamento já existe e foi conferido em 2026-11-09. O plano não muda o app.
  - `PROGRESS.md:8`: `antes do **estudo piloto do projeto** (…)` → `antes do **lançamento** ([ADR-010](spec/stack.md))`. Acrescente: `O marco no GitHub ainda tem o nome "Piloto", de antes de 2026-11-09; renomeá-lo é ação externa.` Na linha 10: `pós-piloto` → `pós-lançamento`.
  - No registro da T0:
    - F-9 → `respondida pelo ADR-010 (2026-11-09): o lançamento não coleta; o estudo de impacto coleta, com TCLE e parecer do CEP antes do 1º participante`;
    - na F-14, troque "estudo piloto" por "estudo de impacto";
    - acrescente `| F-20 | M | Consulta prévia ao CEP/UFRR: (a) desenho em duas partes; (b) UFRR como proponente de estudo de docente da casa (hipótese de trabalho); (c) como o CEP aplica a Res. 510/2016 depois da Lei 14.874/2024; (d) se C1 ou C1+C2, se a validação de produto é pesquisa | Antes do protocolo do estudo de impacto |`;
    - acrescente `| F-21 | I | Titularidade do registro do software (UFRR/NIT ou autores), ligada à F-11 e à F-20 | Antes do registro no INPI |`.

- [ ] **Passo 8: confira.**
  - `python3 -I piloto.py spec/brainstorm.md spec/implantacao.md spec/arquitetura.md docs/operacao.md docs/aprovacoes.md docs/aprovacoes-piloto.md CHANGELOG.md PROGRESS.md .github/workflows/app-release.yml` deve sair com 0.
  - `python3 -I -c "import yaml;yaml.safe_load(open('.github/workflows/app-release.yml'))"` deve terminar sem erro.
  - `grep -nF -e '[C1]' -e '[C2]' -e '[C1+C2]' spec/brainstorm.md` não deve devolver nada.

- [ ] **Passo 9: commit.** `git commit -am "docs(roadmap): portao de lancamento (M6) e estudo de impacto (M8); aprovacoes por parte"`. Antes, rode `git add docs/aprovacoes.md`.

---

### Task 6: `CLAUDE.md`, README e política publicada

**Files:**
- Modify: `CLAUDE.md:19`.
- Verificar sem alterar: `README.md`, `app/assets/legal/{termos,privacidade}_{pt,es}.md` e a fonte do Pages.

- [ ] **Passo 1: `CLAUDE.md:19`.** Troque o item por:
  `- **Lançamento e estudo de impacto são etapas separadas** ([ADR-010](spec/stack.md)). O lançamento publica o app: é produto, sem coleta, sem hipótese e sem CEP, e teste com equipe, bolsistas e alunos é QA. O estudo de impacto é pesquisa com seres humanos sobre o app publicado, com TCLE e parecer do CEP antes do 1º participante (Lei 14.874/2024), e coleta fora do app. Nada observado no lançamento vira resultado do estudo. "Piloto", nome de antes de 2026-11-09, não nomeia mais etapa. TCLE e base LGPD nunca na mesma cláusula.`

- [ ] **Passo 2: README.** `grep -n -i 'piloto\|estudo\|TCLE' README.md`. As linhas 284 e 308 são do CMS e ficam. Qualquer outra ocorrência de "piloto" é corrigida com o mesmo vocabulário.

- [ ] **Passo 3: política publicada.**
  - `grep -l -i 'piloto\|estudo\|TCLE\|CEP' app/assets/legal/termos_*.md app/assets/legal/privacidade_*.md` não deve devolver nada.
  - Confirme que o Pages lê desse diretório: `grep -n 'assets/legal' .github/workflows/pages.yml` deve mostrar o gatilho de `paths` e o comentário de que o site sai dos mesmos arquivos do app.
  - Se as duas conferências passarem, não há edição nem bump, e o site continua correto. Se aparecer algo, **pare**: a edição exige o bump triplo e reabre o "li e concordo".

- [ ] **Passo 4: commit.** `git commit -am "docs(claude): lancamento e estudo de impacto separados"`

---

### Task 7: revisão de consistência cruzada (PRD × lgpd.md × dados-do-usuario.md × ADR-010)

- [ ] **Passo 1: "piloto" órfão.** A lista de arquivos vem do git, para pegar também os `.md` criados depois do inventário:
  - `python3 -I piloto.py --stack $(git ls-files 'spec/*.md' 'docs/*.md' ':!docs/superpowers/*' CLAUDE.md README.md PROGRESS.md CHANGELOG.md .github/workflows/app-release.yml)` deve sair com 0.
  - Rode depois de `git add` dos arquivos novos (`docs/aprovacoes.md`), senão o `ls-files` não os vê. O `*` do pathspec do git é recursivo, então `docs/*.md` já pega subpastas novas, como `docs/deploy/`.
  - Fica de fora só o `docs/superpowers/` (regra c).

- [ ] **Passo 2: TCLE × base LGPD.**
  - `grep -rn 'TCLE' spec docs/dados-do-usuario.md docs/aprovacoes.md CLAUDE.md | grep -i 'consentimento\|base LGPD' | grep -vE 'distint|Não é o TCLE|separad|nunca .*mesma cláusula'` não deve devolver nada.

- [ ] **Passo 3: o app não coleta para o estudo.**
  - `grep -rn -i 'telemetria' spec/PRD.md spec/brainstorm.md docs/dados-do-usuario.md`: nenhuma linha nova pode dizer que a telemetria é enviada ou que mede hipótese. Toda menção nova cita a Decisão 5 do ADR-010.
  - `git diff origin/develop -- spec/espec.md` só pode mostrar a RNF-12, as duas listas de rastreabilidade (linhas 3 e 538) e o fim da célula da RF-15.

- [ ] **Passo 4: rastreabilidade das hipóteses.**
  - H1, H1b e H4 aparecem no PRD §1.3.2, no M8 e no ADR-010, Decisão 4.
  - Toda ocorrência de `\bH2\b` em `spec/`, fora do corpo dos ADRs aceitos, traz "antiga" ou "RNF-12".
  - O RNF-12 aparece no `espec.md`, no PRD (§1.3.3, CAP-10 e §6.4), no ADR-010 (3e) e no brainstorm (métricas).

- [ ] **Passo 5: links.** Rode o script abaixo neste branch e no `origin/develop`. Só valem os defeitos **novos**.

```python
# links.py — python3 -I links.py spec docs CLAUDE.md README.md PROGRESS.md CHANGELOG.md
import re, sys, pathlib
bad = 0
for r in sys.argv[1:]:
    p = pathlib.Path(r)
    for f in ([p] if p.is_file() else p.rglob('*.md')):
        for m in re.finditer(r'\]\(([^)#\s]+)(#[^)]*)?\)', f.read_text()):
            t = m.group(1)
            if t.startswith(('http', 'mailto')): continue
            if not (f.parent / t).exists():
                print(f"{f}: {t}"); bad += 1
sys.exit(1 if bad else 0)
```

- [ ] **Passo 6: números e marcadores.**
  - `grep -rnoE 'ADR-010, (Decisão [0-9][a-g]?|DC-[A-E])' spec docs CLAUDE.md`: toda Decisão está entre 1 e 7, toda letra está entre a e g e só aparece na Decisão 3, e todo DC está entre A e E.
  - `grep -rnF -e '[C1]' -e '[C2]' -e '[C1+C2]' -e '[[DC-C-PENDENTE]]' -e '[Q-' spec docs/aprovacoes.md docs/dados-do-usuario.md CLAUDE.md` não deve devolver nada.

- [ ] **Passo 7: nada fora do escopo.**
  - `git diff --stat origin/develop -- app/` deve sair vazio.
  - `git diff --stat origin/develop` só pode listar `spec/`, `docs/`, `CLAUDE.md`, `PROGRESS.md`, `CHANGELOG.md` e `.github/workflows/app-release.yml`.
  - `npm --workspace @guia-ubs/cms test` deve passar.

- [ ] **Passo 8: PR.** Commit as correções, se houver: `git commit -am "docs: consistencia cruzada do ADR-010"`. Depois, faça o push e abra **uma** PR para o `develop` **como rascunho** (`gh pr create --draft`). A descrição deve:
  - apontar para as Decisões complementares do ADR-010;
  - dizer que nenhum arquivo de `app/` mudou;
  - listar o estado da Task 8.

  A PR só sai de rascunho depois do item 1 da Task 8.

---

### Task 8: ações fora do repositório

Nenhuma destas ações gera commit. Elas são da coordenação e ficam registradas aqui para não se perderem. O item 1 é condição da PR; os outros correm em paralelo.

- [ ] **1. Alinhamento com a coordenação do PET-Saúde/Telessaúde, antes de a PR sair de rascunho.** O PET-Saúde presta contas ao Ministério da Saúde e tem cronograma próprio de relatório. A regra de fronteira (ADR-010, Decisão 5) afeta esses prazos diretamente.
  - Da Parte A, o PET pode reportar o produto, o alcance agregado da loja e o relato de experiência, mas nenhum dado de pessoa.
  - Resultados com participantes só saem depois do parecer do CEP, na Parte B.
  - Confirme a hipótese de trabalho da Decisão 4: a Parte B submetida pelo docente responsável, com a UFRR como proponente.
  - Registre a data e o resultado na descrição da PR e no `docs/aprovacoes.md`.
  - **Se a resposta for negativa** (o PET recusa a regra de fronteira ou a própria separação), a PR não sai de rascunho. O caso volta à coordenação, e o ADR-010 é reaberto pelo gatilho correspondente da sua Revisão. Ressalva sobre o cronograma da Parte B não reabre o ADR: ajusta-se o calendário do estudo em `docs/aprovacoes.md`.
- [ ] **2. Consulta prévia informal ao CEP/UFRR (F-20).** Leve o ADR-010 e o `docs/dados-do-usuario.md` e pergunte:
  - (a) se o desenho em duas partes se sustenta, com o lançamento sem protocolo;
  - (b) a hipótese de trabalho: o CEP/UFRR recebe o protocolo do docente responsável com a UFRR como proponente, mesmo que a cooperação PRISM–UFRR ainda não esteja formalizada;
  - (c) como o CEP aplica hoje a Res. 510/2016, art. 1º, parágrafo único, diante da Lei 14.874/2024 (art. 6º; regulamento do art. 63, parágrafo único, pendente). É uma pergunta aberta: o ADR-010 não presume a resposta;
  - (d) se a Q-C for C1 ou C1+C2: se a validação de produto com pessoas indicadas pelo PET-Saúde, com informação oral, sem registro e sem hipótese, é pesquisa. Peça a resposta por escrito.

  Se o CEP entender que o lançamento precisa de protocolo, reabra o ADR-010.
- [ ] **3. Protocolo na Plataforma Brasil**, em paralelo com o lançamento: projeto, TCLE, instrumentos (roteiros de observação e de entrevista) e a base LGPD em seção distinta. Depende do item 2(b) e da F-11.
- [ ] **4. Renomear o marco "Piloto" no GitHub** para "Lançamento". É ação externa, com confirmação do mantenedor. Depois, tire a frase correspondente do `PROGRESS.md`.
- [ ] **5. Registro do software:** consultar o NIT da UFRR sobre a titularidade (F-21, junto com a F-11 e a F-20) e, se for o caso, registrar no INPI. A produção técnica entra no Lattes dos autores.
