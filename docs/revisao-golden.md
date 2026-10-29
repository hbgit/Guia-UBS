# Roteiro de revisão clínica da suíte golden

Para quem organiza a revisão (mantenedor, Secretaria) e para quem revisa. Este roteiro descreve o processo da issue #2 (P0-2); as decisões estão em `spec/arquitetura.md` §5.17. Enquanto nenhum caso estiver revisado, **nenhum caminho do repositório produz pack assinado**: `npm run pack:build` termina com `BLOQUEADO: 24 problema(s). Nada foi assinado.` e saída 1. `pack:check` (o CI de PR) apenas avisa e sai com 0.

## 1. Quem pode revisar

Médico (CRM) ou enfermeiro (COREN, categoria **ENF**) da atenção primária, com registro profissional **ativo**, ligado à UBS piloto e **indicado pela Secretaria Municipal de Saúde**. Técnico de enfermagem (`-TE`) não é aceito: o contrato recusa. Mínimo de **1** revisor por caso (`MIN_REVISORES`); subir para 2 é mudar uma constante, e o CI passa a reprovar todo caso com um só.

## 2. O termo de ciência

Cada revisor assina um termo de ciência (D3) antes de qualquer revisão. O termo é **arquivado pela Secretaria Municipal de Saúde (controladora)**, no sistema de protocolo dela, **fora do repositório e do CMS**. O repositório guarda só o `termo_sha256` do PDF assinado, que não revela conteúdo. Retenção: a da LGPD-RF04, contada da desativação do último caso que cita o atestado (prazo em anos pendente da LGPD-RF07).

## 3. Como ler um caso

Cada caso tem `tokens` (os sintomas que a pessoa tocaria, na ordem em que aparecem no aplicativo), `expect` (o desfecho esperado) e, às vezes, `note`.

- Os tokens aparecem na tabela da seção 8 com o **rótulo em português** que o aplicativo mostra (vem de `seed/001_ontology.sql`).
- `EMERGENCY` mostra o cartão vermelho **"Procure emergência agora"** e o local **UPA — pronto atendimento**.
- `ROUTINE_UBS` mostra o cartão verde **"Procure a UBS"** e o local **UBS — posto de saúde**.
- Quando nenhuma regra casa, o desfecho padrão é `ROUTINE_UBS`: a orientação é procurar atendimento, nunca silêncio.

## 4. A pergunta

Para **cada** caso, **cada** revisor responde: **"o desfecho esperado é clinicamente seguro?"** Não se pede que o revisor reescreva a regra nem que ache o desfecho ótimo; pede-se que diga se a pessoa descrita, ao receber aquele cartão, estaria segura.

Respostas possíveis e o que acontece com cada uma (D10, literal):

| Resposta | Efeito | Caminho | Quem decide |
|---|---|---|---|
| **concordo** | revisão transcrita | — | — |
| **concordo: seguro, mas mais cauteloso que o ideal** | conta como concordo: revisão transcrita; justificativa registrada no formulário | issue **P1** de ajuste da regra, **obrigatória no mesmo PR da transcrição** (o checklist do PR exige o link; não há robô); linha na tabela "casos seguros, mas cautelosos" da §5.17 | — (regra fixa) |
| **discordo: inseguro, o esperado seria MAIS grave** | caso fica no YAML, sem revisão; **pack bloqueado** | issue **P0** de conteúdo clínico; revisado de novo depois. **Retirar é proibido** (possível falso negativo) | — (regra fixa) |
| **discordo, num caso de severidade máxima** (red flag), em qualquer direção | idem: fica e bloqueia | issue P0 de conteúdo clínico | — (regra fixa) |
| **caso mal construído** (tokens incoerentes, combinação impossível) | caso fica e bloqueia até decisão | retirada em PR próprio `chore(golden): retira <id> mal construido (#2)` com a justificativa do revisor, e linha em §5.17 "casos retirados"; **nunca** para caso de red flag, que segue a linha anterior. Se o revisor sugerir um caso substituto, ele entra como caso novo, revisado pelo fluxo normal | dono, com o revisor |
| **não sei avaliar** | pendente, bloqueia | outro profissional indicado pela Secretaria | Secretaria |
| **dois revisores divergem** | vale a resposta **mais conservadora** (ordem: discordo/inseguro > mal construído > não sei > cauteloso > concordo). **Proibido** transcrever só quem concordou | o da linha correspondente | conforme a linha |

