# Guia UBS — Especificação de Conformidade LGPD

> **Base normativa:** Lei nº 13.709/2018 (LGPD), com alterações da Lei nº 13.853/2019. **Documentos de referência do produto:** [brainstorm.md](brainstorm.md), [stack.md](stack.md), [espec.md](espec.md).
> **Escopo:** aplicativo móvel offline-first (usuário final) + plano de controle web (CMS de conteúdo com admins municipais e revisores clínicos) + telemetria agregada.

## Tese central de conformidade (leia primeiro)

O Guia UBS foi concebido sob **Privacy by Design em grau máximo**: o usuário final **não se cadastra, não se identifica e não transmite dados** — os sintomas selecionados (dado de saúde, portanto **dado pessoal sensível**, art. 5º, II) são processados exclusivamente no dispositivo e **nunca saem dele nem são persistidos**. A telemetria é **agregada e anonimizada por construção** e, nos termos do **art. 12**, dado anonimizado não é considerado dado pessoal quando o processo não for reversível por meios razoáveis.

Isso **não** torna a LGPD inaplicável ao projeto. Ela incide plenamente sobre:

1. **Dados dos administradores e revisores do CMS** (nome, e-mail, credenciais, trilha de auditoria) — dados pessoais comuns de profissionais;
2. **Participantes do piloto/UAT** (observação de uso por 20–30 pessoas reais) — exige consentimento específico;
3. **O desenho da telemetria** — que só permanece fora do escopo do art. 5º, I, enquanto a anonimização for irreversível (coortes pequenas podem reidentificar);
4. **Operadores contratados** (provedor do VPS que hospeda a stack self-hosted) — com **transferência internacional** (arts. 33 a 36) aplicável apenas se o datacenter estiver no exterior; a stack 100% self-hosted permite escolher datacenter no Brasil e eliminar essa hipótese na prática.

Todos os requisitos abaixo derivam dessa tese. Onde o produto **não possui** uma função (marketing, anúncios, cookies), o requisito é formulado como **guardrail proibitivo**: a função não pode ser introduzida sem cumprir as condições listadas — isso é Privacy by Default (art. 46 c/c art. 6º, III).

---

# 1. Requisitos de Conformidade LGPD

**Formato:** cada requisito traz identificador, nome, descrição, objetivo, base legal, artigos e critério de aceitação. Prioridades: **P0** = bloqueia lançamento; **P1** = exigível no primeiro ciclo pós-lançamento; **P2** = condicional (só se a função for criada).

### LGPD-RF01 — Minimização e não-coleta de dados do usuário final
- **Descrição:** o aplicativo não deve coletar, transmitir ou persistir qualquer dado pessoal do usuário final: sem cadastro, sem identificador de dispositivo, sem localização, sem contatos, sem telefone. As permissões Android solicitadas devem se limitar a rede (para o sync de conteúdo) e armazenamento interno do próprio app.
- **Objetivo:** eliminar a superfície de tratamento na origem (necessidade/minimização).
- **Base legal:** princípio da necessidade; Privacy by Default.
- **Artigos:** art. 6º, III; art. 46, §2º.
- **Critério de aceitação:** auditoria de tráfego de rede em uso real demonstra que nenhuma requisição contém identificadores de usuário/dispositivo; análise do manifest Android confirma ausência de permissões além de `INTERNET` e afins; teste automatizado em CI falha se qualquer módulo de feature importar APIs de identificação (IMEI, Advertising ID, localização).

### LGPD-RF02 — Consentimento (piloto/UAT e admins do CMS)
- **Descrição:** (a) participantes do piloto UAT devem fornecer consentimento **livre, informado e inequívoco**, por escrito ou registro equivalente, destacado das demais cláusulas, descrevendo finalidade (validação de usabilidade), dados coletados (observações de uso, respostas a entrevistas) e prazo de descarte; para participantes não alfabetizados, o termo deve ser lido em voz alta no idioma da pessoa, com registro do assentimento. (b) Admins do CMS aceitam Termo de Uso no primeiro login, com registro de aceite.
- **Objetivo:** legitimar as duas únicas frentes de coleta direta de dados pessoais do projeto.
- **Base legal:** consentimento (usuários do piloto); execução de contrato/procedimentos preliminares (admins).
- **Artigos:** art. 7º, I e V; art. 8º, caput e §§1º–4º; art. 11, I (se o piloto registrar dados de saúde).
- **Critério de aceitação:** existe termo de consentimento do piloto revisado juridicamente; nenhum dado do piloto é coletado antes do registro do consentimento; o fluxo de primeiro login do CMS bloqueia o acesso até o aceite.

### LGPD-RF03 — Gerenciamento de preferências de privacidade
- **Descrição:** o app deve ter uma tela de privacidade acessível (ícone de cadeado/escudo, com leitura em áudio pt/es) permitindo: desligar a telemetria agregada (opt-out local), apagar todos os dados locais (`user.db` + sessões) com um toque, e ouvir o aviso de privacidade. No CMS, cada admin acessa e edita seus dados cadastrais.
- **Objetivo:** dar controle efetivo ao titular mesmo num produto sem conta.
- **Base legal:** livre acesso e autodeterminação informativa.
- **Artigos:** art. 6º, IV; art. 9º; art. 18, II e IV.
- **Critério de aceitação:** opt-out de telemetria zera envios na próxima janela de sync (verificável em teste de integração); "apagar meus dados" remove `user.db` e preferências e é irreversível; a tela é operável sem leitura (ícones + áudio).

