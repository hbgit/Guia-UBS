# Guia UBS — Brainstorm do Projeto

## Nome do Conceito

**Guia UBS** — direto, memorável e autoexplicativo para o público brasileiro. "UBS" no nome designa a **categoria de serviço do SUS** sobre a qual o app ensina, não uma unidade parceira.

- **Tagline:** *"Entenda o SUS e saiba onde buscar atendimento, mesmo sem internet."*
- **Decisão do nome (F-0, 2026-11-02; [ADR-005](stack.md), Decisão 5):** o nome fica, com aviso obrigatório de não afiliação e de caráter educativo no 1º uso, na tela Sobre e na ficha das lojas ([espec](espec.md) RF-16). Alternativas que soavam como canal oficial do SUS ou de um posto foram descartadas. O risco de o nome ser lido como oficial está registrado nos Custos aceitos do ADR-005.
- **Quem faz:** projeto educativo e de código aberto do Grupo de Pesquisa PRISM (UFRR), em cooperação com o PET-Saúde: Inovação e Saúde Digital (Núcleo de Telessaúde UFRR). **Sem vínculo com unidades de saúde, secretarias ou prefeituras.**

## Pitch de Uma Frase

Um guia visual e por voz de **educação em saúde** que roda 100% offline no celular e ensina — apenas com toques em ícones — moradores de áreas rurais, imigrantes e pessoas de baixo letramento a entender o SUS: o que cada serviço faz, que documentos levar e quais sinais de alerta pedem emergência; como apoio secundário, uma IA local ajuda a decidir onde buscar atendimento.

## Problema Central

O acesso à Atenção Primária no Brasil é travado por três barreiras simultâneas:

1. **Barreira de conectividade:** grande parte das áreas rurais e periféricas tem internet restrita ou inexistente, inviabilizando apps convencionais que dependem de nuvem.
2. **Barreira de letramento (digital e textual):** interfaces baseadas em texto e formulários excluem usuários com baixa alfabetização ou pouca familiaridade com smartphones.
3. **Barreira linguística e de conhecimento do sistema:** imigrantes hispanofalantes e populações indígenas não sabem distinguir UBS, UPA e hospital, quais documentos levar, nem quais serviços são gratuitos — resultando em deslocamentos inúteis (às vezes de horas), sobrecarga das UPAs com casos de atenção básica e abandono de tratamentos e vacinação.

A dor concreta: **pessoas perdem dias de trabalho e viagens longas para descobrir, no balcão, que estavam no lugar errado, sem o documento certo ou fora do horário do serviço.**

## Conceito e Escopo

### Propósito

Promover **educação social em saúde** sobre o SUS e a Atenção Primária — direitos, documentos, sinais de alerta e o papel de cada serviço (UBS, UPA, hospital) —, com entrada exclusivamente por **ícones e imagens** e resposta **multimodal (visual + áudio)** em português, espanhol e línguas indígenas locais, tudo rodando no dispositivo (offline-first). A **Edge AI** (um agente local) entra como apoio **secundário**: ajuda a pessoa a decidir onde buscar atendimento, sempre sob a camada de regras de segurança.

### Usuários-alvo

| Perfil | Necessidade principal |
|---|---|
| Moradores de áreas rurais | Entender antes de se deslocar: que serviço procurar, que documento levar, o horário típico de funcionamento (a confirmar na própria unidade) e o que a Farmácia Básica do SUS costuma oferecer |
| Imigrantes hispanofalantes | Entender o SUS (UBS vs. UPA), direitos e documentação aceita |
| Populações indígenas | Orientação em áudio na própria língua, sem depender de texto |
| Pessoas com baixa alfabetização | Navegar por ícones, sem ler nem digitar nada |
| Multiplicadores comunitários — ACS, educadores, voluntários do PET-Saúde (uso indireto) | Material de apoio educativo em conversas e ações comunitárias, sem uso institucional por equipe de unidade |

### O que o app faz (escopo v1)

- Educação visual sobre a divisão do SUS (UBS vs. UPA/Hospital) — foco primário.
- Orientação de documentos, fluxo típico de atendimento, Farmácia Básica (elenco nacional), calendário vacinal, saúde da mulher/pré-natal e programas sociais.
- Como apoio secundário: triagem visual de sintomas com decisão UBS vs. emergência (IA local sob regras de segurança).
- Respostas com ícones + síntese de voz offline.
- Atualização silenciosa de conteúdo quando houver qualquer janela de conectividade.