A #2 fecha quando todos os 24 casos estiverem revisados (concordo, com ou sem cautela) ou retirados como mal construídos. Discordância por insegurança deixa a #2 aberta, com o critério "`pack:check` sem aviso" pendente e referência à P0. O YAML não guarda votos: o formulário os guarda, e é por isso que as regras acima são obrigatórias.

**Quando dois revisores divergem, vale a resposta mais conservadora. É proibido transcrever só quem concordou.**

## 5. Conferência do registro profissional

Quem recebe o formulário, antes de pedir o ID, consulta o cadastro do conselho (Cofen/COREN-RR para enfermeiros, CFM/CRM-RR para médicos) e confere:

- situação **ativa**;
- categoria **ENF** (COREN);
- o nome confere com o do termo.

O sufixo `-IR` que aparece em algumas inscrições (`12.345-ENF-IR`) deve ser **confirmado com o setor de inscrição do COREN-RR**. **Se a confirmação mudar o formato aceito, pare e abra uma mudança de contrato (`fix(contract): ...`) antes de transcrever qualquer revisão (D2)**; nunca ajuste o formato na hora de transcrever. O código não consulta nenhum cadastro (seria dependência de rede sem API estável): a consulta é humana e é este passo.

## 6. Atribuição do ID e transcrição

1. O mantenedor abre um PR acrescentando `{ id, conselho, uf, categoria, termo_sha256 }` a `seed/golden/atestados.yaml`: próximo `AT-NNNN` livre, **nunca reaproveitado**. Sem nome e sem número de registro (o repositório é público).
2. Depois do merge, registra o atestado **completo, com o mesmo ID**, em cada CMS implantado: `POST /api/golden-cases/atestados` (corpo com `termo_sha256`, em snake_case; ver `docs/operacao.md` §4.5b). Nome e registro vivem só ali.
3. Os casos são transcritos para `seed/golden/clinical_cases.yaml` em `reviewed_by`, uma entrada por revisor, no formato de `contract/src/golden.ts` (`atestado`, `conselho`, `uf`, `categoria`, `reviewed_at`). Conselho, UF e categoria repetem o registro de propósito, e o portão confere que coincidem.
4. `reviewed_at` é a data em que o revisor respondeu (`AAAA-MM-DD`, não futura), **uma por revisor**.
5. Para o CMS, `npm run cms:import-golden` (ver `docs/operacao.md`): tudo ou nada, e só acrescenta revisor a caso com conteúdo idêntico.

Nenhum dado pessoal de revisor entra no repositório, nem em exemplo, nem em mensagem de commit.

## 7. Formulário por caso e checklist do PR

O formulário tem **um campo para cada revisor**, por caso: resposta (uma da seção 4), justificativa, desfecho que o revisor considera seguro (se discorda) e data. O formulário fica com a Secretaria, junto do termo.

Checklist do PR de transcrição:

- [ ] só respostas "concordo" (com ou sem cautela) de **todos** os revisores do caso; nenhum caso transcrito com voto de outro tipo em qualquer revisor;
- [ ] cada atestado citado já existe em `atestados.yaml` (PR anterior mergeado);
- [ ] para cada caso "cauteloso": issue **P1** de ajuste da regra aberta, **com o link neste PR**, e linha acrescentada à tabela "casos seguros, mas cautelosos" da §5.17;
- [ ] para cada caso retirado como mal construído: PR próprio `chore(golden): retira <id> mal construido (#2)` e linha em §5.17 "casos retirados";
- [ ] `npm run pack:check` sem o aviso de caso sem revisão (ou, se restarem casos, a lista bate com o que está pendente).

## 8. Os 24 casos

Gerada de `seed/golden/clinical_cases.yaml` (rótulos de `seed/001_ontology.sql`) no commit `1189c2c`, antes desta documentação. Se o YAML mudar, a tabela envelhece: regenere. As notas estão como no YAML (sem acento, por convenção do repositório).