### LGPD-RF04 — Registro e auditoria de consentimentos
- **Descrição:** todo consentimento/aceite (piloto e CMS) deve ser registrado com: identificador do titular, versão do documento aceito, data/hora, meio de coleta e hash do texto vigente. Registros são imutáveis (append-only) e conserváveis pelo prazo prescricional.
- **Objetivo:** permitir ao controlador **provar** o consentimento (o ônus da prova é dele).
- **Base legal:** responsabilização e prestação de contas.
- **Artigos:** art. 8º, §2º (ônus da prova); art. 6º, X; art. 37 (registro das operações).
- **Critério de aceitação:** consulta ao registro retorna, para qualquer titular fictício de teste (ex.: `admin.teste@municipio-exemplo.gov.br`), a cadeia completa de versões aceitas; tentativa de UPDATE/DELETE no registro falha.

### LGPD-RF05 — Revogação de consentimento
- **Descrição:** o titular pode revogar consentimento a qualquer momento, por procedimento **gratuito e facilitado**, pelo mesmo canal em que consentiu. Revogação no piloto interrompe a coleta e descarta os dados do participante; revogação de telemetria = opt-out da RF03. Tratamentos realizados sob o consentimento anterior permanecem válidos até a revogação.
- **Objetivo:** garantir que o consentimento seja um estado reversível, não um evento.
- **Base legal:** revogabilidade do consentimento.
- **Artigos:** art. 8º, §5º; art. 18, IX.
- **Critério de aceitação:** fluxo de revogação testado de ponta a ponta em ≤ 2 interações; dados do participante revogado ausentes do conjunto final do piloto.

### LGPD-RF06 — Compartilhamento com terceiros (operadores)
- **Descrição:** com a stack 100% self-hosted (MinIO, Caddy, `sqld`, CMS num único VPS), o rol de operadores reduz-se ao **provedor de infraestrutura do VPS** (e ao serviço de e-mail transacional do CMS, se houver). Esses operadores devem: (a) constar de inventário público na Política de Privacidade; (b) ter contrato/DPA com cláusulas de tratamento conforme instruções do controlador; (c) **preferencialmente operar datacenter no Brasil** — o que elimina a transferência internacional; se no exterior, enquadrar-se em hipótese válida dos arts. 33–36 (cláusulas contratuais padrão ou garantias equivalentes). Espelhos de conteúdo (rsync) não tratam dado pessoal — servem apenas artefatos públicos assinados. É proibida qualquer transmissão de conteúdo de triagem a terceiros — estruturalmente garantido, pois a triagem não sai do device.
- **Objetivo:** manter a cadeia de tratamento sob controle jurídico e técnico.
- **Base legal:** disciplina controlador–operador; transferência internacional.
- **Artigos:** art. 5º, VI e VII; art. 39; arts. 33 a 36.
- **Critério de aceitação:** inventário de operadores versionado no repositório de compliance; DPA arquivado para cada um; a Política de Privacidade lista todos com finalidade e localização.

### LGPD-RF07 — Retenção e exclusão de dados
- **Descrição:** política de retenção explícita por classe: (a) dados de admins — enquanto durar o vínculo + prazo prescricional para trilhas de auditoria; (b) dados do piloto — descartados ou irreversivelmente anonimizados em até 90 dias após o relatório final; (c) telemetria — já nasce agregada, sem retenção individual; (d) dados locais do device — sob controle exclusivo do usuário (RF03). Ao término do tratamento, eliminação verificada, ressalvadas as hipóteses do art. 16.
- **Objetivo:** impedir acúmulo de dados sem finalidade vigente.
- **Base legal:** término do tratamento e conservação excepcional.
- **Artigos:** arts. 15 e 16; art. 6º, III.
- **Critério de aceitação:** tabela de retenção aprovada pelo encarregado; job de expurgo automatizado com log de execução; amostragem trimestral não encontra dados fora de prazo.

### LGPD-RF08 — Direitos do titular
- **Descrição:** implementar canal e fluxos para todos os direitos do art. 18 (detalhados na Seção 6), com confirmação de existência de tratamento, acesso, correção, anonimização/bloqueio/eliminação, portabilidade, informação sobre compartilhamentos, e revisão de decisões automatizadas quando aplicável.
- **Objetivo:** operacionalizar o exercício de direitos sem fricção.
- **Base legal:** direitos do titular.
- **Artigos:** arts. 17 a 22; art. 19 (prazos).
- **Critério de aceitação:** solicitação fictícia de teste percorre o fluxo completo dentro dos prazos da Seção 6, com registro auditável.