### O que o app NÃO faz (fora de escopo)

- **Não faz diagnóstico médico** — apenas orientação de encaminhamento (disclaimer permanente).
- Não agenda consultas nem acessa prontuários (sem integração com sistemas do SUS na v1).
- Não fala por nenhuma unidade de saúde, secretaria, prefeitura ou pelo Ministério, e não traz dado de uma unidade específica (estoque, agenda, horário daquela UBS): o conteúdo é educativo e de alcance nacional.
- Não coleta dados pessoais identificáveis — nenhum cadastro é exigido.
- Não substitui o Meu SUS Digital; o complementa onde ele não chega (offline + baixo letramento).

## Principais Funcionalidades

> A numeração é histórica (roadmap e código citam as funcionalidades por número). A ordem de importância é outra: as funcionalidades educativas (2, 3, 6, 4, 5, 7, 8) são o núcleo, e a triagem (1) é apoio secundário ([ADR-005](stack.md), Decisão 2).

1. **Triagem Visual Baseada em Sintomas (Chatbot Local):** o usuário compõe frases visuais tocando em ícones de partes do corpo + sintomas (cabeça + raio = dor de cabeça; termômetro = febre). O modelo de IA local interpreta a combinação e responde: "vá à UBS" ou "procure emergência". É apoio à decisão de onde buscar atendimento, nunca diagnóstico.
2. **Guia de Encaminhamento UBS vs. UPA/Hospital:** fluxogramas de ícones e animações simples ensinam a divisão do SUS — corte leve/vacina → imagem da UBS; acidente grave/dor no peito → imagem do Hospital/UPA.
3. **Orientador de Documentação Necessária:** ao tocar no serviço desejado, o app exibe fotos ilustrativas dos documentos exigidos (Cartão SUS, identidade/passaporte, comprovante de residência).
4. **Navegador da Farmácia Básica:** ícones de condições (coração = hipertensão, gota de sangue = diabetes) explicam visualmente quais medicamentos o SUS oferece gratuitamente na Farmácia Básica (elenco nacional, RENAME) e o que levar para retirá-los. Não mostra estoque: a disponibilidade varia, e o app orienta a perguntar na recepção.
5. **Calendário Vacinal Interativo:** perfis por ícone (bebê, criança, adulto, gestante, idoso) exibem as vacinas devidas com símbolos universais de proteção e tempo.
6. **Fluxo Típico de Atendimento na UBS:** cartões visuais sequenciais do passo a passo **comum** na Atenção Primária: Recepção → Acolhimento → Consulta → Pós-consulta/Farmácia. Descreve o caminho típico, não o de uma unidade específica.
7. **Módulo de Saúde da Mulher e Pré-Natal:** ao selecionar o ícone da gestante, o app mostra os serviços garantidos (testes rápidos, exames de rotina, ultrassom, vitaminas) e reforça o acompanhamento regular.
8. **Orientador de Programas Sociais e Saúde:** seção visual dos programas ligados à Atenção Primária (condicionalidades do Bolsa Família, saúde bucal) — ex.: tocar na escova de dentes explica que a saúde bucal faz parte do atendimento da UBS e que o agendamento se pergunta na recepção.
9. **Resposta Multimodal (Visual + Áudio Offline):** toda resposta combina ícones com Text-to-Speech rodando no dispositivo, em português, espanhol ou línguas indígenas locais.
10. **Sincronização Assíncrona de Oportunidade:** invisível ao usuário — ao detectar qualquer conectividade (Wi-Fi de escola, centro comunitário), baixa em segundo plano atualizações de conteúdo (campanhas nacionais de vacinação, conteúdo educativo revisado) e atualiza a base de conhecimento local, voltando a operar 100% offline.

## Fluxo do Usuário

