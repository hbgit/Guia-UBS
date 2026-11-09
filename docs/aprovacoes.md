# Aprovações do lançamento e do estudo de impacto

> Quadro de situação de 2026-11-09, depois do [ADR-010](../spec/stack.md#10-registro-de-decisões-arquiteturais-adr). As exigências vêm do `spec/`, que prevalece em conflito. O estado de cada uma vem das issues e das perguntas abertas na data. Atualize o estado sempre que uma exigência for cumprida.

O ADR-010 separa duas etapas, cada uma com seu portão:
- **o lançamento (Parte A):** a publicação do app. É produto, não pesquisa, e não depende de CEP;
- **o estudo de impacto (Parte B):** pesquisa com seres humanos sobre o app já publicado.

Nenhuma das duas passa por unidade de saúde.

## Parte A — Lançamento

O dogfooding interno e o QA não exigem aprovação externa (ADR-010, Decisão 3f). O canal é a *pre-release* do GitHub ou a faixa de teste da Play.

| Exigência | Base | Estado em 2026-11-09 |
|---|---|---|
| Primeira tag e configuração do repositório | [`spec/implantacao.md`](../spec/implantacao.md) §2 | depende do plano B e dos passos do mantenedor |
| (a) Conteúdo validado por profissionais com registro ativo, com registro de revisão | ADR-010, 3a; [#2](https://github.com/hbgit/Guia-UBS/issues/2) | os 24 casos golden ainda não foram revisados |
| (a) Enquadramento educacional (sem "triagem", sem "não é emergência") | ADR-004, R1 e R2; [#48](https://github.com/hbgit/Guia-UBS/issues/48) | aberta |
| (a) O modelo só sinaliza escalada; o desfecho exibido vem da regra do pack | ADR-004; [#47](https://github.com/hbgit/Guia-UBS/issues/47) | aberta |
| (b) Aviso de que o app não substitui atendimento; sinais de alarme encaminhados para SAMU 192, UPA ou UBS | ADR-010, 3b; RF-16; INV-1 | implementados (RF-16 e gate); revisar na promoção |
| (c) Responsável institucional identificado, mais o parecer jurídico do ADR-004 | ADR-010, 3c; F-11; T7-R | aberta (**F-11**) |
| (d) Política de privacidade e termos publicados; políticas da Play para apps de saúde conferidas | ADR-010, 3d; `implantacao.md` §2.7 e §2.9 | publicados em `guiasaude.prismrr.com.br`; checklist da Play pendente (F-4) |
| (e) Correção de conteúdo publicada em ≤ 7 dias | ADR-010, 3e; RNF-12 | requisito novo; depende do host de conteúdo (plano B) |
| (f) QA interno, mais as mitigações de linguagem: revisão de linguagem simples pelo PET-Saúde, índice de legibilidade, escuta do TTS | ADR-010, 3f (variante C1+C2) | a fazer; índice e limiar a definir |
| (f) Validação de produto com pessoas indicadas pelo PET-Saúde | ADR-010, 3f | **só depois** da manifestação escrita do CEP/UFRR (F-20 d) |
| Teste fechado da Play, se a conta for pessoal | ADR-010, DC-D; `implantacao.md` §2.7 | depende da F-4; os testadores são QA |
| Aparelhos do dogfooding provisionados do zero a partir do storage próprio, não do Hugging Face | ADR-004 | depende do plano B |
| (g) **Critério de promoção para produção:** nenhuma orientação clinicamente incorreta na revisão clínica e aprovação da coordenação clínica | ADR-010, 3g | — |
| Registro do software como produção técnica (opcional: INPI) | ADR-010, Decisão 7 | titularidade aberta (**F-21**) |

**Caminho crítico do lançamento:** F-11 → parecer jurídico (T7-R) → revisão clínica (#2) → #47 e #48 → promoção.

## Parte B — Estudo de impacto

| Exigência | Base | Estado em 2026-11-09 |
|---|---|---|
| Consulta prévia informal ao CEP/UFRR | ADR-010, Decisões 3f e 4; **F-20** | a fazer |
| Instituição proponente. Hipótese de trabalho: a UFRR, com o docente responsável como pesquisador | ADR-010, Decisão 4 | a confirmar na F-20 (b) |
| TCLE e parecer do CEP/UFRR (Plataforma Brasil) antes do 1º participante | ADR-010, Decisão 4; Lei 14.874/2024 | protocolo não submetido |
| Base LGPD dos dados do estudo (consentimento, ou termo de informação se for o art. 7º, IV), em seção distinta do TCLE | [`spec/lgpd.md`](../spec/lgpd.md), RF02; ADR-010, Decisão 6 | depende da F-11 |
| Controlador LGPD e encarregado | LGPD, art. 9º; F-11 | aberta (**F-11**) |
| RIPD | LGPD, art. 38; ADR-010, DC-A | não escrito |
| Meta de alcance fixada com o PET-Saúde | PRD §1.3.2 (H4); F-14 | aberta (**F-14**) |

- **Hipóteses do estudo:** H1, H1b e H4 ([`spec/PRD.md`](../spec/PRD.md) §1.3.2).
- **Método:** observação de uso e entrevistas, por canal próprio, fora do app ([`dados-do-usuario.md`](dados-do-usuario.md) §5).

**Caminho crítico do estudo:** consulta prévia ao CEP (F-20) → instituição proponente → protocolo na Plataforma Brasil → TCLE e base LGPD, em seções distintas → RIPD → 1º participante. A tramitação corre em paralelo com o lançamento.

## O que o PET-Saúde pode reportar

Regra de fronteira do ADR-010, Decisão 5:

| Etapa | Pode reportar | Não pode |
|---|---|---|
| Lançamento | O produto, o alcance agregado da loja (instalações, versões ativas) e o relato de experiência de desenvolvimento | Qualquer dado de pessoa, inclusive o que se observar no QA ou no dogfooding |
| Estudo de impacto | Resultados com participantes, depois do parecer do CEP e dentro do protocolo | Dados coletados antes do parecer, porque o CEP não aprova retroativamente |

O alinhamento com a coordenação do PET-Saúde/Telessaúde está pendente. Ele é condição da PR do ADR-010.

## Anvisa

O ADR-004 sustenta que o app fica fora da **RDC 657/2022** pela exclusão de software "de bem-estar" (art. 1º, § 2º, I). A ressalva fica registrada: orientar a partir de sintomas fica perto da borda dessa definição. A exclusão só se sustenta se produto, textos, onboarding e página da loja forem coerentes com o rótulo educacional.

Por isso as issues #47 e #48 importam do ponto de vista regulatório, não só do de produto. O plano de realinhamento trata essa leitura como **proposta**, a confirmar por revisão jurídica (T7-R).

Nada neste quadro é parecer jurídico. As bases legais e o enquadramento regulatório continuam como proposta até a revisão (T7-R) e a manifestação do CEP/UFRR (F-20).