### LGPD-RNF09 — Segurança da informação
- **Descrição:** medidas técnicas e administrativas aptas a proteger os dados: criptografia em trânsito (TLS 1.2+) e em repouso no plano de controle; assinatura Ed25519 dos pacotes de conteúdo; segregação de ambientes; princípio do menor privilégio; segredos fora do código; testes de segurança antes de cada release (já previstos no M5 do roadmap).
- **Objetivo:** proteger contra acessos não autorizados e situações acidentais ou ilícitas de destruição, perda, alteração ou difusão.
- **Base legal:** segurança e prevenção.
- **Artigos:** arts. 46 e 47; art. 6º, VII e VIII; art. 49.
- **Critério de aceitação:** checklist da Seção 5 100% atendido antes do lançamento; varredura de vulnerabilidades sem achados críticos abertos.

### LGPD-RF10 — Transparência no tratamento
- **Descrição:** informações sobre tratamento devem ser **claras, precisas e facilmente acessíveis** — no caso do Guia UBS, isso exige formato **multimodal**: aviso de privacidade disponível em ícones + áudio (pt/es), além do texto integral. Nenhuma informação sobre tratamento pode ser exclusivamente textual no app.
- **Objetivo:** transparência real para público de baixo letramento — não apenas formal.
- **Base legal:** transparência e livre acesso.
- **Artigos:** art. 6º, IV e VI; art. 9º.
- **Critério de aceitação:** teste de usabilidade demonstra que usuário não alfabetizado consegue ouvir e compreender o aviso ("o app não guarda nada seu; tudo fica só no seu telefone") sem mediação.

### LGPD-RF11 — Controle de acesso
- **Descrição:** CMS com RBAC mínimo de 3 papéis — **Editor** (edita conteúdo), **Revisor clínico** (aprova regras/conteúdo; não edita o que aprova), **Admin** (gestão de usuários) — com 2FA TOTP obrigatório, sessões com expiração, e vedação de contas compartilhadas. Acesso ao banco de produção restrito e registrado.
- **Objetivo:** limitar tratamento a agentes autorizados e rastreáveis; garantir segregação de funções na cadeia clínica.
- **Base legal:** segurança; prevenção.
- **Artigos:** arts. 46 e 47; art. 6º, VII e VIII.
- **Critério de aceitação:** matriz papel×permissão testada automaticamente; tentativa de auto-aprovação (mesmo usuário edita e aprova) é bloqueada; revisão de acessos trimestral registrada.

### LGPD-RF12 — Comunicação de incidentes de segurança
- **Descrição:** plano de resposta a incidentes com: detecção, contenção, avaliação de risco aos titulares, e comunicação à **ANPD** e aos titulares quando o incidente puder acarretar risco ou dano relevante — em prazo razoável, observado o prazo regulamentar da ANPD (3 dias úteis, conforme regulamento de comunicação de incidentes). A comunicação deve conter: descrição dos dados afetados, titulares envolvidos, medidas de mitigação, e riscos.
- **Objetivo:** resposta tempestiva e transparente que reduza dano ao titular e exposição regulatória.
- **Base legal:** comunicação de incidente.
- **Artigos:** art. 48, caput e §§1º–2º; art. 46.
- **Critério de aceitação:** runbook de incidentes aprovado e testado em simulação (tabletop) anual; template de comunicação à ANPD pronto; responsáveis nomeados.

### LGPD-RF13 — Tratamento de dados sensíveis (saúde)
- **Descrição:** os tokens de sintomas são dado de saúde (sensível). Regra absoluta: **processamento exclusivamente local, em memória; proibida a persistência da sequência de tokens e proibida qualquer transmissão** (espelha a INV-5 da spec). A telemetria só pode conter **contadores agregados por severidade de resultado**, nunca a combinação de sintomas de uma sessão. O piloto UAT, se registrar queixas de saúde de participantes identificáveis, opera sob consentimento específico e destacado (RF02).
- **Objetivo:** impossibilitar, por arquitetura, a formação de base de dados de saúde de pessoas identificáveis.
- **Base legal:** tratamento de dado sensível; anonimização.
- **Artigos:** art. 5º, II; art. 11, caput e I; art. 12.
- **Critério de aceitação:** revisão de código confirma que a sessão de triagem morre em memória (nenhum write da sequência de tokens); schema de telemetria versionado no repositório e validado em CI contra lista de campos permitidos; teste de rede confirma ausência de payload de sintomas.

### LGPD-RF14 — Telemetria, analytics e anti-reidentificação
- **Descrição:** a telemetria agregada só permanece fora do conceito de dado pessoal (art. 12) se irreversível. Requisitos: (a) sem identificadores de device/instalação persistentes; (b) agregação por coorte (município do pack + versão) com **k-anonimato ≥ 20** — coortes menores não são enviadas; (c) sem timestamps finos (granularidade mínima: dia); (d) qualquer novo campo passa por revisão do encarregado antes de entrar no schema.
- **Objetivo:** impedir que "dados anônimos" degradem para dados pessoais por acúmulo ou cruzamento.
- **Base legal:** anonimização e meios razoáveis de reversão.
- **Artigos:** art. 12, caput e §1º; art. 6º, III.
- **Critério de aceitação:** validador no pipeline rejeita lotes com coorte < 20; schema de telemetria só muda via PR aprovado pelo encarregado; análise de reidentificação documentada a cada release maior.

