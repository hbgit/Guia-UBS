# Guia UBS — Brainstorm do Projeto

## Nome do Conceito

**Guia UBS** — direto, memorável e autoexplicativo para o público brasileiro.

- **Tagline:** *"Sua UBS na palma da mão, mesmo sem internet."*
- Alternativas consideradas: **PostoAmigo**, **SUS Fácil**, **Ubi** (mascote/assistente). "Guia UBS" vence por clareza imediata: o nome já comunica o que o app faz, essencial para um público com letramento digital reduzido.

## Pitch de Uma Frase

Um guia de saúde visual e por voz que roda 100% offline no celular, usando IA local para orientar — apenas com toques em ícones — moradores de áreas rurais e imigrantes sobre quando, onde e como usar os serviços do SUS.

## Problema Central

O acesso à Atenção Primária no Brasil é travado por três barreiras simultâneas:

1. **Barreira de conectividade:** grande parte das áreas rurais e periféricas tem internet restrita ou inexistente, inviabilizando apps convencionais que dependem de nuvem.
2. **Barreira de letramento (digital e textual):** interfaces baseadas em texto e formulários excluem usuários com baixa alfabetização ou pouca familiaridade com smartphones.
3. **Barreira linguística e de conhecimento do sistema:** imigrantes hispanofalantes e populações indígenas não sabem distinguir UBS, UPA e hospital, quais documentos levar, nem quais serviços são gratuitos — resultando em deslocamentos inúteis (às vezes de horas), sobrecarga das UPAs com casos de atenção básica e abandono de tratamentos e vacinação.

A dor concreta: **pessoas perdem dias de trabalho e viagens longas para descobrir, no balcão, que estavam no lugar errado, sem o documento certo ou fora do horário do serviço.**

## Conceito e Escopo

### Propósito

Democratizar o acesso à informação sobre os serviços das Unidades Básicas de Saúde por meio de **Edge AI**: um agente conversacional que roda integralmente no dispositivo (offline-first), com entrada exclusivamente por **ícones e imagens** e resposta **multimodal (visual + áudio)** em português, espanhol e línguas indígenas locais.

### Usuários-alvo

| Perfil | Necessidade principal |
|---|---|
| Moradores de áreas rurais | Saber antes de se deslocar: serviço, horário, documento, remédio disponível |
| Imigrantes hispanofalantes | Entender o SUS (UBS vs. UPA), direitos e documentação aceita |
| Populações indígenas | Orientação em áudio na própria língua, sem depender de texto |
| Pessoas com baixa alfabetização | Navegar por ícones, sem ler nem digitar nada |
| Agentes Comunitários de Saúde (uso indireto) | Ferramenta de apoio educativo nas visitas domiciliares |

### O que o app faz (escopo v1)

- Triagem visual de sintomas com decisão UBS vs. emergência (IA local).
- Educação visual sobre a divisão do SUS (UBS vs. UPA/Hospital).
- Orientação de documentos, fluxo de atendimento, farmácia básica, calendário vacinal, saúde da mulher/pré-natal e programas sociais.
- Respostas com ícones + síntese de voz offline.
- Atualização silenciosa de conteúdo quando houver qualquer janela de conectividade.

### O que o app NÃO faz (fora de escopo)

- **Não faz diagnóstico médico** — apenas orientação de encaminhamento (disclaimer permanente).
- Não agenda consultas nem acessa prontuários (sem integração com sistemas do SUS na v1).
- Não coleta dados pessoais identificáveis — nenhum cadastro é exigido.
- Não substitui o Meu SUS Digital; o complementa onde ele não chega (offline + baixo letramento).

## Principais Funcionalidades

