# Realinhamento institucional e diretrizes de implantação — Plano

> **Para agentes executores:** SUB-SKILL OBRIGATÓRIA: superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar tarefa por tarefa. Passos em checkbox (`- [ ]`). **Quem recebe uma única tarefa lê** este resumo, a "Exceção de código", as "Restrições globais" e as seções da linha **Leia:** da tarefa, e mais nada.

## Resumo executivo

- **O que muda:** a spec, as diretrizes e os textos ao usuário passam a refletir um projeto educativo aberto do PRISM/UFRR com o PET-Saúde, sem vínculo com unidades de saúde. A orientação de onde buscar atendimento fica como apoio secundário.
- **O que entra:**
  - os ADR-005 a 009 e a revisão do ADR-004 e do ADR-001;
  - RF-16/17 e RNF-10/11;
  - `spec/implantacao.md`, com a release do APK no GitHub Releases e no Google Play e o CMS na VPS do PRISM.
- **O que não muda:** INV-1…8, FSM-A/B, dual review, Ed25519, zero PII.
- **Estágios (um PR cada):**
  - **E1:** ADR-005;
  - **E2:** PRD + espec + stack + lgpd (neutralização);
  - **E3:** implantação + roadmap;
  - **E4:** revisão jurídica e bases legais;
  - **E5:** textos do app sem parecer;
  - **E6:** README e registro histórico;
  - **E7:** textos do app com parecer.
- **Única pergunta que bloqueia o início:** a **F-0** (nome do app; material na §F.1).
- **Gargalo real do estudo piloto:** a revisão clínica golden (§J.1). O estudo com participantes externos exige E7 e o RIPD (§J.2).
- **Código:** só a T8a e a T8b, em arquivos listados.

**Objetivo:** alinhar especificação, diretrizes e textos ao usuário do Guia UBS ao novo contexto, para que seja possível executar e testar o piloto. O contexto novo:
- projeto do PRISM/UFRR em cooperação com o PET-Saúde (Núcleo de Telessaúde UFRR);
- educação social em saúde como foco primário;
- código aberto;
- sem vínculo com unidades de saúde;
- APK distribuído por GitHub Releases e Google Play;
- CMS numa VPS mantida pelo PRISM.

**Arquitetura da mudança:** o plano é **documental**, com **uma exceção declarada**: as Tarefas 8a e 8b (ver "Exceção de código" abaixo). As decisões entram como ADR em `spec/stack.md` §10. As diretrizes de implantação viram um documento normativo novo, `spec/implantacao.md`, porque `docs/` descreve o que existe, e o pipeline de release e o provisionamento da VPS ainda não existem. A implementação desses itens (pipeline, playbook, backup) fica em itens de roadmap com plano próprio; este plano só os especifica.

**Stack tocada:** Markdown (`spec/`, `docs/`, raiz). Na T8a e na T8b, também ARB, `app/assets/legal/` e os testes Dart que conferem esses textos.

**Fonte:** pedido do mantenedor (2026-11-02) e revisão do plano no mesmo dia. **Base do levantamento:** `develop` em `2ab9f93`.

## Exceção de código (declarada)

A restrição "não alterar código" vale para todas as tarefas **menos a T8a e a T8b**. As duas alteram:
- `app/lib/l10n/app_{pt,es}.arb`;
- `app/assets/legal/{termos,privacidade}_{pt,es}.md`;
- uma string e a exibição de uma chave ARB em `app/lib/ui/more/about_screen.dart`;
- os testes listados nelas.

A exceção existe porque o pedido inclui textos ao usuário, que vivem no app, e porque esses textos são conferidos por teste. Mudar o texto sem mudar o teste deixaria o CI vermelho. **Fora desses arquivos, nada de código.**

Cada uma tem PR próprio: a T8a no estágio E5 e a T8b no E7. Um executor que só possa mexer em documentos pula as duas e entrega o resto.

## Restrições globais

- **Ponto de partida.** A execução parte de `2ab9f93`. Se `develop` tiver avançado, a T0 refaz a conferência dos trechos citados na §A antes da T1, porque números de linha mudam.
- **Precedência documental:** `PRD > espec > stack > lgpd > brainstorm`.
- **Regra de propagação (CLAUDE.md) e commits.** A consistência entre PRD, espec, stack e lgpd é exigida em **cada PR mergeado em `develop`**, não em cada commit da branch de trabalho. Commits intermediários podem estar inconsistentes entre si. Por isso o estágio E2 junta T2, T3, T4 e T7a num PR só.
- **`spec/` é normativo e `docs/` é derivado do código.** Nenhum procedimento para código que ainda não existe entra em `docs/`.
- **Idioma.** Documentos novos em pt-BR. Texto ao usuário em pt **e** es.
- **Decisão jurídica ou de política de terceiros nunca sai deste plano como decisão.**
  - Bases legais da LGPD, o enquadramento regulatório (RDC 657/2022) e as regras do Google Play são **propostas**.
  - Base legal só vira texto normativo depois da revisão jurídica (T7-R).
  - Toda regra da Play citada aqui é conferida no Play Console **na data da publicação**. Os documentos registram essa data.
- **Preservar sem mudar o mérito:**
  - INV-1…INV-8, FSM-A e FSM-B;
  - as duas chamadas de rede e a degradação em escada;
  - dual review, assinatura Ed25519 e chave fora do processo HTTP;
  - gate e `RuleOnlyEngine` lendo a mesma tabela;
  - zero PII e k ≥ 20;
  - as regras R1–R3 do ADR-004.
- **Categorias de serviço do SUS ficam.** `venue` UBS/UPA/HOSPITAL e `ROUTINE_UBS` são conteúdo educativo, não unidades parceiras. Palavras como "UBS", "posto" e "horário" são **legítimas** no conteúdo educativo. O que se proíbe é **atribuir** regra, decisão ou configuração a uma unidade.
- **Registro histórico** (as §5.x de `arquitetura.md` e os planos antigos) não é reescrito. Ganha uma nota de supersessão.
- **Commits:** sem atribuição de IA.
- **Perguntas abertas** seguem a classificação da §F. A tarefa que depende de uma pergunta do tipo **B** fica bloqueada até a resposta.
- **Repositório público.** As respostas operacionais (F-1, F-2, F-4, F-8) ficam num **registro de decisões fora do repositório**, no cofre do grupo; o plano e os ADRs registram só "respondida em <data>". As respostas que viram conteúdo de ADR (nome, `applicationId`, versionamento, canais, ABIs) são públicas por natureza. O país do provedor da VPS só entra no texto público se a revisão jurídica (T7-R) exigir isso para a política de privacidade.

## Foco de revisão

1. **Nome do app.** "Guia UBS" pode ser lido como canal oficial. A política de *Misrepresentation* da Play reprova isso, e o `applicationId` é permanente depois da 1ª publicação. Nenhum id pode ser fixado antes de o nome estar decidido (F-0).
2. **"Piloto" sem dono volta a significar "piloto em UBS".** Toda ocorrência precisa passar a "estudo piloto do projeto (PRISM/PET-Saúde)".
3. **Proibição ampla demais, ou estreita demais.** Um teste ou grep que barre a palavra "posto" ou "horário" barra justamente o conteúdo educativo primário ("procure o posto de saúde mais próximo"). Um que esqueça "da" deixa passar "regras da UBS". Os padrões são **frásicos**, só pegam atribuição de regra, decisão ou configuração, e são conferidos contra um corpus de frases permitidas e proibidas (T8a).
4. **Teste que impede dizer a verdade.** `no_endorsement_test.dart` reprova toda menção à UFRR. Afrouxá-lo demais faz sumir a guarda contra endosso do Google.
5. **Versão dos termos sem bump**, ou **chave de assinatura diferente entre canais sem aviso**. No primeiro caso, quem já aceitou não vê a mudança. No segundo, quem troca de canal perde os ajustes sem ter sido avisado.

---

## A. Conflitos identificados (em `2ab9f93`)

### A.1 Graves: bloqueiam o piloto ou a publicação

| # | Onde | O que diz hoje | Por que conflita |
|---|---|---|---|
| C0 | Nome "Guia UBS" (`appTitle`), `brainstorm.md:5-8` ("Sua UBS na palma da mão", alternativa "SUS Fácil") | O nome e a tagline sugerem canal oficial de UBS ou do SUS | Sem vínculo com unidade; política de *Misrepresentation* da Play |
| C1 | `spec/lgpd.md:147-151`; `docs/revisao-golden.md:3,7,11,35,64`; issues P0-2, P1-9, P1-10, P2-8; `_epica.md:57` | A **Secretaria Municipal de Saúde é a controladora**, indica os revisores e arquiva os termos; base legal art. 7º, III | Não há vínculo com secretaria |
| C2 | `spec/stack.md:398,433-435` (ADR-004); `app/test/ui/more/no_endorsement_test.dart:85-90` | "não há vínculo formal com a UFRR"; o teste reprova "UFRR" em todo ARB e documento legal | Há cooperação com o PET-Saúde (Núcleo de Telessaúde UFRR) |
| C3 | `spec/stack.md:464` (gatilhos do ADR-004) | "publicar o app em loja" reabre o ADR com parecer jurídico e entidade responsável | A distribuição pela Play está decidida, então o gatilho dispara |
| C4 | `brainstorm.md:151-153` (M6); `PRD.md:31,301` (H4, Fase 2); `PROGRESS.md:8`; marco "Piloto" do GitHub | "Piloto em 2 UBS", "aprovação formal dos gestores das unidades piloto", "≥ 20 usuários/UBS" | O piloto depende de unidade de saúde |
| C5 | `espec.md:34` (RF-15); `design_selo_procedencia.html:147,163,216`; `app_pt.arb:211,219`; `app_es.arb:127,129`; CLAUDE.md | Selo "**regras do posto**" / "reglas del puesto" | Atribui regras clínicas a um posto |
| C6 | `app/android/app/build.gradle.kts:8,22` | `applicationId = "br.gov.exemplo.guia_ubs"` | `gov` sugere órgão público; o id é permanente na Play |
| C7 | `build.gradle.kts:70-73`; `.github/workflows/`; nenhuma tag git | Release assinado com a chave **debug**; sem job de release, AAB, tag ou changelog do app | Os dois canais decididos ficam sem pipeline |
| C8 | `PRD.md:12,14`; `espec.md:11-12`; `brainstorm.md:12,26-28,164,170`; `termos_{pt,es}.md:8-10`; `termsGateBody` (`app_pt.arb:191`) | A triagem é o "coração do produto" | Educação é o primário e o apoio à saúde é secundário |

### A.2 Estruturais: pressupõem curadoria municipal ou instalação feita por unidade

| # | Onde | Trecho |
|---|---|---|
| C9 | `espec.md:56` (A2); `stack.md:102`; `lgpd.md:4,51,118,184,193` | "Admin de conteúdo municipal", "dezenas de admins municipais", "suporte a municípios" |
| C10 | `PRD.md:22` (JTBD-3); `brainstorm.md:34,60,64,66,75,159,181` | Gestor municipal como ator; "remédio disponível"; "farmácia da UBS" (estoque); "como marcar o dentista"; "campanhas, horários" como dado mantido por unidade; "dados locais curados por município" |
| C11 | `arquitetura.md:193,222,246-287,1338`; `espec.md:44,488,498`; `pack_manifest.dart:66`; `defines.example.json:3`; `operacao.md:398,583-587,732` | Pack, coorte e release **por município**; "QR na UBS" |
| C12 | `stack.md:112,129,141`; `PRD.md:315` (R8); `brainstorm.md:92` | Espelhos e canal "por prefeitura"; "máquina de secretaria municipal" |
| C13 | `espec.md:455` (INV-8); `app_pt.arb:88,118`; `app_es.arb:59,83`; `privacidade_{pt,es}.md:26`; `about_screen.dart:377` | "posto sem rede"; "override pelo administrador"; "se o posto liberou dados móveis"; "se o posto não tem Wi-Fi"; "aparelhos do piloto" |

### A.3 Infraestrutura e distribuição