### LGPD-RF15 — E-mail marketing (guardrail)
- **Descrição:** o produto **não realiza** e-mail marketing e não coleta e-mails de usuários finais. Guardrail: nenhuma função de marketing pode ser introduzida sem (a) base legal própria (consentimento opt-in específico, nunca pré-marcado); (b) descadastro em 1 clique em toda mensagem; (c) atualização da Política de Privacidade; (d) registro de consentimento (RF04). E-mails transacionais do CMS (reset de senha) não são marketing e operam sob execução de contrato.
- **Objetivo:** impedir scope creep de comunicação não solicitada.
- **Base legal:** consentimento (se um dia existir); execução de contrato (transacionais).
- **Artigos:** art. 7º, I e V; art. 8º; art. 9º, §2º (mudança de finalidade exige novo consentimento).
- **Critério de aceitação:** inexistência de qualquer módulo de envio em massa no código; revisão de compliance obrigatória (gate de PR) para features que enviem e-mail.

### LGPD-RF16 — Anúncios personalizados (proibição por design)
- **Descrição:** é **vedada** a integração de SDKs de publicidade, advertising ID, fingerprinting ou perfilamento de usuários finais. A vedação é reforçada pelo contexto: perfilar comportamento de busca de saúde de população vulnerável criaria tratamento de dado sensível para fim comercial, de altíssimo risco jurídico e ético.
- **Objetivo:** blindar o ativo central do produto — a confiança de populações vulneráveis (incluindo imigrantes em situação irregular).
- **Base legal:** necessidade; não discriminação; vedação de tratamento de sensíveis sem hipótese do art. 11.
- **Artigos:** art. 6º, III e IX; art. 11; art. 12, §2º (dados comportamentais vinculáveis a pessoa).
- **Critério de aceitação:** CI bloqueia dependências de bibliotecas de ads/tracking (lista de bloqueio de pacotes); análise estática do APK confirma ausência de advertising ID.

### LGPD-RF17 — Integração com APIs e serviços externos
- **Descrição:** toda integração externa (CDN, banco, hospedagem, e futuras APIs) deve: (a) trafegar somente dados estritamente necessários; (b) nunca incluir dado pessoal em URLs/query strings (aparecem em logs de terceiros); (c) usar TLS com validação de certificado; (d) ter o fornecedor inventariado (RF06); (e) no app, a única integração de rede permitida é o download de manifest/pack — qualquer nova chamada de rede exige revisão de privacidade em PR.
- **Objetivo:** impedir vazamento lateral por fornecedores e logs de terceiros.
- **Base legal:** segurança; responsabilidade solidária da cadeia.
- **Artigos:** arts. 42, 46 e 47; art. 39.
- **Critério de aceitação:** teste automatizado varre logs de acesso simulados e não encontra dado pessoal em URL; lista de endpoints permitidos no app é fixa e verificada em CI.

---

# 2. Requisitos para Termo de Uso e Política de Privacidade

| ID | Documento | Obrigatoriedade |
|---|---|---|
| LGPD-DOC01 | **Termo de Uso** | Obrigatório para o CMS (admins). Para o app: versão simplificada com o disclaimer clínico ("este app orienta, não diagnostica") em ícones + áudio. |
| LGPD-DOC02 | **Política de Privacidade** | Obrigatória, pública, versionada, disponível no app (multimodal) e na página do projeto. |
| LGPD-DOC03 | **Aviso de Consentimento** | Obrigatório no piloto UAT (RF02) e no primeiro login do CMS. |
| LGPD-DOC04 | **Banner de Cookies** | **Não aplicável ao app** (não usa cookies). Obrigatório apenas se existir site institucional com cookies não essenciais — nesse caso, com recusa tão fácil quanto o aceite e bloqueio prévio de cookies não essenciais. |

**Requisitos de conteúdo e forma (aplicáveis a DOC01–DOC03):**

1. **Linguagem simples** (art. 9º c/c art. 6º, VI): frases curtas, sem juridiquês; toda expressão técnica explicada ("dado pessoal é qualquer informação que identifique você"). No app, o resumo em áudio pt/es é obrigatório — coerente com RF10.
2. **Quais dados são coletados** — declaração honesta e específica. Para o app, a declaração central é negativa e deve ser dita com destaque: *"Não pedimos seu nome, telefone ou documento. Suas escolhas de sintomas ficam apenas no seu telefone e são apagadas ao fim da consulta ao app."*
3. **Finalidade de cada coleta** (art. 6º, I): tabela finalidade × dado × base legal (CMS: operar contas de admins; telemetria: melhorar o serviço, de forma agregada).
4. **Tempo de retenção** de cada classe (conforme RF07).
5. **Compartilhamento com terceiros:** lista nominal de operadores (RF06), com país e finalidade.
6. **Usos específicos:** declarar expressamente que **não há** e-mail marketing, anúncios personalizados nem venda/compartilhamento comercial de dados; analytics existe apenas em forma agregada e anônima, com opt-out no app.
7. **Como exercer direitos:** instruções passo a passo para solicitar exclusão, revogar consentimento, exportar dados e atualizar cadastro (Seção 6), com canal gratuito.
8. **Contato do Encarregado (DPO):** identificação e canal (ex. fictício: `privacidade@guiaubs.exemplo.br`), conforme art. 41, §1º.
9. **Medidas de segurança** em linguagem acessível: "os pacotes de conteúdo são assinados digitalmente; o app confere a assinatura antes de usar" etc.
10. **Versionamento e vigência:** data de vigência, histórico de versões público, e re-aceite quando houver mudança material (art. 9º, §2º).