1. **Triagem Visual Baseada em Sintomas (Chatbot Local):** o usuário compõe frases visuais tocando em ícones de partes do corpo + sintomas (cabeça + raio = dor de cabeça; termômetro = febre). O modelo de IA local interpreta a combinação e responde: "vá à UBS" ou "procure emergência".
2. **Guia de Encaminhamento UBS vs. UPA/Hospital:** fluxogramas de ícones e animações simples ensinam a divisão do SUS — corte leve/vacina → imagem da UBS; acidente grave/dor no peito → imagem do Hospital/UPA.
3. **Orientador de Documentação Necessária:** ao tocar no serviço desejado, o app exibe fotos ilustrativas dos documentos exigidos (Cartão SUS, identidade/passaporte, comprovante de residência).
4. **Navegador da Farmácia Básica:** ícones de condições (coração = hipertensão, gota de sangue = diabetes) mostram visualmente os medicamentos gratuitos disponíveis na farmácia da UBS, evitando deslocamentos inúteis.
5. **Calendário Vacinal Interativo:** perfis por ícone (bebê, criança, adulto, gestante, idoso) exibem as vacinas devidas com símbolos universais de proteção e tempo.
6. **Fluxograma de Atendimento da Unidade:** cartões visuais sequenciais do passo a passo dentro da UBS: Recepção → Triagem/Acolhimento → Consulta → Pós-consulta/Farmácia.
7. **Módulo de Saúde da Mulher e Pré-Natal:** ao selecionar o ícone da gestante, o app mostra os serviços garantidos (testes rápidos, exames de rotina, ultrassom, vitaminas) e reforça o acompanhamento regular.
8. **Orientador de Programas Sociais e Saúde:** seção visual dos programas vinculados à UBS (condicionalidades do Bolsa Família, saúde bucal) — ex.: tocar na escova de dentes mostra como marcar o dentista.
9. **Resposta Multimodal (Visual + Áudio Offline):** toda resposta combina ícones com Text-to-Speech rodando no dispositivo, em português, espanhol ou línguas indígenas locais.
10. **Sincronização Assíncrona de Oportunidade:** invisível ao usuário — ao detectar qualquer conectividade (Wi-Fi de escola, centro comunitário), baixa em segundo plano atualizações de conteúdo (campanhas, horários) e atualiza a base de conhecimento local, voltando a operar 100% offline.

## Fluxo do Usuário

1. **Primeira abertura (única vez, offline):** o usuário toca na bandeira/ícone do idioma (🇧🇷 / 🇪🇸 / símbolo da etnia local). Sem cadastro, sem formulário — o app já está pronto.
2. **Tela inicial:** grade minimalista de 6–8 ícones grandes (corpo humano = sintomas; prédio = onde ir; documentos; pílula = farmácia; seringa = vacinas; gestante; escova de dentes; interrogação = como funciona a UBS).
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

## Vantagem Competitiva (Moat)

1. **Edge AI genuinamente offline:** os apps oficiais (Meu SUS Digital) e concorrentes de telessaúde **exigem internet e login**. O Guia UBS funciona onde eles falham por definição — este é o fosso estrutural.
2. **Interface 100% iconográfica com resposta por voz:** nenhuma solução de saúde pública brasileira atende simultaneamente analfabetos funcionais, imigrantes e povos indígenas. A curadoria de ícones validados em campo + TTS em línguas locais é um ativo difícil de replicar.
3. **Arquitetura de sincronização de oportunidade:** o modelo "conteúdo empacotado + delta updates em segundos de conectividade" cria confiabilidade que soluções cloud-first não conseguem imitar sem reescrever sua arquitetura.
4. **Custo marginal próximo de zero:** sem servidores de inferência (a IA roda no aparelho), o custo por usuário é quase nulo — viabiliza adoção por prefeituras pequenas e ONGs, o canal de distribuição natural.
5. **Neutralidade de dados:** por não coletar dados pessoais, elimina barreiras de LGPD e de confiança — crítico para imigrantes em situação migratória irregular, que evitam apps oficiais.

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
- **Infraestrutura mínima:** um bucket estático (Firebase Hosting/S3/GitHub Pages) para servir os pacotes de conteúdo — nenhum backend dinâmico é necessário na v1.

## Marcos de Entrega (Milestones)

### M1 — Wireframes (Semanas 1–2)

- Mapear os 6 fluxos principais (triagem, encaminhamento, documentos, farmácia, vacinas, fluxo da UBS) em wireframes de baixa fidelidade.
- Definir a gramática visual: catálogo inicial de ~60 ícones com significado único.
- **Critério de saída:** fluxos navegáveis em papel/Figma validados com 3–5 usuários representativos (incluindo ao menos 1 pessoa de baixo letramento).

### M2 — Protótipo Funcional de UI/UX (Semanas 3–5)

- Protótipo interativo de alta fidelidade (Figma) com a identidade minimalista final.
- Teste de usabilidade sem mediação verbal: o usuário consegue completar a triagem sem que ninguém explique o app?
- **Critério de saída:** taxa de conclusão ≥ 80% das tarefas-chave por usuários do público-alvo, sem ajuda.

### M3 — Configuração do Backend e Arquitetura Local (Semanas 5–7)