| # | Onde | Trecho |
|---|---|---|
| C14 | `PRD.md:302`; `stack.md:295`; `brainstorm.md:157`; `arquitetura.md:1319` | Canais: Play + **F-Droid** + sideload Bluetooth/SD, sem GitHub Releases |
| C15 | `stack.md:297,494-496`; `espec.md:59,476`; `lgpd.md:15,61,190`; `brainstorm.md:109` | VPS sem dono; "provedor contratado" como operador; Firebase/S3/GitHub Pages |
| C16 | `arquitetura.md:54,62-66` | `infra/ansible/`, `control-plane.yml` e `pack-release.yml` prometidos, mas não existem |
| C17 | (ausente) | Backup, restauração, monitoramento, hardening, atualização, DNS; domínio real em aberto (`arquitetura.md:1146`) |
| C18 | `docs/operacao.md:130,331` | `cd infra && docker compose up` carrega o override de dev (edge sem TLS) na VPS |
| C19 | `stack.md:174` (§7); `infra/.env.example:16-17`; `espec.md:60` (S3) | `PACK_SIGNING_KEY` no `cms`; "assinatura só no CI"; "Packer (CI)". Contradizem a topologia real (o `packer` assina, sem porta, no compose). Entra aqui por ser diretriz de deploy |
| C20 | `build.gradle.kts:39-42,81-90`; `minSdk = 26` | Release só em `arm64-v8a`. O público provavelmente usa aparelhos baratos ou antigos, alguns 32-bit, que hoje ficam sem app nenhum, quando poderiam ter pelo menos os módulos educativos |
| C21 | ADR-003; `model_catalog.dart:50` | O modelo de ~806 MB é baixado no 1º acesso. Com a triagem secundária, o download automático pode afastar quem usa dados móveis |

### A.4 Fora deste plano

Inconsistências encontradas que **não decorrem** do vínculo com unidades. Vão para o plano 2 (§I):
- texto "telemetria é enviada" (`PRD.md:52-57`, `brainstorm.md:158`, `privacyTelemetryBody`);
- M3 < 3 s contra ADR-003;
- `consent_record` sem rota (LGPD-RF02(b)/RF04);
- titular da `LICENSE`;
- status "PROPOSTA" em `arquitetura.md:4`;
- `app/README.md` de template;
- falta de CONTRIBUTING, SECURITY, CODE_OF_CONDUCT e templates.

Onde uma tarefa deste plano reescrever um parágrafo que contém um desses pontos, ela não introduz erro novo, mas também não é obrigada a corrigir o antigo.

### A.5 O que não conflita e fica

- INV-1…8 e FSM-A/B.
- Dual review e golden 100 %.
- Zero PII.
- "Não faz diagnóstico" e "ligue 192".
- `espec.md` §5.2: "conteúdo educativo, não transacional".
- R1–R3 do ADR-004.
- Seeds sem unidade real.
- Semântica de cor.
- Sneakernet/pendrive para modelo e pack.
- Permissões em lista fechada e proibição de SDKs (RF16).
- "Quem compila a própria versão responde por ela".

---

## B. Inventário de artefatos

Legenda: **A** alterar · **C** criar · **N** nota de supersessão. Nenhum arquivo é removido. Saem trechos: F-Droid e sideload como canal oficial, "QR na UBS", conteúdo dependente de unidade, "Moat".

| Artefato | Ação | Tarefa | Pontos | Conflitos |
|---|---|---|---|---|
| `spec/stack.md` §10 | A | T1, T4 | ADR-005; ADR-004 revisado; ADR-006…009 | C0, C2, C3, C6, C7, C14, C15, C20 |
| `spec/PRD.md` | A | T2 | §1.1, §1.2 (sai JTBD-3), §1.3 (H1/H1b/H4), §1.5, §2.2 (CAP reordenadas; CAP-20/21), §4.1, §6.2, §6.3 (R6, R8, R9 novo), rodapé, hierarquia | C0, C4, C8, C10, C12, C14 |
| `spec/espec.md` | A | T3 | §1.1; RF-07, RF-09, RF-15; RF-16/17 e RNF-10/11 novos; RNF-04; §1.3 (A2, A3, S2, S3, fronteira); INV-8 (texto da exceção); §6.1; §6.3; §7.1 | C5, C8, C9, C11, C13, C15, C19 |
| `spec/brainstorm.md` | A | T3 | Nome/tagline (F-0), pitch, propósito, personas, escopo v1, F4/F6/F8/F10, "Moat" → "Diferenciais", infra mínima, M1/M4–M7, MVP, métricas | C0, C4, C8, C10, C12, C14, C15 |
| `spec/design.html`, `spec/design_selo_procedencia.html` | A | T3 | Rodapé institucional, aviso de não afiliação, ordem dos ladrilhos (≤ 8); rótulo do selo | C5, C8 |
| `spec/stack.md` (fora do §10) | A | T4 | §1.1, §4.1, §4.2, §5, §6, §7 (compose real), §9, §11; fundamentos 4 e 5 do ADR-001 | C9, C12, C14, C15, C19 |
| `spec/implantacao.md` | **C** | T5 | §D deste plano em texto normativo | C7, C17, C18, C19, C20 |
| `spec/arquitetura.md` | A + N | T6 | L54 e L62-66 (planejado); §4.3 (nota do ADR-008); rótulos "pré-requisito de piloto"; L736, L763; itens 21/22; itens 25, 27, 28, 30 e 31 | C11, C14, C16 |
| `spec/lgpd.md` | A | T7a, T7b | T7a neutraliza: Secretaria, municípios, VPS sem dono. T7b reescreve, depois da revisão jurídica: bases legais, controlador, RIPD, operadores | C1, C9, C15 |
| `docs/revisao-golden.md` | A | T7a | Secretaria → coordenação do projeto | C1 |
| `docs/operacao.md` | A | T7a | `-f compose.yaml`; "manifest da edição"; "estudo piloto" | C11, C18 |
| ARB, `assets/legal/`, `about_screen.dart:377`, testes de texto | A | T8a, T8b (exceção) | T8a: tudo que não depende do parecer. T8b: controlador e bases legais da privacidade | C0, C2, C5, C8, C13 |
| `README.md`, `CLAUDE.md`, `PROGRESS.md` | A | T9 | Enquadramento, hierarquia, rótulo do selo, "Instalar", seção "Release e implantação" | C0, C4, C5, C14 |
| Issues e planos de 2026-10-28; plano P1-1 | N | T12 | Nota de supersessão; edição no GitHub com confirmação | C1, C3, C4 |

---

## C. Requisitos: sai, muda, entra

### C.1 Sai do escopo

| Item | Onde | Tratamento |
|---|---|---|
| Piloto em UBS, aprovação de gestores, validação com equipe da UBS | M6, PRD Fase 2, H4 | Vira o **estudo piloto do projeto** (C.2) |
| JTBD-3 (gestor municipal) | PRD §1.2 | Removido |
| Conteúdo que depende de **uma** unidade: estoque local, marcação local, "fluxograma **da** unidade", horários **de uma unidade específica** | RF-09, F4, F8, F10, CAP-17 | RF-09 vira o fluxo **típico** da APS. CAP-17 explica a Farmácia Básica/RENAME em nível nacional. Informação genérica e educativa ("UBS costuma funcionar em horário comercial; confirme na sua") **fica** |
| Curadoria municipal e admins municipais | A2, stack §4.1, lgpd | Equipe editorial do projeto |
| QR afixado na UBS; espelhos municipais | espec §7.1, stack | Removidos |
| Modo ACS como uso institucional de equipe de UBS | CAP-18 | Vira "modo multiplicador" (v2) |
| F-Droid e sideload como **canais oficiais** | PRD, stack §9, M7 | F-Droid fica como futuro, sem compromisso. Repassar o APK entre pessoas não é proibido, mas não é canal oficial |
| Integração, dados ou aprovação de unidade de saúde | (implícito) | Vira **restrição explícita** na fronteira (espec §1.3) |

### C.2 Muda

| ID | De | Para |
|---|---|---|
| Missão | Orientar quando, onde e como usar a APS (triagem) | **Educação social em saúde**; orientação de onde buscar atendimento como apoio **secundário** |
| H1 | Completar a triagem sem mediação | **Compreensão sem mediação** (UBS × UPA, o que levar). A triagem passa a H1b |
| H4 | Prefeituras e ONGs distribuem; ≥ 20 usuários/UBS | GitHub Releases + Play, com apoio das ações do PET-Saúde. Meta: F-14 (provisória) |
| North Star | Triagens completadas | Provisória (F-14): "módulos educativos concluídos sem mediação". Triagem como métrica secundária |
| CAP-02/07/08/09 × CAP-03..06 | Triagem primeiro | Ordem e redação com educação primeiro. **Não muda** o teto de 8 elementos nem a navegação (§E.4) |
| RF-15 | "regras do posto" | Rótulo novo (F-15), mesmo comportamento |
| RNF-04, §6.3 | Coorte `município+versão` | Coorte `(versão_app, versão_pack, edição)` (ADR-008). k ≥ 20 continua |
| INV-8 (exceção) | "posto sem rede"; "override pelo administrador" | "Pessoa sem rede"; dados móveis por escolha do próprio usuário |
| Atores | A2 admin municipal; A3 indicado pela Secretaria | A2 editor da equipe do projeto. A3 profissional de saúde colaborador, com registro ativo, sem representar unidade |
| Piloto | UAT em 2 UBS | **Estudo piloto do projeto**: PRISM/PET-Saúde com voluntários da comunidade, fora de unidades de saúde, pelo canal de teste da Play e/ou pré-release do GitHub. **Saída:** zero orientação clinicamente incorreta, aprovação da coordenação clínica do projeto e, **se** houver coleta de dados de participantes, parecer de CEP (F-9) |

### C.3 Entra no escopo

**Requisitos novos (espec §1.2):**

- **RF-16. Aviso de não afiliação e caráter educativo.**
  - Onde aparece: 1º uso (gate dos termos), tela Sobre e ficha das duas lojas. Em pt e es, com áudio.
  - O que diz: o app é um projeto educativo do PRISM/UFRR com o PET-Saúde; não é serviço de saúde; não fala por UBS, SUS, Secretaria ou Ministério.
  - *Aceite:* chave ARB nos dois idiomas; teste confere a exibição no gate e no Sobre; checklist de release confere a ficha.
- **RF-17. Procedência verificável do binário.**
  - A release no GitHub traz o SHA-256 do APK e a impressão do certificado. A versão aparece no Sobre.
  - *Aceite:* o job de release falha sem `SHA256SUMS`.
- **RNF-10. Release em pipeline.**
  - APK e AAB saem do CI a partir de tag `vX.Y.Z` em `main`, com `versionCode` monotônico e chave nunca versionada.
  - As guardas `build_apk.sh`/`model_url_check` e `check_release_permissions` rodam no job.
  - *Aceite:* uma tag gera os artefatos; `versionCode` ≤ o publicado reprova.
- **RNF-11. Operação do plano de controle.**
  - Backup diário cifrado fora do host, com restauração testada a cada trimestre.
  - Monitoramento externo de `manifest.json` e do CMS.
  - Imagens pinadas e atualizadas por PR. TLS automático.
  - *Aceite:* §D.2.

**Capacidades novas (PRD §2.2):** CAP-20, pipeline de release do APK; CAP-21, operação do CMS na VPS do PRISM.

**Itens novos de roadmap (`arquitetura.md`, Fase 4), cada um com plano próprio:**

**Numeração.** O item 26 já existe no roadmap (desfecho padrão derivado no packer, `arquitetura.md` §5.15). Por isso o workflow de release, que este plano chamava de 26 até a execução do E3, é o **item 31**, o primeiro número livre depois dos já reservados por este plano (25, 27, 28, 29, 30). Nenhum documento do E1 ou do E2 citava o "item 26" com o sentido novo.