---

# 3. Bases Legais por Cenário

| Cenário | Base legal recomendada | Justificativa | Riscos | Cuidados |
|---|---|---|---|---|
| Cadastro de usuários (CMS/admins) | **Execução de contrato** (art. 7º, V) | A conta é necessária à relação funcional entre município/projeto e o profissional | Coleta além do necessário | Campos mínimos (nome, e-mail funcional); nada de CPF se não for imprescindível |
| Usuário final do app | **Nenhuma coleta** — LGPD não incide sobre o que não existe | Minimização levada ao limite (art. 6º, III) | Introdução acidental de coleta em release futura | Gate de revisão de privacidade em todo PR que toque rede/persistência (RF17) |
| Login/autenticação (CMS) | **Execução de contrato** (art. 7º, V) + **obrigação de segurança** (art. 46) | Autenticar é condição de segurança do sistema | Retenção excessiva de logs de acesso | Logs de autenticação com retenção definida (RF07) |
| Envio de e-mails transacionais (reset de senha, alertas do CMS) | **Execução de contrato** (art. 7º, V) | Comunicação necessária ao serviço contratado | Confundir transacional com marketing | Sem conteúdo promocional em e-mail transacional |
| Marketing | **Consentimento** (art. 7º, I) — hoje N/A (RF15) | Comunicação não solicitada exige opt-in ativo | Consentimento pré-marcado = nulo; multa e dano reputacional | Opt-in granular, registro (RF04), descadastro 1 clique |
| Personalização de anúncios | **Nenhuma base adotada — vedado por design** (RF16) | Perfilar busca de saúde de vulneráveis tangencia o art. 11 sem hipótese válida | Altíssimo: dado sensível + população vulnerável | Manter vedação; qualquer mudança exige RIPD e parecer jurídico |
| Compartilhamento com terceiros (operadores de infraestrutura) | **Execução de contrato + legítimo interesse** (art. 7º, V e IX) | Hospedar/entregar conteúdo exige operadores; interesse legítimo em operar com segurança | Transferência internacional sem salvaguarda | DPA + cláusulas de transferência (arts. 33–36); teste de balanceamento documentado para o legítimo interesse (art. 10) |
| Cumprimento de obrigações legais | **Obrigação legal/regulatória** (art. 7º, II) | Guarda de registros exigidos por lei (ex.: trilhas fiscais/trabalhistas do projeto) | Usar a base como cheque em branco | Mapear a obrigação específica que exige cada guarda |
| Emissão de documentos fiscais (se o projeto contratar/faturar) | **Obrigação legal** (art. 7º, II) | Legislação tributária exige dados do prestador/tomador | Reter além do prazo fiscal | Retenção = prazo legal tributário; acesso restrito ao financeiro |
| Atendimento e suporte (canal do DPO, suporte a municípios) | **Execução de contrato** (art. 7º, V) ou **legítimo interesse** (art. 7º, IX) | Responder a quem procura o serviço | Acumular histórico com dados desnecessários | Coletar só o necessário ao atendimento; expurgo após resolução |
| Analytics e métricas de uso | **Fora de escopo se anonimizado** (art. 12); alternativa: **legítimo interesse** (art. 7º, IX) se algum dia houver dado pessoal | Dado verdadeiramente anônimo não é dado pessoal | Anonimização fraca reverte a base para dado pessoal sem base legal | RF14: k-anonimato ≥ 20, sem IDs persistentes, revisão do encarregado |

**Nota sobre dados sensíveis (art. 11):** se qualquer cenário futuro envolver dado de saúde identificável (ex.: modo ACS na v2), as bases do art. 7º **não bastam** — será necessário consentimento específico e destacado (art. 11, I) ou hipótese de tutela da saúde (art. 11, II, f), com RIPD prévio (art. 38).

---

# 4. Princípios da LGPD Aplicados (art. 6º)