- Esquema do banco local (SQLite): entidades `Serviço`, `Sintoma`, `Documento`, `Medicamento`, `Vacina`, `PacoteConteúdo` (versionado).
- Pipeline do pacote de conteúdo: formato, versionamento, assinatura e hospedagem estática.
- Prova de conceito da IA local: SLM quantizado + regras de segurança rodando em aparelho Android mínimo (≥ 4 GB RAM; recomendado 6–8 GB — ADR-003).
- **Critério de saída:** inferência local < 3 s em aparelho de entrada; sync de pacote funcionando em rede instável simulada.

### M4 — Desenvolvimento de Módulos em Sprints (Semanas 7–17, 5 sprints de 2 semanas)

- **Sprint 1:** casca do app + navegação iconográfica + i18n (pt/es) + TTS.
- **Sprint 2:** Triagem Visual (regras de segurança + SLM) — Funcionalidade 1.
- **Sprint 3:** Encaminhamento UBS vs. UPA + Fluxograma de Atendimento — Funcionalidades 2 e 6.
- **Sprint 4:** Documentação + Farmácia Básica — Funcionalidades 3 e 4.
- **Sprint 5:** Sincronização de oportunidade + Calendário Vacinal — Funcionalidades 10 e 5.
- Revisão ao fim de cada sprint com build instalável (APK) testada em campo.
- **Critério de saída:** MVP completo em build de release candidate.

### M5 — Testes de Usabilidade e Desempenho (Semanas 17–19)

- Correção de bugs priorizada por severidade.
- Testes de desempenho: consumo de bateria da inferência, uso de RAM, tamanho do app (≤ 1,2 GB com modelo — ADR-003), cold start.
- Testes de segurança: validação de assinatura dos pacotes de conteúdo; auditoria das respostas de triagem contra os protocolos oficiais (revisão por profissional de saúde).
- Teste de estabilidade: 72h de uso simulado offline sem crash.

### M6 — Teste de Aceitação do Usuário / UAT (Semanas 19–21)

- Piloto em campo: 1 UBS rural + 1 UBS com população imigrante, 20–30 usuários reais por 2 semanas.
- Validação com a equipe da UBS (enfermagem/ACS) de que as orientações refletem o funcionamento real da unidade.
- **Critério de saída:** aprovação formal dos gestores das unidades piloto + zero orientações clinicamente incorretas registradas.

### M7 — Lançamento, Operações e Manutenção (Semana 22 em diante)

- Publicação na Play Store + distribuição direta de APK (essencial para instalação via Bluetooth/SD em áreas sem internet).
- Monitoramento pós-lançamento por telemetria anônima e agregada (enviada apenas nas janelas de sync).
- Ciclo mensal de atualização dos pacotes de conteúdo (campanhas, horários) e trimestral do app.
- Backlog v2: Funcionalidades 7, 8 e 9 completas (línguas indígenas), novos municípios, modo ACS.

## Definição do MVP (v1.0)

**Princípio de corte:** o MVP deve provar as duas hipóteses de risco — (a) IA local + interface iconográfica funciona para o público-alvo sem mediação; (b) a arquitetura offline-first com sync de oportunidade é confiável.

### Dentro do MVP

| # | Funcionalidade | Justificativa |
|---|---|---|
| 1 | Triagem Visual (Chatbot Local) | Coração do produto; valida a Edge AI |
| 2 | Encaminhamento UBS vs. UPA | Maior dor dos imigrantes; baixo custo (conteúdo estático) |
| 3 | Orientador de Documentação | Elimina a viagem perdida mais comum; trivial de implementar |
| 6 | Fluxograma de Atendimento | Complementa o encaminhamento com custo mínimo |
| 9* | Resposta Visual + TTS (apenas pt/es) | Sem áudio o app exclui o público de baixo letramento — inegociável |
| 10 | Sincronização de Oportunidade | Valida a arquitetura; sem ela o conteúdo nasce morto |

\* Versão reduzida: TTS em português e espanhol; línguas indígenas ficam para a v2 (exigem gravação em campo).

### Fora do MVP (v1.1 → v2)

- **v1.1:** Calendário Vacinal (5) e Farmácia Básica (4) — dependem de dados locais curados por município.
- **v2:** Saúde da Mulher/Pré-Natal (7), Programas Sociais (8), áudios em línguas indígenas (9 completo) e modo de apoio ao Agente Comunitário de Saúde.

### Métricas de sucesso do MVP

- ≥ 80% dos usuários do piloto completam uma triagem sem ajuda humana.
- 100% dos casos com sinais de alarme direcionados corretamente à emergência (camada de regras).
- ≥ 90% dos dispositivos do piloto recebem uma atualização de conteúdo via sync de oportunidade em até 7 dias.
- Redução autodeclarada de deslocamentos inúteis entre os usuários do piloto.