| # | id | Tokens (rótulo em português) | Desfecho esperado | Nota |
|---|---|---|---|---|
| 1 | `chest-pain` | Peito (`chest`), Dor (`pain`) | `EMERGENCY` | Dor toracica — regra rf.chest_pain |
| 2 | `chest-pain-with-noise` | Peito (`chest`), Dor (`pain`), Não passa (`persistent`), Pessoa idosa (`elderly`) | `EMERGENCY` | Tokens adicionais nao podem rebaixar uma red flag |
| 3 | `breathless-alone` | Falta de ar (`breathless`) | `EMERGENCY` | Dispneia isolada — regra rf.breathless |
| 4 | `breathless-with-routine-token` | Tosse (`cough`), Falta de ar (`breathless`) | `EMERGENCY` | Tosse sozinha seria rotina; com dispneia a prioridade menor vence |
| 5 | `airway-swelling` | Garganta (`throat`), Inchaço (`swelling`) | `EMERGENCY` | Via aerea — regra rf.airway_swelling |
| 6 | `bleeding-severe` | Sangramento (`bleeding`), Muito forte (`severe`) | `EMERGENCY` | Primeiro grupo (OU) de rf.bleeding_critical |
| 7 | `bleeding-pregnant` | Sangramento (`bleeding`), Grávida (`pregnant`) | `EMERGENCY` | Segundo grupo (OU) de rf.bleeding_critical |
| 8 | `sudden-headache` | Cabeça (`head`), Dor (`pain`), Começou de repente (`sudden`) | `EMERGENCY` | Cefaleia subita — regra rf.sudden_headache |
| 9 | `palpitation-with-pain` | Coração acelerado (`palpitation`), Dor (`pain`) | `EMERGENCY` | Primeiro grupo de rf.palpitation |
| 10 | `palpitation-with-breathless` | Coração acelerado (`palpitation`), Falta de ar (`breathless`) | `EMERGENCY` | Segundo grupo de rf.palpitation |
| 11 | `infant-fever` | Bebê (`infant`), Febre (`fever`) | `EMERGENCY` | Febre em bebe — regra rf.infant_fever |
| 12 | `chest-alone` | Peito (`chest`) | `ROUTINE_UBS` | Parte do corpo sem sintoma nao dispara red flag; cai no padrao |
| 13 | `headache-not-sudden` | Cabeça (`head`), Dor (`pain`) | `ROUTINE_UBS` | Exercita o termo negado de rt.headache (ausencia de `sudden`) |
| 14 | `bleeding-alone` | Sangramento (`bleeding`) | `ROUTINE_UBS` | Sangramento sem `severe` nem `pregnant` nao satisfaz nenhum grupo |
| 15 | `palpitation-alone` | Coração acelerado (`palpitation`) | `ROUTINE_UBS` | Palpitacao isolada nao satisfaz nenhum grupo de rf.palpitation |
| 16 | `swelling-without-throat` | Perna (`leg`), Inchaço (`swelling`) | `ROUTINE_UBS` | Inchaco fora da via aerea nao e red flag |
| 17 | `fever-adult` | Febre (`fever`) | `ROUTINE_UBS` | Febre sem o modificador `infant` |
| 18 | `severe-without-bleeding` | Costas (`back`), Dor (`pain`), Muito forte (`severe`) | `ROUTINE_UBS` | `severe` sozinho nao escala — so compoe grupo com `bleeding` |
| 19 | `cough-alone` | Tosse (`cough`) | `ROUTINE_UBS` | — |
| 20 | `minor-cut` | Braço (`arm`), Corte (`cut`) | `ROUTINE_UBS` | — |
| 21 | `vomit` | Barriga (`belly`), Vômito (`vomit`) | `ROUTINE_UBS` | — |
| 22 | `diarrhea` | Diarreia (`diarrhea`) | `ROUTINE_UBS` | Segundo grupo de rt.gastro |
| 23 | `rash` | Pele (`skin`), Manchas na pele (`rash`) | `ROUTINE_UBS` | — |
| 24 | `no-rule-matches` | Pessoa idosa (`elderly`) | `ROUTINE_UBS` | Nenhuma regra cobre este conjunto. O desfecho padrao do pacote assume, e a orientacao segura e procurar atendimento — nunca silencio. |