**Notas para o plano do item 31** (revisão do PR #65, 2026-11-02):
- **Fonte do "maior `versionCode` já publicado": a maior tag `vX.Y.Z` do repositório.** O `versionCode` é função do SemVer, e a tag anotada é obrigatória. A guarda compara com a maior tag existente: é determinística, funciona offline, não depende de API nem de conta na Play, e as pre-releases contam automaticamente, porque também têm tag.
- **"Aprovador diferente de quem criou a tag"** é a opção ***Prevent self-review*** do *environment* `release` no GitHub. Ela vale como configuração e não deve ser reimplementada à mão no workflow.

| Item | Entrega | Depende de |
|---|---|---|
| 25 | `applicationId` definitivo; `signingConfig` de release a partir de `key.properties` fora do repo; ABIs e `minSdk` do ADR-009. Para `armeabi-v7a`: APK sem o shim, e o app **não oferece o download do modelo** onde o shim não existe. Um build por ABI, sem `--split-per-abi`. Guarda de `minAppBuild` (hoje inexistente) com teste | F-3, F-6; P: F-17 |
| 31 | `app-release.yml`: tag → APK(s) + AAB assinados, checksums, nota de release; AAB para a faixa de teste da Play | 25, F-4 |
| 27 | Playbook Ansible da VPS (substitui a promessa de `infra/ansible/`) | F-1, F-2 |
| 28 | Backup/restauração e monitoramento externo | 27, F-8 |
| 30 | Avaliar o modelo SLM como download **opcional/sob demanda** (módulos educativos sem ele) | F-18; reabre ADR-003 se adotado |

Os itens 21 e 22 existentes são absorvidos por 26 e 27, com nota no roadmap. O 29 (aceite de termos no CMS) foi para o plano 2 (§I).

---

## D. Diretrizes de implantação (conteúdo de `spec/implantacao.md`)

**[F-n]** marca dependência de pergunta aberta. **(P)** marca proposta provisória, registrada no ADR com data de revisão. **(Play@data)** marca regra de terceiro que se confere no Play Console na data da publicação.

### D.1 APK Android

**Identidade**

- Primeiro decide-se o **nome do app [F-0]** (material de decisão na §F.1). O `applicationId` vem **depois**, e antes da 1ª publicação na Play, porque depois disso não muda **[F-3]**.
- O id não leva `gov` e usa domínio reverso que o PRISM controle.
- **Recomendado: o id não codifica o nome.** Na Play, o título da ficha pode ser trocado depois; o id, não. Um id neutro (ex.: `<domínio-reverso-do-PRISM>.saude`) separa as duas decisões: renomear mais tarde custa uma ficha nova e material refeito, nunca um app novo.
- Mudam junto, no item 25, que é código: os nomes de tarefa do WorkManager (`pack_sync_scheduler.dart:19`, `model_sync_scheduler.dart:19`) e `release_permissions.dart:34`.

**Versionamento** (P; F-5)

- Hoje `0.1.0+1`, sem tags.
- `pubspec.yaml` em SemVer `MAJOR.MINOR.PATCH`:
  - MAJOR: o app passa a rejeitar packs de um `schemaVersion` major antigo, ou muda o comportamento perceptível da orientação.
  - MINOR: funcionalidade nova.
  - PATCH: correção.
- `versionCode` = `MAJOR*10000 + MINOR*100 + PATCH`. É estritamente crescente e único entre os canais.
  - **Limites:** MINOR e PATCH ≤ 99. MAJOR ≤ 210, porque a Play aceita `versionCode` até 2 100 000 000.
  - Estourar MINOR ou PATCH exige um MAJOR novo ou a revisão da fórmula no ADR-009.
- **Modelo de promoção, não de rebuild.**
  - O artefato testado é o artefato publicado: mesma tag, mesmo `versionCode`, mesmo binário.
  - Na Play, o AAB sobe para a faixa de teste e é **promovido** para produção.
  - No GitHub, a release nasce marcada como *pre-release*, e a marca é retirada na promoção. O APK e o `SHA256SUMS` não mudam.
  - Não existe sufixo `-rc` nem PATCH reservado para pré-release. Se o estudo piloto achar defeito, a correção é um PATCH novo e uma nova rodada na faixa de teste, nunca um rebuild da mesma versão.
- Tag anotada `vX.Y.Z` em `main`. `CHANGELOG.md` na raiz, no formato Keep a Changelog.
- A versão do pack (INV-7) e o `schemaVersion` seguem independentes.
- **`minAppBuild` hoje não é conferido.** O app o lê (`pack_manifest.dart:83,179`), mas nenhum código em `app/lib` o compara com nada; o packer grava `1` por padrão. A diretriz:
  - `minAppBuild` compara com o `versionCode` **único** do app (ver ABIs, abaixo);
  - a guarda que faz essa comparação é implementada no item 25, com teste;
  - até lá, publicar pack que dependa de app novo é proibido, porque nenhum aparelho o recusaria.

**ABIs e versão mínima** [F-17, P]

- Hoje o release só tem `arm64-v8a` e `minSdk 26`.
- **Proposta provisória:**
  - incluir `armeabi-v7a` **sem o shim nativo**;
  - nesses aparelhos a triagem roda pelo `RuleOnlyEngine`, degradação que o INV-8 já prevê;
  - um aparelho 32-bit dificilmente tem memória para o modelo de ~806 MB, então compilar o llama.cpp para ele não compensa;
  - `minSdk` continua 26.
- **Consequência obrigatória:** onde o shim não existe, o app **não oferece nem inicia** o download do modelo. Baixar 806 MB que nunca vão rodar desperdiça o plano de dados de quem menos pode pagar. O item 25 cobre isso com teste.
- Distribuição: APK separado por ABI no GitHub (dois arquivos, dois SHA-256). O AAB já serve a ABI certa na Play.
- **Sem `--split-per-abi`.** O plugin gradle do Flutter, nesse modo, sobrescreve o código: `versionCode = abi*1000 + versionCode`, com `armeabi-v7a`=1, `arm64-v8a`=2 e `x86_64`=4 (conferido em `flutter_tools/gradle/src/main/kotlin/FlutterPlugin.kt:669-674` e `FlutterPluginConstants.kt:39-45` do SDK local). Isso quebra duas premissas:
  - o APK `arm64`, o `armeabi-v7a` e o AAB sairiam com códigos diferentes, então "mesmo `versionCode` em todos os canais" cai;
  - o deslocamento de 1000 cai **dentro** da fórmula da §D.1, que anda de 100 em 100 por MINOR. O APK `arm64` de `0.1.0` (100 + 2000 = 2100) colidiria com o `0.21.0`.
- **Proposta provisória:** cada APK sai de um `flutter build apk --release --target-platform=android-arm64` (e `android-arm`) **separado**, sem split. O `versionCode` fica único, e o AAB usa o mesmo.
- **Antes de fixar no ADR-009, o plano A verifica** que cada APK contém só as `.so` da sua ABI e que o `versionCode` lido no aparelho (`aapt dump badging` e o Sobre) é igual nos três artefatos. A alternativa, se isso falhar, é o `minAppBuild` passar a comparar com um número derivado do SemVer injetado por `--dart-define`, e não com o `versionCode` do pacote.
- O que resta medir: o tamanho do APK `armeabi-v7a` e o custo de uma configuração a mais no CI do app (não do shim).

**Assinatura**

- O keystore de release é gerado uma vez e fica em cofre offline com duas custódias, no mesmo regime da chave Ed25519.
- Nunca vai para o repositório (o `.gitignore` já cobre). No CI, entra como segredo do *environment* `release`, com aprovação manual.
- **[F-6]:** com Play App Signing e chave gerada pela Google, o APK do GitHub e o da Play **não se atualizam um sobre o outro**.
  - A nota de release e a página do projeto avisam: "troque de canal só desinstalando; seus ajustes se perdem; nada de saúde é guardado".
  - A alternativa é enviar a chave própria. Mantém a compatibilidade entre canais, mas a equipe passa a responder sozinha pela custódia.

**Fluxo de release (item 31)**

1. PR `develop` → `main` com CHANGELOG e CI verde (`app`, `interop`, `shim`, `contract`, `cms`).
2. Tag `vX.Y.Z`. O `app-release.yml` roda no *environment* `release` e exige aprovação de um segundo mantenedor.
3. Build: `tool/build_apk.sh release` (guardas de `MODEL_URL`/`PACK_MANIFEST_URL` a partir de `defines.release.json`, vindo de segredo), `flutter build appbundle` com as mesmas guardas, e depois `check_release_permissions.dart`.
4. Artefatos: APK por ABI, `SHA256SUMS`, impressão SHA-256 do certificado. O AAB não é anexado ao GitHub.
5. Release no GitHub marcada como *pre-release*, com a nota-modelo: novidades, aviso educativo e de não afiliação, link da política, como conferir o SHA-256, aviso de canal.
6. O mesmo AAB vai para a faixa de teste interno ou fechado da Play (o estudo piloto roda aqui).
7. Promoção manual, condicionada ao checklist da ficha: o AAB passa da faixa de teste para produção na Play, e a marca *pre-release* sai no GitHub. Não há rebuild.
8. `docs/operacao.md` registra a versão publicada em cada canal.

**Google Play: checklist da ficha.** Cada linha é conferida no console na data da publicação.
- **Conta de desenvolvedor [F-4]:** pessoal ou de organização (D-U-N-S). Exigências de teste fechado para conta pessoal nova (Play@data).
- **Técnico:** `targetSdk` dentro do mínimo vigente (Play@data); limite de tamanho do AAB (Play@data). O modelo já fica fora do pacote.
- **Política de privacidade** em URL pública, da mesma fonte e na mesma versão de `assets/legal/privacidade_*.md` [F-7].
- **Data safety:** proposta de declarar "nenhum dado coletado nem compartilhado pelo app", **sujeita** à revisão jurídica do tratamento de IP (T7-R) (Play@data).
- **Declaração de app de saúde:** proposta "informação/educação em saúde, não dispositivo médico". O enquadramento RDC 657/2022 do ADR-004 é **leitura a confirmar** na T7-R (Play@data).
- **Classificação e contato:** IARC, público adulto, e-mail de contato.
- **Descrição:** segue R1–R3 (sem "triagem", "diagnóstico" ou "classificação de risco"), traz o RF-16 e o link para fontes oficiais (*Misrepresentation*, Play@data).

### D.2 CMS na VPS do PRISM

**Propriedade e requisitos mínimos [F-1, F-2]**
- VPS contratada e administrada pelo PRISM; não é da UFRR nem de unidade de saúde.
- Requisitos mínimos (P): datacenter no Brasil (ou país declarado no RIPD), ≥ 2 vCPU, 4 GB RAM, disco ≥ 80 GB, snapshot disponível.
- Dois administradores nomeados por papel.

**Domínio e TLS [F-7]**
- Domínio em conta do PRISM, com dois administradores.
- `CONTENT_DOMAIN` (só GET/HEAD) e `CMS_DOMAIN`.
- Caddy com ACME e `ACME_EMAIL` de caixa do grupo. HSTS e CSP como hoje. `BETTER_AUTH_URL` em `https://`.
- Só 80/443 públicas. `sqld` e MinIO em 127.0.0.1.

**Provisionamento (item 27)**
- O playbook Ansible é a fonte da verdade. Ele configura:
  - usuário de deploy com SSH só por chave e `PermitRootLogin no`;
  - firewall 22/80/443;
  - `unattended-upgrades` de segurança;
  - Docker pinado;
  - LUKS, se o provedor permitir;
  - systemd com `docker compose -f compose.yaml` **sem** override (C18).
- `infra/.env` só na VPS, com permissão 600, e cópia cifrada no cofre.
- A chave Ed25519 fica `:ro` só no `packer`.
- Risco residual registrado: chave numa VPS sem HSM. Mitigação: chave de rotação embarcada e runbook de revogação.

**Atualização**
- Imagens com tag exata ou digest. As flutuantes `caddy:2.9-alpine` e `node:22-bookworm-slim` deixam de ser.
- Toda mudança entra por PR com CI verde, seguida de `docker compose -f compose.yaml up -d --build`.
- Migração: backup **antes**, `npm run cms:migrate`, conferência da trilha.
- O app não depende do CMS em runtime.

**Backup (item 28) [F-8, P]**
- **O que é copiado, diariamente:** `sqld` (dump consistente), MinIO (só o que for fonte primária), `caddydata` e `.env`.
- **Proteção:** tudo cifrado (restic/age), com cópia fora da VPS.
- **Retenção (P):** 7 diárias, 4 semanais e 6 mensais.
- **Teste de restauração:** trimestral, numa VPS descartável.
- **Prioridade:** banco master e trilha, que não são reconstruíveis. Os packs são, pelo packer reprodutível.

**Segurança e monitoramento**
- 2FA e rate limit como hoje.
- `fail2ban` no SSH.
- Monitor externo de `manifest.json` e do CMS, com alerta aos dois administradores.
- Alertas de expiração do TLS e de disco acima de 80 %.
- Log do Caddy com retenção curta [F-10, P: 14 dias].
- Incidente: o runbook LGPD-RF12 nomeia o PRISM como comunicante, sob o controlador da F-11.

---

## E. Privacidade, termos e avisos

### E.1 Hierarquia nos textos

Todo texto ao usuário segue esta ordem:
1. **O que é:** projeto educativo aberto.
2. **O que ensina.**
3. **O apoio secundário:** onde procurar atendimento, sem substituir profissional.
4. **O que não é:** não é serviço de saúde; não tem vínculo com unidade, SUS ou Secretaria; não diagnostica; emergência = 192.

### E.2 LGPD: propostas para revisão jurídica

Nada nesta seção é decisão. É o material que a T7-R leva ao encarregado ou à assessoria jurídica. Só o que voltar aprovado entra no `lgpd.md` e nos textos do app.

- **Controlador [F-11, consulta institucional].** Um grupo de pesquisa não tem personalidade jurídica. Opções a levar:
  - **(a)** UFRR como controladora, com PRISM e PET-Saúde executando. Valem os arts. 23–24 (poder público), e o encarregado é o institucional.
  - **(b)** Pessoa física coordenadora do PRISM.
  - Até a resposta, o texto diz "[a definir — F-11]" e **nunca** a Secretaria.
- **Tese central (não depende da revisão):** sem dado pessoal do usuário final. Os tratamentos restantes são: operadores do CMS, IP em logs de download e, se coletados, dados de participantes do estudo piloto.
- **Bases legais candidatas:**
  - operadores do CMS: legítimo interesse (art. 7º, IX) com teste de balanceamento, ou art. 7º, III/IV, se (a);
  - log de IP: legítimo interesse com retenção mínima;
  - revisores clínicos: art. 7º, IX ou consentimento.
  - **Pergunta à revisão:** a base atual "tutela da saúde, art. 11, II, f" se sustenta sem profissional, serviço de saúde ou autoridade sanitária como controlador?
- **RF02:** TCLE sob CEP, se houver coleta (F-9).
- **RF06/RF17 (operadores e terceiros):**
  - VPS do PRISM, cujo provedor é suboperador;
  - GitHub (Releases e Pages veem IP);
  - Google Play (a Google como controladora própria; confirmar);
  - Hugging Face, enquanto o modelo vier de lá.
- **Demais pontos:**
  - **RF07:** retenção de trilha, logs e backups.
  - **RF08/§6:** canal do titular.
  - **RF10/DOC02:** política em URL pública.
  - **Revisores golden:** termo arquivado pelo responsável do F-11.
  - **Governança:** RIPD **antes** do estudo piloto.

**Textos do app.** Ficam em duas levas, para que o parecer não segure o que não depende dele.

- **T8a**, sem parecer, logo depois do E2:
  - **Termos (pt/es):**
    - abertura educativa;
    - não afiliação;
    - crédito de cooperação, só se a F-13 permitir citar o PET-Saúde;
    - canais oficiais, e o aviso de que cópia de outra origem não tem garantia;
    - avisos de não substituição preservados;
    - "MINUTA" continua.
  - **Privacidade (pt/es):**
    - o servidor de conteúdo do projeto como destino de rede;
    - instalação pela Play;
    - "posto" atribuidor → "você";
    - o controlador aparece como o marcador explícito "[a definir — F-11]".
  - **ARB:** rótulo do selo, `aboutNoAffiliation`, `appTitle` (F-0), `termsGateBody`.
  - **Versão:** **1º bump** nos quatro documentos, o que reabre o 1º "li e concordo".
- **T8b**, depois da T7-R/T7b:
  - **Privacidade (pt/es):** controlador e encarregado nomeados; a seção de bases legais aprovadas; a retenção do log.
  - **Termos:** só se o parecer mexer no "Responsável".
  - **Versão:** **2º bump**, que reabre o "li e concordo" de novo.
- **Custo aceito:** dois reaceites no estudo piloto. Em troca, os textos não esperam semanas pela procuradoria.

### E.3 Rótulo do selo [F-15]

"regras do posto" / "reglas del puesto" passa a atribuir as regras ao **app revisado por profissionais**. Proposta: "regras de segurança do app" / "reglas de seguridad de la app". O rótulo muda em `espec.md` RF-15, no `design_selo_procedencia.html`, no CLAUDE.md e nos ARB. `provenanceFor` não muda.

### E.4 Ênfase educativa na interface

Só no **protótipo** (`design.html`): troca de ordem e de destaque, sem elemento novo (RNF-06; `accessibility_test.dart` reprova 9 elementos). A implementação no app vira item de roadmap depois do estudo piloto.

---

## F. Perguntas abertas

**Classes:**
- **B — bloqueia.** A tarefa indicada não começa sem a resposta.
- **P — provisória.** O executor adota a proposta escrita neste plano e a registra no campo **Revisão** do ADR indicado, com data de revisão (padrão: fim do estudo piloto).
- **M — marcador.** O documento pode levar `[a definir — F-n]`. Bloqueia só o item de implementação.
- **I — consulta institucional.** Não deve ser respondida pelo mantenedor sozinho: exige consulta ao encarregado ou à procuradoria da UFRR.

**Onde registrar as respostas:** na coluna "Situação" desta tabela entra só "respondida em <data>" ou "provisória em <data>". O conteúdo das respostas operacionais (F-1, F-2, F-4, F-8) fica no registro de decisões fora do repositório, conforme as restrições globais.

| # | Classe | Pergunta | Bloqueia / registra em |
|---|---|---|---|
| **F-0** | **B** | **Nome do app.** "Guia UBS" se mantém, dado o risco de parecer canal oficial (*Misrepresentation*)? Se mudar, qual nome (pt/es)? Material de decisão na §F.1 | **E1 (T1)**, T8a, item 25. **É a única pergunta que bloqueia o E1** |
| F-3 | B | `applicationId` definitivo. **Já decidido provisoriamente: o id é neutro e não codifica o nome** (`<domínio-reverso-do-PRISM>.<sufixo neutro>`, sem `gov` e sem `guiaubs`). Com isso, a F-0 pode mudar depois sem um app novo. A resposta pendente é só **qual domínio reverso** o PRISM controla e qual o sufixo | T4 (ADR-009), item 25 |
| F-6 | B | Play App Signing com chave da Google (canais incompatíveis) ou com chave própria (compatíveis)? | T4 (ADR-009) |
| F-15 | B | Texto final do rótulo do selo (§E.3) | T3, T8a |
| F-11 | B + I | Controlador LGPD (UFRR ou pessoa física) e encarregado | T7b, T8b. O ADR-005 registra "pendente de consulta"; a T8a usa o marcador "[a definir — F-11]" |
| F-13 | P + B | A cooperação PRISM–PET-Saúde tem instrumento formal? Pode ser citada pelo nome ao usuário? O logo do PET-Saúde entra no Sobre? | **P** para o ADR-005 ("cooperação em andamento, formalização pendente"). **B** só para citar o PET-Saúde em texto ao usuário (T8a): sem resposta, a T8a sai sem o crédito, que entra na T8b ou num PR à parte |
| F-16 | P | Pack único nacional ou edições regionais (ex.: Roraima)? Provisório: uma edição nacional, com o mecanismo de edição preservado | ADR-008, Revisão |
| F-17 | P | ABIs e `minSdk`. Provisório: `arm64-v8a` + `armeabi-v7a` sem shim, `minSdk 26`, um build por ABI **sem `--split-per-abi`** (§D.1); confirmação pela verificação do plano A | ADR-009, Revisão |
| F-5 | P | Política de versionamento: adotar a da §D.1 (modelo de promoção) | ADR-009, Revisão |
| F-8 | P | Destino do backup fora da VPS. Provisório: um segundo provedor de objeto com conta do PRISM | ADR-007, Revisão |
| F-10 | P | Retenção do log do Caddy: 14 dias | ADR-007, Revisão (e T7-R) |
| F-14 | P | North Star e meta de alcance do estudo piloto: "módulos educativos concluídos sem mediação", com meta a fixar com o PET-Saúde | ADR-005, Revisão; PRD §1.5 |
| F-19 | M | **Titularidade do `prismrr.com.br`**: CPF ou CNPJ do titular no Registro.br, quem recebe os avisos de renovação e o plano de transferência se o titular sair do grupo (resposta **fora do repositório**, junto com F-1, F-2, F-4, F-8). O alerta de expiração cobre o esquecimento, não a saída da pessoa | Itens 27 e 28; ADR-009 |
| F-1 | M | Provedor da VPS, região, snapshot, LUKS (resposta fora do repo) | Itens 27–28 |
| F-2 | M | Os dois administradores da VPS e do domínio, por papel (resposta fora do repo) | Item 27 |
| F-4 | M | Conta do Google Play: existe? Pessoal ou de organização? Em nome de quem? (resposta fora do repo) | Item 31 |
| F-7 | M | Domínio do projeto e URL da política de privacidade. **Domínio respondido em 2026-11-02: `prismrr.com.br`.** Falta a URL da política (GitHub Pages ou o próprio domínio) e o nome dos subdomínios de conteúdo e do CMS | Itens 27 e 31 |
| F-9 | M | O estudo piloto coleta dados de participantes? Há protocolo no CEP? | Início do estudo piloto (§J) |
| F-18 | M | Com a triagem secundária, o modelo de ~806 MB continua sendo baixado automaticamente no 1º acesso ou passa a opt-in/sob demanda? | Item 30 (não bloqueia este plano) |
| F-12 | — | Titular do copyright e DCO: **movida para o plano 2** (§I); classe I | — |

### Registro da T0 (2026-11-02)

Base conferida: `develop` local e `origin/develop` em `2ab9f93`. As linhas citadas na §A valem.

| # | Situação | Resposta (só o que é público por natureza) |
|---|---|---|
| F-0 | respondida em 2026-11-02 | **Manter "Guia UBS"**, com aviso forte de não afiliação (RF-16). O risco vai para os Custos aceitos do ADR-005 |
| F-3 | **respondida** em 2026-11-02 (3 registros) | **(1) 1ª resposta do dono do projeto, 2026-11-02:** "subdomínio da UFRR" (`br.ufrr.prism.<sufixo>`). **(2) Substituída pelo dono do projeto em 2026-11-02**, nas respostas ao PR #63, com as palavras: *"O PRISM não controla ou pode obter prism.ufrr.br, focar na ADR-007 (VPS do PRISM)"*. Fica valendo a (2): prefixo de **domínio próprio do PRISM, fora de `ufrr.br`**, e sufixo **`guiasaude`**, indicado na mesma rodada (neutro quanto ao nome, específico deste app; o PRISM tem outro app com o PET-Saúde). O executor não decidiu: registrou. **Fechada em 2026-11-02:** o dono do projeto registrou **`prismrr.com.br`** (Registro.br), e o id é **`br.com.prismrr.guiasaude`** (ADR-009). A escolha de `.br` contraria a recomendação do `docs/operacao.md`; o custo está nos Custos aceitos do ADR-009 |
| F-6 | respondida em 2026-11-02 | **Play App Signing com chave gerada pela Google.** APK do GitHub e da Play não se atualizam um sobre o outro; o aviso de canal é obrigatório |
| F-15 | respondida em 2026-11-02 | **"regras de segurança do app"** / es "reglas de seguridad de la app" |
| F-13, F-14, F-16, F-17, F-5, F-8, F-10 | provisórias em 2026-11-02 | Propostas deste plano adotadas. Datas de revisão no ADR que as registra: F-13 até 2027-02-01; F-14 com a meta antes do 1º participante externo e a métrica até 2027-05-01 (ADR-005). As demais recebem data no ADR do E2 |
| F-11 | aberta (consulta institucional) | — |
| F-19 | respondida em 2026-11-03 | Fora do repositório (dado pessoal do titular). Público por natureza, no `implantacao.md` §3.2: dois contatos de cobrança, pagamento adiantado de mais de um ano, transferência ao próximo responsável pelo PRISM em caso de afastamento |
| F-1 | respondida em 2026-11-03 | Fora do repositório. Público por natureza: datacenter no Brasil, como exige o ADR-007; instância **ARM**, o que pede imagens `linux/arm64` de `sqld`, MinIO, Caddy e Node no item 27 (conferir cada uma). Se alguma imagem não tiver `linux/arm64`: compilar a própria ou trocar de instância, **nunca emulação em produção** |
| F-4 | respondida em 2026-11-03 | Fora do repositório. Público por natureza: **conta pessoal** da Play. Conferir no Play Console as exigências de conta pessoal nova (teste fechado, verificação de identidade) e se apps de saúde pedem conta de organização (Play@data) |
| F-8 | respondida em 2026-11-03 | Fora do repositório. Público por natureza: **outro provedor que não o da VPS**, região no Brasil, escrita sem permissão de apagar ou bucket imutável por período, leitura com pessoa diferente do administrador da VPS, restauração trimestral registrada com data (ADR-007, Decisão 7) |
| F-7 | respondida em 2026-11-03 | Subdomínios: **`guiasaude.conteudo.prismrr.com.br`** (só manifest e packs, estático; é o embarcado no APK) e **`guiasaude.cms.prismrr.com.br`** (CMS atrás de VPN ou autenticação). Política e termos em **`https://prismrr.com.br/guiasaude/{privacidade,termos}`**, no GitHub Pages atrás de CNAME, publicando o mesmo arquivo que o app embarca, com versão e data, sem analytics (`implantacao.md` §2.9) |
| F-2 | respondida em 2026-11-03 (opção **a**) | Fora do repositório. Público por natureza: **duas pessoas**. O administrador da VPS e um segundo mantenedor que não opera a VPS, mas é revisor do release, segunda custódia das chaves, mantenedor B do pack, tem a leitura do backup e sabe restaurá-lo numa VPS nova. Motivo: **fator ônibus** (ADR-007, Decisão 1). Nenhum controle dos ADR-001 e 009 mudou |
| Modelo no HF | decidido em 2026-11-03 | A exceção do ADR-004 **continua por decisão**, com quatro condições na Revisão do ADR-004: URL do modelo no manifest (plano B); aviso "servidor fora do Brasil" antes do "Baixar agora" (E7, T7-R); o espelho `ggml-org` e o limite de download anônimo do HF (controle: SHA-256 no app, que reprova); revisão de custo pelo volume real de downloads do estudo piloto |
| F-9, F-18 | abertas (classe M) | — |

**Liberado:** E1 e, desde 2026-11-02, o E2 (domínio `prismrr.com.br` registrado). Os administradores do domínio (F-2) ficam no registro fora do repositório.

### F.1 Material para decidir a F-0 (nome do app)

**Critérios:**
1. Não evoca órgão, programa ou serviço oficial: nem "SUS", nem "UBS", nem "Ministério", nem "gov".
2. Funciona em pt e es: **o mesmo nome**, ou uma tradução literal evidente que quem fala uma língua reconhece na outra. A ficha da Play aceita título por idioma, mas o ícone, o áudio e o boca a boca funcionam melhor com um nome só. O mesmo nome é preferível; a tradução literal é aceitável.
3. Diz "aprender sobre saúde", não "ser atendido".
4. É curto e pronunciável por quem lê pouco. O nome também é dito em áudio.
5. Não colide com app existente na Play nem com marca registrada. Conferir na Play, no INPI e na busca de domínio **antes** de decidir; nada disso foi verificado neste plano.

**As duas opções:**

| | Manter "Guia UBS" com aviso forte de não afiliação | Renomear agora |
|---|---|---|
| Custo agora | Baixo: só o RF-16 | Baixo: `appTitle`, textos, ícone sem mudança, material do estudo piloto |
| Custo depois | Risco de rejeição ou suspensão na Play (*Misrepresentation*), e quem lê pouco continua lendo "UBS" como "oficial", com ou sem aviso | Renomear **depois** da 1ª publicação custa a ficha, o material impresso e o reconhecimento de quem já instalou. O id não muda se for neutro (F-3) |
| Outro risco | "UBS" também é marca de um banco suíço, o que pode confundir a busca na loja (verificar) | Precisa de uma rodada rápida de compreensão do nome com o público, que pode caber no próprio estudo piloto |

O nome alternativo "SUS Fácil", citado no brainstorm, tem o mesmo problema, possivelmente pior: "SUS" é o nome do sistema oficial, e "Fácil" sugere um atalho de acesso a ele.

**Candidatos** (ilustrativos, sujeitos ao critério 5). Pelo critério 2, só "Saber" se aproxima do mesmo nome nos dois idiomas, e mesmo ele traz "Saúde"/"Salud" traduzidos. Os outros dois são traduções literais evidentes, portanto aceitáveis, mas não preferíveis:
- **Saber Saúde / Saber Salud.** "Saber" é igual nas duas línguas, e o nome diz educação.
- **Caminho do Cuidado / Camino del Cuidado.** Fala em orientar sem prometer atendimento.
- **Guia Saúde Aberta / Guía Salud Abierta.** Preserva "Guia", que o público do estudo talvez já conheça, e marca o caráter aberto.

**Recomendação:** decidir a F-0 antes do E1. Se "Guia UBS" ficar, a decisão e o risco aceito entram nos **Custos aceitos** do ADR-005, e o id da F-3 sai neutro de qualquer jeito.

---

## G. ADRs a registrar (`spec/stack.md` §10)

Formato vigente: `### ADR-NNN — <Título>: **VEREDITO** (AAAA-MM-DD)`, com **Contexto.**, **Decisão.**, **Fundamentos**, **Custos aceitos**, **Revisão**. Toda decisão provisória (classe P) aparece em **Revisão** com data.

| ADR | Título | Decisão | Depende |
|---|---|---|---|
| ADR-005 | Enquadramento institucional: projeto educativo aberto, sem vínculo com unidades de saúde | PRISM/UFRR + PET-Saúde (cooperação em andamento, formalização pendente: F-13); educação primária e apoio secundário; código aberto; nenhum requisito pressupõe unidade; nome do app; "estudo piloto do projeto"; controlador **pendente de consulta (F-11)** | F-0; P: F-13, F-14 |
| ADR-004 (revisão) | Gatilho "publicar em loja" disparado | Registra o disparo e o que ele exige (parecer jurídico, responsável = F-11). A cooperação substitui "sem vínculo formal com a UFRR". "Parceria com Secretaria/UBS" passa a fora de escopo e exige ADR novo | ADR-005 |
| ADR-001 (revisão) | Vercel rejeitado: fundamento 4 corrigido e exceção provisória de assinatura | O fundamento 4 deixa de dizer "assinatura só no CI" (C19). **Revisão:** assinatura provisória do pack na máquina de um mantenedor, conferida por um segundo mantenedor, até o item 27 (§J.3). Quem procurar "quem assina o pack" acha aqui. O ADR-007 aponta para cá | — |
| ADR-006 | Canais oficiais: GitHub Releases e Google Play | Dois canais; F-Droid é futuro; repasse entre pessoas não é canal oficial; RF-17 | — |
| ADR-007 | Plano de controle numa VPS mantida pelo PRISM | Dono, requisitos mínimos, compose sem override, backup fora do host, Ansible. Complementa ADR-001 e §9. Referência cruzada: a assinatura do pack enquanto a VPS não existe está na **Revisão do ADR-001** (§J.3) | P: F-8, F-10 |
| ADR-008 | Escopo de conteúdo: de "município" para "edição" | `municipality` fica no contrato, reinterpretado como edição, sem curador municipal. Renomear só com motivo de código | P: F-16 |
| ADR-009 | Identidade, versionamento, ABIs e assinatura do app | `applicationId` **inteiro**, num lugar só: prefixo do domínio próprio do PRISM + sufixo `guiasaude` (registro da T0); o ADR-005 só traz o princípio; SemVer + `versionCode` com os limites da §D.1; modelo de promoção; ABIs e `minSdk` (32-bit sem shim e sem download do modelo; um build por ABI **sem `--split-per-abi`**, para o `versionCode` ser único); `minAppBuild` compara com esse código único; custódia do keystore; Play App Signing e a consequência entre canais. A decisão sobre ABIs fica em **Revisão** até a verificação do plano A | F-3, F-6; P: F-5, F-17 |

---

## H. Tarefas e estágios de entrega

### Estágios (um PR por estágio, mergeado em `develop`)

| Estágio | Tarefas | Pré-condição |
|---|---|---|
| E1 | T1 | T0 com **a F-0** respondida (as P registradas como provisórias) |
| E2 | T2, T3, T4, T7a, num PR só (regra de propagação), com commits nessa ordem | E1; F-3, F-6, F-15 respondidas |
| E3 | T5, T6 | E2 |
| E4 | T7-R → T7b | E2; F-11 respondida pela consulta institucional; revisão jurídica concluída. **Corre em paralelo** com E3, E5 e E6 |
| E5 | T8a (exceção de código) | E2 |
| E6 | T9, T12 | E3 e E5 |
| E7 | T8b (exceção de código) | E4 e E5 |

```
T0 ─► E1(T1) ─► E2(T2+T3+T4+T7a) ─┬─► E3(T5+T6) ──┬─► E6(T9+T12)
                                  ├─► E5(T8a) ────┘
                                  └─► E4(T7-R ─► T7b) ──────────► E7(T8b)   (E7 também depende de E5)
```

O caminho crítico **não** passa mais pela revisão jurídica. Só o E7 espera por ela.

A T11 (varredura) roda **no fim de cada estágio**, sobre os arquivos daquele PR, e uma última vez depois do E7.

### Tarefa 0: decisões e conferência da base

**Leia:** §A (para reconferir as linhas), §F, §F.1.

- [ ] **Passo 1:** conferir a base. Se `git rev-parse develop` ≠ `2ab9f93`, rodar `git diff 2ab9f93 develop --stat -- spec docs app/lib/l10n app/assets/legal README.md CLAUDE.md`. Para cada arquivo alterado, reconferir as linhas citadas na §A e atualizar a tabela.
- [ ] **Passo 2:** levar a F-0 ao mantenedor com o material da §F.1. Em seguida, as demais perguntas classe B. As de classe I vão à consulta institucional, que pode correr em paralelo.
- [ ] **Passo 3:** registrar as respostas.
  - Na §F entra só "respondida em <data>".
  - O conteúdo das operacionais (F-1, F-2, F-4, F-8) vai para o registro de decisões fora do repositório.
  - O conteúdo das que viram ADR vai para o próprio ADR.
- [ ] **Passo 4:** para cada pergunta classe P, anotar "provisória em <data>; revisar em <data>".

*Aceite:* a F-0 está respondida, o que libera o E1. A situação de cada pergunta B está registrada, e nenhuma resposta operacional aparece no repositório.

### Tarefa 1: ADR-005 (E1)

**Leia:** §A.1, §C.2 (linha "Piloto"), §F (F-0, F-11, F-13, F-14), §F.1, §G.

**Arquivo:** `spec/stack.md` §10, depois do ADR-004.

- [ ] **Passo 1:** escrever o ADR-005 (§G):
  - **Contexto:** C0–C4 e C8.
  - **Decisão:** os quatro pontos do contexto; o nome (F-0); a definição do estudo piloto (§C.2); "Controlador: pendente de consulta institucional (F-11)"; "Cooperação PRISM–PET-Saúde: em andamento, formalização pendente (F-13)".
  - **Custos aceitos:** o canal "prefeitura distribui" deixa de existir; todos os textos ao usuário são revistos.
  - **Revisão:** F-14 com data; vínculo com unidade só por ADR novo.
- [ ] **Passo 2:** `grep -n "^### ADR-005" spec/stack.md` retorna 1 linha.
- [ ] **Passo 3:** commit e PR do E1.

*Aceite:* o ADR existe, não contradiz INV-1…8 e não fixa base legal nem controlador.

### Tarefa 2: PRD (E2)

**Leia:** §A.1–A.3 (linhas com `PRD.md`), §B (linha PRD), §C, §G.

**Arquivo:** `spec/PRD.md`.

- [ ] **Passo 1:**
  - §1.1 e §1.2: JTBD educativos; sai o JTBD-3.
  - §1.3: H1, H1b, H4 (§C.2).
  - §1.5: North Star provisório (F-14).
- [ ] **Passo 2:** §2.2: CAP reordenadas; CAP-17 nacional; CAP-18 "multiplicador"; CAP-20/21.
- [ ] **Passo 3:**
  - §4.1: linha `manifest`.
  - §6.2: Fase 2 com o estudo piloto e o critério de saída; Fase 3 com os canais do ADR-006.
  - §6.3: R6 (VPS do PRISM); R8 ("baixo alcance pelos canais"); **R9** novo ("rejeição ou suspensão na Play por política de saúde ou *misrepresentation*"; contingência: GitHub Releases continua).
- [ ] **Passo 4:** hierarquia com `implantacao.md`. Rodapé de aprovação: coordenação do projeto, revisor clínico responsável, encarregado. **Retirar** a nota "Transição (2026-11-02)" do cabeçalho do PRD e o parágrafo "Precedência durante a transição" do ADR-005: com o E2, PRD, espec e lgpd passam a dizer o mesmo.
- [ ] **Passo 5:** verificar com grep frásico. `grep -nE "2 UBS|UBS piloto|unidades piloto|gestor(es)? (municipa|da UBS|das unidades)|prefeituras?/ONGs|F-Droid" spec/PRD.md` deve sair vazio. Conferir também que cada trecho do PRD citado na §A sumiu ou foi reescrito.

*Aceite:* o grep sai vazio e o PRD cita os ADR-005 e 006.

### Tarefa 3: espec, brainstorm e protótipos (E2)

**Leia:** §A, §B (linhas espec, brainstorm, design), §C.2, §C.3, §E.3, §E.4.

**Arquivos:** `spec/espec.md`, `spec/brainstorm.md`, `spec/design.html`, `spec/design_selo_procedencia.html`.

- [ ] **Passo 1:** `espec.md` nos pontos da §B, usando as redações da §C.2 e da §C.3 e o rótulo F-15. Corrigir S3 ("job `packer` do compose", C19).
- [ ] **Passo 2:** `brainstorm.md` nos pontos de C0, C4, C8, C10, C12, C14 e C15. **Fica** a informação genérica e educativa sobre UBS, horários e farmácia. **Sai** a que depende de uma unidade específica.
- [ ] **Passo 3:** protótipos (§E.3, §E.4).
- [ ] **Passo 4:** verificar com grep frásico. `grep -nE "regras do posto|reglas del puesto|conteúdo municipal|QR na UBS|remédio disponível|farmácia da UBS|como marcar o dentista|curados por município|unidades piloto|Sua UBS na palma" spec/espec.md spec/brainstorm.md spec/design*.html` deve sair vazio. `grep -cE "RF-16|RF-17|RNF-10|RNF-11" spec/espec.md` deve dar ≥ 4.
- [ ] **Passo 5:** abrir os dois HTML no navegador. O protótipo navega, e a inicial tem ≤ 8 elementos acionáveis.

*Aceite:* os greps passam, o protótipo funciona e nenhuma linha de FSM, INV-1…7 ou RF-01…06 mudou de mérito (conferir com `git diff`).

### Tarefa 4: ADRs 004 (revisão) e 006–009, e o resto do `stack.md` (E2)

**Leia:** §A (linhas com `stack.md`, C19, C20), §B (linhas stack), §D (para os fundamentos dos ADRs), §F (classes P), §G, §J.3 ("Plano B", para a Revisão do ADR-001).

- [ ] **Passo 1:** ADR-004: acrescentar "**Revisão 2026-11-xx.**" e corrigir o Enquadramento, sem apagar o histórico.
- [ ] **Passo 2:** escrever os ADR-006 a 009 (§G), com **Custos aceitos** e as decisões provisórias em **Revisão**. O ADR-006 (canais) e o ADR-007 (VPS) **citam a Decisão 6 do ADR-005 como origem** e só detalham. Não reapresentam a decisão como nova: os dois canais e a VPS do PRISM vieram do pedido do dono do projeto, não de pergunta aberta.
- [ ] **Passo 3:** §1.1, §4.1 (incluindo "Turso" → `sqld`), §4.2, §5, §6, §7 (compose real, C19), §9, §11 e os fundamentos 4 e 5 do ADR-001. O fundamento 4 cita a política "assinatura só no CI" (`stack.md:314`), que faz parte da C19: passa a "assinatura pelo job `packer` sem porta, com a chave do cofre; exceção provisória na **Revisão** deste ADR (§J.3)". A **Revisão** do ADR-001 ganha o procedimento provisório da §J.3.
- [ ] **Passo 4:** `grep -c "^### ADR-" spec/stack.md` = 9. `grep -nE "admins municipais|servidores municipais|secretaria municipal" spec/stack.md` sai vazio. "F-Droid" pode aparecer no §9 e no ADR-006 **só** como canal futuro ou não previsto: o critério original o proibia fora do ADR-004 e contradizia o pedido da própria tarefa (corrigido na execução do E2).

*Aceite:* os nove ADRs existem e todo item P tem data em **Revisão**.

### Tarefa 7a: neutralização em `lgpd.md` e `docs/` (E2)

**Leia:** §A (C1, C9, C11, C15, C18), §B (linhas lgpd, revisao-golden, operacao), §E.2 (só para saber o que **não** decidir).

Esta tarefa **não decide base legal**. Ela só remove pressuposições.

- [ ] **Passo 1:** `spec/lgpd.md`:
  - "Secretaria", "admins municipais", "município do pack" e "suporte a municípios" → equipe do projeto / edição;
  - o controlador vira "[a definir — F-11]";
  - "provedor do VPS contratado" → "provedor da VPS do PRISM [F-1]".
  - Cada base legal atual ganha a marca "**em revisão (T7-R)**", sem trocar a base.
- [ ] **Passo 2:** `docs/revisao-golden.md`: Secretaria → coordenação do projeto; termo arquivado pelo "[responsável — F-11]".
- [ ] **Passo 3:** `docs/operacao.md`: só o que já é verdade no código: `-f compose.yaml`, "manifest da edição", "estudo piloto".
- [ ] **Passo 4:** `npm --workspace @guia-ubs/cms test -- doc-operacao` deve dar PASS.
- [ ] **Passo 5:** `grep -nE "Secretaria (Municipal|indica|arquiv)|admins? municipa|indicad[oa]s? pela Secretaria" spec/lgpd.md docs/revisao-golden.md docs/operacao.md` deve sair vazio.
- [ ] **Passo 6:** PR do E2 com T2, T3, T4 e T7a. Os commits seguem essa ordem, um por tarefa, para o revisor ler commit a commit. A descrição segue a T11, Passo 4.

*Aceite:* os greps passam, o `doc-operacao` está verde e nenhuma base legal foi trocada.

### Tarefa 5: `spec/implantacao.md` (E3)

**Leia:** §D inteira, §F (classes M e P), §G (ADR-001 revisão, 006, 007, 009), §J.3 ("Plano B").

- [ ] **Passo 1:** transcrever a §D como texto normativo com as respostas da T0:
  1. Princípios (ADR-005 a 009);
  2. APK;
  3. VPS;
  4. Responsabilidades por papel;
  5. Critérios de RNF-10 e RNF-11.
  - Cada regra da Play leva a nota "(conferir no console em AAAA-MM-DD)".
- [ ] **Passo 2:** no topo, declarar que o documento é normativo e que o procedimento operacional vai para `docs/operacao.md` quando o código existir.

*Aceite:*
- todo `[a definir — F-n]` remanescente corresponde a uma pergunta M ainda aberta;
- nenhuma pergunta B aparece como marcador;
- os limites do `versionCode` estão escritos;
- cada linha do checklist da Play tem a data de conferência a preencher.

### Tarefa 6: `arquitetura.md` (E3)

**Leia:** §A (C11, C14, C16), §B (linha arquitetura), §C.3 (tabela de itens).

- [ ] **Passo 1:** L54 e L62-66 (planejado, com o número do item); nota do ADR-008 na §4.3.
- [ ] **Passo 2:** Roadmap:
  - rótulos "pré-requisito de piloto" → "pré-requisito de release pública";
  - L736 e L763;
  - itens 21 e 22 com nota "absorvidos por 27 e 31";
  - itens 25, 27, 28, 30 e 31 (§C.3), cada um com link para `implantacao.md` e as dependências.
- [ ] **Passo 3:** PR do E3.

*Aceite:*
- `git diff spec/arquitetura.md` não remove linha de nenhuma §5.x;
- `grep -nE "pré-requisito de piloto" spec/arquitetura.md` sai vazio;
- os itens 25, 27, 28, 30 e 31 existem com dependência declarada.

### Tarefa 7-R: revisão jurídica (E4, gate)

**Leia:** §E.2, §F (F-9, F-11), §J.2.

- [ ] **Passo 1:** preparar um dossiê curto com a §E.2 deste plano, a tese central do `lgpd.md` e as perguntas F-11 e F-9.
- [ ] **Passo 2:** submeter ao encarregado ou à assessoria jurídica (classe I). Registrar quem revisou (por papel), a data e o parecer resumido. **Não** registrar nomes no repositório público, conforme a regra dos revisores golden.
- [ ] **Passo 3:** registrar também a leitura de RDC 657/2022 e da *Health apps declaration* que a revisão confirmar.
- [ ] **Passo 4:** o dossiê explica a distinção entre **responsável pelo app** e **controlador de dados**. Os termos (versão `2026-11-02`) dizem "Responsável: PRISM, da UFRR", e a privacidade diz "controlador: [a definir — F-11]". Não é contradição: são papéis distintos (quem mantém e distribui o app × quem decide sobre o tratamento de dado pessoal, LGPD art. 5º, VI). A pergunta ao parecer é se o controlador será a mesma entidade ou outra, para que a resposta à F-11 venha alinhada com os dois documentos.

*Aceite:* existe um parecer com data. Sem ele, a T7b e a T8b não começam. A T8a não depende dele.

### Tarefa 7b: bases legais e controlador (E4)

**Leia:** §E.2, o parecer da T7-R, §G (ADR-004 e 005).

- [ ] **Passo 1:** aplicar no `lgpd.md` **só** o que o parecer aprovou: controlador, encarregado, bases legais, RF02 (TCLE/CEP), RF06/RF17 (operadores e terceiros, incluindo GitHub e Play), RF07, RF08, RF10/DOC02, revisores e RIPD.
- [ ] **Passo 2:** emendar o ADR-005 (controlador) e o ADR-004 (responsável).
- [ ] **Passo 3:** a marca "em revisão (T7-R)" sai de toda base aprovada. A base não aprovada continua marcada.
- [ ] **Passo 4:** PR do E4.

*Aceite:* toda base legal no `lgpd.md` está aprovada pelo parecer ou explicitamente marcada; o controlador está nomeado.

### Tarefa 8a: textos ao usuário que não dependem do parecer (E5, exceção de código)

**Leia:** §A (C0, C2, C5, C8, C13), §C.3 (RF-16), §E.1, §E.2 (parte "T8a"), §E.3, §F (F-0, F-13, F-15).

**Arquivos:**
- Modificar: `app/lib/l10n/app_{pt,es}.arb`; `app/assets/legal/{termos,privacidade}_{pt,es}.md`; `app/lib/ui/more/about_screen.dart` (só a string L377 e a exibição de `aboutNoAffiliation`).
- Testes:
  - `app/test/ui/more/no_endorsement_test.dart`;
  - `app/test/ui/more/legal_documents_test.dart`;
  - `app/test/ui/legal/terms_gate_test.dart`;
  - `app/test/ui/privacy/privacy_screen_test.dart`;
  - `app/test/ui/more/about_screen_test.dart`, só se a F-13 liberar o logo do PET-Saúde.

**Interfaces:**
- Produz a chave ARB `aboutNoAffiliation` (pt/es), o texto novo de `provenanceRules`/`provenanceRulesOnly` e o `appTitle` da F-0.
- Produz também as constantes de versão esperada nos testes (Passo 1).
- `provenanceFor` não muda.

- [ ] **Passo 1: testes que falham primeiro.**
  - **`no_endorsement_test.dart`:**
    - Trocar a proibição global de "UFRR" por uma **allowlist de origens**: as chaves `aboutCooperationCredit` e `aboutNoAffiliation` e a seção "Responsável" de termos e privacidade. A negação de endosso do Google fica intacta.
    - Novo teste: `'nenhum texto atribui regra, decisão ou configuração a posto ou unidade'`. Ele percorre todo ARB e documento legal com estes padrões, todos com `caseSensitive: false`:
      ```dart
      // (1) regra/decisão/configuração "de/do/da/del/de la" unidade
      RegExp(r'\b(regras?|reglas?|decis(ão|ões|ión|iones)|configura(ção|ções|ción|ciones))\s+'
             r'(d[oa]|de|del|de la)\s+(sua\s+|tu\s+|su\s+)?'
             r'(posto|puesto|UBS|unidade|unidad|centro de salud)\b', caseSensitive: false)
      // (2) unidade ou administrador que libera/configura/autoriza DADOS, REDE ou APARELHO,
      //     ou que "não tem Wi-Fi": a gestão do aparelho atribuída a uma unidade
      RegExp(r'\b(o|a|el|la)\s+(posto|puesto|UBS|unidade|unidad|administrador)\s+'
             r'(?:(?:liber|configur|autoriz)\w*\b[^.]{0,40}?\b'
             r'(dados|datos|rede|red|aparelho|aparato|celular|downloads?|baixar|descargar|Wi-?Fi)\b'
             r'|não tem Wi-?Fi\b|no tiene Wi-?Fi\b)',
             caseSensitive: false)
      // (3) voz passiva: download/dados/Wi-Fi/aparelho "liberado pelo posto"
      RegExp(r'\b(downloads?|descarga|dados móveis|datos móviles|Wi-?Fi|aparelho|aparato)\b'
             r'[^.]{0,30}?\b(liberad|autorizad|configurad|habilitad)\w*\s+'
             r'(pel[oa]|por\s+(el|la))\s+(posto|puesto|UBS|unidade|unidad|administrador)\b',
             caseSensitive: false)
      ```
      O `\b` no fim do grupo de complemento é obrigatório. Sem ele, `red` casa dentro de "redução" e "A unidade autoriza a redução da dose" reprovaria (conferido).
      "orientação" fica **fora** do grupo de propósito: "siga as orientações da sua UBS" é conteúdo educativo.

      `permit*` e `habilit*` também ficam fora, e `liber|configur|autoriz` só reprovam com um complemento de dados, rede ou aparelho. Motivo: "A UBS permite levar acompanhante" e "a UBS autoriza a retirada do remédio por outra pessoa" são informação educativa sobre o SUS.

      Os três padrões e o corpus abaixo foram conferidos em Python (`re.I|re.A`, a mesma fronteira de palavra ASCII do Dart) ao escrever este plano: zero permitida reprova, zero proibida passa. O executor confere de novo em Dart no Passo 2.
    - Novo teste **corpus** `'padrões frásicos: permitidas passam, proibidas reprovam'`, com duas listas constantes no próprio teste:
      - **Permitidas** (nenhum padrão casa):
        - "Procure o posto de saúde mais próximo."
        - "Siga as orientações da sua UBS."
        - "A UBS costuma atender em horário comercial; confirme na sua."
        - "Leve o cartão do SUS ao posto."
        - "Busque el puesto de salud más cercano."
        - "Siga las orientaciones de su UBS."
        - "A UBS permite levar acompanhante."
        - "A unidade habilita a vacinação sem agendamento."
        - "La unidad permite llevar acompañante."
        - "A UBS autoriza a retirada do remédio por outra pessoa com receita."
        - "A unidade autoriza a redução da dose."
        - "O exame é autorizado pela UBS."
        - "La vacuna es autorizada por la unidad."
      - **Proibidas** (ao menos um padrão casa):
        - "Orientação das regras do posto"
        - "Regras da UBS"
        - "Se o posto liberou baixar por dados móveis"
        - "Ligue se o posto não tem Wi-Fi"
        - "Decisão da unidade"
        - "Reglas del puesto"
        - "Si el puesto no tiene Wi-Fi"
        - "Configuración de la unidad"
        - "O administrador configurou o aparelho"
        - "Si el puesto autorizó descargar por datos móviles"
        - "Download liberado pelo posto"
        - "Descarga autorizada por el puesto"
        - "A UBS liberou os downloads"

      Se uma frase nova legítima reprovar, ela entra na lista de permitidas **e** o padrão é corrigido no mesmo PR.
  - **`legal_documents_test.dart`:**
    - Os termos pt/es contêm a cláusula de não afiliação. O PET-Saúde só é citado se a F-13 permitir.
    - A seção de contato e responsável da privacidade pt/es contém **exatamente** o marcador `[a definir — F-11]`. Isso substitui a asserção "≠ A ser preenchido": o texto antigo reprova, e um nome inventado também reprova.
    - A privacidade cita o servidor de conteúdo do projeto como destino de rede.
    - **Versão por constante, não por histórico** (o teste não enxerga o git):
      ```dart
      const versaoEsperadaTermos = '2026-11-xx';       // bumpada pelo PR junto com o documento
      const versaoEsperadaPrivacidade = '2026-11-xx';
      ```
      O teste afirma que o `<!-- versao -->` de cada documento é **igual** à constante. Um documento editado sem bump continua igual à constante, então o teste não pega sozinho. Quem pega é a revisão, e o template de PR do plano 2 (§I) traz o lembrete "mexeu em `assets/legal/`? bumpe o documento **e** a constante".
  - **`terms_gate_test.dart`:**
    - O gate mostra `aboutNoAffiliation`.
    - Quem aceitou a versão anterior vê o gate de novo. Esse teste já existe e só passa a usar a constante nova.
  - **`privacy_screen_test.dart`:** a lista declarada usa a redação nova de `privacyStoredMetered`.
- [ ] **Passo 2:** `cd app && flutter test test/ui/more test/ui/legal test/ui/privacy`. Esperado: FAIL nos testes novos. O corpus passa nas permitidas e reprova pelo texto atual nas proibidas.
- [ ] **Passo 3:** editar ARB e Markdown (§E.1, §E.2 parte T8a, §E.3, C13). O texto de `aboutNoAffiliation` (RF-16) diz **explicitamente que apoio institucional não é responsabilidade institucional**. O logo do Telessaúde UFRR na tela "Sobre" fica (ADR-005, Decisão 1), e para quem lê pouco o logo diz o contrário da frase "a UFRR não responde pelo app". Por isso o aviso fica **ao lado** dos logos, e o `about_screen_test` confere que os dois aparecem na mesma tela. Avançar o `<!-- versao -->` dos quatro documentos e as constantes (**1º bump**).
- [ ] **Passo 4:** `flutter pub get && flutter analyze --fatal-infos && flutter test`. Esperado: tudo verde, incluindo `accessibility_test.dart` e `lgpd_surface_test.dart`.
- [ ] **Passo 5:** instalar no aparelho e conferir gate, Sobre, privacidade e selo, em pt e es, retrato e paisagem.
- [ ] **Passo 6:** PR do E5.

*Aceite:*
- suíte verde e corpus verde;
- `git diff --stat` só mostra os arquivos listados;
- o marcador F-11 está presente nos dois idiomas;
- conferência no aparelho registrada no PR.

### Tarefa 8b: controlador e bases legais na política de privacidade (E7, exceção de código)

> **Para o E7, tela de download do modelo (revisão do #74):** a frase "servidor fora do Brasil" entra acompanhada do **tamanho em MB** e da palavra **"opcional"**. "Módulo de idiomas" não diz à pessoa que são 800 MB, nem que o app funciona sem eles, e a frase sobre o país sozinha não resolve isso.
>
> **Decidido no #66 (2026-11-02), não reabrir no E7:** o gate (`termsGateBody`) diz "Grupo de Pesquisa PRISM, da UFRR". Está em `origensQueCitamUfrr` e, via `ufrrSoNaFrase`, a UFRR só pode aparecer nessa frase. O ajuste de dados móveis diz "Ative", e "ligue" fica reservado ao 192. Um guarda reprova o contrário.

**Leia:** §E.2 (parte "T8b"), o `lgpd.md` aprovado na T7b.

**Arquivos:**
- Modificar: `app/assets/legal/privacidade_{pt,es}.md`, e os `termos_{pt,es}.md` só se o parecer mexer no "Responsável".
- Testes: `app/test/ui/more/legal_documents_test.dart`, `app/test/ui/legal/terms_gate_test.dart`.

**Interfaces:** consome o controlador, o encarregado e as bases legais aprovadas da T7b.

- [ ] **Passo 1: o teste falha primeiro.**
  - Em `legal_documents_test.dart`, a asserção do marcador **troca de lado**: agora a privacidade **não** contém `[a definir — F-11]` e contém o nome do controlador e o canal do encarregado, como constantes no teste copiadas do `lgpd.md` aprovado.
  - As constantes de versão avançam (**2º bump**).
- [ ] **Passo 2:** `flutter test test/ui/more/legal_documents_test.dart`. Esperado: FAIL.
- [ ] **Passo 3:** escrever na política a seção de controlador e encarregado e a de bases legais, **literalmente** a partir do texto aprovado na T7b, e avançar as versões.
- [ ] **Passo 4:** `flutter analyze --fatal-infos && flutter test`. Esperado: verde. O `terms_gate_test` prova o 2º reaceite.
- [ ] **Passo 5:** conferir no aparelho a política e o reaceite, nos dois idiomas.
- [ ] **Passo 6:** PR do E7.

*Aceite:*
- nenhum `[a definir — F-11]` restante nos textos ao usuário;
- texto idêntico ao aprovado;
- suíte verde;
- reaceite visto no aparelho.

### Tarefa 9: README, CLAUDE.md, PROGRESS.md (E6)

**Leia:** §A (C0, C4, C5, C14), §B (linha README/CLAUDE/PROGRESS), §D.1 (armadilhas), §E.1, §G.

- [ ] **Passo 1:** README:
  - abertura na ordem da §E.1;
  - "Quem faz";
  - "Instalar" (GitHub Releases com SHA-256, Play, aviso de canais);
  - hierarquia com `implantacao.md`;
  - L246.
- [ ] **Passo 2:** CLAUDE.md:
  - "Estado do repositório" com link ao ADR-005;
  - hierarquia;
  - rótulo do selo;
  - seção "Release e implantação" com as armadilhas novas: `applicationId` imutável na Play; override do compose na VPS; limites do `versionCode`.
- [ ] **Passo 3:** PROGRESS.md: o marco deixa de ser "piloto em UBS".

*Aceite:*
- `grep -nE "piloto em UBS|regras do posto|pré-requisito de piloto" README.md CLAUDE.md PROGRESS.md` sai vazio;
- os três apontam para `spec/implantacao.md` e para o ADR-005;
- todo link relativo resolve: `grep -ohE "\]\([^)#]+\.md" README.md CLAUDE.md PROGRESS.md`, e cada alvo existe.

### Tarefa 11: varredura por estágio

**Leia:** §A (tabela C0–C21), as restrições globais (categorias de serviço permitidas).

- [ ] **Passo 1:** no fim de cada estágio, rodar sobre os arquivos do PR:
  ```sh
  grep -nE "regras do posto|reglas del puesto|piloto em UBS|UBS piloto|unidades piloto|indicad[oa]s? pela Secretaria|Secretaria Municipal de Saúde \(controladora\)|admins? (de conteúdo )?municipa|se o posto liber|si el puesto|QR na UBS|br\.gov\.exemplo" <arquivos do PR>
  ```
  Esperado: vazio. A exceção é `br.gov.exemplo` até o item 25, que deve estar anotado como pendência em `arquitetura.md`.
- [ ] **Passo 2:** `npm test && npm run typecheck` sempre. `cd app && flutter analyze --fatal-infos && flutter test` no E5 e no E7.
- [ ] **Passo 3:** cada trecho citado na §A que pertence aos arquivos do estágio foi reescrito ou justificado como categoria de serviço do SUS.
- [ ] **Passo 4:** a descrição do PR traz a tabela **C0–C21**:
  - colunas: conflito, situação (resolvido neste PR / resolvido em PR anterior / estágio futuro / fora do plano), commit que o resolve;
  - no E2, os commits internos seguem a ordem T2 → T3 → T4 → T7a, e a tabela aponta o commit de cada conflito, para o revisor ler commit a commit;
  - a tabela também lista as perguntas P adotadas no PR, cada uma com a data de revisão registrada no ADR.

*Aceite:* grep vazio, suítes verdes e tabela C0–C21 completa na descrição do PR.

### Tarefa 12: registro histórico e GitHub (E6)

**Leia:** §B (linha das issues), §C.3 (itens 25, 27, 28, 30 e 31).

- [ ] **Passo 1:** colocar a nota "Superado pelo ADR-005 em 2026-11-02; ver plano 2026-11-02" no topo dos planos e issues de 2026-10-28 (P0-2, P1-5, P1-8, P1-9, P1-10, P2-7, P2-8, `_epica.md`, `levantamento`, `p0-2`) e do plano P1-1 (gatilho disparado).
- [ ] **Passo 2:** **com confirmação do mantenedor** (ação externa):
  - editar a descrição do marco "Piloto" e os corpos dessas issues no GitHub;
  - abrir issues para os itens 25, 27, 28, 30 e 31;
  - fechar a P2-11 como absorvida por 27/28.
- [ ] **Passo 3:** PR do E6, junto com a T9.

*Aceite:* toda issue ou plano que cita Secretaria ou UBS como parceiro tem a nota; as issues novas existem (se confirmado).

---

## J. Caminho mínimo para o estudo piloto

Depois deste plano, as especificações estão alinhadas, mas **ainda não existe APK assinado nem servidor de conteúdo**. Esta seção mostra o que falta, quantos planos isso custa e qual é o gargalo real. Nada aqui é tarefa deste plano.

### J.1 O gargalo: a revisão clínica dos 24 casos golden

O packer **recusa assinar** sem a revisão clínica da suíte golden (`docs/revisao-golden.md`, P0-2). Isso decide quando o estudo com conteúdo acontece:
- a revisão depende de profissionais voluntários com registro ativo;
- não tem data;
- nenhum plano de engenharia a acelera.

O que se pode fazer é **começá-la já**, em paralelo com tudo o mais: recrutamento dos revisores pela coordenação do projeto e termo de colaboração arquivado pelo responsável F-11 (T7a já tira a Secretaria desse papel).

**Se o pack assinado não vier a tempo,** o estudo roda só com o conteúdo do seed embarcado, sem atualização. Ele ainda valida a compreensão da interface, os módulos educativos com o conteúdo semente, a triagem e o selo. Ele **deixa de validar** o fluxo de conteúdo: download do pack, verificação Ed25519, troca atômica, convergência da frota (H2). Também não exercita a correção de conteúdo publicada durante o estudo, que é metade do motivo de o conteúdo não morar no binário.

### J.2 Dois tipos de teste, dois portões

| | **Dogfooding interno** | **Estudo piloto com participantes externos** |
|---|---|---|
| Quem usa | Só a equipe do projeto (PRISM/PET-Saúde), ciente de que o texto legal está incompleto | Voluntários da comunidade |
| Deste plano | **E1, E2, E5** | **E1 a E7**: E7 é obrigatório |
| LGPD | Política com o marcador "[a definir — F-11]" é aceitável **só aqui**: ninguém de fora é titular de nada | O art. 9º exige identificar o controlador e o contato. Política com marcador **não serve**. Exige o **RIPD** pronto |
| Ética em pesquisa | Não se aplica | TCLE e parecer de CEP se a F-9 for "sim". O TCLE nomeia o responsável, o que também exige a F-11 respondida |
| Canal | Pre-release do GitHub ou faixa interna da Play | Faixa de teste fechado da Play e/ou pre-release do GitHub |

Assim a revisão jurídica volta ao caminho crítico **do estudo com participantes**, que é o lugar certo dela, e fica fora do caminho crítico **deste plano**.

### J.3 O que falta, além deste plano

| # | Entrega | Plano | Necessário para | Depende de |
|---|---|---|---|---|
| 1 | Revisão clínica golden (J.1) | processo existente | pack assinado | voluntários com registro; F-11 para o arquivamento |
| 2 | Item 25: id, keystore, `signingConfig`, ABIs sem split, guarda de `minAppBuild` | **plano A** | os dois tipos de teste | ADR-009; F-3, F-6 |
| 3 | Item 31 até a faixa de teste e a pre-release | **plano A** | os dois | 2; F-4 só para a Play. **Sem conta Play**, os dois testes rodam pela pre-release do GitHub |
| 4 | Conteúdo estático com `CONTENT_DOMAIN` real (`manifest.json` + pack) | **plano B** | fluxo de conteúdo | F-7; 1 |
| 5 | `MODEL_URL` de release | existente (ADR-004) | triagem com SLM (opcional) | 4, se o modelo sair do Hugging Face. Sem modelo, roda o `RuleOnlyEngine` (F-18) |
| 6 | RIPD | T7b + documento | estudo externo | F-11, T7-R |
| 7 | TCLE e protocolo no CEP | fora do repositório | estudo externo, se F-9 = sim | F-11 |

**Plano B: o TLS do host de conteúdo, antes de embarcar o nome.** `guiasaude.conteudo.prismrr.com.br` vai embarcado no APK, e servi-lo de um provedor de objeto exige **TLS nesse nome**. Nem todo bucket aceita domínio customizado com certificado, e às vezes é preciso um CDN ou um Caddy na frente. O plano B responde isso **antes** de o nome entrar no `defines.release.json`.

**Plano B: onde o pack é assinado enquanto a VPS não existe.**
- O CMS não é necessário: o app só lê arquivos estáticos, e o pack sai pelo **caminho `seed/`** (`npm run pack:build`, golden por YAML e atestados).
- A chave Ed25519 **continua fora de qualquer processo HTTP** e **fora de CI**. Pôr a chave privada num segredo do GitHub Actions a expõe a um terceiro e a qualquer workflow que alguém com escrita no repositório edite. Seria reabrir a C19 por outro caminho.
- **Procedimento provisório.** Assinar na máquina de um mantenedor, mas sem perder o segundo par de olhos. O dual review do compose garantia que ninguém assina sozinho, e o packer reprodutível (`SOURCE_DATE_EPOCH`) permite manter isso com um comando.
  1. Os dois mantenedores partem do **mesmo commit** (tag), com o mesmo `SOURCE_DATE_EPOCH` e o mesmo `PACK_VERSION`.
  2. **Mantenedor B** (sem a chave): `npm run pack:check` (`--dry-run`: portões verdes, sem assinatura) e `sha256sum` do `content.db` gerado. Publica o hash por um canal que fique registrado (comentário no PR da release de conteúdo).
  3. **Mantenedor A** (custódia): traz a chave do cofre **sem tocar disco persistente**: arquivo em `tmpfs` (`/dev/shm`, `umask 077`, com swap desligado ou cifrado, porque página de tmpfs pode ir para o swap) ou um descritor (`PACK_SIGNING_KEY_PATH=/dev/fd/3 … 3< <(comando-do-cofre)`). Roda `npm run pack:build` e remove o arquivo do tmpfs no fim, em `trap`, mesmo se falhar.
  4. **A** confere que o hash do `content.db` assinado (e o `packHash` do `manifest.json`) é **igual** ao publicado por **B**. Se diferir, nada é enviado.
  5. **A** envia ao host estático. **B** baixa o manifest publicado e confere a assinatura com a chave pública embarcada e o hash (a mesma verificação do job `interop`).
- **O plano B verifica, antes de adotar o procedimento:**
  - que `pack:check` deixa o `content.db` no mesmo caminho e com o mesmo hash que `pack:build`, ou seja, que a assinatura só toca o manifest;
  - que `resolveFromRepo` aceita um caminho absoluto como `/dev/fd/3`.

  Se qualquer um falhar, o procedimento é ajustado **antes** do 1º pack.
- **Registro:** o procedimento entra na **Revisão do ADR-001**, com referência cruzada no ADR-007, como "assinatura provisória fora da VPS, até o item 27". Ele **sai** quando o item 27 entrar e o job `packer` do compose passar a assinar. O `infra/.env.example` corrigido no E2 não volta a citar CI.

**Reaceite dos termos durante o estudo.** Se o E7 for mergeado com o estudo em andamento, os participantes verão o gate dos termos de novo. O protocolo do estudo e o TCLE (se houver) trazem a linha: "o app pode pedir que você aceite os termos de novo durante o estudo; isso não apaga nada do que você fez nem envia nada". Para o estudo externo, que já exige o E7 antes de começar, isso só acontece se os termos mudarem de novo durante o estudo.

**Total depois deste plano:**
- dois planos de engenharia (A: itens 25 e 31 até a faixa de teste; B: conteúdo estático com assinatura provisória);
- a revisão clínica golden, que é o gargalo;
- dois documentos de governança (RIPD; TCLE se for o caso).

Os itens 27, 28 e 30 e a promoção para produção na Play **não** são pré-requisitos do estudo.

---

## I. Plano 2 (fora deste): higiene de código aberto

Registrado aqui só para não se perder. Terá plano próprio, sem dependência com este, exceto onde indicado:

- `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `.github/ISSUE_TEMPLATE/`, template de PR. O template de PR inclui o lembrete "mexeu em `assets/legal/`? bumpe o `<!-- versao -->` **e** a constante `versaoEsperada*` do `legal_documents_test`".
- Titular da `LICENSE` e DCO (F-12, classe I).
- Texto "telemetria é enviada" (PRD §1.5, brainstorm M7, `privacyTelemetryBody`). Se a T8a já tiver mexido no ARB, a correção entra num PR próprio depois do E5.
- M3 < 3 s → 3–5 s (ADR-003).
- **Onboarding em pt e es** (`app/lib/ui/onboarding/onboarding_screen.dart`). Hoje a tela é só em português, inclusive o motivo `deviceUnsupported`. Esse motivo aparece justamente nos aparelhos 32-bit, os mais baratos, onde está parte do público hispanofalante de Roraima.
- Item 29: aceite do Termo de Uso do CMS no 1º login (`consent_record`, LGPD-RF02(b)/RF04). Depende do controlador definido na T7b.
- Status "PROPOSTA" em `arquitetura.md:4`; `app/README.md` de template.

---

## Autorrevisão

- **Cobertura do pedido original:**
  - inventário: §A e §B;
  - requisitos (sai, muda, entra): §C;
  - deploy: APK, versionamento com limites, ABIs, assinatura; VPS com backup, atualização, segurança, domínio e TLS (§D);
  - privacidade e termos, como propostas para revisão jurídica: §E;
  - ADRs: §G;
  - ordem, dependências, estágios e aceite em todas as tarefas: §H;
  - perguntas classificadas: §F.
- **Cobertura da revisão:**

  | Ponto | Onde foi tratado |
  |---|---|
  | 1. Nome do app | F-0 é a primeira pergunta B e bloqueia T1 e o item 25 |
  | 2. Classes de pergunta | B/P/M/I |
  | 3. Código no plano | Exceção declarada no topo, restrita a arquivos listados |
  | 4. Padrões amplos demais | Frásicos, com teste-sentinela |
  | 5. Commits × propagação | Regra aplicada ao merge; E2 junta PRD, espec, stack e lgpd |
  | 6. Decisões jurídicas e da Play | Propostas com gate T7-R e (Play@data) |
  | 7. Escopo | Plano 2 e seis estágios |
  | 8. ABIs e `minSdk` | F-17 |
  | 9. Modelo opcional | F-18 e item 30 |
  | 10. Acabamentos | Aceite em todas as tarefas, limites do `versionCode`, base `2ab9f93` com reconferência na T0 |

- **Cobertura da 2ª revisão:**

  | Ponto | Onde foi tratado |
  |---|---|
  | 1. Caminho crítico | T8 dividida em T8a (E5, logo após E2) e T8b (E7, após o parecer), com dois bumps aceitos; a T8a exige o marcador F-11 |
  | 2. F-13 e F-16 | Rebaixadas a P; só a F-0 bloqueia o E1 |
  | 3. Material da F-0 | §F.1: critérios, as duas opções, "SUS Fácil", candidatos; id neutro recomendado |
  | 4. Regex | Inclui "da"; "orientação" sai do grupo; corpus de 6 permitidas e 8 proibidas em pt/es |
  | 5. Promoção | Mesmo artefato, mesma tag e mesmo `versionCode`; *pre-release* no GitHub; sem PATCH de pré-release |
  | 6. ABIs | F-17 como P: 32-bit sem shim **e sem oferecer o download do modelo** |
  | 7. Versão no teste | Constante no teste, bumpada pelo PR; o limite está declarado, e o lembrete vai no template do plano 2 |
  | 8. Caminho mínimo | §J |
  | 9. Respostas operacionais | Registro fora do repositório; no plano, só a data |
  | 10. PR do E2 | Commits na ordem T2→T3→T4→T7a; tabela C0–C21 na descrição |

- **Cobertura da 3ª revisão:**

  | Ponto | Onde foi tratado |
  |---|---|
  | 1. Estudo sem controlador | §J.2: dogfooding interno (E1, E2, E5) × estudo externo (E7 + RIPD + TCLE) |
  | 2. `--split-per-abi` | Confirmado no SDK (`FlutterPlugin.kt:669-674`); um build por ABI sem split; colisão com a fórmula declarada; verificação no plano A antes do ADR-009; `minAppBuild` hoje não é conferido em lugar nenhum, e a guarda vai para o item 25 |
  | 3. Onde o plano B assina | §J.3: máquina de mantenedor com chave do cofre, nunca CI; sai com o item 27; registrado no ADR-007 |
  | 4. Gargalo golden | §J.1 abre a seção, com o que o estudo valida e o que deixa de validar só com o seed |
  | 5. `permit`/`habilit` | Fora do padrão (2); `liber/configur/autoriz` só com complemento de dados, rede ou aparelho; 4 permitidas e 2 proibidas a mais no corpus, conferidas em Python |
  | 6. Reaceite no estudo | §J.3, com a frase para o protocolo e o TCLE |
  | 7. Acabamentos | Critério 2 da §F.1 relaxado e candidatos avaliados contra ele; id neutro já decidido na linha da F-3 |

- **Cobertura da 4ª revisão:**

  | Ponto | Onde foi tratado |
  |---|---|
  | 1. `\b` final e voz passiva | Padrão (2) com `\b` no fim; padrão (3) para a voz passiva; 3 permitidas e 3 proibidas a mais no corpus; o furo do "redução" foi confirmado no padrão antigo e some no novo (conferido em Python) |
  | 2. Segundo par de olhos | §J.3: B reconstrói com `pack:check` e publica o hash, A assina e confere, B verifica a assinatura publicada; chave em tmpfs (com swap desligado ou cifrado) ou por descritor; duas premissas a verificar no plano B |
  | 3. ADR certo | A exceção mora na **Revisão do ADR-001**, e o fundamento 4 dele ("assinatura só no CI", `stack.md:314`) entra na C19. O ADR-007 só aponta para lá |
  | 4. Entrega a subagentes | Resumo executivo no topo e linha **Leia:** em cada tarefa |

- **Consistência:** RF-16/17, RNF-10/11, CAP-20/21, itens 25, 27, 28, 30 e 31, ADR-005…009, F-0…F-18 e E1…E7 têm o mesmo significado em todas as seções. O item 29 e a F-12 aparecem só na §I.