1. **Primeira abertura (única vez, offline):** o usuário toca na bandeira/ícone do idioma (🇧🇷 / 🇪🇸 / símbolo da etnia local). Sem cadastro, sem formulário — o app já está pronto.
2. **Tela inicial:** grade minimalista de 6–8 ícones grandes, com os módulos educativos primeiro (prédio = onde ir; interrogação = como funciona a UBS; documentos; pílula = farmácia; seringa = vacinas; gestante; escova de dentes) e corpo humano = sintomas como apoio.
3. **Interação por triagem (exemplo):** toca no corpo humano → toca na cabeça → toca no ícone de raio (dor) e no termômetro (febre) → o chatbot local processa a combinação.
4. **Resposta multimodal:** o app exibe o cartão-resposta (ícone da UBS + ícone de sol indicando "vá amanhã de manhã" OU ícone da ambulância/UPA em vermelho) e reproduz o áudio na língua escolhida: *"Procure a UBS amanhã pela manhã e leve estes documentos."*
5. **Encadeamento contextual:** a resposta oferece próximos passos em ícones — "quais documentos levar?" e "como é o atendimento?" — mantendo o usuário em um fluxo guiado, sem becos sem saída.
6. **Sincronização invisível:** dias depois, ao passar pela escola com Wi-Fi, o app baixa silenciosamente a nova campanha de vacinação; na próxima abertura (offline), o calendário vacinal já exibe o aviso.

## Estilo Visual

**Minimalista e de altíssima legibilidade**, projetado para sol forte, telas baratas e mãos calejadas:

- Ícones grandes (alvo de toque ≥ 64 dp), traço único, alto contraste, sem ambiguidade cultural (validados em campo).
- Máximo de 8 elementos por tela; navegação sempre com botão "voltar" e "casa" visuais.
- Paleta reduzida com semântica fixa: **verde = UBS/rotina**, **vermelho = emergência**, **azul = informação**.
- Zero texto obrigatório: qualquer rótulo textual é redundante ao ícone e ao áudio.
- Animações apenas funcionais (fluxogramas), nunca decorativas — economia de bateria e de atenção.

## Diferenciais

1. **Genuinamente offline:** os apps oficiais (Meu SUS Digital) e as soluções de telessaúde **exigem internet e login**. O Guia UBS funciona onde eles não chegam, e complementa — não substitui — os canais oficiais.
2. **Interface 100% iconográfica com resposta por voz:** nenhuma solução de saúde pública brasileira atende simultaneamente analfabetos funcionais, imigrantes e povos indígenas. A curadoria de ícones validados com o público + TTS em línguas locais é o diferencial central.
3. **Arquitetura de sincronização de oportunidade:** o modelo "conteúdo empacotado + delta updates em segundos de conectividade" cria confiabilidade que soluções cloud-first não conseguem imitar sem reescrever sua arquitetura.
4. **Custo marginal próximo de zero:** sem servidores de inferência (a IA roda no aparelho), o custo por usuário é quase nulo — viabiliza distribuição pública e gratuita (GitHub Releases e Google Play) por um projeto acadêmico, sem orçamento de nuvem e sem depender de quem compre o app.
5. **Neutralidade de dados:** por não coletar dados pessoais, elimina barreiras de LGPD e de confiança — crítico para imigrantes em situação migratória irregular, que evitam apps oficiais.
6. **Aberto e auditável:** código público; qualquer pessoa pode conferir as regras de segurança e a procedência do APK ([espec](espec.md) RF-17).

## Uso Criativo de Tecnologias Emergentes

- **SLM local (Small Language Model):** um modelo compacto quantizado (ex.: Gemma/Phi via llama.cpp ou MediaPipe LLM Inference) roda no dispositivo. Os ícones selecionados são convertidos em tokens estruturados (`[dor][cabeça][febre]`) que o modelo interpreta contra uma base de conhecimento local (RAG offline sobre os protocolos da Atenção Básica), gerando o encaminhamento.
- **Camada de segurança determinística:** combinações de "sinais de alarme" (dor no peito + falta de ar) são resolvidas por regras fixas ANTES do LLM — a IA nunca decide sozinha um caso de emergência. LLM para nuance, regras para segurança.
- **TTS neural on-device:** vozes sintetizadas embarcadas (pt/es); para línguas indígenas sem TTS disponível, áudios gravados por falantes nativos servidos pelo mesmo pipeline multimodal.
- **Atualização de conhecimento sem atualizar o app:** a sincronização de oportunidade baixa apenas o **pacote de conteúdo versionado** (base RAG + áudios + calendários), não o binário — atualizações de campanhas de vacinação chegam em kilobytes.