| Princípio | Em linguagem simples | Como o Guia UBS aplica | Exemplo prático |
|---|---|---|---|
| **Finalidade** (I) | Só usar dados para o propósito informado, específico e legítimo | Telemetria serve só para melhorar o app; dados de admin servem só para operar o CMS | O contador de triagens nunca pode virar insumo de marketing |
| **Adequação** (II) | O uso precisa ser compatível com o que foi prometido | O aviso diz "nada sai do seu telefone" — e a arquitetura garante isso | Se um dia o app precisar de rede para algo novo, o aviso muda ANTES da feature |
| **Necessidade** (III) | Coletar o mínimo indispensável | Zero cadastro; permissões Android mínimas; telemetria só agregada | Não pedimos localização: o usuário escolhe seu município uma vez, offline |
| **Livre acesso** (IV) | O titular consulta grátis e facilmente o que existe sobre ele | Tela de privacidade no app (RF03); autoatendimento do admin no CMS | Um toque no cadeado → áudio: "o app não guarda nada seu" |
| **Qualidade dos dados** (V) | Dados exatos e atualizados | Conteúdo clínico com dual review e versionamento; cadastro de admin editável | Admin corrige o próprio e-mail sem abrir chamado |
| **Transparência** (VI) | Informação clara sobre o tratamento e quem trata | Política multimodal (texto + ícones + áudio, pt/es); lista pública de operadores | O aviso é ouvível por quem não lê |
| **Segurança** (VII) | Proteger os dados contra acesso indevido | TLS, Ed25519 nos packs, 2FA no CMS, RBAC, menor privilégio | Pack adulterado na CDN é rejeitado pelo app |
| **Prevenção** (VIII) | Evitar o dano antes que aconteça | Privacy by Design: o dado que não existe não vaza | A sequência de sintomas morre em memória — não há o que vazar |
| **Não discriminação** (IX) | Dados nunca para fins discriminatórios ou abusivos | Sem perfilamento; app serve imigrantes sem exigir documento ou status migratório | Ninguém é tratado diferente por idioma ou origem |
| **Responsabilização** (X) | Provar que tudo acima é cumprido | Registros de consentimento (RF04), trilhas de auditoria, RIPD, este documento | Em fiscalização da ANPD, cada requisito aqui tem evidência associada |

---

# 5. Checklist de Segurança e Boas Práticas

| # | Medida | Objetivo | Como implementar | Riscos mitigados |
|---|---|---|---|---|
| 1 | **Criptografia** | Confidencialidade em trânsito e repouso | TLS 1.2+ em toda rede; storage do CMS/banco com criptografia em repouso do provedor; assinatura Ed25519 + SHA-256 dos packs; segredos em cofre (nunca no código) | Interceptação, adulteração de conteúdo clínico, vazamento de credenciais |
| 2 | **Controle de acesso por perfil** | Menor privilégio e segregação de funções | RBAC de 3 papéis no CMS (RF11); 2FA TOTP; sessões expiráveis; proibição de conta compartilhada | Acesso indevido, edição clínica sem revisão, abuso interno |
| 3 | **Logs e auditoria** | Rastreabilidade sem criar novo risco | Trilha append-only de ações no CMS (quem editou/aprovou o quê); logs **sem dado pessoal desnecessário** e sem dado de saúde; retenção definida | Fraude interna, impossibilidade de investigação, log que vira vazamento |
| 4 | **Backup seguro** | Disponibilidade e recuperação | Backup criptografado do banco master com teste de restauração periódico; backups sujeitos à mesma política de retenção e expurgo | Perda de conteúdo curado, ransomware, retenção fantasma em backup |
| 5 | **Gestão de consentimento** | Prova e reversibilidade | Registro versionado e imutável de aceites (RF04); fluxo de revogação (RF05) | Impossibilidade de provar consentimento; tratamento após revogação |
| 6 | **Política de retenção** | Dados não sobrevivem à finalidade | Tabela de retenção por classe (RF07) + job de expurgo automatizado e logado | Acúmulo ilegal, ampliação da superfície de vazamento |
| 7 | **Anonimização/pseudonimização** | Reduzir dado pessoal ao mínimo | Telemetria com k-anonimato ≥ 20, sem IDs persistentes (RF14); IDs opacos (UUID) nos logs do CMS, nunca nome/e-mail | Reidentificação, perfilamento acidental |
| 8 | **Plano de resposta a incidentes** | Reagir rápido e comunicar certo | Runbook: detectar → conter → avaliar risco → comunicar ANPD/titulares (RF12); simulação anual; template de notificação pronto | Dano ampliado ao titular, sanção por omissão de comunicação |
| 9 | **Treinamento da equipe** | Pessoas são o maior vetor | Onboarding de privacidade para todo dev/admin; treinamento anual; regras práticas ("nunca dado pessoal em log/URL/print") | Vazamento por erro humano, engenharia social |
| 10 | **Gestão de vulnerabilidades** | Fechar portas antes do ataque | Auditoria de dependências em CI; varredura antes de release (M5); prazo máximo para correção de achados críticos; canal de disclosure responsável | Exploração de CVE conhecida, supply chain do app |

---

# 6. Direitos dos Titulares (art. 18)

**Quem são os titulares no projeto:** admins/revisores do CMS, participantes do piloto e — na medida em que algum dado pessoal venha a existir — usuários do app (hoje, nenhum).

| Direito (art. 18) | Como o sistema permite exercer |
|---|---|
| I — Confirmação da existência de tratamento | Canal do DPO responde se há dados sobre o solicitante; para usuários do app a resposta-padrão é verificável: "não tratamos dados seus" |
| II — Acesso aos dados | Admin: autoatendimento no CMS; demais: extrato via canal do DPO |
| III — Correção | Edição de cadastro no CMS; solicitação via canal para os demais |
| IV — Anonimização, bloqueio ou eliminação de dados desnecessários/excessivos | Avaliação pelo encarregado + execução com evidência de expurgo |
| V — Portabilidade | Exportação em formato aberto (JSON/CSV) dos dados do solicitante |
| VI — Eliminação de dados tratados com consentimento | Piloto: descarte imediato; CMS: eliminação ressalvado o art. 16 |
| VII — Informação sobre compartilhamentos | Lista de operadores (RF06) entregue com o extrato |
| VIII — Informação sobre a possibilidade de não consentir | Termos do piloto explicitam que a recusa não impede o uso do app |
| IX — Revogação do consentimento | Fluxo da RF05 |
| Art. 20 — Revisão de decisão automatizada | A triagem é orientativa, local e não produz decisão sobre pessoa identificada; ainda assim, o app sempre exibe o caminho humano (procurar a UBS) — nenhuma porta se fecha por decisão do algoritmo |

**Fluxo recomendado de atendimento:**

1. **Recepção** (canal gratuito do DPO — e-mail/formulário; ex. fictício `privacidade@guiaubs.exemplo.br`) → registro com protocolo.
2. **Verificação de identidade** proporcional (evitar entregar dados a terceiro que se passa pelo titular — isso seria um incidente).
3. **Triagem da solicitação** pelo encarregado → classificação por direito.
4. **Execução** com evidência (query, log de expurgo, export).
5. **Resposta ao titular** em linguagem simples.
6. **Registro para auditoria**: protocolo, datas, ação executada, responsável — retido pelo prazo prescricional.

**Prazos (art. 19):** confirmação de existência e acesso — **imediatamente em formato simplificado**, ou por **declaração completa em até 15 dias**. Demais direitos: sem prazo legal fixo — adotar **15 dias** como SLA interno, prorrogável com justificativa comunicada ao titular.

---

# 7. Requisitos Técnicos de Implementação

| ID | Área | Requisito técnico |
|---|---|---|
| LGPD-RT01 | APIs | Nenhum dado pessoal em URL/query string; autenticação em todo endpoint do CMS; respostas de erro sem dados de titulares (mensagem genérica + ID opaco no log servidor) |
| LGPD-RT02 | Banco de dados | Colunas de dado pessoal do CMS marcadas no schema (`COMMENT ... 'PII'`); acesso de produção restrito e logado; sem dado pessoal no `content.db` distribuído (por construção) |
| LGPD-RT03 | Logs | Proibido dado pessoal e dado de saúde em logs; IDs opacos (UUID); ring buffer local do app sem PII (espelha INV-5 da spec); retenção de logs do CMS definida na tabela RF07 |
| LGPD-RT04 | Consentimento versionado | Documentos legais com versão semântica + hash do texto; aceite referencia a versão exata; mudança material dispara re-aceite |
| LGPD-RT05 | Registro de aceite | Tabela append-only: `titular_id, doc_versao, doc_hash, timestamp, meio` — sem UPDATE/DELETE (constraint + permissão) |
| LGPD-RT06 | Criptografia | TLS 1.2+ obrigatório; Ed25519 para packs; Argon2id/bcrypt para senhas do CMS; segredos via cofre do provedor |
| LGPD-RT07 | Sessões/autenticação | Better Auth com 2FA TOTP; expiração de sessão ≤ 24 h; invalidação de sessão no logout e na troca de senha; bloqueio progressivo de força bruta |
| LGPD-RT08 | Backup | Criptografado; inventariado; teste de restauração semestral; expurgo alcança backups (ou prazo de expiração de backup ≤ prazo de retenção + ciclo) |
| LGPD-RT09 | Monitoramento | Alertas de acesso anômalo ao CMS/banco; monitoração de rejeição de assinatura de packs (proxy de ataque à cadeia de conteúdo); sem monitoramento de comportamento individual de usuário final |
| LGPD-RT10 | Exclusão segura | Expurgo com evidência (log do job); dados em SSD gerenciado: exclusão lógica + criptografia em repouso como compensação; no device, "apagar meus dados" remove os arquivos do sandbox do app |
| LGPD-RT11 | Provedores externos | Lista fixa de endpoints permitidos no app, verificada em CI; DPA por fornecedor; avaliação de transferência internacional documentada; revisão anual do inventário |

---

# 8. Tabela Consolidada de Requisitos