## Pré-requisitos

- **Obrigatório:** conhecimentos básicos de programação em **Flutter/Dart** (app multiplataforma Android-first).
- **Vantajoso, não obrigatório:**
  - Familiaridade com **Hugging Face Transformers** e quantização de LLMs (GGUF/ONNX).
  - Noções de SQLite/armazenamento local e de background tasks (WorkManager).
  - Experiência com design acessível/iconografia.
- **Infraestrutura mínima:** uma VPS mantida pelo PRISM, com o CMS e um servidor de arquivos estáticos (MinIO + Caddy) para os pacotes de conteúdo ([stack](stack.md) ADR-005/ADR-007) — nenhum backend dinâmico no caminho do usuário. Nada depende de infraestrutura de unidade de saúde nem da UFRR.

## Marcos de Entrega (Milestones)

### M1 — Wireframes (Semanas 1–2)

- Mapear os 6 fluxos principais (encaminhamento, documentos, fluxo típico da UBS, farmácia, vacinas e, como apoio, triagem) em wireframes de baixa fidelidade.
- Definir a gramática visual: catálogo inicial de ~60 ícones com significado único.
- **Critério de saída:** fluxos navegáveis em papel/Figma validados com 3–5 usuários representativos (incluindo ao menos 1 pessoa de baixo letramento).

### M2 — Protótipo Funcional de UI/UX (Semanas 3–5)

- Protótipo interativo de alta fidelidade (Figma) com a identidade minimalista final.
- Teste de usabilidade sem mediação verbal: o usuário consegue entender um módulo educativo (UBS × UPA, o que levar) e completar a triagem sem que ninguém explique o app?
- **Critério de saída:** taxa de conclusão ≥ 80% das tarefas-chave por usuários do público-alvo, sem ajuda.

### M3 — Configuração do Backend e Arquitetura Local (Semanas 5–7)

- Esquema do banco local (SQLite): entidades `Serviço`, `Sintoma`, `Documento`, `Medicamento`, `Vacina`, `PacoteConteúdo` (versionado).
- Pipeline do pacote de conteúdo: formato, versionamento, assinatura e hospedagem estática.
- Prova de conceito da IA local: SLM quantizado + regras de segurança rodando em aparelho Android mínimo (≥ 4 GB RAM; recomendado 6–8 GB — ADR-003).
- **Critério de saída:** inferência local < 3 s em aparelho de entrada; sync de pacote funcionando em rede instável simulada.

### M4 — Desenvolvimento de Módulos em Sprints (Semanas 7–17, 5 sprints de 2 semanas)

- **Sprint 1:** casca do app + navegação iconográfica + i18n (pt/es) + TTS.
- **Sprint 2:** Triagem Visual (regras de segurança + SLM) — Funcionalidade 1.
- **Sprint 3:** Encaminhamento UBS vs. UPA + Fluxo Típico de Atendimento — Funcionalidades 2 e 6.
- **Sprint 4:** Documentação + Farmácia Básica — Funcionalidades 3 e 4.
- **Sprint 5:** Sincronização de oportunidade + Calendário Vacinal — Funcionalidades 10 e 5.
- Revisão ao fim de cada sprint com build instalável (APK) testada pela equipe do projeto.
- **Critério de saída:** MVP completo em build de release candidate.

### M5 — Testes de Usabilidade e Desempenho (Semanas 17–19)

- Correção de bugs priorizada por severidade.
- Testes de desempenho: consumo de bateria da inferência, uso de RAM, tamanho do app (≤ 1,2 GB com modelo — ADR-003), cold start.
- Testes de segurança: validação de assinatura dos pacotes de conteúdo; auditoria das respostas de triagem contra os protocolos oficiais (revisão por profissional de saúde).
- Teste de estabilidade: 72h de uso simulado offline sem crash.

### M6 — Estudo Piloto do Projeto (Semanas 19–21)

Conduzido pelo PRISM/PET-Saúde com voluntários da comunidade, **fora de unidades de saúde** ([ADR-005](stack.md), Decisão 7). Dois portões, nesta ordem:

- **Portão 1 — dogfooding interno:** só a equipe do projeto, ciente de que os textos legais podem estar incompletos. Canal: pré-release do GitHub ou faixa interna da Play.
- **Portão 2 — estudo com participantes externos:** voluntários da comunidade, pela faixa de teste fechado da Play e/ou pré-release do GitHub. Exige antes a política de privacidade com o controlador identificado (LGPD, art. 9º), o RIPD e, **se** houver coleta de dados de participantes, TCLE e parecer de Comitê de Ética em Pesquisa.
- Validação das orientações pela coordenação clínica do projeto (profissionais de saúde colaboradores, com registro ativo, sem representar unidade).
- **Critério de saída:** zero orientações clinicamente incorretas registradas + aprovação da coordenação clínica do projeto. Nenhum dos portões passa por unidade de saúde.

### M7 — Lançamento, Operações e Manutenção (Semana 22 em diante)

- **Canais oficiais:** GitHub Releases (APK com SHA-256 e impressão do certificado — [espec](espec.md) RF-17) e Google Play, os dois alimentados pelo pipeline de release ([espec](espec.md) RNF-10). Os APKs dos dois canais não se atualizam um sobre o outro. Repassar o APK de pessoa para pessoa (Bluetooth/cartão SD) não é proibido, mas não é canal oficial; F-Droid fica como possibilidade futura, sem compromisso.
- Monitoramento pós-lançamento por telemetria anônima e agregada (enviada apenas nas janelas de sync).
- Ciclo mensal de atualização dos pacotes de conteúdo (campanhas nacionais, conteúdo educativo revisado) e trimestral do app.
- Backlog v2: Funcionalidades 7, 8 e 9 completas (línguas indígenas), edições regionais de conteúdo, modo multiplicador.

## Definição do MVP (v1.0)

**Princípio de corte:** o MVP deve provar as duas hipóteses de risco — (a) a interface iconográfica com áudio ensina o público-alvo sem mediação, e a IA local apoia o encaminhamento com segurança; (b) a arquitetura offline-first com sync de oportunidade é confiável.

### Dentro do MVP

| # | Funcionalidade | Justificativa |
|---|---|---|
| 2 | Encaminhamento UBS vs. UPA | Núcleo educativo; maior dor dos imigrantes; baixo custo (conteúdo estático) |
| 3 | Orientador de Documentação | Elimina a viagem perdida mais comum; trivial de implementar |
| 6 | Fluxo Típico de Atendimento | Complementa o encaminhamento com custo mínimo |
| 1 | Triagem Visual (Chatbot Local) | Apoio secundário; valida a Edge AI e a camada de regras de segurança |
| 9* | Resposta Visual + TTS (apenas pt/es) | Sem áudio o app exclui o público de baixo letramento — inegociável |
| 10 | Sincronização de Oportunidade | Valida a arquitetura; sem ela o conteúdo nasce morto |

\* Versão reduzida: TTS em português e espanhol; línguas indígenas ficam para a v2 (exigem gravação em campo).

### Fora do MVP (v1.1 → v2)

- **v1.1:** Calendário Vacinal (5) e Farmácia Básica (4) — exigem curadoria e revisão clínica de conteúdo nacional (calendário do PNI, elenco da RENAME), sem dado de estoque ou agenda de unidade.
- **v2:** Saúde da Mulher/Pré-Natal (7), Programas Sociais (8), áudios em línguas indígenas (9 completo) e modo multiplicador (apoio a ACS, educadores e voluntários em ações comunitárias).

### Métricas de sucesso do MVP

- **Métrica-norte (provisória, F-14):** módulos educativos concluídos sem mediação. A meta é fixada com o PET-Saúde antes do 1º participante externo; a métrica é revisada até 2027-05-01 ou no fim do estudo piloto ([ADR-005](stack.md), Revisão).
- Secundária: ≥ 80% dos participantes do estudo piloto completam uma triagem sem ajuda humana.
- 100% dos casos com sinais de alarme direcionados corretamente à emergência (camada de regras).
- ≥ 90% dos dispositivos do estudo piloto recebem uma atualização de conteúdo via sync de oportunidade em até 7 dias.
- Redução autodeclarada de deslocamentos inúteis entre os participantes do estudo piloto.