| ID | Categoria | Requisito | Descrição resumida | Prioridade | Base legal | Art. LGPD | Critério de aceitação |
|---|---|---|---|---|---|---|---|
| LGPD-RF01 | Coleta | Não-coleta no app | Zero dado pessoal do usuário final; permissões mínimas | P0 | Necessidade | 6º III; 46 §2º | Auditoria de tráfego + manifest limpos; CI bloqueia APIs de identificação |
| LGPD-RF02 | Consentimento | Consentimento piloto/CMS | Termo destacado, multimodal no piloto; aceite no 1º login do CMS | P0 | Consentimento; contrato | 7º I e V; 8º; 11 I | Nenhuma coleta antes do registro do aceite |
| LGPD-RF03 | Preferências | Tela de privacidade | Opt-out de telemetria; apagar dados locais; aviso em áudio | P1 | Livre acesso | 6º IV; 9º; 18 II/IV | Opt-out zera envio; exclusão local irreversível; operável sem leitura |
| LGPD-RF04 | Auditoria de consentimento | Registro imutável | Aceites versionados, append-only, com hash do documento | P0 | Prestação de contas | 8º §2º; 6º X; 37 | Cadeia completa recuperável; UPDATE/DELETE bloqueados |
| LGPD-RF05 | Revogação | Revogação facilitada | Gratuita, mesmo canal, interrompe tratamento | P0 | Revogabilidade | 8º §5º; 18 IX | Fluxo ≤ 2 interações; dados do revogante fora do conjunto |
| LGPD-RF06 | Terceiros | Inventário de operadores + DPA | Fornecedores listados, contratados, transferência internacional regular | P0 | Controlador–operador | 5º VI/VII; 39; 33–36 | DPA arquivado por fornecedor; lista pública na Política |
| LGPD-RF07 | Retenção | Tabela de retenção + expurgo | Prazo por classe; eliminação verificada ao término | P1 | Término do tratamento | 15; 16; 6º III | Job de expurgo logado; amostragem sem dados vencidos |
| LGPD-RF08 | Direitos | Canal e fluxos do art. 18 | Todos os direitos operacionalizados com protocolo | P0 | Direitos do titular | 17–22; 19 | Solicitação teste concluída no prazo com registro |
| LGPD-RNF09 | Segurança | Medidas técnicas/administrativas | TLS, assinatura de packs, RBAC, menor privilégio, testes | P0 | Segurança | 46; 47; 6º VII/VIII | Checklist §5 100%; sem vulnerabilidade crítica aberta |
| LGPD-RF10 | Transparência | Aviso multimodal | Informação clara em texto + ícones + áudio pt/es | P0 | Transparência | 6º IV/VI; 9º | Usuário não alfabetizado compreende o aviso sem mediação |
| LGPD-RF11 | Acesso | RBAC + 2FA no CMS | 3 papéis, segregação edição×aprovação, sessões expiráveis | P0 | Segurança | 46; 47 | Matriz papel×permissão testada; auto-aprovação bloqueada |
| LGPD-RF12 | Incidentes | Plano de resposta e comunicação | Runbook; comunicação ANPD/titulares em prazo regulamentar | P0 | Incidentes | 48; 46 | Tabletop anual; template pronto; responsáveis nomeados |
| LGPD-RF13 | Dados sensíveis | Saúde só no device | Tokens de sintomas em memória; proibida persistência/transmissão | P0 | Dado sensível | 5º II; 11; 12 | Revisão de código + teste de rede + schema de telemetria em CI |
| LGPD-RF14 | Analytics | Anti-reidentificação | Sem IDs persistentes; k-anonimato ≥ 20; granularidade diária | P0 | Anonimização | 12; 6º III | Validador rejeita coorte < 20; schema muda só com aval do encarregado |
| LGPD-RF15 | Marketing | Guardrail de e-mail marketing | Inexistente hoje; futura introdução exige opt-in + descadastro | P2 | Consentimento | 7º I; 8º; 9º §2º | Sem módulo de envio em massa; gate de compliance em PR |
| LGPD-RF16 | Anúncios | Vedação de ads/perfilamento | Proibidos SDKs de ads, advertising ID, fingerprinting | P0 | Necessidade; não discriminação | 6º III/IX; 11; 12 §2º | CI bloqueia libs de ads; APK sem advertising ID |
| LGPD-RF17 | Integrações | Higiene de APIs externas | Sem PII em URL; TLS; endpoints permitidos fixos; DPAs | P0 | Segurança; cadeia | 42; 46; 47; 39 | Varredura de logs limpa; allowlist de endpoints em CI |
| LGPD-DOC01–04 | Documentos legais | Termo, Política, Aviso, Banner | Conteúdo mínimo da §2; linguagem simples; multimodal | P0 | Transparência | 9º; 41 §1º | Revisão jurídica + teste de compreensão com público-alvo |
| LGPD-RT01–11 | Técnicos | Requisitos da §7 | Implementação de APIs, banco, logs, sessões, backup, exclusão | P0/P1 | Segurança | 46–49 | Verificação item a item em CI e em auditoria de release |

---

## Governança mínima recomendada

- **Encarregado (DPO)** nomeado e publicado (art. 41) — pode ser membro da equipe com independência funcional; canal fictício de exemplo: `privacidade@guiaubs.exemplo.br`.
- **Registro das operações de tratamento** (art. 37) mantido vivo — este documento é o ponto de partida.
- **RIPD/Relatório de Impacto** (art. 38) elaborado antes do piloto UAT e revisado a cada feature que toque dados (o modo ACS da v2 exigirá um novo).
- **Revisão anual** desta especificação ou a cada mudança material de arquitetura.

> **Nota de método:** este documento é uma especificação técnica de conformidade, não parecer jurídico. A revisão final dos documentos legais (§2) por advogado habilitado permanece obrigatória antes do lançamento. O texto integral da lei está em [planalto.gov.br](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm).
